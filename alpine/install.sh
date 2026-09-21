#!/bin/sh
# ============================================================
# alpine/install.sh — install a SOVR node on Alpine Linux
#
# Lays down a self-contained native deployment from an extracted release
# bundle: the static musl `sovrd`, the container supervisor
# (`entrypoint.sh`), the bundle verifier, an OpenRC service, and a
# /etc/conf.d/sovrd template. Idempotent: re-run it with a newer bundle to
# upgrade the binary — node data and /etc/conf.d/sovrd are never touched.
#
# /bin/sh (busybox ash) compatible on purpose: a fresh Alpine has no bash,
# and this script installs it.
#
# Usage:
#   alpine/install.sh --bundle DIR [--role fullnode|rpc|validator] [options]
#
#   --bundle DIR            extracted release bundle (required). Must contain
#                           sovrd-linux-amd64-musl, entrypoint.sh,
#                           verify-release-bundle.sh, genesis.json, launch.env,
#                           checksums.txt. Build it with
#                           `scripts/build-release-bundle.sh --static-musl`.
#   --role ROLE             fullnode (default) | rpc | validator. Sets
#                           listener binding and PEX defaults; all knobs stay
#                           editable in /etc/conf.d/sovrd.
#   --environment NAME      mainnet (default) | public-testnet | internal-testnet | local-dev
#   --chain-id ID           default: sovr-1
#   --moniker NAME          node moniker (default: sovr-node)
#   --external-address ADDR public P2P address, tcp://<ip>:26656 (all mainnet
#                           roles require a real value before the node starts)
#   --seeds LIST            comma-separated seed nodes
#   --persistent-peers LIST comma-separated persistent peers
#   --cors-origins JSON     CORS origins for the public RPC/REST API (rpc role)
#   --release-pubkey PATH   armored release-captain public key used to verify
#                           checksums.txt.asc. REQUIRED on mainnet (the
#                           manifest must be authenticated, not just
#                           internally consistent). An https:// URL is fetched.
#   --snapshot-baseurl URL  snapshot bucket (default: official mainnet bucket)
#   --snapshot-cosign-pubkey KEY  snapshot cosign key (default: official mainnet)
#   --snapshot-anchors LIST two distinct RPC anchors for the cross-check
#   --snapshot-network NAME bucket path segment (default: --environment name)
#   --start                 enable + start the service after install
#
# Note: when --release-pubkey is an https URL, the key is only as trustworthy
# as that host. Prefer an origin DIFFERENT from where the bundle/tarball is
# hosted, so a single compromised origin cannot supply both the key and the
# payload it is supposed to authenticate.
#   -h, --help              this help
#
# Validators: install, sync, then follow mainnet-runbook/add-validator.md
# (the native section) and mainnet-runbook/sentry-topology.md before bonding.
#
# Docs: mainnet-runbook/alpine-node-setup.md
# ============================================================
set -eu

ROLE="fullnode"
BUNDLE=""
ENVIRONMENT="mainnet"
CHAIN_ID="sovr-1"
MONIKER="sovr-node"
EXTERNAL_ADDRESS=""
SEEDS=""
PERSISTENT_PEERS=""
CORS_ORIGINS=""
RELEASE_PUBKEY=""
DO_START=0

# Snapshot bootstrap. From-genesis sync is NOT viable on sovr-1 (many on-chain
# upgrades; one modern binary cannot reproduce the historical app hashes), so a
# fresh node restores a signed archive snapshot first. These defaults are the
# PUBLIC mainnet values (identical to deploy/validator/.env.example); override
# with the flags below for another network.
MAINNET_SNAPSHOT_BASEURL="https://svrn-chain-snapshots-mainnet.nyc3.digitaloceanspaces.com/snapshots"
MAINNET_SNAPSHOT_COSIGN_PUBKEY="MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEv6XtLWy4H3IhmiLMUXEbRCeWswmXS8Y3xuNHo96Bwt2TbZSnwxnn4sHbl1/2cTH+b85pb/zGRIfURBad2ZOpfA=="
MAINNET_SNAPSHOT_ANCHORS="https://rpc.sovrchain.net,https://rpc2.sovrchain.net"
SNAPSHOT_BASEURL=""
SNAPSHOT_COSIGN_PUBKEY=""
SNAPSHOT_ANCHORS=""
SNAPSHOT_NETWORK=""

SOVR_USER="sovr"
SOVR_HOME="/home/sovr/.sovr"
RELEASE_DIR="/etc/sovr/release"
CONF_FILE="/etc/conf.d/sovrd"
INIT_FILE="/etc/init.d/sovrd"

log() { printf '[sovr-install] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Mirrors docker/entrypoint.sh is_placeholder(): empty, or a value marked
# REPLACE / REQUIRED / TODO / PLACEHOLDER (case-insensitive). The entrypoint
# rejects these on mainnet at every start, so the installer must use the SAME
# predicate when deciding whether it is safe to start (otherwise it reports
# success while supervise-daemon crash-loops on the entrypoint's fatal()).
is_placeholder() {
	case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
	"" | *replace* | *required* | *todo* | *placeholder*) return 0 ;;
	*) return 1 ;;
	esac
}

# Single-quote a value for a file that is later sourced as shell
# (sovrd.openrc does `set -a; . /etc/conf.d/sovrd`). Without this, a value
# like `--moniker "West Coast"` or one containing `$(...)` / `;` would be
# re-parsed — and, because conf.d is sourced as root, could execute. Embedded
# single quotes become '\'' (the standard POSIX close/escape/reopen).
shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Write `KEY='shell-quoted value'` to the conf.d file currently being built.
emit() {
	printf '%s=%s\n' "$1" "$(shell_quote "$2")"
}

# Replace a live file atomically: write alongside it in the same directory, then
# rename(2) over the target, so an interrupted copy can never leave a truncated
# binary/script in place.
install_file_atomic() {
	src=$1 dest=$2 mode=$3
	tmp="$(dirname "$dest")/.$(basename "$dest").new.$$"
	cp "$src" "$tmp" || die "could not stage $dest"
	chmod "$mode" "$tmp" || die "could not chmod $dest"
	mv -f "$tmp" "$dest" || die "could not install $dest"
}

# Read a variable back out of the generated conf.d the way the service will:
# source it in a subshell (values are shell-quoted, so a plain grep would
# return the quotes). Read-only; a malformed file yields empty.
read_conf_var() {
	(
		# shellcheck disable=SC1090  # $CONF_FILE is generated at runtime
		. "$CONF_FILE" >/dev/null 2>&1 || exit 0
		eval "printf '%s' \"\${$1:-}\""
	)
}

# The environment that will actually govern this node: an existing conf.d is
# authoritative (the installer leaves it untouched on reruns), otherwise the
# --environment flag. Security policy (signed-manifest requirement) must follow
# this — not the flag — so a rerun cannot downgrade an installed mainnet node
# by passing `--environment internal-testnet`.
effective_environment() {
	if [ -f "$CONF_FILE" ]; then
		read_conf_var DEPLOYMENT_ENVIRONMENT
	else
		printf '%s' "$ENVIRONMENT"
	fi
}

# Authenticate the checksum manifest with the release-captain's detached
# signature before it is trusted. `sha256sum -c` alone only proves internal
# consistency: whoever can replace the tarball can replace checksums.txt too.
# mainnet fails closed without a public key + signature.
verify_manifest_signature() {
	sig="$BUNDLE/checksums.txt.asc"
	env_for_sig="$(effective_environment)"
	if [ "$env_for_sig" = "mainnet" ] && [ "$ENVIRONMENT" != "mainnet" ]; then
		log "WARNING: installed conf.d governs DEPLOYMENT_ENVIRONMENT=$env_for_sig; --environment=$ENVIRONMENT does not relax signature policy"
	fi
	if [ -z "$RELEASE_PUBKEY" ]; then
		if [ "$env_for_sig" = "mainnet" ]; then
			die "mainnet requires --release-pubkey (path to the out-of-band release-captain public key) to authenticate checksums.txt.asc (effective environment: $env_for_sig)"
		fi
		if [ -f "$sig" ]; then
			log "WARNING: bundle has checksums.txt.asc but no --release-pubkey; skipping signature verification"
		fi
		return 0
	fi
	case "$RELEASE_PUBKEY" in
	https://*)
		# Fetch the armored public key from a stable URL (it is a public key).
		# https ONLY, and refuse redirects below TLS: this key is the trust
		# anchor for the whole bundle, so an http:// URL (or a redirect to one)
		# would let a network attacker swap the key, the signature AND the
		# tarball — gpg verification would then pass a malicious sovrd.
		pk_tmp="$(mktemp)"
		# Clean up on every exit path (including the dies below).
		trap 'rm -f "${pk_tmp:-}"' EXIT
		curl -fsSL --proto '=https' --tlsv1.2 "$RELEASE_PUBKEY" -o "$pk_tmp" \
			|| die "could not fetch --release-pubkey URL: $RELEASE_PUBKEY"
		RELEASE_PUBKEY="$pk_tmp"
		;;
	http://*)
		die "--release-pubkey must be an https:// URL; plain http would let a network attacker replace the trust anchor. Download it yourself and pass a file path if you must."
		;;
	esac
	[ -f "$RELEASE_PUBKEY" ] || die "--release-pubkey not found: $RELEASE_PUBKEY"
	[ -f "$sig" ] || die "bundle is missing checksums.txt.asc (--release-pubkey given, cannot authenticate the manifest)"
	if ! command -v gpg >/dev/null 2>&1; then
		log "installing gnupg for signature verification"
		apk add --no-cache gnupg >/dev/null
	fi
	gpg_home="$(mktemp -d)"
	gpg --batch --quiet --homedir "$gpg_home" --import "$RELEASE_PUBKEY" \
		|| die "could not import release public key: $RELEASE_PUBKEY"
	gpg --batch --quiet --homedir "$gpg_home" --verify "$sig" "$BUNDLE/checksums.txt" \
		|| die "checksums.txt.asc signature verification FAILED against $RELEASE_PUBKEY"
	rm -rf "$gpg_home"
	log "authenticated checksums.txt against $RELEASE_PUBKEY"
}

usage() {
	cat >&2 <<'EOF'
alpine/install.sh — install a SOVR node on Alpine Linux

Usage: alpine/install.sh --bundle DIR [--role fullnode|rpc|validator] [options]

  --bundle DIR             extracted release bundle (required)
  --role ROLE              fullnode (default) | rpc | validator
  --environment NAME       mainnet (default) | public-testnet | internal-testnet | local-dev
  --chain-id ID            default: sovr-1
  --moniker NAME           node moniker (default: sovr-node)
  --external-address ADDR  public P2P address, tcp://<ip>:26656
  --seeds LIST             comma-separated seed nodes
  --persistent-peers LIST  comma-separated persistent peers
  --cors-origins JSON      CORS origins for the public API (rpc role)
  --release-pubkey PATH|URL release-captain public key (required on mainnet);
                           an https:// URL is fetched
  --snapshot-baseurl URL   snapshot bucket (default: official mainnet bucket)
  --snapshot-cosign-pubkey KEY  snapshot cosign public key (default: official)
  --snapshot-anchors LIST  two distinct RPC anchors for the block-hash
                           cross-check (default: https://rpc.sovrchain.net,
                           https://rpc2.sovrchain.net)
  --snapshot-network NAME  snapshot bucket path segment (default: --environment)
  --start                  enable + start the service after install
  -h, --help               this help
EOF
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--bundle) BUNDLE="${2:-}"; [ -n "$BUNDLE" ] || die "--bundle requires a value"; shift 2 ;;
	--role) ROLE="${2:-}"; [ -n "$ROLE" ] || die "--role requires a value"; shift 2 ;;
	--environment) ENVIRONMENT="${2:-}"; [ -n "$ENVIRONMENT" ] || die "--environment requires a value"; shift 2 ;;
	--chain-id) CHAIN_ID="${2:-}"; [ -n "$CHAIN_ID" ] || die "--chain-id requires a value"; shift 2 ;;
	--moniker) MONIKER="${2:-}"; [ -n "$MONIKER" ] || die "--moniker requires a value"; shift 2 ;;
	--external-address) EXTERNAL_ADDRESS="${2:-}"; [ -n "$EXTERNAL_ADDRESS" ] || die "--external-address requires a value"; shift 2 ;;
	--seeds) SEEDS="${2:-}"; [ -n "$SEEDS" ] || die "--seeds requires a value"; shift 2 ;;
	--persistent-peers) PERSISTENT_PEERS="${2:-}"; [ -n "$PERSISTENT_PEERS" ] || die "--persistent-peers requires a value"; shift 2 ;;
	--cors-origins) CORS_ORIGINS="${2:-}"; [ -n "$CORS_ORIGINS" ] || die "--cors-origins requires a value"; shift 2 ;;
	--release-pubkey) RELEASE_PUBKEY="${2:-}"; [ -n "$RELEASE_PUBKEY" ] || die "--release-pubkey requires a value"; shift 2 ;;
	--snapshot-baseurl) SNAPSHOT_BASEURL="${2:-}"; [ -n "$SNAPSHOT_BASEURL" ] || die "--snapshot-baseurl requires a value"; shift 2 ;;
	--snapshot-cosign-pubkey) SNAPSHOT_COSIGN_PUBKEY="${2:-}"; [ -n "$SNAPSHOT_COSIGN_PUBKEY" ] || die "--snapshot-cosign-pubkey requires a value"; shift 2 ;;
	--snapshot-anchors) SNAPSHOT_ANCHORS="${2:-}"; [ -n "$SNAPSHOT_ANCHORS" ] || die "--snapshot-anchors requires a value"; shift 2 ;;
	--snapshot-network) SNAPSHOT_NETWORK="${2:-}"; [ -n "$SNAPSHOT_NETWORK" ] || die "--snapshot-network requires a value"; shift 2 ;;
	--start) DO_START=1; shift ;;
	-h | --help) usage 0 ;;
	*) die "unknown flag: $1 (try --help)" ;;
	esac
done

[ -n "$BUNDLE" ] || { log "--bundle is required"; usage 1; }
case "$ROLE" in
fullnode | rpc | validator) ;;
*) die "invalid --role: $ROLE (expected fullnode|rpc|validator)" ;;
esac
# DEPLOYMENT_ENVIRONMENT is written verbatim and gates every mainnet safety
# check in docker/entrypoint.sh behind an exact `= "mainnet"` match, so a
# typo/miscase ("Mainnet") would silently install a fail-open mainnet node.
case "$ENVIRONMENT" in
mainnet | public-testnet | internal-testnet | local-dev) ;;
*) die "invalid --environment: $ENVIRONMENT (expected mainnet|public-testnet|internal-testnet|local-dev)" ;;
esac

# Default the snapshot bootstrap to the official mainnet values (public
# artifact; identical to deploy/validator/.env.example). Only mainnet gets
# defaults — pass the flags explicitly for another network.
if [ "$ENVIRONMENT" = "mainnet" ]; then
	[ -n "$SNAPSHOT_BASEURL" ] || SNAPSHOT_BASEURL="$MAINNET_SNAPSHOT_BASEURL"
	[ -n "$SNAPSHOT_COSIGN_PUBKEY" ] || SNAPSHOT_COSIGN_PUBKEY="$MAINNET_SNAPSHOT_COSIGN_PUBKEY"
	[ -n "$SNAPSHOT_ANCHORS" ] || SNAPSHOT_ANCHORS="$MAINNET_SNAPSHOT_ANCHORS"
fi
# Snapshot bootstrap is all-or-nothing: the entrypoint needs the bucket, the
# cosign public key AND the two anchors. Fail here rather than write a conf.d
# that dies at first start (a non-mainnet install with only --snapshot-baseurl
# used to produce SNAPSHOT_RESTORE=true + empty key/anchors).
if [ -n "$SNAPSHOT_BASEURL$SNAPSHOT_COSIGN_PUBKEY$SNAPSHOT_ANCHORS" ]; then
	[ -n "$SNAPSHOT_BASEURL" ] || die "snapshot config is incomplete: --snapshot-cosign-pubkey/--snapshot-anchors set without --snapshot-baseurl"
	[ -n "$SNAPSHOT_COSIGN_PUBKEY" ] || die "snapshot config is incomplete: --snapshot-baseurl/--snapshot-anchors set without --snapshot-cosign-pubkey"
	[ -n "$SNAPSHOT_ANCHORS" ] || die "snapshot config is incomplete: --snapshot-baseurl/--snapshot-cosign-pubkey set without --snapshot-anchors"
fi
# Snapshot bucket path segment. Defaults to the environment name; overridable
# because a network's bucket segment need not equal its DEPLOYMENT_ENVIRONMENT.
if [ -n "$SNAPSHOT_BASEURL" ]; then
	SNAPSHOT_NETWORK="${SNAPSHOT_NETWORK:-$ENVIRONMENT}"
fi
[ "$(id -u)" = "0" ] || die "must run as root (try: doas \"$0\" --bundle \"$BUNDLE\")"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
[ -f "$SCRIPT_DIR/sovrd.openrc" ] || die "sovrd.openrc not found next to install.sh ($SCRIPT_DIR); run from the repo's alpine/ dir"

[ -d "$BUNDLE" ] || die "bundle directory not found: $BUNDLE"
[ -f "$BUNDLE/checksums.txt" ] || die "bundle is missing checksums.txt: $BUNDLE"

# The native Alpine profile is x86_64-only: published release bundles ship the
# amd64 musl binary (scripts/build-release-bundle.sh --static-musl builds
# linux/amd64). On arm64, run the multi-arch Alpine *image* instead.
case "$(uname -m)" in
x86_64 | amd64) ARCH=amd64 ;;
*)
	die "unsupported architecture: $(uname -m). The native Alpine profile is x86_64-only (published bundles ship sovrd-linux-amd64-musl). On arm64, use the multi-arch Alpine container image (ghcr.io/parler-tech/sbn:<version>-alpine) instead."
	;;
esac
MUSL_BIN="sovrd-linux-${ARCH}-musl"

# Role defaults. These are only written into a fresh /etc/conf.d/sovrd; an
# existing file is never modified (operators tune it by hand).
case "$ROLE" in
fullnode)
	RPC_ADDR="tcp://127.0.0.1:26657"
	API_ADDR="tcp://127.0.0.1:1317"
	GRPC_ADDR="127.0.0.1:9090"
	PEX="true"
	API_ENABLE="true"
	;;
rpc)
	# Public RPC/REST/gRPC node. Firewall: 26656 (P2P), 26657 (RPC),
	# 1317 (REST), 9090 (gRPC) — see infrastructure-and-ops.md §10.
	RPC_ADDR="tcp://0.0.0.0:26657"
	API_ADDR="tcp://0.0.0.0:1317"
	GRPC_ADDR="0.0.0.0:9090"
	PEX="true"
	API_ENABLE="true"
	;;
validator)
	# Never expose RPC/API from a consensus node (infrastructure-and-ops.md
	# §10). Peering is closed: only the sentries listed in
	# PERSISTENT_PEERS/PRIVATE_PEER_IDS may connect — see sentry-topology.md.
	RPC_ADDR="tcp://127.0.0.1:26657"
	API_ADDR="tcp://127.0.0.1:1317"
	GRPC_ADDR="127.0.0.1:9090"
	PEX="false"
	API_ENABLE="true"
	;;
esac

# ---------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------
log "installing packages (bash curl jq zstd openrc file)"
apk add --no-cache bash ca-certificates curl jq zstd openrc file >/dev/null

if [ -n "$CORS_ORIGINS" ]; then
	# Validate real JSON (not just `[...]`): the entrypoint splices this value
	# into config.toml, so `[https://a.example]` would otherwise pass the
	# installer and only fail as invalid TOML at `sovrd start`.
	if ! printf '%s' "$CORS_ORIGINS" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
		die "--cors-origins must be a JSON array of strings, e.g. '[\"https://a.example\"]'"
	fi
fi

# ---------------------------------------------------------------
# 2. Service user + home
# ---------------------------------------------------------------
if id "$SOVR_USER" >/dev/null 2>&1; then
	log "user $SOVR_USER already exists"
else
	log "creating user $SOVR_USER (no login)"
	addgroup -g 1000 "$SOVR_USER" 2>/dev/null || addgroup "$SOVR_USER" 2>/dev/null || true
	# Prefer uid 1000 (parity with the container image) but fall back to any
	# free uid so a host that already uses 1000 still works — the OpenRC
	# service addresses the user by name, not by uid.
	if ! adduser -D -u 1000 -G "$SOVR_USER" -s /sbin/nologin -h "/home/$SOVR_USER" "$SOVR_USER" 2>/dev/null; then
		log "uid 1000 is already in use; allocating a free uid for $SOVR_USER"
		adduser -D -G "$SOVR_USER" -s /sbin/nologin -h "/home/$SOVR_USER" "$SOVR_USER"
	fi
fi
mkdir -p "$SOVR_HOME"
# Non-recursive on purpose: on an upgrade /home/sovr/.sovr/data can be 100 GB+
# with a huge file count, and walking it on every installer run would burn a
# chunk of a coordinated halt window (and contradict the "upgrades never touch
# node data" guarantee). Only the two directories this step creates need
# ownership; files the node created are already the service user's.
chown "$SOVR_USER:$SOVR_USER" "/home/$SOVR_USER" "$SOVR_HOME"

# supervise-daemon opens the log after dropping to the service user, so the
# file must already exist and be writable by that user (it cannot create a
# file in root-owned /var/log).
touch /var/log/sovrd.log
chown "$SOVR_USER:$SOVR_USER" /var/log/sovrd.log
chmod 0644 /var/log/sovrd.log

# ---------------------------------------------------------------
# 3. Verify the bundle, fail-closed
# ---------------------------------------------------------------
# First authenticate the manifest itself (detached signature, pinned key)
# before trusting any checksum in it.
verify_manifest_signature

# Every file this script installs must be present AND have a checksum entry.
# A missing checksums.txt line is a hard failure, not a silent skip:
# entrypoint.sh / verify-release-bundle.sh are installed once and never
# re-verified later, so a stripped-checksum supervisor must not slip through.
# Optional files are checked when present (their absence is legitimate).
BUNDLE_FILES_REQUIRED="genesis.json launch.env entrypoint.sh verify-release-bundle.sh $MUSL_BIN"
BUNDLE_FILES_OPTIONAL="seeds.txt addrbook.json"

bundle_checksum_for() {
	awk -v t="$1" '$2 == t || $2 == "./" t { print $1; exit }' "$BUNDLE/checksums.txt"
}

log "verifying bundle checksums"
CHECKLIST="$(mktemp)"
trap 'rm -f "$CHECKLIST"' EXIT
for f in $BUNDLE_FILES_REQUIRED; do
	[ -f "$BUNDLE/$f" ] || die "bundle is missing required file: $f"
	sum="$(bundle_checksum_for "$f")"
	[ -n "$sum" ] || die "checksums.txt has no entry for $f (refusing to install an unverifiable file)"
	printf '%s  %s\n' "$sum" "$f" >>"$CHECKLIST"
done
for f in $BUNDLE_FILES_OPTIONAL; do
	[ -f "$BUNDLE/$f" ] || continue
	sum="$(bundle_checksum_for "$f")"
	[ -n "$sum" ] || die "bundle contains $f but checksums.txt has no entry for it"
	printf '%s  %s\n' "$sum" "$f" >>"$CHECKLIST"
done
( cd "$BUNDLE" && sha256sum -c "$CHECKLIST" ) || die "bundle checksum verification failed"

# The whole point of this profile is the *static musl* binary. A dynamically
# linked one (e.g. the glibc `sovrd` mislabeled as the musl build) installs
# fine and then dies at `sovrd start` on Alpine — fail at install time instead.
bin_desc="$(file "$BUNDLE/$MUSL_BIN" 2>/dev/null)"
case "$bin_desc" in
*ELF*x86-64*) ;;
*) die "$MUSL_BIN is not an x86-64 ELF binary: $bin_desc" ;;
esac
case "$bin_desc" in
*"statically linked"*) ;;
*) die "$MUSL_BIN is not statically linked (the glibc 'sovrd' will not run on Alpine): $bin_desc" ;;
esac
log "verified $MUSL_BIN is a statically linked x86-64 ELF"

# ---------------------------------------------------------------
# 3b. Stop a running node before replacing its live files
# ---------------------------------------------------------------
# The binary, supervisor, and staged bundle are copied straight into their
# live paths. Under supervise-daemon (respawn_max=0) a respawn during the copy
# could observe a missing/partial binary or a mixed bundle; chain-upgrades.md
# §3.1 also requires sentries to be stopped inside the halt window.
SERVICE_WAS_RUNNING=0
if rc-service sovrd status >/dev/null 2>&1; then
	SERVICE_WAS_RUNNING=1
	log "stopping running sovrd before replacing its files"
	if ! rc-service sovrd stop >/dev/null 2>&1; then
		die "failed to stop running sovrd; refusing to replace live files"
	fi
	if rc-service sovrd status >/dev/null 2>&1; then
		die "sovrd still reports running after stop; refusing to replace live files"
	fi
fi

# ---------------------------------------------------------------
# 4. Install binaries + supervisor
# ---------------------------------------------------------------
log "installing $MUSL_BIN -> /usr/local/bin/sovrd"
install_file_atomic "$BUNDLE/$MUSL_BIN" "/usr/local/bin/$MUSL_BIN" 0755
ln -sf "/usr/local/bin/$MUSL_BIN" /usr/local/bin/sovrd
install_file_atomic "$BUNDLE/entrypoint.sh" /usr/local/bin/entrypoint.sh 0755
install_file_atomic "$BUNDLE/verify-release-bundle.sh" /usr/local/bin/verify-release-bundle.sh 0755

# ---------------------------------------------------------------
# 5. Stage the release bundle for the entrypoint's start-time verification
# ---------------------------------------------------------------
log "staging release bundle -> $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
for f in genesis.json checksums.txt launch.env entrypoint.sh verify-release-bundle.sh; do
	cp "$BUNDLE/$f" "$RELEASE_DIR/$f"
done
# Mirror the optional files *exactly*: a stale seeds.txt / addrbook.json left
# from a previous release makes entrypoint.sh refuse to start on mainnet (file
# present, but no entry in the new checksums.txt).
for f in seeds.txt addrbook.json; do
	if [ -f "$BUNDLE/$f" ]; then
		cp "$BUNDLE/$f" "$RELEASE_DIR/$f"
	else
		rm -f "$RELEASE_DIR/$f"
	fi
done
chmod 0644 "$RELEASE_DIR"/* 2>/dev/null || true
chmod 0755 "$RELEASE_DIR/entrypoint.sh" "$RELEASE_DIR/verify-release-bundle.sh" 2>/dev/null || true

# ---------------------------------------------------------------
# 6. Config (never clobber an edited file)
# ---------------------------------------------------------------
if [ -f "$CONF_FILE" ]; then
	log "$CONF_FILE exists; leaving it untouched (re-run with a newer bundle to upgrade the binary)"
else
	log "writing $CONF_FILE (role=$ROLE)"
	{
		cat <<EOF
# /etc/conf.d/sovrd — generated by alpine/install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Role: $ROLE. Same env-var interface as the container image
# (docker/entrypoint.sh). See mainnet-runbook/alpine-node-setup.md, then:
#   rc-service sovrd restart
#
# Every value is single-quoted: sovrd.openrc sources this file as root, so an
# unquoted value containing shell syntax or spaces would be re-parsed there.
EOF
		emit SOVR_HOME "$SOVR_HOME"
		emit DEPLOYMENT_ENVIRONMENT "$ENVIRONMENT"
		emit CHAIN_ID "$CHAIN_ID"
		emit MONIKER "$MONIKER"
		emit KEYRING_BACKEND file
		emit SIGNER_MODE disabled
		emit RELEASE_BUNDLE_DIR "$RELEASE_DIR"
		cat <<'EOF'
# The native install runs the static musl binary; verify it against the
# matching checksums.txt entry (the glibc "sovrd" entry is a different file).
EOF
		emit SOVRD_BINARY_PATH "/usr/local/bin/$MUSL_BIN"
		emit EXTERNAL_ADDRESS "$EXTERNAL_ADDRESS"
		emit SEEDS "$SEEDS"
		emit PERSISTENT_PEERS "$PERSISTENT_PEERS"
		if [ -n "$SNAPSHOT_BASEURL" ]; then
			cat <<'EOF'

# --- snapshot bootstrap (fresh node) ---------------------------------------
# From-genesis sync is NOT viable on sovr-1 (the chain has had many on-chain
# upgrades; no single binary reproduces the historical app hashes), so a fresh
# node restores a signed archive snapshot first, then blocksyncs the short gap
# to head. No-op on a node that already has data. The entrypoint cosign-verifies
# the manifest, cross-checks the block_hash against BOTH anchors, and verifies
# the tarball sha256 (fail-closed). The two anchors must be DISTINCT.
EOF
			emit SNAPSHOT_RESTORE true
			emit SNAPSHOT_BASEURL "$SNAPSHOT_BASEURL"
			emit SNAPSHOT_NETWORK "$SNAPSHOT_NETWORK"
			emit SNAPSHOT_COSIGN_PUBKEY "$SNAPSHOT_COSIGN_PUBKEY"
			emit SNAPSHOT_ANCHORS "$SNAPSHOT_ANCHORS"
		fi
		printf '\n# --- role defaults (%s): edit as needed ---\n' "$ROLE"
		emit RPC_LISTEN_ADDR "$RPC_ADDR"
		emit API_LISTEN_ADDR "$API_ADDR"
		emit GRPC_LISTEN_ADDR "$GRPC_ADDR"
		emit API_ENABLE "$API_ENABLE"
		emit PROMETHEUS_ENABLE true
		emit PEX "$PEX"
		if [ "$ROLE" = "validator" ]; then
			cat <<'EOF'
# Validator peering — two supported shapes:
#   1) Sentry topology (hardened): set PERSISTENT_PEERS, PRIVATE_PEER_IDS and
#      UNCONDITIONAL_PEER_IDS to your OWN sentry node IDs (sentry-topology.md).
#   2) Standalone (no own sentries yet): leave PEX=false and set
#      PERSISTENT_PEERS to the public persistent peers from
#      sovr-networks/mainnet/joining.md so the node always has peers to gossip
#      with (or pass --persistent-peers at install). Inbound 26656 is still not
#      required — the node dials out.
EOF
			emit PRIVATE_PEER_IDS ""
			emit UNCONDITIONAL_PEER_IDS ""
		fi
		if [ -n "$CORS_ORIGINS" ]; then
			emit CORS_ORIGINS "$CORS_ORIGINS"
		fi
	} >"$CONF_FILE"
	chmod 0644 "$CONF_FILE"
fi

# ---------------------------------------------------------------
# 7. OpenRC service
# ---------------------------------------------------------------
log "installing $INIT_FILE"
cp "$SCRIPT_DIR/sovrd.openrc" "$INIT_FILE"
chmod 0755 "$INIT_FILE"
rc-update add sovrd default >/dev/null 2>&1 || true

# ---------------------------------------------------------------
# 8. Start
# ---------------------------------------------------------------
current_ext="$(read_conf_var EXTERNAL_ADDRESS)"
# entrypoint.sh only fatals on a placeholder EXTERNAL_ADDRESS when the
# *effective* DEPLOYMENT_ENVIRONMENT (from /etc/conf.d/sovrd, which it sources)
# is exactly "mainnet". On a testnet/local install the node comes up fine
# without one, so refusing --start there would be misleading.
effective_env="$(read_conf_var DEPLOYMENT_ENVIRONMENT)"

# Restart if the caller asked (--start) or the node was already running when we
# stopped it for the file replacement above.
SHOULD_START=0
if [ "$DO_START" = 1 ] || [ "$SERVICE_WAS_RUNNING" = 1 ]; then
	SHOULD_START=1
fi

if [ "$effective_env" = "mainnet" ] && is_placeholder "$current_ext"; then
	if [ "$SHOULD_START" = 1 ]; then
		log "WARNING: EXTERNAL_ADDRESS in $CONF_FILE is empty or a placeholder; mainnet requires a real tcp://<ip>:26656, so not starting"
		SHOULD_START=0
	fi
fi

if [ "$SHOULD_START" = 1 ]; then
	log "starting sovrd (role=$ROLE)"
	if ! rc-service sovrd start; then
		# Tighten against OpenRC races ("already starting"): trust the
		# service state, not the start command's exit code, but fail loudly
		# if the node really did not come up.
		sleep 2
		if rc-service sovrd status >/dev/null 2>&1; then
			log "rc-service reported a warning but sovrd is running"
		else
			die "failed to start sovrd; see /var/log/sovrd.log"
		fi
	fi
	log "started; follow logs with: tail -f /var/log/sovrd.log"
else
	log "install complete; service not started"
	log "edit $CONF_FILE, then: rc-service sovrd start"
	log "logs: tail -f /var/log/sovrd.log"
fi

#!/bin/sh
# ============================================================
# alpine/install.sh — install a SOVR node (fullnode | rpc | validator) natively
# on Alpine Linux, from the PUBLIC sovr-networks release artifacts.
#
# Plain-config model (no container supervisor): it installs the static-musl
# `sovrd` and configures `config.toml` / `app.toml` directly, then runs the node
# under OpenRC. On a fresh data dir it first restores the published archive
# snapshot with `restore-snapshot.sh` (from-genesis sync is not viable on
# sovr-1), then starts `sovrd`.
#
# /bin/sh (busybox ash) compatible; the installer pulls in bash, which
# restore-snapshot.sh requires.
#
# Usage:
#   alpine/install.sh --version vX.Y.Z --role ROLE [options]
#
#   --version V              node release tag to install (e.g. v0.27.1). Required
#                            unless --from-dir supplies the assets.
#   --role ROLE              fullnode (default) | rpc | validator
#   --environment NAME       mainnet (default) | public-testnet | internal-testnet | local-dev
#   --chain-id ID            default: sovr-1
#   --moniker NAME           node moniker (default: sovr-node)
#   --external-address ADDR  public P2P address, tcp://<ip>:26656
#   --seeds LIST             comma-separated seed nodes
#   --persistent-peers LIST  comma-separated persistent peers
#   --private-peer-ids LIST  sentry topology: comma-separated private peer IDs
#   --unconditional-peer-ids LIST  sentry topology: unconditional peer IDs
#   --cors-origins JSON      CORS origins for the public API (rpc role)
#   --snapshot-baseurl URL   snapshot bucket (default: official mainnet bucket)
#   --snapshot-cosign-pubkey KEY  snapshot cosign public key (default: official mainnet)
#   --snapshot-anchors LIST  two distinct RPC anchors (default: rpc + rpc2)
#   --snapshot-network NAME  bucket path segment (default: --environment)
#   --release-url URL        base URL for sovrd/restore-snapshot.sh/checksums.txt
#                            (default: this version's sovr-networks release)
#   --genesis-url URL        canonical genesis URL (default: sovr-networks mainnet)
#   --from-dir DIR           use local assets instead of downloading (offline;
#                            must contain sovrd-<version>-linux-amd64-musl,
#                            restore-snapshot.sh, checksums.txt, genesis.json,
#                            genesis.sha256)
#   --start                  enable + start the service after install
#   -h, --help               this help
#
# Docs: mainnet-runbook/alpine-node-setup.md · alpine/README.md
# ============================================================
set -eu

ROLE="fullnode"
VERSION=""
FROM_DIR=""
RELEASE_URL=""
GENESIS_URL=""
ENVIRONMENT="mainnet"
CHAIN_ID="sovr-1"
MONIKER="sovr-node"
EXTERNAL_ADDRESS=""
SEEDS=""
PERSISTENT_PEERS=""
PRIVATE_PEER_IDS=""
UNCONDITIONAL_PEER_IDS=""
CORS_ORIGINS=""
DO_START=0
COSIGN_VERSION="v2.4.1"

# Official mainnet snapshot bootstrap (public; same values as deploy/validator).
MAINNET_SNAPSHOT_BASEURL="https://svrn-chain-snapshots-mainnet.nyc3.digitaloceanspaces.com/snapshots"
MAINNET_SNAPSHOT_COSIGN_PUBKEY="MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEv6XtLWy4H3IhmiLMUXEbRCeWswmXS8Y3xuNHo96Bwt2TbZSnwxnn4sHbl1/2cTH+b85pb/zGRIfURBad2ZOpfA=="
MAINNET_SNAPSHOT_ANCHORS="https://rpc.sovrchain.net,https://rpc2.sovrchain.net"
SNAPSHOT_BASEURL=""
SNAPSHOT_COSIGN_PUBKEY=""
SNAPSHOT_ANCHORS=""
SNAPSHOT_NETWORK=""

SOVR_USER="sovr"
SOVR_HOME="/home/sovr/.sovr"
CONF_FILE="/etc/conf.d/sovrd"
INIT_FILE="/etc/init.d/sovrd"
SOVRD_BIN="/usr/local/bin/sovrd"
RESTORE_BIN="/usr/local/bin/restore-snapshot.sh"
WORK="/var/tmp/sovr-install.$$"

log() { printf '[sovr-install] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

is_placeholder() {
	case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
	'' | *replace* | *required* | *todo* | *placeholder*) return 0 ;;
	*) return 1 ;;
	esac
}

# Single-quote a value for /etc/conf.d/sovrd (sourced as root).
emit() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"; }

fetch() { # url dest
	curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2" || die "download failed: $1"
}
# Same as fetch but returns non-zero instead of exiting, for optional assets
# where the caller has a fallback.
fetch_optional() { # url dest
	curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2"
}

usage() {
	cat >&2 <<'EOF'
alpine/install.sh — install a SOVR node on Alpine Linux

Usage: alpine/install.sh --version vX.Y.Z --role ROLE [options]

  --version V              node release tag (e.g. v0.27.1) — required unless --from-dir
  --role ROLE              fullnode (default) | rpc | validator
  --environment NAME       mainnet (default) | public-testnet | internal-testnet | local-dev
  --chain-id ID            default: sovr-1
  --moniker NAME           node moniker (default: sovr-node)
  --external-address ADDR  public P2P address, tcp://<ip>:26656
  --seeds LIST             comma-separated seed nodes
  --persistent-peers LIST  comma-separated persistent peers
  --private-peer-ids LIST  sentry topology: private peer IDs
  --unconditional-peer-ids LIST  sentry topology: unconditional peer IDs
  --cors-origins JSON      CORS origins for the public API (rpc role)
  --snapshot-baseurl URL   snapshot bucket (default: official mainnet bucket)
  --snapshot-cosign-pubkey KEY  snapshot cosign key (default: official mainnet)
  --snapshot-anchors LIST  two distinct RPC anchors (default: rpc + rpc2)
  --snapshot-network NAME  bucket path segment (default: --environment)
  --release-url URL        base URL for the release assets (default: sovr-networks release)
  --genesis-url URL        canonical genesis URL (default: sovr-networks mainnet)
  --from-dir DIR           use local assets instead of downloading (offline)
  --start                  enable + start the service after install
  -h, --help               this help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--version) VERSION="${2:-}"; [ -n "$VERSION" ] || die "--version requires a value"; shift 2 ;;
	--role) ROLE="${2:-}"; [ -n "$ROLE" ] || die "--role requires a value"; shift 2 ;;
	--environment) ENVIRONMENT="${2:-}"; [ -n "$ENVIRONMENT" ] || die "--environment requires a value"; shift 2 ;;
	--chain-id) CHAIN_ID="${2:-}"; [ -n "$CHAIN_ID" ] || die "--chain-id requires a value"; shift 2 ;;
	--moniker) MONIKER="${2:-}"; [ -n "$MONIKER" ] || die "--moniker requires a value"; shift 2 ;;
	--external-address) EXTERNAL_ADDRESS="${2:-}"; [ -n "$EXTERNAL_ADDRESS" ] || die "--external-address requires a value"; shift 2 ;;
	--seeds) SEEDS="${2:-}"; [ -n "$SEEDS" ] || die "--seeds requires a value"; shift 2 ;;
	--persistent-peers) PERSISTENT_PEERS="${2:-}"; [ -n "$PERSISTENT_PEERS" ] || die "--persistent-peers requires a value"; shift 2 ;;
	--private-peer-ids) PRIVATE_PEER_IDS="${2:-}"; [ -n "$PRIVATE_PEER_IDS" ] || die "--private-peer-ids requires a value"; shift 2 ;;
	--unconditional-peer-ids) UNCONDITIONAL_PEER_IDS="${2:-}"; [ -n "$UNCONDITIONAL_PEER_IDS" ] || die "--unconditional-peer-ids requires a value"; shift 2 ;;
	--cors-origins) CORS_ORIGINS="${2:-}"; [ -n "$CORS_ORIGINS" ] || die "--cors-origins requires a value"; shift 2 ;;
	--snapshot-baseurl) SNAPSHOT_BASEURL="${2:-}"; [ -n "$SNAPSHOT_BASEURL" ] || die "--snapshot-baseurl requires a value"; shift 2 ;;
	--snapshot-cosign-pubkey) SNAPSHOT_COSIGN_PUBKEY="${2:-}"; [ -n "$SNAPSHOT_COSIGN_PUBKEY" ] || die "--snapshot-cosign-pubkey requires a value"; shift 2 ;;
	--snapshot-anchors) SNAPSHOT_ANCHORS="${2:-}"; [ -n "$SNAPSHOT_ANCHORS" ] || die "--snapshot-anchors requires a value"; shift 2 ;;
	--snapshot-network) SNAPSHOT_NETWORK="${2:-}"; [ -n "$SNAPSHOT_NETWORK" ] || die "--snapshot-network requires a value"; shift 2 ;;
	--release-url) RELEASE_URL="${2:-}"; [ -n "$RELEASE_URL" ] || die "--release-url requires a value"; shift 2 ;;
	--genesis-url) GENESIS_URL="${2:-}"; [ -n "$GENESIS_URL" ] || die "--genesis-url requires a value"; shift 2 ;;
	--from-dir) FROM_DIR="${2:-}"; [ -n "$FROM_DIR" ] || die "--from-dir requires a value"; shift 2 ;;
	--start) DO_START=1; shift ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown flag: $1 (try --help)" ;;
	esac
done

case "$ROLE" in
fullnode | rpc | validator) ;;
*) die "invalid --role: $ROLE (expected fullnode|rpc|validator)" ;;
esac
case "$ENVIRONMENT" in
mainnet | public-testnet | internal-testnet | local-dev) ;;
*) die "invalid --environment: $ENVIRONMENT (expected mainnet|public-testnet|internal-testnet|local-dev)" ;;
esac
[ -n "$VERSION" ] || [ -n "$FROM_DIR" ] || die "one of --version or --from-dir is required"
[ "$(id -u)" = "0" ] || die "must run as root (try: doas \"$0\" --version \"$VERSION\")"

ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] || die "the published musl bundles are x86_64-only (got $ARCH); use the multi-arch container image instead"

# Snapshot defaults: official mainnet only. All-or-nothing, so a partial set
# cannot write a config that dies at first start.
if [ "$ENVIRONMENT" = "mainnet" ]; then
	[ -n "$SNAPSHOT_BASEURL" ] || SNAPSHOT_BASEURL="$MAINNET_SNAPSHOT_BASEURL"
	[ -n "$SNAPSHOT_COSIGN_PUBKEY" ] || SNAPSHOT_COSIGN_PUBKEY="$MAINNET_SNAPSHOT_COSIGN_PUBKEY"
	[ -n "$SNAPSHOT_ANCHORS" ] || SNAPSHOT_ANCHORS="$MAINNET_SNAPSHOT_ANCHORS"
fi
if [ -n "$SNAPSHOT_BASEURL$SNAPSHOT_COSIGN_PUBKEY$SNAPSHOT_ANCHORS" ]; then
	[ -n "$SNAPSHOT_BASEURL" ] || die "snapshot config incomplete: --snapshot-baseurl missing"
	[ -n "$SNAPSHOT_COSIGN_PUBKEY" ] || die "snapshot config incomplete: --snapshot-cosign-pubkey missing"
	[ -n "$SNAPSHOT_ANCHORS" ] || die "snapshot config incomplete: --snapshot-anchors missing"
	SNAPSHOT_NETWORK="${SNAPSHOT_NETWORK:-$ENVIRONMENT}"
fi
if [ -n "$EXTERNAL_ADDRESS" ] && is_placeholder "$EXTERNAL_ADDRESS"; then
	log "WARNING: EXTERNAL_ADDRESS '$EXTERNAL_ADDRESS' looks like a placeholder; peers cannot dial it"
fi
if [ "$ENVIRONMENT" = "mainnet" ] && is_placeholder "$EXTERNAL_ADDRESS"; then
	die "mainnet requires --external-address tcp://<public-ip>:26656"
fi

case "$ROLE" in
fullnode)
	PEX="true"
	RPC_LADDR="tcp://127.0.0.1:26657"
	API_ENABLE="true"
	API_ADDR="tcp://127.0.0.1:1317"
	GRPC_ADDR="127.0.0.1:9090"
	;;
rpc)
	PEX="true"
	RPC_LADDR="tcp://0.0.0.0:26657"
	API_ENABLE="true"
	API_ADDR="tcp://0.0.0.0:1317"
	GRPC_ADDR="0.0.0.0:9090"
	;;
validator)
	# Never expose RPC/API from a consensus node. Peering is closed to the
	# sentries named in PERSISTENT_PEERS/PRIVATE_PEER_IDS (see
	# mainnet-runbook/sentry-topology.md).
	PEX="false"
	RPC_LADDR="tcp://127.0.0.1:26657"
	API_ENABLE="false"
	API_ADDR="tcp://127.0.0.1:1317"
	GRPC_ADDR="127.0.0.1:9090"
	;;
esac

# ── 1. Packages ─────────────────────────────────────────────────────────────
log "installing packages (bash curl jq zstd openrc coreutils ca-certificates)"
apk add --no-cache bash ca-certificates curl jq zstd openrc coreutils file >/dev/null

# --cors-origins must be a JSON array of strings; it is written verbatim into
# config.toml [rpc] as a TOML array, so validate the shape here (jq is now
# installed) instead of shipping invalid TOML that only fails at `sovrd start`.
if [ -n "$CORS_ORIGINS" ]; then
	printf '%s' "$CORS_ORIGINS" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 \
		|| die "--cors-origins must be a JSON array of strings, e.g. '[\"https://a.example\"]'"
fi

# ── 2. Service user + home ──────────────────────────────────────────────────
if id "$SOVR_USER" >/dev/null 2>&1; then
	log "user $SOVR_USER already exists"
else
	# Prefer uid/gid 1000 (parity with the container image); fall back.
	if grep -q '^[^:]*:[^:]*:1000:' /etc/group; then addgroup -S "$SOVR_USER" >/dev/null; else addgroup -g 1000 -S "$SOVR_USER" >/dev/null; fi
	if grep -q '^[^:]*:[^:]*:1000:' /etc/passwd; then
		adduser -S -D -H -s /sbin/nologin -G "$SOVR_USER" "$SOVR_USER" >/dev/null
	else
		adduser -S -D -H -u 1000 -s /sbin/nologin -G "$SOVR_USER" "$SOVR_USER" >/dev/null
	fi
	log "created user $SOVR_USER"
fi
mkdir -p "$SOVR_HOME"
# Non-recursive: on an upgrade $SOVR_HOME/data can be 100 GB+ and walking
# it on every run would burn a coordinated halt window. Only the top dirs
# created here need ownership; data/ is the node's own.
chown "$SOVR_USER:$SOVR_USER" "/home/$SOVR_USER" "$SOVR_HOME"

# supervise-daemon opens its output/error log after dropping to the
# service user, which cannot create a file in root-owned /var/log.
touch /var/log/sovrd.log
chown "$SOVR_USER:$SOVR_USER" /var/log/sovrd.log
chmod 0644 /var/log/sovrd.log

# ── 3. Fetch + verify the release assets ────────────────────────────────────
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
[ -n "$RELEASE_URL" ] || RELEASE_URL="https://github.com/sovrn-tech/sovr-networks/releases/download/${VERSION}"
[ -n "$GENESIS_URL" ] || GENESIS_URL="https://raw.githubusercontent.com/sovrn-tech/sovr-networks/main/mainnet/genesis.json"

MUSL_BIN=""
if [ -n "$FROM_DIR" ]; then
	# --version is optional for air-gapped installs: infer the asset (and its
	# version segment) from the filename when it is omitted.
	if [ -z "$VERSION" ]; then
		for cand in "$FROM_DIR"/sovrd-*-linux-amd64-musl; do
			[ -f "$cand" ] || continue
			MUSL_BIN="$(basename "$cand")"
			break
		done
		[ -n "$MUSL_BIN" ] || die "--from-dir has no sovrd-<version>-linux-amd64-musl asset (and --version was omitted)"
	else
		MUSL_BIN="sovrd-${VERSION}-linux-amd64-musl"
	fi
	log "using local assets from $FROM_DIR ($MUSL_BIN)"
	for f in "$MUSL_BIN" restore-snapshot.sh checksums.txt genesis.json genesis.sha256; do
		[ -f "$FROM_DIR/$f" ] || die "--from-dir is missing $f"
		cp "$FROM_DIR/$f" "$WORK/$f"
	done
else
	log "fetching release assets ($VERSION)"
	MUSL_BIN="sovrd-${VERSION}-linux-amd64-musl"
	fetch "$RELEASE_URL/$MUSL_BIN" "$WORK/$MUSL_BIN"
	fetch "$RELEASE_URL/restore-snapshot.sh" "$WORK/restore-snapshot.sh"
	fetch "$RELEASE_URL/checksums.txt" "$WORK/checksums.txt"
	fetch "$GENESIS_URL" "$WORK/genesis.json"
	# genesis.sha256 is published beside genesis.json (raw repo) or on the
	# release; try the repo-relative path first, then fall back.
	if ! fetch_optional "${GENESIS_URL%.json}.sha256" "$WORK/genesis.sha256"; then
		fetch "$RELEASE_URL/genesis.sha256" "$WORK/genesis.sha256"
	fi
fi

# Integrity model: HTTPS transport to the sovrn-tech GitHub release plus a
# sha256sum self-consistency check of checksums.txt (and genesis.sha256). There
# is NO signature on the manifest — a deliberate change from the old (private)
# bundle model, which required a GPG-signed checksums.txt.asc against a pinned,
# out-of-band key. Cosign-signing the published release assets is tracked in
# #453 (#446 covers images); until then this trusts the sovr-networks release
# channel over TLS. Documented in mainnet-runbook/alpine-node-setup.md.
log "verifying $MUSL_BIN against checksums.txt"
( cd "$WORK" && grep -E "  ${MUSL_BIN}\$|  restore-snapshot.sh\$" checksums.txt >.want \
	&& sha256sum -c .want >/dev/null ) || die "checksums.txt verification failed"
log "verifying genesis.json against genesis.sha256"
( cd "$WORK" && sha256sum -c genesis.sha256 >/dev/null ) || die "genesis sha256 mismatch"
bin_desc="$(file "$WORK/$MUSL_BIN" 2>/dev/null)"
case "$bin_desc" in
*ELF*x86-64*) ;;
*) die "$MUSL_BIN is not an x86-64 ELF: $bin_desc" ;;
esac
case "$bin_desc" in
*"statically linked"*) ;;
*) die "$MUSL_BIN is not statically linked (the glibc sovrd will not run on Alpine): $bin_desc" ;;
esac

# ── 4. Install binaries ─────────────────────────────────────────────────────
# Stop a running node before replacing its live files: supervise-daemon
# (respawn_max=0) can otherwise respawn mid-copy and run a truncated binary.
SERVICE_WAS_RUNNING=0
if rc-service sovrd status >/dev/null 2>&1; then
	SERVICE_WAS_RUNNING=1
	log "stopping running sovrd before replacing its files"
	rc-service sovrd stop >/dev/null 2>&1 \
		|| die "failed to stop running sovrd; refusing to replace live files"
	rc-service sovrd status >/dev/null 2>&1 \
		&& die "sovrd still running after stop; refusing to replace live files"
fi

# Write-then-rename so an interrupted copy can never leave a truncated binary.
install_atomic() { # src dest mode
	install -m "$3" "$1" "$2.new.$$" || die "could not stage $2"
	mv -f "$2.new.$$" "$2" || die "could not install $2"
}

log "installing $MUSL_BIN -> $SOVRD_BIN"
install_atomic "$WORK/$MUSL_BIN" "$SOVRD_BIN" 0755
log "installing restore-snapshot.sh -> $RESTORE_BIN"
install_atomic "$WORK/restore-snapshot.sh" "$RESTORE_BIN" 0755

# ── 5. Seed the node home (init + genesis) ──────────────────────────────────
if [ -f "$SOVR_HOME/config/config.toml" ]; then
	log "node home already initialised; leaving config/ untouched"
else
	log "initialising node home (sovrd init)"
	# Pass values as positional args, never string-interpolated: a moniker or
	# chain-id containing a quote would otherwise break out of the `sh -c`
	# string and execute as the service user.
	# shellcheck disable=SC2016  # $0/$1.. are expanded by the inner sh, by design
	su -s /bin/sh -c 'SOVRD_HOME="$0" exec "$1" init "$2" --chain-id "$3" --home "$0"' -- \
		"$SOVR_USER" "$SOVR_HOME" "$SOVRD_BIN" "$MONIKER" "$CHAIN_ID" >/dev/null 2>&1 \
		|| die "sovrd init failed"
fi
install -m 0644 "$WORK/genesis.json" "$SOVR_HOME/config/genesis.json"

# ── 6. Configure config.toml / app.toml (plain config) ──────────────────────
# set_section FILE SECTION KEY VALUE(quoted) ; set_root FILE KEY VALUE(quoted)
set_section() {
	sed -i "/^\[$2\]/,/^\[/ s|^$3 *=.*|$3 = $4|" "$1"
}
set_root() {
	sed -i "s|^$2 *=.*|$2 = $3|" "$1"
}
cfg="$SOVR_HOME/config/config.toml"
app="$SOVR_HOME/config/app.toml"
log "applying node config (role=$ROLE)"
set_section "$cfg" p2p seeds "\"$SEEDS\""
set_section "$cfg" p2p persistent_peers "\"$PERSISTENT_PEERS\""
set_section "$cfg" p2p private_peer_ids "\"$PRIVATE_PEER_IDS\""
set_section "$cfg" p2p unconditional_peer_ids "\"$UNCONDITIONAL_PEER_IDS\""
set_section "$cfg" p2p pex "\"$PEX\""
set_section "$cfg" p2p external_address "\"$EXTERNAL_ADDRESS\""
set_section "$cfg" rpc laddr "\"$RPC_LADDR\""
set_root "$app" minimum-gas-prices "\"0.001usovr\""
set_root "$app" pruning "\"default\""
set_section "$app" api enable "\"$API_ENABLE\""
set_section "$app" api address "\"$API_ADDR\""
set_section "$app" grpc address "\"$GRPC_ADDR\""
if [ -n "$CORS_ORIGINS" ]; then
	# cors_allowed_origins is a CometBFT config.toml [rpc] key (a TOML string
	# array), NOT an app.toml [api] key. Write the JSON array verbatim.
	set_section "$cfg" rpc cors_allowed_origins "$CORS_ORIGINS"
fi
# config/ was just rewritten by root (install + sed), so re-own it; do NOT
# walk data/ (100 GB+ on a live validator). $SOVR_HOME itself is non-recursive.
chown -R "$SOVR_USER:$SOVR_USER" "$SOVR_HOME/config"
chown "$SOVR_USER:$SOVR_USER" "$SOVR_HOME"

# ── 7. Service config (/etc/conf.d/sovrd) — restore-helper env ──────────────
if [ -f "$CONF_FILE" ]; then
	log "$CONF_FILE exists; leaving it untouched"
else
	log "writing $CONF_FILE"
	{
		cat <<EOF
# /etc/conf.d/sovrd — generated by alpine/install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Consumed by /etc/init.d/sovrd: it runs restore-snapshot.sh once (fresh data
# dir) with these vars, then starts sovrd. Values are single-quoted because the
# service sources this file as root.
EOF
		emit SOVR_HOME "$SOVR_HOME"
		emit CHAIN_ID "$CHAIN_ID"
		emit DEPLOYMENT_ENVIRONMENT "$ENVIRONMENT"
		if [ -n "$SNAPSHOT_BASEURL" ]; then
			cat <<'EOF'
# Snapshot bootstrap (fresh node). No-op once data/ exists.
EOF
			emit SNAPSHOT_RESTORE true
			emit SNAPSHOT_BASEURL "$SNAPSHOT_BASEURL"
			emit SNAPSHOT_NETWORK "$SNAPSHOT_NETWORK"
			emit SNAPSHOT_COSIGN_PUBKEY "$SNAPSHOT_COSIGN_PUBKEY"
			emit SNAPSHOT_ANCHORS "$SNAPSHOT_ANCHORS"
			emit SNAPSHOT_COSIGN_VERSION "$COSIGN_VERSION"
		fi
	} >"$CONF_FILE"
	chmod 0644 "$CONF_FILE"
fi

# ── 8. OpenRC service ───────────────────────────────────────────────────────
log "installing $INIT_FILE"
install_atomic "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/sovrd.openrc" "$INIT_FILE" 0755
rc-update add sovrd default >/dev/null 2>&1 || true

# ── 9. Start ────────────────────────────────────────────────────────────────
if [ "$DO_START" = 1 ] || [ "$SERVICE_WAS_RUNNING" = 1 ]; then
	log "starting sovrd"
	rc-service sovrd start || die "rc-service sovrd start failed"
	log "started; follow logs with: tail -f /var/log/sovrd.log"
else
	log "installed. Review /etc/conf.d/sovrd and $SOVR_HOME/config, then: rc-service sovrd start"
fi

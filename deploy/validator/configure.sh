#!/usr/bin/env bash
# configure.sh — one-shot setup for a Sovren mainnet (sovr-1) validator/full node.
#
# Run this once in the deploy/validator directory, answer a couple of prompts,
# then `docker compose up -d`. It:
#   - writes .env from .env.example (official values are already filled in),
#   - sets your external address (auto-detected, with a load-balancer option),
#   - sets your moniker,
#   - stages + verifies the canonical genesis.json,
#   - creates the launch.env / checksums.txt the mainnet entrypoint requires,
#   - makes ./data writable by the container's user (uid 1000).
#
# It does NOT generate keys or stake — that happens on first start / manually
# (see README §4, §7). Re-running it re-prompts and rewrites .env.
set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f .env.example ] || die "run this from the deploy/validator directory (.env.example not found)"

# Canonical genesis source, used only if a local copy is not found next to this dir.
GENESIS_URL="${GENESIS_URL:-https://raw.githubusercontent.com/sovrn-tech/sovr-networks/main/mainnet/genesis.json}"

# --- set KEY=VALUE in .env (replace the whole line, or append) ---------------
set_kv() {
	local key="$1" val="$2" tmp
	tmp="$(mktemp)"
	awk -v k="$key" -v v="$val" '
		$0 ~ "^"k"=" { print k"="v; found=1; next }
		{ print }
		END { if (!found) print k"="v }
	' .env >"$tmp" && mv "$tmp" .env
}
get_kv() { sed -n "s/^$1=//p" .env | head -n1; }

# --- 0. .env ----------------------------------------------------------------
if [ -f .env ]; then
	read -r -p ".env already exists. Overwrite it? [y/N] " ans
	case "$ans" in y | Y) ;; *) die "keeping existing .env; edit it by hand or remove it to reconfigure" ;; esac
fi
cp .env.example .env
say "Wrote .env from .env.example (official values pre-filled)."

# --- 1. external address (OPTIONAL — inbound P2P is not required) ------------
say ""
say "Inbound P2P is OPTIONAL. A NAT'd, outbound-only validator signs and earns"
say "fine. Set an external address only if you WANT inbound peers to dial you"
say "(and you've opened/forwarded TCP 26656)."
detected=""
for svc in https://api.ipify.org https://checkip.amazonaws.com https://ifconfig.me; do
	detected="$(curl -fsS -m 8 "$svc" 2>/dev/null | tr -d '[:space:]')" && [ -n "$detected" ] && break
	detected=""
done
if [ -n "$detected" ]; then
	echo "  Detected public IP: $detected"
	echo "  - Enter to accept inbound on it, or type a different IP/DNS (e.g. an LB)."
	echo "  - Type 'none' for outbound-only (no inbound peers)."
	read -r -p "  External address [$detected, or 'none']: " ext
	ext="${ext:-$detected}"
	[ "$ext" = "none" ] && ext=""
else
	echo "  No public IP auto-detected."
	read -r -p "  External IP/DNS for inbound peers (blank = outbound-only): " ext
fi
if [ -n "$ext" ]; then
	case "$ext" in
		tcp://*) : ;;                       # already a full multiaddr
		*:*[0-9]) ext="tcp://$ext" ;;       # host:port given
		*) ext="tcp://$ext:26656" ;;        # bare host/IP
	esac
	set_kv EXTERNAL_ADDRESS "$ext"
	set_kv P2P_PORT_PUBLISH ""              # default: publish 26656 on all interfaces
	echo "  EXTERNAL_ADDRESS=$ext (inbound enabled)"
else
	set_kv EXTERNAL_ADDRESS ""
	set_kv P2P_PORT_PUBLISH "127.0.0.1:26656:26656"   # bind loopback: outbound-only
	echo "  outbound-only: EXTERNAL_ADDRESS blank, P2P bound to loopback (no inbound)."
fi

# --- 2. moniker -------------------------------------------------------------
say ""
read -r -p "Validator moniker (public display name): " mon
[ -n "$mon" ] || die "a moniker is required"
set_kv MONIKER "$mon"

# --- 3. snapshot cross-check anchors (pre-filled; optional override) ---------
say ""
echo "Snapshot restore cross-checks the signed snapshot against two RPC anchors."
echo "Both public anchors (rpc + rpc2) are pre-filled, so this works out of the box."
echo "They currently share a backend, so for a genuinely INDEPENDENT check you can"
echo "supply your own already-synced node / a trusted third-party sovr-1 RPC as the"
echo "second anchor (optional)."
read -r -p "  Your own second anchor (blank = keep the pre-filled rpc + rpc2): " anchor2
if [ -n "$anchor2" ]; then
	set_kv SNAPSHOT_ANCHORS "https://rpc.sovrchain.net,$anchor2"
	echo "  SNAPSHOT_ANCHORS = rpc + your anchor."
else
	echo "  keeping pre-filled SNAPSHOT_ANCHORS (rpc + rpc2)."
fi

# --- 4. stage + verify genesis ----------------------------------------------
say ""
say "Staging genesis.json…"
mkdir -p release data
gsha="$(get_kv GENESIS_SHA256)"
case "$gsha" in "" | REPLACE*) die "GENESIS_SHA256 is not set in .env (expected the official pre-filled value)" ;; esac
if [ ! -f release/genesis.json ]; then
	local_src=""
	for c in ../mainnet/genesis.json ../../mainnet/genesis.json ./mainnet/genesis.json; do
		[ -f "$c" ] && { local_src="$c"; break; }
	done
	if [ -n "$local_src" ]; then
		cp "$local_src" release/genesis.json
		echo "  Copied genesis from $local_src"
	else
		echo "  Downloading genesis from $GENESIS_URL"
		curl -fSL -m 120 "$GENESIS_URL" -o release/genesis.json || die "genesis download failed"
	fi
fi
if command -v sha256sum >/dev/null 2>&1; then
	echo "${gsha}  release/genesis.json" | sha256sum -c - >/dev/null || die "genesis sha256 mismatch — refusing (expected $gsha)"
elif command -v shasum >/dev/null 2>&1; then
	echo "${gsha}  release/genesis.json" | shasum -a 256 -c - >/dev/null || die "genesis sha256 mismatch — refusing (expected $gsha)"
else
	warn "  no sha256 tool found; skipping genesis verification (install coreutils)"
fi
echo "  genesis.json staged + verified (sha256 $gsha)"

# --- 5. launch.env + checksums.txt (entrypoint mainnet gate) ----------------
# launch.env is a presence/integrity marker the mainnet entrypoint requires; it
# is never read.
printf 'CHAIN_ID=%s\n' "$(get_kv CHAIN_ID)" >release/launch.env
( cd release && { command -v sha256sum >/dev/null 2>&1 && sha256sum launch.env || shasum -a 256 launch.env; } >checksums.txt )
echo "  release/launch.env + checksums.txt created"

# --- 5b. size memory to this box's RAM (prevents OOM -> jail + slash) --------
# GOMEMLIMIT must fit physical RAM or Go grows past it and the kernel OOM-kills
# sovrd; on mainnet's tight downtime window that jails and slashes you.
say ""
ram_kb=$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
if [ "${ram_kb:-0}" -gt 0 ]; then
	ram_mib=$((ram_kb / 1024))
	set_kv GOMEMLIMIT "$((ram_mib * 75 / 100))MiB"     # Go heap soft cap ~75% RAM
	set_kv MEMORY_LIMIT "$((ram_mib * 85 / 100))m"     # container cap ~85% RAM
	echo "  sized for ${ram_mib} MiB RAM: GOMEMLIMIT=$(get_kv GOMEMLIMIT) MEMORY_LIMIT=$(get_kv MEMORY_LIMIT)"
	sw_kb=$(awk '/^SwapTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
	if [ "$ram_mib" -lt 4096 ]; then
		warn "  < 4 GiB RAM (below the recommended minimum) — a validator is memory-tight"
		warn "  here; an OOM kill on mainnet jails+slashes you. Add swap and/or resize:"
		warn "    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile \\"
		warn "      && sudo mkswap /swapfile && sudo swapon /swapfile"
	elif [ "${sw_kb:-0}" -eq 0 ]; then
		warn "  no swap configured — a small swapfile is a useful OOM cushion."
	fi
else
	set_kv GOMEMLIMIT "1200MiB"     # conservative safe floor when RAM is unknown
	set_kv MEMORY_LIMIT "1600m"
	warn "  couldn't read /proc/meminfo — set a CONSERVATIVE GOMEMLIMIT=1200MiB /"
	warn "  MEMORY_LIMIT=1600m. RAISE both per the .env.example table for your box."
fi

# --- 6. data dir ownership (container runs as uid 1000) ---------------------
say ""
home_dir="$(get_kv HOST_SOVR_HOME)"; home_dir="${home_dir:-./data}"
cur_uid="$(stat -c %u "$home_dir" 2>/dev/null || stat -f %u "$home_dir" 2>/dev/null || echo -1)"
if [ "$cur_uid" != "1000" ]; then
	if chown -R 1000:1000 "$home_dir" 2>/dev/null; then
		echo "  chowned $home_dir to uid 1000"
	elif command -v sudo >/dev/null 2>&1 && sudo chown -R 1000:1000 "$home_dir"; then
		echo "  chowned $home_dir to uid 1000 (sudo)"
	else
		warn "  could not chown $home_dir — the container runs as uid 1000 and needs to"
		warn "  write it. Run:  sudo chown -R 1000:1000 $home_dir"
	fi
fi

# --- done -------------------------------------------------------------------
say ""
say "Configured. Review .env, then start the node:"
echo "    docker compose up -d && docker compose logs -f"
echo ""
echo "Then: back up ./data/config/priv_validator_key.json (your consensus key),"
echo "wait for catching_up=false, and only then create-validator (README §4–§7)."

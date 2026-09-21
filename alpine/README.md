# SOVR on Alpine Linux

Native (non-container) deployment profile for SOVR nodes on Alpine. It runs
the **static musl** `sovrd` (built by `Dockerfile.alpine` /
`scripts/build-release-bundle.sh --static-musl`) under **OpenRC**, reusing
the container image's supervisor (`entrypoint.sh`) so the configuration
interface is byte-for-byte the same as a container deployment: every
`/etc/conf.d/sovrd` variable is a `docker/entrypoint.sh` variable.

Full procedure, validator specifics, and troubleshooting:
**[`mainnet-runbook/alpine-node-setup.md`](../mainnet-runbook/alpine-node-setup.md)**.

## Roles

| Role | What it is | Network exposure |
|---|---|---|
| `fullnode` | Syncing full node / sentry; no public API | P2P 26656 only |
| `rpc` | Public RPC/REST/gRPC full node (wallet/explorer backend) | 26656, 26657, 1317, 9090 |
| `validator` | Consensus node behind sentries | **No public RPC**; P2P reachable only by its sentries |

## Quickstart

```sh
# 0. Get the installer from the tagged repo checkout (it verifies the tarball,
#    so it is not shipped inside it).
git clone --branch vX.Y.Z https://github.com/parler-tech/sbn && cd sbn

# 1. Get a release bundle and extract it. The bundle must contain
#    sovrd-linux-amd64-musl (build with `scripts/build-release-bundle.sh
#    --static-musl`, or download a published release tarball), plus
#    checksums.txt and its checksums.txt.asc signature.
tar -xzf ../release-bundle-vX.Y.Z.tar.gz

# 2. Install (as root). On mainnet --release-pubkey (the out-of-band
#    release-captain public key) is required so the checksum manifest is
#    authenticated, not just internally consistent. Idempotent: re-run with
#    a newer bundle to upgrade; node data and /etc/conf.d/sovrd are untouched.
alpine/install.sh \
  --bundle ./vX.Y.Z \
  --role fullnode \
  --release-pubkey ./release-captain.asc \
  --external-address "tcp://203.0.113.10:26656"

# 3. Confirm /etc/conf.d/sovrd, then start.
rc-service sovrd start
tail -f /var/log/sovrd.log
```

Public RPC node:

```sh
alpine/install.sh --bundle ./vX.Y.Z --role rpc \
  --release-pubkey ./release-captain.asc \
  --external-address "tcp://203.0.113.10:26656" \
  --cors-origins '["https://sovrscan.com","https://api.sovrchain.net"]' \
  --start
```

Validator (install, sync, then bond — do **not** start it as a validator
until it is caught up and wired to its sentries):

```sh
alpine/install.sh --bundle ./vX.Y.Z --role validator \
  --release-pubkey ./release-captain.asc \
  --external-address "tcp://<validator-ip>:26656"
# On mainnet the installer also fills in the signed-snapshot bootstrap
# (SNAPSHOT_RESTORE/BASEURL/COSIGN_PUBKEY/ANCHORS) — a fresh sovr-1 node MUST
# restore a snapshot; from-genesis sync is not viable.
#
# Peering, pick one in /etc/conf.d/sovrd:
#   - sentry topology: PERSISTENT_PEERS/PRIVATE_PEER_IDS/UNCONDITIONAL_PEER_IDS
#     -> your two sentry node IDs (sentry-topology.md);
#   - standalone (no own sentries): PERSISTENT_PEERS -> the public persistent
#     peers from sovr-networks/mainnet/joining.md.
rc-service sovrd start
```

`--release-pubkey` also accepts an `https://` URL (the public key is published
as a public artifact), so a from-scratch install needs no out-of-band file.
Prefer a key origin **different** from the bundle's host — otherwise a single
compromised origin could serve both the key and the payload it authenticates.

## Layout

```
/usr/local/bin/sovrd                        # symlink -> sovrd-linux-amd64-musl
/usr/local/bin/sovrd-linux-amd64-musl       # static musl binary
/usr/local/bin/entrypoint.sh                # container supervisor (shared)
/usr/local/bin/verify-release-bundle.sh
/etc/sovr/release/                          # staged release bundle (genesis, checksums, launch.env, seeds)
/etc/conf.d/sovrd                           # node config (entrypoint env vars)
/etc/init.d/sovrd                           # OpenRC service (supervise-daemon)
/var/log/sovrd.log                          # service output
/home/sovr/.sovr                            # node home: config, data, keys
```

## Upgrades

At the coordinated halt, stop the supervised process, install the new bundle,
then start it again:

```sh
rc-service sovrd stop
alpine/install.sh --bundle ./vNEXT --release-pubkey ./release-captain.asc
rc-service sovrd start
```

Stopping first avoids replacing a live binary/`entrypoint.sh` while
`supervise-daemon` can respawn (`chain-upgrades.md` §3.1). `install.sh` also
stops a running service before replacing files and restarts it afterwards, but
the coordinated stop/start above is the procedure to follow. The entrypoint
re-verifies the new binary against the new bundle's `checksums.txt` on every
start. For fleet-wide halt timing, see
[`mainnet-runbook/chain-upgrades.md`](../mainnet-runbook/chain-upgrades.md).

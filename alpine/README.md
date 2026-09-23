# SOVR on Alpine Linux

Native (non-container) deployment profile for SOVR nodes on Alpine. It installs
the **static-musl** `sovrd` from the public `sovrn-tech/sovr-networks` release,
configures `config.toml` / `app.toml` directly, and runs it under **OpenRC** —
no container, no supervisor. On a fresh data dir it first restores the published
archive snapshot with `restore-snapshot.sh` (from-genesis sync is not viable on
`sovr-1`), then starts the node.

Full procedure, validator specifics, and troubleshooting:
**[`mainnet-runbook/alpine-node-setup.md`](../mainnet-runbook/alpine-node-setup.md)**.

> **Two methods, coexisting.** The container method — `deploy/validator/`
> (docker-compose) and the `ghcr.io/sovrn-tech/sovrd` image, supervised by
> `docker/entrypoint.sh` — is **unchanged and remains the fleet default**. This
> native Alpine profile is an independent second method for hosts that don't run
> containers. They do not share a node home: use one or the other for a given
> data directory.

## Roles

| Role | What it is | Network exposure |
|---|---|---|
| `fullnode` | Syncing full node / sentry; no public API | P2P 26656 only |
| `rpc` | Public RPC/REST/gRPC full node (wallet/explorer backend) | 26656, 26657, 1317, 9090 |
| `validator` | Consensus node behind sentries | **No public RPC**; P2P reachable only by its sentries |

## Quickstart

```sh
# 0. The installer ships with the network metadata (it is what fetches +
#    verifies the release assets), so grab it from sovr-networks.
git clone https://github.com/sovrn-tech/sovr-networks && cd sovr-networks

# 1. Install (as root). --version selects the node release; the installer
#    fetches sovrd-<version>-linux-amd64-musl, restore-snapshot.sh and
#    checksums.txt from that release, plus the canonical mainnet genesis, and
#    verifies both. Idempotent: re-run with a newer --version to upgrade; node
#    data and /etc/conf.d/sovrd are untouched.
alpine/install.sh --version v0.27.1 --role fullnode \
  --external-address "tcp://203.0.113.10:26656"

# 2. Review /etc/conf.d/sovrd and ~/.sovr/config, then start.
rc-service sovrd start
tail -f /var/log/sovrd.log
```

Public RPC node:

```sh
alpine/install.sh --version v0.27.1 --role rpc \
  --external-address "tcp://203.0.113.10:26656" \
  --cors-origins '["https://sovrscan.com","https://api.sovrchain.net"]' \
  --start
```

Validator (install, sync, then bond — do **not** bond until it is caught up and
wired to its sentries):

```sh
alpine/install.sh --version v0.27.1 --role validator \
  --external-address "tcp://<validator-ip>:26656" \
  --persistent-peers  "<sentry1-nodeid>@<sentry1>:26656,<sentry2-nodeid>@<sentry2>:26656" \
  --private-peer-ids  "<sentry1-nodeid>,<sentry2-nodeid>" \
  --unconditional-peer-ids "<sentry1-nodeid>,<sentry2-nodeid>"
rc-service sovrd start
```

`--role validator` sets `pex = false` and binds RPC/API to loopback. On mainnet
the installer also fills in the signed-snapshot bootstrap (`SNAPSHOT_RESTORE` /
`BASEURL` / `COSIGN_PUBKEY` / `ANCHORS`) — a fresh `sovr-1` node must restore a
snapshot. Without your own sentries yet, point `--persistent-peers` at the
public persistent peers from [`mainnet/joining.md`](../mainnet/joining.md) §4.

**Air-gapped / offline:** pass `--from-dir DIR` with the release assets
(`sovrd-<version>-linux-amd64-musl`, `restore-snapshot.sh`, `checksums.txt`,
`genesis.json`, `genesis.sha256`) instead of downloading.

**Integrity:** the assets are verified against the release's `checksums.txt`
(HTTPS + sha256); there is **no signature** on that manifest yet — cosign
signing the published release assets is tracked in
[#453](https://github.com/parler-tech/sbn/issues/453).

## Layout

```
/usr/local/bin/sovrd                # static musl binary (from the release)
/usr/local/bin/restore-snapshot.sh  # snapshot bootstrap (idempotent, fail-closed)
/usr/local/bin/cosign               # fetched on first restore if absent
/etc/conf.d/sovrd                   # service + snapshot-bootstrap env (OpenRC)
/etc/init.d/sovrd                   # OpenRC service (supervise-daemon)
/var/log/sovrd.log                  # service output
/home/sovr/.sovr                    # node home: config.toml/app.toml, data, keys
```

The node's own configuration is `config.toml` / `app.toml` under
`/home/sovr/.sovr/config` — the installer seeds peering, listeners, gas and
pruning; edit those files directly for anything else.

## Upgrades

At the coordinated halt, stop the node, install the new release, then start it:

```sh
rc-service sovrd stop
alpine/install.sh --version vNEXT
rc-service sovrd start
```

Stopping first avoids replacing a live binary while `supervise-daemon` can
respawn (`chain-upgrades.md` §3.1). For fleet-wide halt timing, see
[`mainnet-runbook/chain-upgrades.md`](../mainnet-runbook/chain-upgrades.md).

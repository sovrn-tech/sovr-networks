# Joining Sovren Mainnet (`sovr-1`)

How to connect a node to `sovr-1`. Chain identity, versions, fees, and ports
are in [`chain-params.md`](./chain-params.md).

## 1. Node software

Node software is published on this repository's
[releases page](https://github.com/sovrn-tech/sovr-networks/releases). The current mainnet release
is [v0.23.0](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.23.0):

| Artifact | Notes |
|---|---|
| `sovrd-v0.23.0-linux-amd64` | The chain daemon. linux/amd64, glibc ≥ 2.36 |
| `libwasmvm.x86_64.so` | **Required** — `sovrd` links against it; install on the library path |
| `checksums.txt` | SHA-256 of both; verify before running |

Container image (the **same build** — the release binary was extracted from this image, not
rebuilt):

```
ghcr.io/sovrn-tech/sovrd:v0.23.0
digest: sha256:2d2fbb8f48986b5ced9ca01ad515b41e5c34844ef43ba77ceb252ab938ecb396
```

**Pin the digest, not the tag** — it is the exact image every Sovren mainnet node runs, so what you
execute is byte-identical to what the network validates with.

Do not run binaries or images obtained from any other source claiming to be Sovren node software —
this repository's releases page and the `ghcr.io/sovrn-tech` registry are the only official
channels.

## 2. Initialize the node home

```
sovrd init <your-moniker> --chain-id sovr-1
```

This creates `$HOME/.sovr/config/` (the genesis copy in the next step
overwrites the freshly generated placeholder genesis).

## 3. Genesis

Use the canonical genesis file from this directory and verify it first:

```sh
shasum -a 256 -c genesis.sha256   # must print: genesis.json: OK
cp genesis.json $HOME/.sovr/config/genesis.json
```

Expected SHA-256:
`04529695e7ccfe32fcf3bc8031c343056d27cbe4aa3b3046027e27065bb9a855`

## 4. Peers

All Sovren bootstrap peers are published as DNS names; Sovren never publishes
raw-IP peer strings.

**Seeds** (`p2p.seeds` in `config.toml`):

```
381af5e4d0d5e24af3bb4d506b06081399622d01@seed1.mainnet.sovrchain.net:32000,68d9058a5dd7062d72d917ae8f2a2e30101b5a74@seed2.mainnet.sovrchain.net:32001
```

**Persistent peers** (`p2p.persistent_peers` in `config.toml`), optional if
seeds are configured:

```
24ebffde61a15df70687df28d9d9259dcb4beb64@sentry1a.mainnet.sovrchain.net:32200,6ee852fb24a636109f49a6b7184c8533d60d71ae@sentry1b.mainnet.sovrchain.net:32201,f9f287196905f574334d87370ee28369814a01eb@sentry2a.mainnet.sovrchain.net:32220,d41608b237019c09281c9542bbe90532b03b65ea@sentry2b.mainnet.sovrchain.net:32221,b8c805f050e090edf52fcd5169e239826ffb21a5@sentry3a.mainnet.sovrchain.net:32240,a49544b198f062c893b849a37389a227a51b40d4@sentry3b.mainnet.sovrchain.net:32241
```

## 5. Gas price

Set the node's minimum gas price at or above the network floor:

```toml
# app.toml
minimum-gas-prices = "0.001usovr"
```

Clients should submit at the recommended `0.025usovr` (see
[`chain-params.md`](./chain-params.md)).

## 6. State sync

Sovren does not yet publish state-sync snapshots or trusted-height/hash
parameters. This section gains the state-sync RPC servers and trust
parameters when that service is published; until then, new nodes sync from
genesis.

## 7. Public endpoints

| Kind | URL |
|---|---|
| RPC | https://rpc.sovrchain.net |
| REST | https://api.sovrchain.net |

These endpoints carry **browser-grade per-IP rate limits**: they are sized
for wallets, explorers, and light integration use — not for production data
planes, custody-critical operations, or bulk indexing. For those workloads,
run your own node using this guide. Live endpoint health is published at
https://sovrscan.com/node-health.

---

*Source note: peers, endpoints, and checksums verified by the Sovren team
against the live network and the v0.23.0 release manifest, 2026-08-10.*

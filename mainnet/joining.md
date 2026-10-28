# Joining Sovren Mainnet (`sovr-1`)

How to connect a node to `sovr-1`. Chain identity, versions, fees, and ports
are in [`chain-params.md`](./chain-params.md).

## 1. Node software

Node software is published on this repository's
[releases page](https://github.com/sovrn-tech/sovr-networks/releases). The current mainnet release
is [v0.27.4](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.27.4):

| Artifact | Notes |
|---|---|
| `sovrd-v0.27.4-linux-amd64` | The chain daemon. linux/amd64, glibc ≥ 2.36 |
| `libwasmvm.x86_64.so` | **Required** — `sovrd` links against it; install on the library path |
| `checksums.txt` | SHA-256 of both; verify before running |

Container image (the **same build** — the release binary was extracted from this image, not
rebuilt):

```
ghcr.io/sovrn-tech/sovrd:v0.27.4
digest:       sha256:b7490a32529bae1b164ddc600ed454ff3cb210dab03d349cdf1e95d827c6b756
amd64 child:  sha256:b5009d664ca5e45b98fa056cf13ba1b3a871ada9048a20881fc9841b7a15d67a
```

**Pin the digest, not the tag** — it is the exact image every Sovren mainnet node runs, so what you
execute is byte-identical to what the network validates with. `digest` is the multi-arch index:
pin it, and verify it with `cosign verify --key cosign.pub ghcr.io/sovrn-tech/sovrd@<digest>`
([`cosign.pub`](../cosign.pub)). The `amd64 child` line (the linux/amd64 image in the index) is for reference only: it is the image
the release binary was extracted from, and it carries no signature of its own.

Do not run binaries or images obtained from any other source claiming to be Sovren node software —
this repository's releases page and the `ghcr.io/sovrn-tech` registry are the only official
channels.

### Fork at height 2633375 (v0.27.4, not a governance upgrade)

`sovr-1` halted at height 2633375. v0.27.4 forks the chain at that height to roll back gov
proposal 16 (see [CHANGELOG](../CHANGELOG.md)).

- **This is not a governance `x/upgrade` plan.** The v0.27.4 binary schedules the
  `v0.27.4-emission-rollback` plan itself, on `sovr-1` at height 2633375 only. A v0.27.3 node does
  not get an upgrade plan or an `upgrade-info.json` file. Cosmovisor does **not** switch binaries
  automatically. Replace the binary manually.
- **Before restart:** on the node RPC, check the applied height:

  ```
  curl -s localhost:26657/abci_info | jq -r .result.response.last_block_height
  ```

  It must print `2633374`. `/status` can show 2633374 or 2633375, because the block store can
  already hold block 2633375. Then stop the node, replace the binary with v0.27.4, and start it.
- **Height 2633374 and below:** v0.27.4 replays these blocks without change.
- **Height 2633375 and above:** you must use v0.27.4. A v0.27.3 node cannot apply block 2633375.
- **Snapshots:** use a snapshot at or below height 2633374. A later snapshot is usable only if
  it records the rollback as applied. Without that record, v0.27.4 stops with an error above
  height 2633375.

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
against the live network and the v0.27.4 release manifest, 2026-10-28.*

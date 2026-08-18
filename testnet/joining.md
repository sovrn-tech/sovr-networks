# Joining Sovren Testnet (`test-sovr-1`)

How to connect a node to `test-sovr-1`, the Sovren public testnet. Chain
identity, versions, fees, and ports are in
[`chain-params.md`](./chain-params.md).

## 1. Node software

**Node binaries and container images are not yet publicly downloadable.** The
public release channel opens with the Sovren Exchange Integration Kit general
availability; when it does, this section will carry the release download
references and the container **image digest** so operators can pin exactly
what Sovren runs. Until then, integrators and node operators should request
node software through the Sovren support channel
(support@sovrentech.io · [Discord support channel](https://discord.com/channels/1496907756718915645/1496907758283526168)).

Do not run binaries or images obtained from any other source claiming to be
Sovren node software.

## 2. Initialize the node home

```
sovrd init <your-moniker> --chain-id test-sovr-1
```

This creates `$HOME/.sovr/config/` (the genesis copy in the next step
overwrites the freshly generated placeholder genesis).

## 3. Genesis

Use the canonical testnet genesis file from this directory and verify it
first:

```sh
shasum -a 256 -c genesis.sha256   # must print: genesis.json: OK
cp genesis.json $HOME/.sovr/config/genesis.json
```

Expected SHA-256:
`5eb3be46b3020ffc9105be09fdaed874cad0f6e9110aaa58053d72711c8aef40`

## 4. Peers

All Sovren bootstrap peers are published as DNS names; Sovren never publishes
raw-IP peer strings.

**Seeds** (`p2p.seeds` in `config.toml`):

```
d5e5770e1198b6ab66dcf7bfadb90610e82bf6cd@seed1.testnet.sovrchain.net:32000,c24ded42a0026b4d912d8576b3d84d3c690b2d02@seed2.testnet.sovrchain.net:32001
```

**Persistent peers** (`p2p.persistent_peers` in `config.toml`), optional if
seeds are configured:

```
2dae62e74b0b175e7d905eeaca530464de8d8183@sentry1a.testnet.sovrchain.net:32200,5a5dca65a8fa75d66a65eca470d2c88d3c1c2703@sentry1b.testnet.sovrchain.net:32201,70ac5c238c5f83d6ef7480f64ec5c22d29364797@sentry2a.testnet.sovrchain.net:32220,c5385795047ac6a11d3328362033721ed3213657@sentry2b.testnet.sovrchain.net:32221,8cfacb1a936e3b848923a6fe631690336dc7717e@sentry3a.testnet.sovrchain.net:32240,dbf89f924f158c77222343d322e57eb1042b0a4c@sentry3b.testnet.sovrchain.net:32241
```

Known divergence from mainnet: all testnet P2P bootstrap names (seeds and
sentries) currently resolve to a single host, whereas mainnet fronts its P2P
layer with load-balanced infrastructure. Reduced bootstrap redundancy is
expected on testnet.

## 5. Gas price

Set the node's minimum gas price at or above the network floor:

```toml
# app.toml
minimum-gas-prices = "0.001usovr"
```

## 6. State sync

Sovren does not yet publish state-sync snapshots or trusted-height/hash
parameters for the testnet. This section gains the state-sync RPC servers and
trust parameters when that service is published; until then, new nodes sync
from genesis.

## 7. Public endpoints & faucet

| Kind | URL |
|---|---|
| RPC | https://rpc.testnet.sovrchain.net |
| REST | https://api.testnet.sovrchain.net |
| Faucet | https://faucet.testnet.sovrchain.net |

The RPC/REST endpoints carry **browser-grade per-IP rate limits**: they are
sized for wallets and light integration use — not for production data planes
or bulk indexing. For those workloads, run your own node using this guide.

---

*Source note: peers, endpoints, faucet, and checksums verified by the Sovren
team against the live testnet and the v0.23 release manifest, 2026-08-10.*

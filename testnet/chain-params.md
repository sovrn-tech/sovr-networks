# Sovren Testnet — Chain Parameters

Chain identity and consensus-relevant parameters for `test-sovr-1`, the
Sovren public testnet. These values are kept identical to the Sovren
chain-registry records and the Sovren Exchange Integration Kit network
manifest; a mismatch anywhere is a bug.

## Identity

| Parameter | Value |
|---|---|
| Chain ID | `test-sovr-1` |
| Daemon | `sovrd` |
| Node home | `$HOME/.sovr` |
| Bech32 account prefix | `sovr` |
| Bech32 validator operator prefix | `sovrvaloper` |
| Bech32 validator consensus prefix | `sovrvalcons` |
| Account key algorithm | secp256k1 |
| Consensus key algorithm | ed25519 |
| SLIP-44 coin type | 118 |

## Denomination

| Parameter | Value |
|---|---|
| Base denom | `usovr` |
| Display denom (`denom_metadata.display`) | `sovr` — **lowercase** |
| Decimals (display exponent) | 6 (1 SOVR = 1,000,000 usovr) |
| Symbol | `SOVR` — uppercase |

> **Genesis vs. live.** The launch `genesis.json` ships with `bank.denom_metadata` **empty**;
> the metadata above was set on the live chain by a post-genesis governance upgrade. Verify:
>
> ```sh
> curl -s https://api.testnet.sovrchain.net/cosmos/bank/v1beta1/denoms_metadata | jq
> ```

Testnet SOVR has no value and is distributed freely by the faucet (see
[`joining.md`](./joining.md)).

## Staking & fees

| Parameter | Value |
|---|---|
| Unbonding period | 21 days (1,814,400 s) — same as mainnet |
| Minimum gas price (network floor) | `0.001usovr` |
| Recommended gas price | `0.025usovr` |
| Recommended gas adjustment | 1.5 |

The minimum gas price is a **consensus-enforced network floor**, not a per-node setting. It is
enforced by the `x/globalfee` ante decorator, which reads the floor from chain state and applies in
`DeliverTx` as well as `CheckTx` — so a block containing an under-priced transaction is invalid on
every node. (This differs from stock Cosmos SDK, where `min-gas-prices` is a local `app.toml`
setting each operator chooses.)

**One documented exemption.** Five IBC relayer message types pay no floor, provided the
transaction's total gas stays at or below **1,000,000**:

```
/ibc.core.channel.v1.MsgRecvPacket
/ibc.core.channel.v1.MsgAcknowledgement
/ibc.core.channel.v1.MsgTimeout
/ibc.core.channel.v1.MsgTimeoutOnClose
/ibc.core.client.v1.MsgUpdateClient
```

Above the gas cap, or for any other message type, the floor applies normally. Both values are
governance-tunable; read them live:

```sh
curl -s https://api.testnet.sovrchain.net/sovr/globalfee/v1/params | jq .params
```

## Software versions (release line v0.23)

| Component | Version |
|---|---|
| Application | v0.23.0-rc1 (recorded release; the live testnet may run a newer release candidate on the same line — it was observed on v0.23.1-rc1 on 2026-08-10) |
| Cosmos SDK | v0.53.8 |
| CometBFT | v0.38.23 |
| ibc-go | v10.5.0 |
| CosmWasm (wasmd) | v0.60.7 |
| Go toolchain | 1.25.7 |

## Ports (default node configuration)

| Service | Port |
|---|---|
| P2P | 26656 |
| RPC | 26657 |
| gRPC | 9090 |
| REST | 1317 |
| Metrics | 26660 |

## Genesis

The canonical testnet genesis file is [`genesis.json`](./genesis.json) in
this directory. Verify it before use:

```sh
shasum -a 256 -c genesis.sha256
# genesis.json: OK  (5eb3be46b3020ffc9105be09fdaed874cad0f6e9110aaa58053d72711c8aef40)
```

---

*Source note: values verified by the Sovren team against the live testnet and
the v0.23 release manifest, 2026-08-10.*

## Governance

Live values, read from the chain on 2026-08-17. **Governance parameters are changed by governance**
— always re-read them before relying on them:

| Parameter | Live value | Endpoint |
|---|---|---|
| `voting_period` | **14400s (4 hours)** | `/cosmos/gov/v1/params/voting` |
| `expedited_voting_period` | **7200s (2 hours)** | same |
| `quorum` | 0.334 | same |
| `threshold` (regular) | 0.5 | same |
| `expedited_threshold` | **0.667** | same |
| `veto_threshold` | 0.334 | same |
| `min_deposit` | 10000000 `usovr` (10 SOVR) | same |
| `expedited_min_deposit` | 50000000 `usovr` (50 SOVR) | same |
| `max_deposit_period` | 172800s (48 hours) | same |
| `burn_vote_veto` | `true` — a vetoed proposal's deposit is burned | same |

**Two tracks.** A regular proposal votes for 4 hours and passes at a 0.5 threshold. An **expedited**
proposal votes for only **2 hours** but must clear a higher **0.667** threshold and post 5× the
deposit; if it fails to clear that bar it does not simply fail, it converts to a regular proposal
and continues for the normal period. Both tracks share the 0.334 quorum and 0.334 veto threshold.

> **Genesis vs. live.** The launch `genesis.json` records a **regular** `voting_period` of
> `172800s` (48 hours); the live value is **14400s (4 hours)**, set by governance after launch. Genesis is byte-pinned and
> is never edited, so the two differ by design — the live value is the operative one. Anything
> stating a 48-hour voting period is describing genesis, not the running chain.
>
> A 4-hour voting period is short. Integrators who need to react to governance — validators,
> exchanges pausing deposits around an upgrade — should monitor proposals continuously rather than
> polling daily.

```sh
curl -s https://api.testnet.sovrchain.net/cosmos/gov/v1/params/voting | jq .params
```

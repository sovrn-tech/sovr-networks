# Sovren Mainnet — Chain Parameters

Chain identity and consensus-relevant parameters for `sovr-1`. These values
are kept identical to the Sovren chain-registry records and the Sovren
Exchange Integration Kit network manifest; a mismatch anywhere is a bug.

## Identity

| Parameter | Value |
|---|---|
| Chain ID | `sovr-1` |
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
| Display denom | `sovr` (lowercase — this is `denom_metadata.display`) |
| Decimals (display exponent) | 6 (1 SOVR = 1,000,000 usovr) |
| Symbol | `SOVR` (uppercase ticker) |

> **Genesis vs. live — confirmed 2026-08-14.** The launch `genesis.json` ships with
> `bank.denom_metadata` **empty**; the metadata was set on the live chain by a post-genesis
> governance upgrade and now returns `display: "sovr"` (lowercase), `symbol: "SOVR"`, alias
> `SOVR`, `base: "usovr"`, and an approved on-chain `description`: *"SOVR is the sole unit of
> account of the Sovren Layer 1: staking, governance, gas, and service payments."* **The registry
> `display` field is lowercase `sovr`; the ticker/symbol is uppercase `SOVR`** — these are
> distinct fields and must not be conflated (an earlier version of this table wrongly listed the
> display denom as uppercase `SOVR`, which would produce wrong wallet/DEX display). Wallets,
> Osmosis, GeckoTerminal and the Cosmos chain-registry read this from the **live** chain. Verify:
>
> ```sh
> curl -s https://api.sovrchain.net/cosmos/bank/v1beta1/denoms_metadata | jq
> ```

## Staking & fees

| Parameter | Value |
|---|---|
| Unbonding period | 21 days (1,814,400 s) |
| Minimum gas price (network floor) | `0.001usovr` |
| Recommended gas price | `0.025usovr` |
| Recommended gas adjustment | 1.5 |

The minimum gas price is a **consensus-enforced network floor**, not a per-node setting.
It is enforced by the `x/globalfee` ante decorator, which reads the floor from chain state and
applies in `DeliverTx` as well as `CheckTx` — so a block containing an under-priced transaction is
invalid on every node, and a permissively configured validator cannot propose one. (This differs
from stock Cosmos SDK, where `min-gas-prices` is a local `app.toml` setting each operator chooses.)

**One documented exemption.** Five IBC relayer message types pay no floor, provided the
transaction's total gas stays at or below **1,000,000**:

```
/ibc.core.channel.v1.MsgRecvPacket
/ibc.core.channel.v1.MsgAcknowledgement
/ibc.core.channel.v1.MsgTimeout
/ibc.core.channel.v1.MsgTimeoutOnClose
/ibc.core.client.v1.MsgUpdateClient
```

This keeps relaying economically viable — a relayer delivering packets should not be priced out of
keeping the chain's IBC connections alive. Above the gas cap, or for any other message type, the
floor applies normally. Both values are governance-tunable; read them live:

```sh
curl -s https://api.sovrchain.net/sovr/globalfee/v1/params | jq .params
```

## Software versions (release v0.27.4)

| Component | Version |
|---|---|
| Application | v0.27.4 |
| Cosmos SDK | v0.53.8 |
| CometBFT | v0.38.23 |
| ibc-go | v10.5.0 |
| CosmWasm (wasmd) | v0.60.7 |
| Go toolchain | 1.25.14 |

## Ports (default node configuration)

| Service | Port |
|---|---|
| P2P | 26656 |
| RPC | 26657 |
| gRPC | 9090 |
| REST | 1317 |
| Metrics | 26660 |

## Consensus timing

Observed average block time is **~6 seconds** (live measurement by the Sovren
team, 2026-08-10). Block time is an observed network average, not a protocol
constant — do not hard-code it.

## Genesis

The canonical genesis file is [`genesis.json`](./genesis.json) in this
directory. Verify it before use:

```sh
shasum -a 256 -c genesis.sha256
# genesis.json: OK  (04529695e7ccfe32fcf3bc8031c343056d27cbe4aa3b3046027e27065bb9a855)
```

---

*Source note: values verified by the Sovren team against the live network and
the v0.27.4 release manifest, 2026-10-28.*

## Governance

Values effective from height 2633375 (v0.27.4). **Governance parameters are changed by governance**,
and also by a halt-recovery release: the v0.27.4 rollback handler raised the floors below. Always
re-read them before relying on them:

| Parameter | Value | Endpoint |
|---|---|---|
| `voting_period` | **172800s (48 hours)** | `/cosmos/gov/v1/params/voting` |
| `expedited_voting_period` | **43200s (12 hours)** | same |
| `quorum` | **0.5** | same |
| `threshold` (regular) | 0.5 | same |
| `expedited_threshold` | **0.667** | same |
| `veto_threshold` | 0.334 | same |
| `min_deposit` | 1000000000 `usovr` (1,000 SOVR) | same |
| `expedited_min_deposit` | 5000000000 `usovr` (5,000 SOVR) | same |
| `min_initial_deposit_ratio` | **0.5** — a proposer pays 500 SOVR at submission | same |
| `max_deposit_period` | 172800s (48 hours) | same |
| `burn_vote_veto` | `true` — a vetoed proposal's deposit is burned | same |

**Two tracks.** A regular proposal votes for 48 hours and passes at a 0.5 threshold. An
**expedited** proposal votes for **12 hours** but must clear a higher **0.667** threshold and post
5× the deposit; if it fails to clear that bar it does not simply fail, it converts to a regular
proposal and continues for the normal period. Both tracks share the 0.5 quorum and 0.334 veto
threshold.

> **Floors from v0.27.4.** At height 2633375 the v0.27.4 handler raised `voting_period`,
> `expedited_voting_period`, `quorum`, `min_deposit`, `expedited_min_deposit` and
> `min_initial_deposit_ratio` to the values above. It never lowers a value that is already
> higher. Before that height the values were 4h / 2h voting, 0.334 quorum, and 10 / 50 SOVR
> deposits. See the [CHANGELOG](../CHANGELOG.md).
>
> **Genesis vs. live.** The launch `genesis.json` is byte-pinned and is never edited, so its gov
> values can differ from the live values. The live value is the operative one.

```sh
curl -s https://api.sovrchain.net/cosmos/gov/v1/params/voting | jq .params
```

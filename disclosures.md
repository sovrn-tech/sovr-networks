# Genesis & Chain Disclosures

`genesis.json` publishes the complete `app_state` of roughly 45 modules, most of them custom to
Sovren. This page explains the entries whose meaning is not obvious from their names, and — more
importantly — records every place where **what genesis says differs from what the live chain does**,
or from what other Sovren documents say.

Everything here is independently verifiable. Each item names the endpoint or file that proves it.

## How to read this page

Three layers can disagree, legitimately:

1. **Genesis** — byte-pinned to the network's launch state and **never edited**. Where a genesis
   value is wrong or outdated, it stays wrong; the correction happens on-chain, and genesis remains
   a historical record of launch.
2. **The deployed software** — what the current binary can and cannot execute.
3. **Live chain state** — what governance has since changed.

Where these differ, this page says so and gives the query. Mainnet and testnet genesis are
byte-identical except for two governance voting-period values, so unless stated otherwise the
descriptions below apply to both.

---

## Supply

**`bank.supply` reports the full 1,000,000,000 SOVR.** That is the aggregator-facing number, returned
by `/cosmos/bank/v1beta1/supply/by_denom?denom=usovr`. The protocol reserve sits **inside**
`bank.supply` — it is not a separate "unminted" figure held outside it.

`x/supply` splits the same 1,000,000,000 into four pools under the closed-loop invariant
`latent + locked + vesting + claimed = 1,000,000,000`:

| Pool | Meaning |
|---|---|
| `latent` | The unissued protocol reserve (~939.3M) |
| `locked` / `vesting` | Operator rewards under a 180-day lock and linear vest |
| `claimed` | Issued and liquid |

The `latent` reserve is further split into four named, independently queryable sub-buckets —
`protocol_emissions`, `bootstrap_rewards`, `exchange_allocation`, `node_revenue_match` — via
`/sovr/supply/v1/latent-sub-buckets`. `/sovr/supply/v1/audit` independently proves the invariant
holds, reporting whether the bank total and the ledger total agree.

**Supply figures for listings and aggregators:**

- **Max supply** — 1,000,000,000 (hard cap).
- **Total supply** — 1,000,000,000. Filing any smaller figure is contradicted by the on-chain
  endpoint that aggregators read automatically.
- **Non-circulating** — the `latent` protocol reserve, plus operator rewards still under lock or
  vest, plus the genesis treasury held in `claimed`.
- **Circulating** — the remainder actually in third-party hands, which is currently a very small
  fraction of supply. Nearly everything issued since genesis is either genesis treasury or still
  inside its lock/vest window.
- **Wrapped SOVR** — when the EVM bridge is live, wrapped SOVR is minted 1:1 against native SOVR
  **locked** by the bridge. It is **not additional supply**; the locked native backs it and the
  total remains 1,000,000,000.

### Why genesis shows 60M and the live chain shows 1B

This is the single most likely thing to look like a discrepancy, so it is worth stating plainly.

**In the genesis file**, `bank.supply` is **60,000,000,000,000 usovr (60M SOVR)** — matching
`bank.balances` exactly — while the `x/supply` ledger already describes the full
1,000,000,000 SOVR (940M latent + 60M claimed). At genesis those two do **not** reconcile: the
ledger asserted a 940M reserve that had no corresponding tokens in `x/bank`, and no module account
held it.

**On the live chain they do reconcile.** The `v0.20.0-closed-loop-supply` upgrade (applied on
`sovr-1` in the `v0.20.0-combined` plan at block height **1,210,440**) closed the gap: it minted
exactly the missing amount into the `x/supply` module account, so the reserve the ledger had always
described became tokens that actually exist and are held by the protocol. Live `bank.supply` is now
the full 1,000,000,000 SOVR, and `/sovr/supply/v1/audit` reports `bank_minus_ledger: 0` and
`physical_minus_latent: 0` — i.e. bank, ledger, and the physically held reserve now agree exactly.

**No tokens were created for anyone.** The minted amount went to the protocol's own module account
as the unissued reserve, and the hard cap of 1,000,000,000 was never exceeded — before the upgrade
the reserve was an accounting entry, after it the reserve is held on-chain. Total supply as reported
to aggregators has always been 1,000,000,000; what changed is that `bank.supply` now says so too.

```sh
curl -s https://api.sovrchain.net/sovr/supply/v1/audit | jq
curl -s https://api.sovrchain.net/cosmos/upgrade/v1beta1/applied_plan/v0.20.0-combined | jq
```

**Holder concentration.** Two addresses hold the overwhelming majority of non-reserve issued supply:
the **Liquidity Pool Reserve (49,970,000 SOVR)** and the **Service Liquidity Reserve
(10,000,000 SOVR)**. Every movement from either is publicly attributable and permanent.

> The Liquidity Pool Reserve holds **49,970,000**, not the 50,000,000 stated in the whitepaper. The
> 30,000 difference funded the three genesis validator self-bonds (10,000 each), which were
> sub-allocated from it at the launch ceremony.

**Emissions are off at genesis, deliberately.** `distro` ships with `initial_annual_emission = 0`,
a no-op `halving_interval_blocks`, and `total_minted = 0`. Operator rewards do not come from
per-block inflation; they come from a work-contingent daily path that mints nothing until operators
attest real work, and a usage-linked path that stays off until governance arms it.

---

## Names that differ between genesis, the whitepaper, and the code

Store keys are byte-pinned at genesis and cannot be renamed without a chain upgrade, so several
modules carry an internal codename rather than their published label. The amounts and purposes
agree across layers; only the labels differ.

| Genesis / on-chain name | Published label |
|---|---|
| `track_a` | Bootstrap Rewards Reserve (150,000,000 SOVR) |
| `bootstrap` | Node Revenue Match (10,000,000 SOVR) |
| `opt_exchange` | `x/exchange_allocation` (50,000,000 SOVR) |
| `settlement.company_dao_bps` / `dao_address` | Treasury Allocation |

- **`track_a` — Bootstrap Rewards Reserve.** The long-term, work-contingent operator reward pool.
  The 150M is **earmarked, not minted**: the module holds only a lifetime drawdown counter, and the
  SOVR sits in `x/supply`'s `bootstrap_rewards` sub-bucket, released daily and only to attesting
  operators. Governance may lower the cap, never raise it.
- **`bootstrap` — Node Revenue Match.** Distinct from `track_a`: a one-time 10M fund matching
  node-earned revenue 2.5×, halting permanently on exhaustion. Its genesis `pool_remaining: 0` is
  **not** "exhausted" — it is the fresh-genesis auto-seed sentinel; the pool seeds to the full 10M
  on the first match.

---

## The Exchange Allocation (`opt_exchange`)

`opt_exchange` is the genesis name of the module now called `x/exchange_allocation`. Under an
earlier concept — mentioned publicly, never activated — it would have allowed holders of a separate
chain's token to claim SOVR at a governance-set rate. It shipped disabled: no rate was ever set, no
allowlist was ever populated, and no SOVR was ever issued through it. The claim mechanism was
removed in `v0.8.0`. The 50,000,000 SOVR reserve remains a passive, unminted set-aside for
centralized-exchange listing requirements, and is not used to pay listing fees, market-maker fees,
or operating expenses. The `opt_exchange` name and `rate_per_opt_*` fields persist only because
launch genesis is byte-pinned and is never edited.

**Verifying that:**

| Statement | How to check |
|---|---|
| Shipped disabled | genesis `app_state.opt_exchange` → `active: false`, `rate_per_opt_usovr: "0"`, `allowed_recipients: []`, `claimed_usovr: "0"` |
| Nothing was ever issued | `/sovr/supply/v1/latent-sub-buckets` → `exchange_allocation` is bit-identical to its genesis value while neighbouring earmarks have visibly changed; `/sovr/exchange_allocation/v1/reserve-status` → `issued_usovr: "0"` |
| No claim path exists today | `/sovr/exchange_allocation/v1/params` returns a single field. In the deployed source the module's only message is a governance parameter update, its keeper is wired to neither the bank nor the supply keeper, and `x/supply` fails closed on any attempt to draw this earmark |
| Parameters were never altered | No governance proposal in the chain's history references this module, and no claim transaction appears anywhere in the archival transaction index |

**Four artifacts of the former module remain publicly discoverable. None is a code path** — they are
records:

1. the byte-pinned genesis block itself;
2. two orphaned key/value records left by the store rename, whose contents encode only the reserve
   cap — the activation flag and rate are absent from the wire, i.e. `false` and `0`;
3. a bookkeeping entry named `opt_exchange` in the chain's module-version map;
4. the legacy module-account name, permanently retained in the chain's blocked-address set so that
   no funds can ever be stranded at that address.

**Reserve size.** 50,000,000 SOVR is the live figure. An approved but **unapplied** upgrade
(`v0.24.0-reserve-reallocation`) would raise it to 75,000,000; it has not been proposed or applied,
and `/cosmos/upgrade/v1beta1/applied_plan/v0.24.0-reserve-reallocation` returns height `0` until it
is. The whitepaper publishes the 75M post-upgrade target.

These statements describe the chain's code and state as deployed. Dormancy is a property of the
current binary, which token holders acting through governance can replace.

---

## Service revenue split

Every settled service payment splits atomically three ways at the consensus level: **50% burned to
the latent reserve, 25% to active operators, 25% to the issuer** (`settlement.company_bps = 2500`).
The issuer's 25% sub-splits 40/40/10/10 as **infrastructure / ecosystem / Treasury Allocation /
staking**.

The split exists in genesis, but usage-linked rewards and service settlement have not started, so
**no SOVR has reached any issuer destination**. When a service does settle, the 50% burn-to-latent
and 25% operator legs are what flow.

> **Field-name note.** The Treasury Allocation leg is carried by parameters literally named
> `company_dao_bps` and `dao_address`. Those names are retained for wire compatibility — renaming a
> protobuf field breaks clients — so `/sovr/settlement/v1/params` shows `dao_*` where this page says
> *Treasury Allocation*. They are the same 10% leg.

**Burns do not reduce total supply.** A burn returns SOVR to the latent reserve rather than
destroying it, so the closed-loop invariant holds and total supply stays 1,000,000,000. Burned SOVR
should not be presented as deflationary in the way a send-to-unspendable-address burn would be.

---

## Auction tranche 10

Genesis records tranche 10 as a Dutch-decay tranche (`TRANCHE_KIND_DUTCH_DECAY`, $20,000 → $7,000).
The genesis file was finalised on 2026-05-06 at 23:58:44 UTC; the change designating tranche 10 as
the non-offered Company Reserve Allocation landed **two hours and thirty-nine minutes later** and
was applied on-chain. Genesis therefore records the pre-change configuration and, being byte-pinned,
is never edited.

**On the live chain, tranche 10 carries no pricing and is not offered at auction.**
`/sovr/auction/v1/tranche/10` returns `kind: TRANCHE_KIND_STRATEGIC_RESERVE` with
`opening_price_usd_cents: "0"`, `floor_price_usd_cents: "0"` and `sold_count: 0`, while tranche 9
still returns a priced `TRANCHE_KIND_DUTCH_DECAY` — so the distinction is externally verifiable in
two queries.

Company-reserve licenses are minted to a Sovren-controlled multi-signature wallet on request, as
needed — **not pre-minted**.

> The whitepaper states that 1,000 tranche-10 licenses are "already minted and held in a Sovren
> multisig". **Nothing was pre-minted at genesis.** Genesis has `licenses: []` and
> `next_license_id: "0"`. The number issued since is published on-chain — see below.

## Licenses issued to company-controlled wallets

Two tranches have licenses issued to Sovren-controlled multi-signature wallets rather than sold on
the open market. Both counters are returned together and should be read together:

```sh
curl -s https://api.sovrchain.net/sovr/auction/v1/params \
  | jq '.params | {t01_preorder_issued_count, t10_issued_count}'
```

- **Tranche 01 — Reserved Node Access.** T01 is offered to approved participants under published
  eligibility rules rather than on the open market, and is issued through a company-controlled
  pre-order wallet. Its count (`t01_preorder_issued_count`) is **substantially larger** than the
  tranche-10 figure.
- **Tranche 10 — Company Reserve.** As described above: carries no pricing, is not offered at
  auction, and is issued on request rather than pre-minted (`t10_issued_count`).

Neither number is fixed in this document, because both change as licenses are issued — read the
endpoint for the current values.

Node licenses are **not SOVR** and do not affect token supply. They are separately transferable
NFT-backed entitlements, subject to a 12-month transfer lockup from mint.

---

## Where genesis and live state differ

- **Denomination metadata.** `bank.denom_metadata` is **empty in genesis** but **set on the live
  chain**: `base: "usovr"`, `display: "sovr"` (lowercase), `symbol: "SOVR"`, exponent 6, name
  "Sovren". The launch genesis predates the metadata, which was added by governance. Integrators
  should read the live value; note the display denom is lowercase `sovr` while the symbol is
  uppercase `SOVR`.
- **Revenue-destination addresses.** Genesis carried placeholder values for the `distro`
  (`treasury`, `ecosystem`, `infrastructure`, `staking_rewards`) and `settlement` (`dao`)
  destinations which were not valid account addresses — they were short ASCII labels rather than
  20-byte accounts, so no key could exist for them. A governance parameter update replaced all of
  them with real addresses; the live values are returned by `/sovr/distro/v1/params` and
  `/sovr/settlement/v1/params`. No funds were ever routed to the placeholders, because the paths
  that would pay them have not started.
- **Auction tranche 10** — see above.

---

## Dormant, placeholder, and inert values

These appear in genesis and are easy to misread. None is active.

- **`x/attestation` endpoint fields** (`triton_endpoint`, `manta_endpoint`, `edgecast_endpoint`,
  `parler_endpoint`) — deprecated, always-empty placeholder fields inherited from the original
  prototype scaffold and **read by no code**. They imply **no integrations**: these were generic
  stand-in *category* labels (compute / object storage / CDN / social), not shipped or planned
  Sovren integrations. They will be marked reserved in a future upgrade; they cannot be removed from
  a byte-pinned genesis. Attestation is not inert because of them — it boots quiescent by design via
  other parameters.
- **`x/testfixtures`** (`{}`) — a development-only helper compiled into every build, so it appears
  in every `app_state` including mainnet. On a real network it is doubly disabled: a build tag
  compiles disabled stubs, and a fail-closed chain-id guard refuses to operate on any real SOVR
  chain-id. It stores nothing. It exists so one binary serves every network.
- **`x/nodelicense` storage-tier price** — the three tiers (Starter 500 GB / Standard 2 TB /
  Enterprise 10 TB) share a uniform placeholder price. The capacities differ and are correct; only
  the price is intentionally uniform, and it is inert because licenses mint through the auction, not
  this direct-purchase path.
- **`oracle.bootstrap_price_usd_micros`** — an internal fallback reference used only when fewer than
  the minimum number of oracle feeders have posted. It is not a published or endorsed market price.
- **`chain_start_unix: 0`** — the token-generation-event anchor has not been set. Both emission
  modules fall back to their most conservative phase until governance installs it. Nothing is
  broken; the Node Revenue Match is a flat 2.5× multiplier, so the anchor does not change its
  payouts.
- **`consensus.block.max_gas = -1`** — the CometBFT default, meaning no explicit per-block gas
  ceiling. Blocks remain bounded by `max_bytes` and block time.
- **`gov.constitution = ""`** — the Cosmos SDK default; an on-chain constitution is optional and has
  not been populated.

---

## Bridge posture

The SOVR↔EVM bridge is **inert**: no contract is deployed (the configured contract address is the
zero address) and the relayer allowlist is empty, so nothing can be bridged in either direction. It
is a separate module from the IBC transfer path used for the Osmosis route, and pausing or
configuring it has no effect on IBC transfers.

Governance is separately hardening the inactive bridge — pausing it explicitly and raising the
relayer quorum above one — so that activation cannot happen without a further, deliberate governance
action. Activation, when it comes, is its own proposal requiring an audited contract, an approved
relayer set, and end-to-end verification. Current values are returned by the bridge module's
parameter query.

Until the bridge is live, **no "SOVR" ERC-20 on any EVM chain is official.** See *Official surfaces*
in the [README](./README.md).

---

## Permissionless CosmWasm

`wasm.code_upload_access` is `Everybody` in genesis — the wasmd default — meaning contract upload is
permissionless. This parameter is governance-tunable and may be tightened; read the live value
rather than assuming this one:

```sh
curl -s https://api.sovrchain.net/cosmwasm/wasm/v1/codes/params | jq
```

Whatever it is set to, the consequence worth restating is the same: a contract claiming to be
"SOVR" can exist, so — **SOVR is a native coin with no token contract address on its own chain.**
Any contract presenting itself as SOVR on `sovr-1` is not SOVR.

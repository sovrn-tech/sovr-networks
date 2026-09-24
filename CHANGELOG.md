# Changelog

All notable changes to the published network metadata in this repository are
recorded here. Dates are UTC. This repository is updated on every chain release,
on IBC route establishment, and on any change to a published value.

## 2026-09-21 — Node software release v0.27.3 (non-consensus)

- Published the node software release [v0.27.3](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.27.3)
  (`sovrd` linux/amd64 + `libwasmvm.x86_64.so` + checksums) and the container image
  `ghcr.io/sovrn-tech/sovrd:v0.27.3` (`sha256:141aeb194773448727ee407687a072add600bfee03d6657667fc42bbd09b0f4d`)
  — both extracted from the exact digest the mainnet fleet runs. **No on-chain upgrade** — this
  release only fixes a `gov` query codec failure (proposal 12's retired `x/bridge` `MsgUpdateParams`
  failed `ListProposals` decode on the API/gRPC-gateway path) and a `txquery` pagination
  undercount; no state-machine, keeper, or handler change. v0.27.2 was published but never
  announced — an issue was found during its release — and this release supersedes it. sovrd sha256
  `516ec1e2e442d356cec7efc430843f95bddd6e98311cade5c310da4cf3eabdde`, libwasmvm sha256
  `1da45df75aa3e97f0635e3b4c9236d551fbf7b696af321462e43fa05726cffe9`.

## 2026-09-16 — Node software release v0.27.1 (v0.27.0-combined upgrade)

- Published the node software release [v0.27.1](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.27.1)
  (`sovrd` linux/amd64 + `libwasmvm.x86_64.so` + checksums) and the container image
  `ghcr.io/sovrn-tech/sovrd:v0.27.1` (`sha256:479ff7ce30a85dc0562bdb3837d3d6418873846aca12697887df714229e39bcd`)
  — both extracted from the exact digest the mainnet fleet runs. Carries the on-chain
  `v0.27.0-combined` upgrade, applied at block height 2044794. sovrd sha256
  `d35269a20eab4af073e3bd2d42d1619ce47f84ee42c2c8a451837d863b65d38d`, libwasmvm sha256
  `1da45df75aa3e97f0635e3b4c9236d551fbf7b696af321462e43fa05726cffe9`.

## 2026-09-08 — Node software release v0.24.0 (reserve-reallocation upgrade)

- Published the node software release [v0.24.0](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.24.0)
  (`sovrd` linux/amd64 + `libwasmvm.x86_64.so` + checksums) and the container image
  `ghcr.io/sovrn-tech/sovrd:v0.24.0` (`sha256:d909fa6cd56648670b48ee3263b40bd248f1aa4dcf4f353a7d2188e42ad00615`)
  — both extracted from the exact digest the mainnet fleet runs. Carries the on-chain
  `v0.24.0-reserve-reallocation` upgrade. sovrd sha256
  `6b6077ce43e5e284123950d9c1419ddcaf2d3b183ab51818c445f857be5a0b94`, libwasmvm sha256
  `1da45df75aa3e97f0635e3b4c9236d551fbf7b696af321462e43fa05726cffe9`.

## 2026-08-18 — Brand assets · chain-registry submission

- Added the SOVR mark under `images/` (`sovr-256.png` 256×256, `sovr.png` 512×512 — both square,
  under the chain-registry 250 KB logo limit, transparent and safe inside a circular mask), for
  reference by the Cosmos chain-registry and Osmosis assetlist submissions.
- Submitted chain-registry records for `sovr` (mainnet) and the `osmosis-sovr` IBC route.
- Published the node software release [v0.23.0](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.23.0)
  (`sovrd` linux/amd64 + `libwasmvm.x86_64.so` + checksums) and the container image
  `ghcr.io/sovrn-tech/sovrd:v0.23.0` — both extracted from the exact digest the mainnet fleet runs.

## 2026-08-17 — Initial public release

Published metadata for `sovr-1` (mainnet) and `test-sovr-1` (testnet), verified against the live
networks on 2026-08-17.

**Network metadata**

- Genesis files and SHA-256 checksums for both networks, reproducing each network's genesis
  `app_state` exactly.
- Chain parameters: identity, denominations, fees, versions, ports, and **governance parameters**
  (live `voting_period` is 14400s / 4 hours — genesis records 172800s, changed by governance after
  launch).
- Join instructions: seeds, persistent peers, and public endpoints.
- Display denomination published as lowercase `sovr` with uppercase symbol `SOVR`, matching the
  live `bank.denom_metadata`.

**IBC**

- Canonical mainnet route to Osmosis (`osmosis-1`) recorded as live: `channel-0` ↔ `channel-110679`,
  both `STATE_OPEN`, with the SOVR voucher denomination and the sovr-side escrow address.
- Testnet route to `osmo-test-5` recorded: `channel-0` ↔ `channel-11825`.

**Disclosures**

- Added [`disclosures.md`](./disclosures.md): supply structure and methodology, holder
  concentration, module codename reconciliations, the Exchange Allocation history, the service
  revenue split, auction tranche 10, licenses issued to company-controlled wallets, genesis-vs-live
  differences, dormant and placeholder values, bridge posture, and permissionless CosmWasm.

**Security**

- Added `SECURITY.md` with the reporting process and response targets, and published the security
  team's PGP public key and fingerprint.
- Bridge containment executed on-chain by governance (proposal 12): the inactive bridge is `paused`
  with `relayer_quorum` raised to 2, so activation requires a further, deliberate governance action.

**Legal**

- Apache-2.0 licence; publisher named as Sovren Technologies, Inc.

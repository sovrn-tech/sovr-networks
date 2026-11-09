# Changelog

All notable changes to the published network metadata in this repository are
recorded here. Dates are UTC. This repository is updated on every chain release,
on IBC route establishment, and on any change to a published value.

## 2026-11-09 — Node software release v0.28.0 (consensus: governance upgrade `v0.28.0-security-hardening` at height 2819382)

- Published the node software release [v0.28.0](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.28.0)
  (`sovrd-v0.28.0-linux-amd64-musl` — a statically linked daemon that needs no `libwasmvm` — plus
  `restore-snapshot.sh` and checksums) and the container image `ghcr.io/sovrn-tech/sovrd:v0.28.0`
  (index `sha256:210c20c0636d6fb52e2b7633d7e852aca909cb88fee37454b97373d2be135aa1`, cosign-signed;
  linux/amd64 child `sha256:0ad2e710bd33cf01620129ece5e5c71819c68ba520531e84bff72cfa69e04079`) — the
  exact digest the mainnet fleet runs. **Consensus release.** Gov proposal 17 scheduled the
  `v0.28.0-security-hardening` plan at height 2819382; `sovr-1` halted there on 2026-11-09 at
  20:48 UTC and resumed on v0.28.0 at 20:57 UTC.
- **A governance upgrade, not a fork.** Cosmovisor switches automatically when the binary is staged
  under `cosmovisor/upgrades/v0.28.0-security-hardening/bin/sovrd`; manual operators replace the
  binary after their node logs `UPGRADE "v0.28.0-security-hardening" NEEDED at height: 2819382`.
  Heights 2633375–2819381 still need v0.27.4. See
  [mainnet/joining.md](mainnet/joining.md#upgrade-at-height-2819382-v0280-governance-plan-v0280-security-hardening).
- Security hardening. SOVR↔EVM bridge (`x/evmbridge`): a bank send restriction on the warp escrow
  and nested-message unwrapping in the ante guard, the policy ISM bound to the canonical route,
  inbound release amounts bounded, the emergency authority can no longer lift a governance pause,
  and a new automated pause-only authority parameter (consensus version 1→2). `x/attestation`:
  the slim-agent signed-report path is closed, `MsgSubmitMerkleBatch` is disabled, and challenges
  are bounded, target-checked, bonded and pruned. `x/wasmguard`: contract sub-messages count
  against the quotas. Store reads fail closed on unexpected errors. The bridge stays dormant and
  fail-closed — no route exists yet.
- Node licenses: tranches T02–T09 convert from Dutch auction to fixed price (T02 $3,000, T03 $3,500,
  T04 $4,000, T05 $4,500, T06 $5,000, T07 $5,500, T08 $6,000, T09 $6,500); T01 ($3,000) and the T10
  company reserve are unchanged (`x/auction` consensus version 2→3). No store additions; no
  governance parameter changed.
- Checksums: `sovrd-v0.28.0-linux-amd64-musl` sha256
  `dad7f46ee8b73b9b7beb58e0f2c9be053a98b8955f035cd43d164a6d412a7e3a`; `restore-snapshot.sh` sha256
  `45d18caa5ef17f5c7afdd14fd54acafef169ba2d3495a978e74b53253031fc1b`. The glibc `sovrd` inside the
  image has sha256 `042f620fe66f94d7d0a816442a8df7618605c7691aa0557cbae95ebcc1a2e34b` (the
  `BINARY_SHA256` value for docker-compose validators).

## 2026-10-27 — Node software release v0.27.4 (consensus: proposal 16 rollback)

- Published the node software release [v0.27.4](https://github.com/sovrn-tech/sovr-networks/releases/tag/v0.27.4)
  (`sovrd` linux/amd64 + `libwasmvm.x86_64.so` + checksums) and the container image
  `ghcr.io/sovrn-tech/sovrd:v0.27.4` (index `sha256:b7490a32529bae1b164ddc600ed454ff3cb210dab03d349cdf1e95d827c6b756`,
  cosign-signed; linux/amd64 child `sha256:b5009d664ca5e45b98fa056cf13ba1b3a871ada9048a20881fc9841b7a15d67a`)
  — both extracted from the exact digest the mainnet fleet runs. **Consensus release — all
  validators must run it to restart `sovr-1`.** Gov proposal 16 changed the emission parameters
  and replaced the four emission sink addresses. Block 2633374 then emitted the full
  `protocol_emissions` bucket to the new sinks, and `sovr-1` halted at block 2633375.
- **Fork height 2633375. This is not a governance upgrade.** The chain is halted, so governance
  cannot schedule a plan. The v0.27.4 binary schedules the plan itself, on `sovr-1` at height
  2633375 only. Cosmovisor does not switch binaries for this fork. Replace the binary manually.
  v0.27.4 replays blocks at or below height 2633374 without change. See
  [mainnet/joining.md](mainnet/joining.md#fork-at-height-2633375-v0274-not-a-governance-upgrade).
- At height 2633375 the `v0.27.4-emission-rollback` handler returns the emitted SOVR to `latent`
  and `protocol_emissions`, rolls back the block 2633374 mint counters, and restores the 13
  parameters that proposal 16 changed. Any pre-state mismatch aborts the block.
- From height 2633375, transactions signed or fee-paid by the proposal 16 submitter or sink
  addresses are rejected, and sends out of these addresses are rejected (except the clawback to
  the `x/supply` module account). Incoming transfers stay allowed. The lock has no end height. A
  later upgrade removes it.
- The handler raises the gov floors: `voting_period` 48h, `expedited_voting_period` 12h,
  `quorum` 0.5, `min_deposit` 1,000 SOVR, `expedited_min_deposit` 5,000 SOVR, and
  `min_initial_deposit_ratio` 0.5. It never lowers a higher value. See
  [mainnet/chain-params.md](mainnet/chain-params.md#governance).
- Before restart, check the applied height on the node RPC:
  `curl -s localhost:26657/abci_info | jq -r .result.response.last_block_height` must print
  `2633374`. (`/status` can show 2633374 or 2633375, because the block store can already hold
  block 2633375.) Then stop the node and replace the binary. To recover
  from pre-rollback state, use a snapshot at or below height 2633374. A later snapshot is usable
  only if it records this rollback as applied. Without that record, v0.27.4 stops with an error
  above height 2633375.
- sovrd sha256 `00f0e6705be471ec57d23fa9db395a5525be1830445f52620fb728f82c6bbf6c`, libwasmvm
  sha256 `1da45df75aa3e97f0635e3b4c9236d551fbf7b696af321462e43fa05726cffe9` (unchanged).

## 2026-10-01 — Release signing key published

- Published Sovren's **release signing key** as [`release-signing-key.asc`](release-signing-key.asc):
  fingerprint `A924 55E6 480F F4F3 3E03  86B8 A77A 79C7 529A 47E7`, `Sovren Release Captain
  <releases@sovrentech.io>`, ed25519 signing-only, valid 2026-10-01 → 2028-09-30. It signs the
  `checksums.txt.asc` detached signature in Sovren release bundles; verification steps and the
  rotation policy are in [SECURITY.md](SECURITY.md#release-signing-key). The security contact key
  is unchanged and does not sign releases.

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

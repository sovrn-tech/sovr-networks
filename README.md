# Sovren Networks

Canonical public network metadata for **Sovren (SOVR)** — a native Layer 1
blockchain built on the Cosmos SDK (CometBFT consensus, IBC-enabled, CosmWasm
smart contracts). SOVR is the sole unit of account of the Sovren Layer 1:
staking, governance, gas, and service payments. The base denomination is
`usovr` (1 SOVR = 1,000,000 usovr).

*Last verified against the live networks: 2026-08-13 (release v0.23.0).*

## At a glance

| | Mainnet | Testnet |
|---|---|---|
| Chain ID | `sovr-1` | `test-sovr-1` |
| Base denom | `usovr` | `usovr` |
| Display denom (`denom_metadata.display`) | `sovr` (lowercase) | `sovr` (lowercase) |
| Symbol / decimals | `SOVR` / 6 | `SOVR` / 6 |
| Bech32 account prefix | `sovr` | `sovr` |
| SLIP-44 coin type | 118 | 118 |

Full parameters: [`mainnet/chain-params.md`](./mainnet/chain-params.md) ·
[`testnet/chain-params.md`](./testnet/chain-params.md)

## What this repository is

The Sovren chain's source code is developed in a private repository. **This
repository is the public networks surface**: the canonical place for network
identity, genesis files, chain parameters, and join instructions. It exists so
that node operators, exchanges, wallet developers, and registry reviewers have
a single verifiable reference that Sovren keeps in lockstep with the live
network. Sovren works to keep this repository consistent with every other
Sovren-published surface as well; if you find a discrepancy between this
repository and another Sovren surface, please report it through the contact
channels below and we will reconcile it.

The definitive list of Sovren's domains, accounts, and token identity is
[Official surfaces](#official-surfaces) below — anything not listed there is
unofficial, however closely it resembles them.

## Official surfaces

These are the only domains, repositories, and accounts operated by **Sovren
Technologies, Inc.** Anything else claiming to be Sovren or SOVR is unofficial,
however closely it resembles these.

- **Publisher:** Sovren Technologies, Inc.
- **Domains:** sovrentech.io · sovrchain.net · sovrscan.com
- **Repository:** github.com/sovrn-tech/sovr-networks
- **Discord:** invites in [Contacts](#contacts) below
- **X:** [@sovrentech](https://x.com/sovrentech) — the only official X account

**Token identity.** SOVR is a **native** Cosmos SDK coin — base denom `usovr` on
chain `sovr-1`. On its native chain it has **no token contract address**; a
"SOVR contract address" on `sovr-1` is meaningless. The only legitimate ERC-20
representation is the official **wrapped SOVR** minted by the Sovren
lock-and-mint bridge; its contract address and supported chains will be
published here (and on the bridge surface) once the bridge is live. Until then,
**no** "SOVR" ERC-20 on any EVM chain is official; after launch, only the token
at the published official bridge contract is genuine.

**IBC identity.** The canonical route to Osmosis (`osmosis-1`) is **live**, and SOVR's only
canonical denomination there is
`ibc/FB26E04E71EACCCCCD6D81F0F7666D5567C3A1686E2AC577FCC03F28F5B5874F`
(the trace `transfer/channel-110679/usovr`). Full route record — clients, connections, channels,
and the escrow address — is in [`mainnet/ibc.md`](./mainnet/ibc.md). **No other `ibc/…` denom is
canonical SOVR**, on Osmosis or any other chain, whatever a UI labels it.

## Links

| What | Where |
|---|---|
| Explorer | https://sovrscan.com |
| Network status / node health | https://sovrscan.com/node-health |
| Mainnet RPC | https://rpc.sovrchain.net |
| Mainnet REST | https://api.sovrchain.net |
| Testnet RPC | https://rpc.testnet.sovrchain.net |
| Testnet REST | https://api.testnet.sovrchain.net |
| Testnet faucet | https://faucet.testnet.sovrchain.net |

## Contacts

| Purpose | Channel |
|---|---|
| Technical support (integration, node operation) | support@sovrentech.io · [Discord — Support](https://discord.gg/uuWZchgxN) |
| Security reports / vulnerability disclosure | security@sovrentech.io — see [SECURITY.md](./SECURITY.md) |
| Upgrade notifications & incidents | [Discord — Announcements](https://discord.gg/ZPGYhmNdq) |

## Chain registry

Sovren's chain-registry records (mainnet chain name `sovr`, testnet
`sovrtestnet`) are prepared from the same source data as this repository and
will be submitted to the [Cosmos chain registry](https://github.com/cosmos/chain-registry);
once merged they are kept value-identical with it. The prepared records
reference this repository as their codebase/genesis surface.

**A note on the genesis files**: the `gentx` memos inside each `genesis.json`
record ceremony-time peer addresses and validator node IDs from the genesis
validator setup. They are historical and are not used for peering — live peers
are in `joining.md`. Genesis is reproduced byte-for-byte and pinned by the
published checksums, so these values are never edited.

## Layout

```
README.md            this file
mainnet/             sovr-1 (mainnet)
  genesis.json       canonical genesis file (byte-identical to the network's)
  genesis.sha256     SHA-256 checksum of genesis.json (shasum -a 256 -c genesis.sha256)
  chain-params.md    chain identity, denominations, fees, versions, ports
  joining.md         seeds, persistent peers, endpoints, node software status
  ibc.md             canonical IBC route record (Osmosis) — live route: ids, denom, escrow
testnet/             test-sovr-1 (public testnet) — same shape as mainnet/
```

## Verify the genesis against the live network

Every `genesis.json` here reproduces the network's genesis **`app_state`** exactly — the chain
state the network launched with. Check it yourself:

```sh
# 1. The published file matches its published checksum.
#    (run from inside mainnet/ or testnet/ — the checksum file names a bare path)
cd mainnet && shasum -a 256 -c genesis.sha256

# 2. The genesis app_state matches what the live network serves.
curl -s https://rpc.sovrchain.net/genesis | jq -S '.result.genesis.app_state' > /tmp/live.json
jq -S '.app_state' genesis.json | diff -q - /tmp/live.json && echo "matches live network"
```

For the testnet, substitute `cd testnet` and `https://rpc.testnet.sovrchain.net`.

> **Why compare `app_state` and not the whole document?** The CometBFT `/genesis` RPC re-serializes
> the file into its own envelope — it emits `consensus_params` where the file has `consensus`, sets
> `app_hash` to `""`, adds `initial_height`, and drops `app_name`/`app_version`. Diffing the whole
> document therefore reports ~55 lines of *presentation* differences and looks like a mismatch when
> nothing is wrong. `app_state` is the part that defines the chain's starting state, and it is
> byte-identical on both networks.

## Node software

Node binaries and container images are **not yet publicly downloadable**. When
they are published, `mainnet/joining.md` and `testnet/joining.md` will carry the
release references and the container image digest to pin against — until then,
genesis-based sync from source is the only path (see `joining.md`).

## Update cadence

This repository is updated on every chain release, on IBC route establishment,
and on any change to a published value; see [`CHANGELOG.md`](./CHANGELOG.md) for
the dated history.

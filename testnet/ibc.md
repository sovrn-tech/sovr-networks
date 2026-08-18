# Sovren Testnet — IBC Routes

The rehearsal IBC route between `test-sovr-1` and the Osmosis testnet (`osmo-test-5`) is **live**.
It mirrors the shape of the mainnet record in [`../mainnet/ibc.md`](../mainnet/ibc.md).

> **Testnet tokens have no value.** This route exists for integration testing. Nothing here is a
> mainnet identifier — do not configure production systems from this page.

## Route — `test-sovr-1` ↔ `osmo-test-5`

| | `test-sovr-1` side | `osmo-test-5` side |
|---|---|---|
| Client | `07-tendermint-0` | `07-tendermint-5262` |
| Connection | `connection-0` | `connection-4590` |
| **Channel** | **`channel-0`** | **`channel-11825`** |
| Port | `transfer` | `transfer` |
| Ordering | `ORDER_UNORDERED` | `ORDER_UNORDERED` |
| Version | `ics20-1` | `ics20-1` |
| State | `STATE_OPEN` | `STATE_OPEN` |

**SOVR on `osmo-test-5`:**

```
ibc/D737511689BB32FBD3E0917649C11CC0219A50B079DD8266C36A135FD42E49E6
```

The SHA-256 of the denomination trace `transfer/channel-11825/usovr`.

**Escrow (test-sovr-1 side):** `sovr1a53udazy8ayufvy0s434pfwjcedzqv34nugjpa`

The same address as mainnet — not a copy-paste error. The ICS-20 escrow address is derived from the
port and channel (`transfer`/`channel-0`), which are identical on both networks, so the derivation
produces the same address on each chain. They are distinct accounts on distinct chains holding
distinct balances.

## Verify it yourself

```sh
curl -s https://api.testnet.sovrchain.net/ibc/core/channel/v1/channels/channel-0/ports/transfer | jq .channel
curl -s https://api.testnet.sovrchain.net/cosmos/bank/v1beta1/balances/sovr1a53udazy8ayufvy0s434pfwjcedzqv34nugjpa | jq .balances
```

## Notes

- **Canonical client.** `07-tendermint-0` is the client backing this route. Clients
  `07-tendermint-1` and `07-tendermint-2` also exist on `test-sovr-1`: they are throwaway artefacts
  of a client-expiry recovery rehearsal (one was deliberately allowed to expire and then revived by
  governance to prove the recovery path). They are **not** part of this route.
- The testnet route is kept running as a standing soak so its light clients are continuously
  refreshed and the upgrade path stays exercised ahead of mainnet.

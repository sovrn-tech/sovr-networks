# Sovren Mainnet — IBC Routes

The canonical IBC route between `sovr-1` and Osmosis (`osmosis-1`) is **live**. This file is the
human-readable mirror of the corresponding Cosmos chain-registry `_IBC` record.

**Exactly one route is canonical.** Any other channel between these chains — including a
third-party-established one — is not Sovren-published, and no other `ibc/…` denomination should be
treated as SOVR on any counterparty chain.

## Canonical route — `sovr-1` ↔ `osmosis-1`

| | `sovr-1` side | `osmosis-1` side |
|---|---|---|
| Client | `07-tendermint-0` | `07-tendermint-3740` |
| Connection | `connection-2` | `connection-11088` |
| **Channel** | **`channel-0`** | **`channel-110679`** |
| Port | `transfer` | `transfer` |
| Ordering | `ORDER_UNORDERED` | `ORDER_UNORDERED` |
| Version | `ics20-1` | `ics20-1` |
| State | `STATE_OPEN` | `STATE_OPEN` |

**SOVR on Osmosis** — the only canonical denomination:

```
ibc/FB26E04E71EACCCCCD6D81F0F7666D5567C3A1686E2AC577FCC03F28F5B5874F
```

It is the SHA-256 of the denomination trace `transfer/channel-110679/usovr`. Any other `ibc/…`
denom claiming to be SOVR on Osmosis is not canonical, whatever it is called in a UI.

**Escrow (sovr-1 side):** `sovr1a53udazy8ayufvy0s434pfwjcedzqv34nugjpa`

Native SOVR sent to Osmosis is locked here and the voucher above is minted 1:1 against it; sending
the voucher back burns it and releases the native. The escrow balance is therefore the backing for
the circulating voucher supply and is **not** separate supply — query it rather than relying on a
figure printed here, since it changes with every transfer.

## Verify it yourself

```sh
# sovr-1 side
curl -s https://api.sovrchain.net/ibc/core/channel/v1/channels/channel-0/ports/transfer | jq .channel

# osmosis-1 side — must reference channel-0 back
curl -s https://lcd.osmosis.zone/ibc/core/channel/v1/channels/channel-110679/ports/transfer | jq .channel

# the voucher's denomination trace must read transfer/channel-110679/usovr
curl -s https://lcd.osmosis.zone/ibc/apps/transfer/v1/denom_traces/FB26E04E71EACCCCCD6D81F0F7666D5567C3A1686E2AC577FCC03F28F5B5874F | jq .denom_trace

# escrowed native backing the vouchers
curl -s https://api.sovrchain.net/cosmos/bank/v1beta1/balances/sovr1a53udazy8ayufvy0s434pfwjcedzqv34nugjpa | jq .balances
```

Both channels must report `STATE_OPEN` **and** name each other as counterparty. A channel that is
open on one side only is not usable.

## Notes

- **Abandoned connections.** `connection-0` and `connection-1` exist on `sovr-1` in `STATE_INIT`
  and are **not** part of the canonical route. They are residue from establishment attempts that
  failed partway through the handshake when the counterparty RPC rate-limited; IBC has no way to
  delete a connection, so they remain, permanently unusable. The canonical connection is
  `connection-2`.
- **Relaying** is operated by Sovren. Packets are relayed in both directions; a transfer that is
  not relayed times out and refunds on the sending chain rather than being lost.
- The registry `_IBC` record derived from this file carries `preferred: true` for this channel.

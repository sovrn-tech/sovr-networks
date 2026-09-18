# Become a Sovren Mainnet (`sovr-1`) validator

This is the entry point for running a **validator** on the Sovren mainnet
(`sovr-1`) from **public artifacts only** — the public `ghcr.io/sovrn-tech/sovrd`
image and the public genesis. Nothing internal to Sovren is required.

There are two supported ways to run the node; both reach the same place (a synced
node holding your consensus key), after which the **staking** steps are identical.

- **A VM or bare server → Docker Compose** — see [the docker-compose guide](./README.md).
- **Kubernetes → Helm chart** — see the `sovr-node` chart in
  [`sovrn-tech/helm-charts`](https://github.com/sovrn-tech/helm-charts).

Read the safety notes below **first** — validating puts real stake at risk.

---

## ⚠️ The non-negotiables

- **One unique consensus key per validator.** Your `priv_validator_key.json` is
  the validator's identity. **Never run the same key on two machines at once** —
  if two nodes sign the same height that is a **double-sign: ~5% of your stake is
  slashed and the validator is permanently _tombstoned_** (unrecoverable). If you
  run more than one validator, each needs its **own** key.
- **Back up `priv_validator_key.json` offline** the moment it exists. Losing it
  means you can't sign; leaking it means someone can double-sign *as you*.
- **Two phases — only the second risks money:**
  1. A *synced node holding a validator key* does **nothing** on-chain. It's safe.
  2. **`create-validator` + self-delegation** bonds real SOVR and turns on
     slashing exposure. Do it only once the node is fully synced and healthy.
- **Never expose a validator's RPC (26657) publicly.** A validator only needs
  **outbound** P2P to stay connected (it dials the seeds/persistent-peers) —
  **inbound 26656 is optional**, so an outbound-only / NAT'd validator works fine
  and earns rewards. Opening inbound only lets peers discover and dial you; the
  hardened sentry topology deliberately keeps the validator **un-dialable**.

---

## 1. Stand up a synced node

Pick your method and follow its guide to a node that reports `catching_up: false`:

| Method | Guide | Best for |
|---|---|---|
| **Docker Compose** (VM / bare server) | [`./README.md`](./README.md) | a single box you manage directly |
| **Helm chart** (Kubernetes) | [`sovrn-tech/helm-charts` → `sovr-node`](https://github.com/sovrn-tech/helm-charts) | an existing cluster / GitOps (Flux, Argo) |

Both methods **bootstrap from a signed snapshot**, not from genesis. From-genesis
sync is not possible on `sovr-1` with a single modern binary (the chain has had
many on-chain upgrades; one binary can't reproduce the historical app hashes), so
each method restores a published, cosign-verified archive snapshot and then
blocksyncs the short gap to head. Canonical network values (image digest, genesis
sha, seeds) live in [`mainnet/joining.md`](../../mainnet/joining.md).

**Confirm the node is synced and holds your key before staking:**

```sh
# caught up? (must print false)
<exec-into-your-node> curl -fsS localhost:26657/status | jq .result.sync_info.catching_up

# the node's consensus pubkey — you'll put this in validator.json (step 3)
<exec-into-your-node> sovrd comet show-validator
```

`<exec-into-your-node>` is `docker compose exec sovr-validator` for the compose
method, or `kubectl -n <ns> exec <pod> -c sovrd --` for Helm.

## 2. Fund your operator account

The **operator account** is a normal account key, **separate from the consensus
key**. It holds the self-delegation and receives rewards/commission. Create (or
import) it in a keyring **you** control — for Kubernetes, keep it on your admin
machine, **not** in the pod (the pod should hold only the consensus key):

```sh
sovrd keys add <operator-name> --keyring-backend file
sovrd keys show <operator-name> --keyring-backend file -a   # the address to fund
```

Fund that address with your intended bond **plus** a little for gas. SOVR has 6
decimals (1 SOVR = 1,000,000 usovr), so a 10,000-SOVR bond is `10000000000usovr`.
The network gas floor is `0.001usovr` and `min_commission_rate` is `0`. Check the
current active set to be sure your bond enters it (up to 100 validators):

```sh
curl -s "https://api.sovrchain.net/cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED&pagination.limit=500" \
  | jq '[.validators[].tokens|tonumber]|min/1e6'   # lowest bonded, in SOVR
```

## 3. `create-validator` — join the active set

This is the on-chain, money-at-risk step. Do it only once step 1 shows
`catching_up: false`. **You do not have to run it from the node** — only the
consensus *pubkey* comes from the node; the transaction is signed by your operator
key and can be broadcast to any RPC.

Create `validator.json` (amounts/rates are examples — set your own; paste **your**
node's pubkey from `sovrd comet show-validator`):

```json
{
  "pubkey": {"@type":"/cosmos.crypto.ed25519.PubKey","key":"<from show-validator>"},
  "amount": "10000000000usovr",
  "moniker": "<your moniker>",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
```

Submit it from wherever your operator key lives, broadcasting through the public
gateway (`--node`), so your node's RPC never needs to be exposed:

```sh
sovrd tx staking create-validator ./validator.json \
  --from <operator-name> --chain-id sovr-1 --keyring-backend file \
  --node https://rpc.sovrchain.net:443 \
  --gas auto --gas-adjustment 1.3 --gas-prices 0.001usovr
```

- `min-self-delegation` is in **usovr** (so `"1"` = 1 usovr — a safe floor).
- You'll be prompted for the keyring passphrase, then to confirm the tx. **Before
  confirming, check** the `pubkey.key`, `amount`, and commission rates in the
  printed tx.
- The immediate output shows `height: "0"` with empty logs — that's only the
  mempool ack (sync broadcast), **not** the result. Look up the printed `txhash`
  (`sovrd query tx <hash> --node https://rpc.sovrchain.net:443`) — a committed tx
  shows a real height and `code: 0`.

## 4. Verify you are validating — and signing

```sh
# valoper form of your operator address:
VALOPER=$(sovrd keys show <operator-name> --keyring-backend file --bech val -a)
sovrd query staking validator "$VALOPER" --node https://rpc.sovrchain.net:443 -o json \
  | jq '.validator | {status, jailed, tokens}'
# want: status BOND_STATUS_BONDED, jailed false (omitted = false), tokens = your bond
```

Then confirm it's actually **signing** (a bonded validator that doesn't sign gets
jailed for downtime) — run this against your node:

```sh
<exec-into-your-node> sh -c 'sovrd query slashing signing-info $(sovrd comet show-address)'
# healthy: start_height = the block you were created at, index_offset climbing,
# missed_blocks_counter absent/0, jailed_until 1970-…(epoch 0), tombstoned false.
```

If `missed_blocks_counter` climbs, the chain is committing blocks but *your*
signatures aren't landing — a **peer-connectivity** problem, not an inbound-port
one. Check `curl -s localhost:26657/net_info | jq .result.n_peers`; if it's 0/low,
your **outbound** path to the seeds is blocked. Add reliable `persistent_peers`
(e.g. your own sentries) so the node always has peers to gossip with. Inbound
26656 does not need to be open.

## 5. Operations

- **Downtime & unjail — mainnet is unforgiving.** Live `sovr-1` params
  (`curl -s https://api.sovrchain.net/cosmos/slashing/v1beta1/params`):
  `signed_blocks_window=100`, `min_signed_per_window=0.5` — you're jailed if you
  miss **more than 50 of any 100 blocks (~5 minutes offline** at ~6s/block).
  Downtime slash is **1%**; the jail lasts `600s` (10 min). **Even a short outage
  jails you** — size RAM adequately and alert on missed blocks. After a jailing,
  once the node is healthy and synced:
  ```sh
  sovrd tx slashing unjail --from <operator-name> --chain-id sovr-1 \
    --keyring-backend file --node https://rpc.sovrchain.net:443 \
    --gas auto --gas-adjustment 1.3 --gas-prices 0.001usovr
  ```
  Double-sign jailing is **permanent** (tombstone) and cannot be unjailed — never
  run this key anywhere else.
- **Monitoring.** Watch `missed_blocks_counter`, disk usage, and peer count
  (`curl -s localhost:26657/net_info | jq .result.n_peers`).
- **Uptime.** A validator on a home/residential connection is more exposed to
  outages and IP changes — if a dynamic public IP changes, restart the node so it
  re-advertises its external address.
- **Software upgrades.** At a governance `x/upgrade` halt height the node stops and
  waits for the new binary. Follow Sovren's upgrade announcements (plan name +
  height) and update the image/chart version before the height. (Docker Compose:
  bump `SOVR_NODE_IMAGE`; Helm: bump the chart version so cosmovisor swaps.)
- **Unbonding.** The unbonding period is **21 days** — undelegations and a
  decommission wait that long.

---

*Public artifacts only. The canonical network values are in
[`mainnet/joining.md`](../../mainnet/joining.md); node software is published on the
[releases page](https://github.com/sovrn-tech/sovr-networks/releases) and the
`ghcr.io/sovrn-tech` registry — the only official channels.*

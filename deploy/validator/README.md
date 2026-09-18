# Become a Sovren Mainnet (`sovr-1`) validator — docker-compose

> **Status: verified end to end on mainnet** — bare VM → snapshot restore → sync
> → funded operator → `create-validator` → bonded, signing validator. Runs on
> **public artifacts only** (the public image and public genesis; nothing
> internal is required). The sentry topology (§9) is the one still-optional
> follow-up.

This guide takes you from a bare VM to a **signing validator** on `sovr-1`,
using Docker Compose. For the overview, the safety model, and the (method-agnostic)
staking + operations steps, see **[Become a sovr-1 validator](./become-a-validator.md)**;
for the Kubernetes/Helm method see the `sovr-node` chart in
[`sovrn-tech/helm-charts`](https://github.com/sovrn-tech/helm-charts).

## Quick start

```sh
# on a VM with Docker + the Compose plugin (outbound internet is enough;
# inbound 26656 is optional — see the P2P note under "Read this first"):
git clone https://github.com/sovrn-tech/sovr-networks && cd sovr-networks/deploy/validator
./configure.sh          # prompts for your public address + moniker; stages genesis
docker compose up -d && docker compose logs -f
```

`configure.sh` fills in everything operator-specific and pre-verifies the
official artifacts; the sections below explain each step, the safety model, and
what to do after the node is synced (fund, `create-validator`, operate). **Read
the safety notes first** — validating puts stake at risk.

---

## ⚠️ Read this first — validating is high-stakes

- **One unique consensus key per validator.** Your `priv_validator_key.json` is
  the validator's identity. **Never** run the same key on two machines at once
  — if two nodes sign the same height, that is a **double-sign: ~5% of your
  stake is slashed and the validator is _tombstoned_ (permanently removed)**.
  If you also run the Helm/k8s validator, it must use a **different** key.
- **Two phases, and only the second one puts money at risk:**
  1. Running a *synced node that holds a validator key* is safe — it does
     nothing on-chain until you stake.
  2. **`create-validator` + self-delegation** bonds real SOVR and turns on
     slashing exposure (downtime jailing, double-sign slashing). This is a
     deliberate, irreversible-ish on-chain action — do it only when the node is
     fully synced, healthy, and you understand the risk.
- **Back up `priv_validator_key.json`** the instant it is generated, offline.
  Losing it means you cannot sign; leaking it means someone can double-sign *as
  you* and get you slashed.
- **Keep the validator's RPC (26657) private; only P2P (26656) faces the
  internet.** These are two separate things:
  - *RPC / queries (26657, 1317, 9090):* a validator does **not** need to
    serve queries — consensus happens over P2P. This compose already binds
    RPC/REST/gRPC to `127.0.0.1` (localhost) so you can query it for ops but
    the internet cannot. Leave it that way. Only run a separate **fullnode**
    with public RPC if you *want* to offer queries to others; you don't need
    one to validate.
  - *P2P (26656):* your node must stay **connected** to the network, but it does
    that with **outbound** connections to the seeds/persistent-peers (pre-filled
    for mainnet) — it dials out, receives proposals, and gossips its votes. It
    does **not** need to be dialable from the internet: **inbound 26656 is
    optional.** A NAT'd, outbound-only validator validates and earns rewards
    fine. Opening inbound + advertising an `EXTERNAL_ADDRESS` only helps other
    peers *discover and dial you* (good for a public full node); the hardened
    **sentry** topology deliberately keeps the validator **un-dialable** (it
    connects only outbound to its sentries, which face the internet). See §9.

---

## 1. Prerequisites

- A VM with outbound internet access. A public IP + inbound **TCP 26656** is
  **optional** (only needed if you want peers to dial you — see the P2P note
  above); an outbound-only / NAT'd node validates fine via the seeds.
  - **Recommended: 4 vCPU / 8 GiB RAM / 100 GiB SSD.** **Minimum: 2 vCPU /
    4 GiB / 50 GiB SSD.** (`configure.sh` sizes `GOMEMLIMIT`/`MEMORY_LIMIT` to
    whatever RAM you actually have.)
    A live `sovr-1` validator idles at ~0.3 core / ~1 GiB RAM on a pruned
    dataset that currently fits well under 20 GiB — the extra headroom is
    for the CPU/IOPS spike during initial sync and for growth.
  - **Use real SSD/NVMe, not a burst/credit-throttled cloud volume** —
    CometBFT is IOPS-sensitive; a throttled disk makes the node fall
    behind and miss blocks (downtime jailing). Disk need scales with
    **pruning**: these figures are for a pruned node (the default, and
    what snapshot-restore in §5 gives you). An unpruned/archive node
    grows without bound — don't run one as a solo validator.
- **Docker** + the Compose plugin (`docker compose version`).
- `curl`, `jq`, and `sha256sum`/`shasum` for verifying downloads.
- Some **SOVR** in a wallet you control, for the self-delegation (see §6).

## 2. What's pre-filled (and what you provide)

Everything official is already in `.env.example` and tracks the current mainnet
release: the pinned node image + digest, the genesis sha256, the `sovrd` binary
sha256, the seeds, and the signed snapshot bucket + cosign key. You do **not** paste any of these by hand. The
canonical source of truth is the public `sovrn-tech/sovr-networks` repo
(`mainnet/joining.md`, `mainnet/genesis.json`) — cross-check there if you wish.

You provide your **moniker** and — **only if you want inbound peers** — an
**external address** (public IP/DNS or the load balancer in front of the node).
An outbound-only / NAT'd validator needs neither; leave the address blank.
`configure.sh` also sizes `GOMEMLIMIT`/`MEMORY_LIMIT` to your box's RAM.

> The entrypoint re-verifies the genesis sha256 and the in-image `sovrd` sha256
> against the pre-filled `GENESIS_SHA256`/`BINARY_SHA256` on every start and
> **refuses to start** on a mismatch — a wrong artifact fails closed rather than
> joining silently.

## 3. Configure

Run the setup script from this directory:

```sh
./configure.sh
```

It writes `.env` from `.env.example`, then:

- **Moniker** — your validator's public display name.
- **External address** (optional) — auto-detects your public IP and offers to
  accept inbound on it or point at a **load balancer / elastic IP**; choose
  `none` for outbound-only (it then binds P2P to loopback — no inbound).
- **Memory sizing** — reads your RAM and sets `GOMEMLIMIT` (~75%) +
  `MEMORY_LIMIT` (~85%), and warns if you're under 4 GiB / have no swap. This is
  the OOM→jail guard, so don't skip it.
- **Second snapshot anchor** (optional; see §5) — the snapshot restore
  cross-checks against two distinct RPC anchors.
- **Genesis** — copies `mainnet/genesis.json` (or downloads it) and verifies it
  against the pinned `GENESIS_SHA256`.
- **`launch.env` + `checksums.txt`** — creates the presence/integrity artifacts
  the mainnet entrypoint requires (a marker only; never read).
- **Permissions** — `chown`s `./data` to uid 1000 (the container's `sovr` user),
  avoiding the silent first-start failure in §10.

To do it by hand instead, copy `.env.example` to `.env`, set `MONIKER`,
`EXTERNAL_ADDRESS` (only if you want to be dialable), and **`GOMEMLIMIT` +
`MEMORY_LIMIT` per the table in `.env.example`** (compose requires `GOMEMLIMIT`
— it's left unset so a small box can't be silently over-committed), then run the
genesis / `launch.env` / `chown` steps that `configure.sh` performs. The
`SNAPSHOT_ANCHORS` come pre-filled (rpc + rpc2).

`HOST_SOVR_HOME=./data` holds the persistent node home (chain data **and** your
key). `./release` holds the genesis + `launch.env`/`checksums.txt` the node
verifies and stages on first start.

## 4. First start — generate & back up your validator key

```sh
docker compose up -d
docker compose logs -f            # watch it init, verify checksums, and begin syncing
```

On the very first start the node runs `sovrd init`, which **generates a fresh
random `priv_validator_key.json`** — *this is your validator's consensus key.*
As soon as it exists:

```sh
# BACK THIS UP OFFLINE, then guard it. Anyone with it can double-sign as you.
cp data/config/priv_validator_key.json  /secure/offline/backup/
```

> If you are migrating an existing validator key instead of generating a new
> one, stop the node, replace `data/config/priv_validator_key.json` with yours,
> and start again — but only if that key is **not** signing anywhere else.

## 5. Sync to the chain head — snapshot restore is REQUIRED

**You cannot sync `sovr-1` from genesis.** The chain has had many on-chain
upgrades since block 1; replaying old blocks needs the binary that was live at
each height, so a single modern binary computes wrong app hashes and the node
halts with `CONSENSUS FAILURE … wrong Block.Header.AppHash`. You **must**
bootstrap from a published, signed **archive snapshot** (§2 values are pre-filled
in `.env.example`):

```sh
# in .env:
SNAPSHOT_RESTORE=true
# SNAPSHOT_BASEURL / SNAPSHOT_NETWORK / SNAPSHOT_COSIGN_PUBKEY and the two
# SNAPSHOT_ANCHORS (rpc + rpc2) are all pre-filled — no change needed.
```

On a **fresh (empty) home** the node resolves `latest.json`, cosign-verifies it,
cross-checks its `block_hash` against both anchors, downloads + sha256-verifies
the tarball, atomically extracts it, then blocksyncs the short gap to head. The
restore is skipped if `data/application.db` already exists — so if you have a
stale/failed home, stop the node and remove the chain data first:
`docker compose down && sudo rm -rf ./data/data` (keeps `./data/config`, i.e.
your keys), then `docker compose up -d`.

> **The snapshot must be at a height *after* the latest on-chain upgrade.** A
> pre-upgrade snapshot forces catch-up to re-execute pre-upgrade blocks with the
> new binary — the same app-hash mismatch. Check `latest.json`'s `height` against
> the most recent upgrade height before restoring.

> **Anchor note:** the cross-check needs two *distinct* RPC anchors; both public
> ones (`rpc.sovrchain.net` + `rpc2.sovrchain.net`) are pre-filled, so it works
> out of the box. They currently share a backend (rpc2 moves to a second
> datacenter later), so for a genuinely *independent* check — one that can catch a
> single lying/forked source — replace the second with your own already-synced
> node or a trusted third-party RPC.

Wait until caught up before staking:

```sh
docker compose exec sovr-validator \
  sh -c 'curl -fsS http://127.0.0.1:26657/status | jq .result.sync_info.catching_up'
# must print: false
```

## 6. Fund your operator account

The **operator account** (a normal account key) is separate from the consensus
key. It holds the self-delegation and receives rewards/commission.

```sh
# create (or import) your operator key in the node's keyring
docker compose exec sovr-validator sovrd keys add <operator-name> --keyring-backend file
# ^ record the address + mnemonic offline. Fund this address with SOVR.

# confirm the key is there and note the address to fund:
docker compose exec sovr-validator sovrd keys show <operator-name> --keyring-backend file -a
```

**Amounts** (SOVR has 6 decimals: 1 SOVR = 1,000,000 usovr, so multiply by 10^6):

- **Bond (self-delegation):** your choice. The active set holds up to **100**
  validators and is far from full today, so a modest bond enters easily — check
  the current lowest bonded validator to be safe:
  `curl -s "https://api.sovrchain.net/cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED&pagination.limit=500" | jq '[.validators[].tokens|tonumber]|min/1e6'`.
  Example: 10,000 SOVR = `10000000000usovr`.
- **`min-self-delegation`:** expressed in **usovr**, not SOVR. `"1"` (= 1 usovr)
  is a safe permissive floor.
- **Leave headroom for gas** — fund the operator account with a bit more than the
  bond (a few SOVR is plenty; the create-validator tx costs a fraction of one).

The network floor is `0.001usovr` and `min_commission_rate` is `0` (verified
live), so the example commission below is valid.

## 7. `create-validator` — join the active set

> This is the on-chain, staking step. Do it only once §5 shows `catching_up:
> false` and your operator account is funded. This flow is **verified** against
> a live mainnet create-validator.

First get your node's consensus pubkey — this is what identifies *your* running
node, so it must come from the node itself:

```sh
docker compose exec sovr-validator sovrd comet show-validator
# -> {"@type":"/cosmos.crypto.ed25519.PubKey","key":"..."}
```

Create `validator.json`. Put it under `./release/` on the host — that (and
`./data`) are the only paths mounted into the container; it appears inside at
`/etc/sovr/release/validator.json`. Amounts/rates below are an example — set your
own, and paste **your** pubkey from `show-validator`:

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

```sh
docker compose exec sovr-validator sovrd tx staking create-validator \
  /etc/sovr/release/validator.json \
  --from <operator-name> --chain-id sovr-1 --keyring-backend file \
  --gas auto --gas-adjustment 1.3 --gas-prices 0.001usovr
```

You'll be prompted for the keyring passphrase, then shown the tx and a
`confirm transaction before signing and broadcasting [y/N]` prompt. **Before
typing `y`, check** that `pubkey.key` matches your `show-validator` output,
`value.amount` is the bond you intended, and the commission rates are right.

> The immediate output shows `height: "0"` with empty `logs` — that is only the
> **mempool-acceptance ack** (sync broadcast), **not** the on-chain result. Look
> up the real result by the `txhash` it printed (next section) — a committed tx
> shows a real height and `code: 0`.

## 8. Verify you are validating

Your valoper address is your operator address in `valoper` form:

```sh
VALOPER=$(docker compose exec -T sovr-validator \
  sovrd keys show <operator-name> --keyring-backend file --bech val -a | tr -d '\r')

# validator status — note the result is wrapped under `.validator`
docker compose exec sovr-validator sovrd query staking validator "$VALOPER" -o json \
  | jq '.validator | {status, jailed, tokens}'
# want: status BOND_STATUS_BONDED, jailed false (omitted = false), tokens = your bond
```

Then confirm it is actually **signing** (a bonded validator that doesn't sign
gets jailed for downtime):

```sh
docker compose exec sovr-validator sh -c \
  'sovrd query slashing signing-info $(sovrd comet show-address)'
# healthy: start_height = the block you were created at, index_offset climbing,
# missed_blocks_counter absent/0, jailed_until 1970-…(epoch 0), tombstoned false.
```

Give it a few minutes and re-check `missed_blocks_counter` stays at/near 0. If it
climbs, the chain is committing blocks but *your* signatures aren't landing — it's
a **peer-connectivity** problem, not an inbound-port one. Check your peer count
(`docker compose exec sovr-validator sh -c 'curl -s localhost:26657/net_info | jq
.result.n_peers'`); if it's 0/low, your outbound path to the seeds is blocked or
the seeds are unreachable. The fix is reliable **outbound** peers — add trusted
`PERSISTENT_PEERS` (e.g. your own sentries) so the node always has someone to
gossip with. (Opening inbound 26656 is not required for this.)

## 9. Operations

- **Downtime & unjail — mainnet is unforgiving.** Live `sovr-1` slashing params
  (verify with `curl -s https://api.sovrchain.net/cosmos/slashing/v1beta1/params`):
  `signed_blocks_window=100`, `min_signed_per_window=0.5` — so you're jailed if you
  miss **more than 50 of any 100 blocks (~5 minutes offline** at ~6s/block).
  Downtime slash is **1%** of stake and the jail lasts `600s` (10 min). This means
  **even a short outage jails you** — treat uptime seriously (adequate RAM, alerts
  on missed blocks). After a jailing, once the node is healthy and synced:
  ```sh
  sovrd tx slashing unjail --from <operator-name> --chain-id sovr-1 \
    --keyring-backend file --gas auto --gas-adjustment 1.3 --gas-prices 0.001usovr
  ```
  Double-sign jailing is **permanent** (tombstone) and cannot be unjailed — never
  run this key elsewhere.
- **Monitoring:** watch `missed_blocks_counter` (above), disk usage, and peer
  count (`curl -s localhost:26657/net_info | jq .result.n_peers`).
- **Unbonding:** the unbonding period is **21 days** (`1814400s`) — undelegations
  and a decommission wait that long.
- **Sentry topology:** optional P2P DDoS/IP hardening — a validator can sit behind
  sentries instead of exposing P2P directly (see the "Read this first" safety
  note above). Not required to validate; a follow-up to document for the public
  method.
- **Software upgrades:** at a governance `x/upgrade` halt height the node stops and
  waits for the new binary — bump `SOVR_NODE_IMAGE` in `.env` to the new release
  digest and `docker compose up -d` to resume. (Watch Sovren's upgrade
  announcements for the plan name + height.)
- **Key rotation / decommission:** unbond/redelegate, then remove the node; the
  consensus key cannot be rotated in place without a new validator.

## 10. Troubleshooting

- **First start exits code 1, logs stop at `Preparing node home…`** (no
  `Prepared node home…` line follows) → a **home-volume permission problem**,
  not the integrity gate. The container runs as user `sovr` (**uid 1000**), and
  if your `HOST_SOVR_HOME` dir (`./data`) is owned by a different user (often
  `root`, if it was created with `sudo`/by Docker), `sovrd init` can't write it
  and fails — its error is suppressed, so it looks silent. Confirm and fix:
  ```sh
  # confirm: prints "NOT WRITABLE" and shows the dir owned by uid 0, not 1000
  docker compose run --rm --entrypoint sh sovr-validator -c \
    'id; touch /home/sovr/.sovr/.w 2>&1 && echo WRITABLE || echo "NOT WRITABLE"; ls -ldn /home/sovr/.sovr'
  # fix: match the image's uid, then restart
  sudo chown -R 1000:1000 ./data && docker compose up -d
  ```
- Node exits immediately on start → it's the mainnet integrity gate. Re-check
  `GENESIS_SHA256`, `BINARY_SHA256`, `SEEDS`, and `EXTERNAL_ADDRESS` in `.env`
  (the log line names the failed check).
- No peers (`n_peers` = 0) → this is about **outbound** connectivity: confirm the
  node can reach the seeds (`SEEDS`) on port 26656 outbound, and add reliable
  `PERSISTENT_PEERS` if the seeds are flaky. Inbound 26656 does **not** need to be
  open. (`EXTERNAL_ADDRESS` only affects whether others can dial *you*.)
- `catching_up` never reaches `false` → check peers/seeds and disk; consider the
  snapshot-restore bootstrap (§5).

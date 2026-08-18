# Security Policy

Sovren takes the security of the Sovren Layer 1 (`sovr-1`), its modules, and the
network surfaces published here seriously. This document explains how to report a
vulnerability and what to expect in return.

## Reporting a vulnerability

**Email `security@sovrentech.io`** — a restricted-access inbox monitored by the
security team. Do **not** report security issues through the public Discord, the
general `support@` inbox, GitHub issues, or any public channel.

Encrypt sensitive reports with our PGP key:

- **PGP fingerprint:** `D3B3 1E04 56E0 19DD C45F  C6A8 7736 3E81 6638 AF41`
- **Key ID:** `0x77363E816638AF41` · **User ID:** `Sovren Security Team <security@sovrentech.io>`
- **Algorithm:** ed25519 signing key with a cv25519 encryption subkey · **Created:** 2026-08-17

The key is published in this repository as [`security-pgp-key.asc`](security-pgp-key.asc). Import
it and **verify the fingerprint above matches** before encrypting anything:

```sh
gpg --import security-pgp-key.asc
gpg --fingerprint security@sovrentech.io   # must match the fingerprint above
```

A useful report includes: a description of the issue, the affected component and
version/height, reproduction steps or a proof of concept, and the potential
impact. Please give us a reasonable window to remediate before any public
disclosure (see below).

## Scope

In scope:

- The Sovren chain (`sovrd`) and its custom Cosmos SDK modules (supply, distro,
  settlement, bridge, and the service modules), consensus, and state machine.
- Genesis, chain parameters, and the network metadata published in **this**
  repository.
- The public network endpoints listed in the README (`rpc`/`api`/`explorer`).

Out of scope (report to the relevant owner instead):

- Third-party infrastructure, wallets, explorers, or exchanges not operated by
  Sovren.
- Social engineering, physical attacks, and volumetric DoS.
- Findings that require a privileged position we do not grant (e.g. a
  compromised validator key you already control).

## Response targets

| Stage | Target |
|---|---|
| Acknowledgement of your report | within **72 hours** |
| Initial triage & severity assessment | within **7 days** |
| Status updates | at least every **7 days** until resolved |
| Fix / mitigation timeline | communicated at triage, based on severity |

## Coordinated disclosure

- We follow coordinated disclosure. Please keep the report confidential until a
  fix (or documented mitigation) is deployed and we have agreed on a disclosure
  date.
- For consensus- or funds-affecting issues, disclosure may be delayed until the
  network has upgraded, and may involve coordinating with validators and
  integrators.
- We are happy to credit reporters who follow this policy.

## Safe harbour

We will not pursue or support legal action against researchers who, in good
faith:

- make a genuine effort to avoid privacy violations, data destruction, and
  service interruption while researching;
- only interact with accounts they own or have explicit permission to test;
- report promptly through `security@sovrentech.io`; and
- keep findings confidential until coordinated disclosure.

Testing against the **public testnet** (`test-sovr-1`) is preferred; the faucet
provides funds for that purpose. Do not test against mainnet in ways that could
degrade the network or affect other users.

# Changelog

Versions are [semver](https://semver.org/) and match the Docker Hub image
tags (`ghcr.io/itefix/ulaknode:<version>`).

## 2.6.0 - 2026-10-18

- Removed ClamAV: it blocked nothing real in production and cost ~1 GB RAM.
  Smaller image, no signature-update daemon, less attack surface.
- `postscreen_greet_action = enforce`: clients that talk before the banner
  (PREGREET) are now rejected.
- `ulaknode-agent` requires a shared-secret token (`ULAKNODE_AGENT_TOKEN`).

## 2.5.0

- Fail2ban, Unbound-backed DNSBL checks (Spamhaus, SpamCop), opendkim/opendmarc
  logging fixes.

## 2.0.0

- Initial tracked release: Postfix, Dovecot, OpenDKIM/OpenDMARC, policyd-spf,
  Postgrey, SpamAssassin in a single container.

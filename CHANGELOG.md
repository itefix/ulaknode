# Changelog

Versions are [semver](https://semver.org/) and match the Docker Hub image
tags (`ghcr.io/itefix/ulaknode:<version>`).

## 2.6.1 - 2026-10-27

- `ULAKNODE_VERSION` is now set correctly inside the image (it was `dev`), so
  `ulaknode-version` reports the real release.
- Image rebuilds run monthly instead of weekly to pick up Debian security
  updates.
- Build summary lists the installed component versions for each architecture.
- Untagged package versions older than one year are pruned automatically.
- Updated support information.

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

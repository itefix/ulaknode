# Changelog

Versions are [semver](https://semver.org/) and match the Docker Hub image
tags (`ghcr.io/itefix/ulaknode:<version>`).

## 2.8.0 - 2026-11-25

- Removed SpamAssassin (spamd and spamass-milter): content scoring is gone;
  inbound filtering is now postscreen/DNSBL, SPF, DKIM and DMARC. Smaller
  image, two fewer daemons. `ulaknode-service`, `ulaknode-errlog` and
  `ulaknode-version` no longer know about it.
- Upgrading: the `ulak_spamassassin` volume (`-v ulak_spamassassin:/etc/spamassassin`)
  is no longer used and can be dropped from your run command / compose file
  and deleted. The obsolete spamass-milter socket is removed automatically from
  an existing `/etc/postfix/master.cf` at startup.

## 2.7.0 - 2026-11-19

- Removed Postgrey (greylisting): the retry delay was too intrusive for
  mail-based OTP and password-reset flows. Smaller image, one less daemon.
  `ulaknode-service`, `ulaknode-errlog` and `ulaknode-version` no longer
  know about it.
- Upgrading: the `ulak_postgrey` volume (`-v ulak_postgrey:/etc/postgrey`) is
  no longer used and can be dropped from your run command / compose file and
  deleted. The obsolete `check_policy_service inet:127.0.0.1:10023` entry is
  removed automatically from an existing `/etc/postfix/main.cf` at startup.

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

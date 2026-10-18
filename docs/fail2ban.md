# Brute-force protection with Fail2ban

ulaknode runs Fail2ban **inside** the container as one of its supervised
services — no separate install, no host bind-mounts. It starts
automatically with the rest of the stack.

Fail2ban's default ban action writes `iptables` rules, which don't work
from inside a container's network namespace. Instead, ulaknode's Fail2ban
is configured with a custom action that bans at the application layer:
it edits the same access-control tables Postfix and Dovecot already read
(a Postfix `cidr` access table for SMTP, a Dovecot filter-scoped `deny`
passdb for IMAP) rather than touching the network stack. That means it
needs no elevated container privileges (`NET_ADMIN`/`--privileged`) — it
only needs what it already has: read access to `/var/log` and write
access to `/etc/postfix`/`/etc/dovecot`.

```
attacker → Postfix/Dovecot reject at the application layer (Fail2ban bans here)
```

**This stops credential-stuffing and brute-force login attempts, not
volumetric floods.** A banned IP still completes the TCP handshake and
gets an instant reject — that's fine for repeated bad logins, but actual
flood/DoS protection is a host- or network-edge concern (rate-limiting
at your firewall or provider), outside what an application-layer ban can
do.

What's already protecting you in addition to this:

- **Postgrey greylisting** — delays unknown senders, eliminates most bot-originated spam
- **Dovecot `auth_failure_delay`** — slows down IMAP password guessing
- **Postfix connection/rate limits** (`smtpd_client_connection_rate_limit`,
  `smtpd_client_message_rate_limit`, etc.) — caps how much a single IP can
  do even before Fail2ban reacts

> RBL/DNSBL blocklist checking (Spamhaus Zen, SpamCop) runs via `postscreen`
> ahead of Fail2ban, backed by a dedicated Unbound resolver so queries
> aren't misclassified as coming from a shared/open resolver. See
> `docs/self-hosted.md` for details.

---

## The two jails

| Jail | Watches | Triggers on |
|---|---|---|
| `ulaknode-smtp` | `/var/log/mail.log` | SASL auth failures, unauthorized RCPT attempts |
| `ulaknode-imap` | `/var/log/dovecot.log` | IMAP login failures |

Both default to `maxretry = 5`, `findtime = 10m`, `bantime = 1h`. A ban
from `ulaknode-smtp` blocks SMTP (25/587) only; a ban from
`ulaknode-imap` blocks IMAP (993) only — each protocol is banned
independently, at its own layer.

---

## Inspecting and managing bans

The ban *mechanism* changed, but the Fail2ban CLI you'd normally reach
for is unchanged — it's just running inside the container now:

```bash
docker exec ulaknode fail2ban-client status
docker exec ulaknode fail2ban-client status ulaknode-smtp
docker exec ulaknode fail2ban-client status ulaknode-imap
```

To unban an IP manually:

```bash
docker exec ulaknode fail2ban-client set ulaknode-smtp unbanip <ip>
docker exec ulaknode fail2ban-client set ulaknode-imap unbanip <ip>
```

To see exactly what's being enforced at the Postfix/Dovecot layer:

```bash
docker exec ulaknode cat /etc/postfix/fail2ban_clients
docker exec ulaknode ls /etc/dovecot/fail2ban.d/
```

---

## Tuning

Edit `/etc/fail2ban/jail.d/ulaknode.conf` (persisted in the
`ulak_fail2ban` volume, survives restarts and upgrades), then reload:

```bash
docker exec ulaknode vi /etc/fail2ban/jail.d/ulaknode.conf
docker exec ulaknode ulaknode-service reload fail2ban
```

### Persistent, escalating bans

By default, `bantime` is fixed and bans reset on their own after it
expires. For repeat offenders, add progressive escalation:

```ini
# /etc/fail2ban/jail.d/ulaknode.conf — add to each jail:
bantime.increment = true
bantime.multiplier = 24
bantime.maxtime = 30d
```

This extends ban times for repeat offenders up to 30 days.

---

## Troubleshooting

- **A ban isn't clearing / a legitimate IP got stuck banned:** first try
  the normal unban command above. If that doesn't work (e.g. Fail2ban's
  own state and the enforcement files have gotten out of sync), remove
  the entry directly and reload:

  ```bash
  # SMTP — edit out the offending line
  docker exec ulaknode sed -i "/^<ip> /d" /etc/postfix/fail2ban_clients
  docker exec ulaknode ulaknode-service reload postfix

  # IMAP — remove its ban file
  docker exec ulaknode rm -f "/etc/dovecot/fail2ban.d/<ip-with-dots-for-colons-and-slashes>.conf"
  docker exec ulaknode ulaknode-service reload dovecot
  ```

- **Fail2ban isn't banning anything:** check it's running
  (`docker exec ulaknode ulaknode-service status fail2ban`) and check its
  own log for filter/action errors:
  `docker exec ulaknode ulaknode-errlog fail2ban`.

- **Bans don't survive a container restart the way you'd expect:**
  confirm the `ulak_fail2ban` volume is actually mounted — without it,
  Fail2ban's ban-tracking database resets on every restart and it will
  never issue the matching unban for anything it forgot about.

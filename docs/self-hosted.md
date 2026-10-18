# Self-hosted deployment

This guide covers deploying Ulaknode on your own Linux server or VM.

---

## Requirements

- Linux server (Ubuntu 22.04+ or Debian 12+ recommended)
- 2+ vCPU, 4+ GB RAM, 40+ GB disk
- A public IP address you control
- A domain name with DNS management access
- Docker installed

---

## 1. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

---

## 2. Configure DNS

Before starting the container, set up DNS records for your domain:

| Record | Type | Value |
|---|---|---|
| `mail.yourdomain.com` | A | Your server's public IP |
| `yourdomain.com` | MX | `mail.yourdomain.com` (priority 10) |

PTR (reverse DNS) should also point your IP back to `mail.yourdomain.com`. This is configured through your hosting provider or ISP and is important for mail deliverability.

SPF, DKIM, and DMARC records should be added after the container is running (see step 6).

---

## 3. Open firewall ports

Allow inbound TCP on the following ports:

| Port | Protocol | Purpose |
|---|---|---|
| 25 | SMTP | Inbound mail from other servers |
| 587 | Submission | Outbound mail from mail clients |
| 993 | IMAPS | Mailbox access (TLS) |

> **Note:** Some ISPs and hosting providers block port 25 by default. Contact your provider to have it unblocked before proceeding.

Also make sure **outbound** UDP/TCP 53 is allowed to the internet at large (not just to one resolver). The container runs its own recursive DNS resolver (Unbound) that queries root/TLD/authoritative servers directly instead of forwarding to your host's resolver — see [DNSBL blocklist checking](#dnsbl-blocklist-checking) below for why. Some hosting providers/firewalls restrict outbound DNS to their own resolver only, which would need an exception.

---

## 4. Run the container

The image is published on Docker Hub — `docker run` pulls it automatically
if it isn't present locally, so no separate pull step is needed. Replace
`mail.yourdomain.com` with your actual mail hostname:

```bash
docker run -d \
  --name ulaknode \
  --hostname mail.yourdomain.com \
  --restart unless-stopped \
  -e MAIL_HOSTNAME=mail.yourdomain.com \
  -p 25:25 -p 587:587 -p 993:993 \
  -v ulak_mail:/var/mail \
  -v ulak_logs:/var/log \
  -v ulak_postfix:/etc/postfix \
  -v ulak_dovecot:/etc/dovecot \
  -v ulak_opendkim:/etc/opendkim \
  -v ulak_opendmarc:/etc/opendmarc \
  -v ulak_spamassassin:/etc/spamassassin \
  -v ulak_policyd_spf:/etc/postfix-policyd-spf-python \
  -v ulak_postgrey:/etc/postgrey \
  -v ulak_fail2ban:/etc/fail2ban \
  -v ulak_unbound:/etc/unbound \
  -v ulak_certs:/etc/ssl/mail \
  -v /etc/letsencrypt/live/mail.yourdomain.com/fullchain.pem:/run/certs/fullchain.pem:ro \
  -v /etc/letsencrypt/live/mail.yourdomain.com/privkey.pem:/run/certs/privkey.pem:ro \
  ghcr.io/itefix/ulaknode:latest
```

Named volumes are created automatically on first run.

---

## 5. Configure TLS

Copy your certificate files into the container, then install them with `ulaknode-cert`:

```bash
docker cp fullchain.pem ulaknode:/tmp/fullchain.pem
docker cp privkey.pem   ulaknode:/tmp/privkey.pem

docker exec ulaknode ulaknode-cert install /tmp/fullchain.pem /tmp/privkey.pem
```

Then restart the affected services:

```bash
docker exec ulaknode ulaknode-service restart postfix
docker exec ulaknode ulaknode-service restart dovecot
```

To verify the installed certificate at any time:

```bash
docker exec ulaknode ulaknode-cert show
docker exec ulaknode ulaknode-cert check
```

---

## 6. Add DKIM, SPF, and DMARC records

**DKIM** — generate a key for your domain and publish the resulting DNS record:

```bash
docker exec ulaknode ulaknode-dkim generate yourdomain.com
# prints the DNS TXT record to publish, then:
docker exec ulaknode ulaknode-service reload opendkim
```

To retrieve the record again later:

```bash
docker exec ulaknode ulaknode-dkim show yourdomain.com
```

**SPF** — generate the record value for your domain:

```bash
docker exec ulaknode ulaknode-spf generate yourdomain.com --mx
# prints the DNS TXT record to publish
```

**DMARC** — generate the record value. Start with `--policy none` to monitor before enforcing:

```bash
docker exec ulaknode ulaknode-dmarc generate yourdomain.com \
  --policy none \
  --rua mailto:postmaster@yourdomain.com
# prints the DNS TXT record to publish
```

All three commands only print the DNS records — publish them in your DNS provider's control panel.

---

## 7. Create domains, mailboxes, and aliases

**Domains** — add a domain before creating any mailboxes under it:

```bash
docker exec ulaknode ulaknode-domain add yourdomain.com
docker exec ulaknode ulaknode-domain list
```

**Mailboxes:**

```bash
# Add
docker exec ulaknode ulaknode-mailbox add user@yourdomain.com <password>

# Set a quota (optional)
docker exec ulaknode ulaknode-mailbox quota-set user@yourdomain.com 2G

# List all mailboxes for a domain
docker exec ulaknode ulaknode-mailbox list yourdomain.com

# Change password
docker exec ulaknode ulaknode-mailbox passwd user@yourdomain.com <newpassword>

# Remove
docker exec ulaknode ulaknode-mailbox remove user@yourdomain.com
```

**Aliases:**

```bash
# Add
docker exec ulaknode ulaknode-alias add info@yourdomain.com user@yourdomain.com

# List all aliases for a domain
docker exec ulaknode ulaknode-alias list yourdomain.com

# Remove
docker exec ulaknode ulaknode-alias remove info@yourdomain.com
```

---

## Sidecar integration (`ulaknode-agent`)

If you run a separate admin UI container (like `ulaknode-web`) that needs to
change mailbox passwords or quotas without a shared filesystem or `docker
exec` access into this container, `ulaknode-agent` is a small TCP RPC
listener built for that — started automatically by `docker-init`. It's
opt-in in effect: nothing calls it unless a sidecar is configured to, and it
rejects every request until you set a shared-secret token.

```bash
# Generate a token once, then set it identically on both containers
openssl rand -hex 32
```

```yaml
# docker-compose.yml, on the ulaknode service
environment:
  - ULAKNODE_AGENT_TOKEN=<the token you generated>
```

Set the same value on the sidecar's own config (e.g. `ulaknode-web`'s
`ULAKNODE_AGENT_TOKEN`). Every request must carry it; `ulaknode-agent` fails
closed — if the token isn't set here, or doesn't match what the caller sent,
every command is rejected before any command-specific logic runs. If you
forgot to set it, `docker-init` logs a startup warning to the container's
own stdout (check `docker logs ulaknode`), since the rejection itself is
otherwise silent from the caller's side.

By default `ulaknode-agent` binds to `127.0.0.1:8787` and only accepts
connections from `127.0.0.1/32` — correct for a sidecar sharing this
container's network namespace. For a sidecar running as its own container on
a bridge network, widen both:

| Variable | Default | Purpose |
|---|---|---|
| `ULAKNODE_AGENT_TOKEN` | *(empty — required)* | Shared secret; every request must include it |
| `ULAKNODE_AGENT_BIND` | `127.0.0.1` | Listen address |
| `ULAKNODE_AGENT_ALLOWED_IPS` | `127.0.0.1/32` | Allowed client IP(s), CIDR |
| `ULAKNODE_AGENT_PORT` | `8787` | Listen port |

Leave all four unset if you're not running a sidecar — the mail server
itself never uses `ulaknode-agent`.

---

## Brute-force protection (Fail2ban)

Fail2ban runs automatically as part of the stack — no setup needed. It
bans brute-force SMTP/IMAP clients at the Postfix/Dovecot application
layer (edits the same access-control tables those services already read,
rather than touching `iptables`), so it needs no extra container
privileges.

```bash
docker exec ulaknode fail2ban-client status
```

Full details, tuning, and troubleshooting: [docs/fail2ban.md](fail2ban.md).

---

## DNSBL blocklist checking

Inbound connections are checked against DNSBL blocklists (Spamhaus Zen, SpamCop) by `postscreen`, before a full SMTP session even starts. Public DNSBL providers throttle or misclassify queries coming from resolvers that are shared across many users/customers, so this stack runs its own recursive resolver — **Unbound** — dedicated to just this mail server, instead of forwarding to your host's default DNS.

This is on by default; no setup needed. To tune it, edit `/etc/postfix/main.cf` (persistent volume):

```bash
docker exec -it ulaknode vi /etc/postfix/main.cf
# postscreen_dnsbl_sites, postscreen_dnsbl_threshold, postscreen_dnsbl_action
docker exec ulaknode ulaknode-service reload postfix
```

Unbound's own settings (cache size, logging) live in `/etc/unbound/unbound.conf.d/ulaknode.conf`, also a persistent volume — restart with `docker exec ulaknode ulaknode-service restart unbound` after editing.

---

## Verify everything is running

```bash
docker exec ulaknode ulaknode-service status all
```

---

## Troubleshooting

- **Permission errors after editing configs:** run `docker exec ulaknode fix-permissions /etc/ulaknode`
- **Port 25 not reachable:** check your firewall rules and confirm your ISP/provider has unblocked the port
- **Service errors:** use `docker exec ulaknode ulaknode-errlog <service>` to inspect recent error logs
- **Mail rejected with "Service unavailable" / DNSBL false positives, or Unbound failing to resolve:** check `docker exec ulaknode ulaknode-errlog unbound` — if outbound port 53 is firewalled to the internet at large, Unbound can't do recursive resolution and DNS (DNSBL checks, MX lookups, everything) breaks. See the outbound firewall note in [step 3](#3-open-firewall-ports).

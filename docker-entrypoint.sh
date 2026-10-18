#!/bin/bash
set -e

# -------------------------------------------------------------
# Seed config volumes on first boot
# -------------------------------------------------------------
for svc in postfix dovecot opendkim opendmarc spamassassin postfix-policyd-spf-python postgrey fail2ban unbound; do
    MARKER="/etc/${svc}/.seeded"
    if [[ ! -f "$MARKER" ]]; then
        echo "Seeding /etc/${svc} from image defaults..."
        cp -rn /etc/${svc}.defaults/. /etc/${svc}/
        touch "$MARKER"
    fi
done

# -------------------------------------------------------------
# Apply hostname from environment
# -------------------------------------------------------------
if [[ -n "${MAIL_HOSTNAME:-}" ]]; then
    MAIL_DOMAIN="${MAIL_DOMAIN:-${MAIL_HOSTNAME#*.}}"
    echo "Configuring hostname: $MAIL_HOSTNAME (domain: $MAIL_DOMAIN)"
    postconf -e "myhostname = $MAIL_HOSTNAME"
    postconf -e "myorigin = $MAIL_HOSTNAME"
    postconf -e "mydomain = $MAIL_DOMAIN"
fi

# -------------------------------------------------------------
# Initialise Postfix hash maps
# -------------------------------------------------------------
for _map in /etc/postfix/virtual_domains \
            /etc/postfix/virtual_mailboxes \
            /etc/postfix/virtual_aliases; do
    [[ -f "$_map" ]] || touch "$_map"
    postmap "$_map"
done
unset _map

# -------------------------------------------------------------
# Install TLS certificate
# -------------------------------------------------------------
if [[ ! -f /run/certs/fullchain.pem || ! -f /run/certs/privkey.pem ]]; then
    echo "Error: TLS certificate files not found. Mount fullchain.pem and privkey.pem at /run/certs/." >&2
    exit 1
fi
echo "Installing TLS certificate from /run/certs..."
/usr/local/bin/ulaknode-cert install /run/certs/fullchain.pem /run/certs/privkey.pem

/usr/local/bin/set-conf-permissions

# -------------------------------------------------------------
# Start main process
# -------------------------------------------------------------
echo "Starting services..."
exec "$@"

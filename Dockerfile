# syntax=docker/dockerfile:1

# --- Base ----------------------------------------------------------------
FROM debian:stable-slim

ARG VERSION=dev
ENV ULAKNODE_VERSION=${VERSION}

# Minimise apt memory usage — must come before the first apt-get update.
# Acquire::Languages "none"  → skip all translation/i18n indices (~50-100 MB RAM saved per update)
# The Install-* lines are belt-and-suspenders alongside --no-install-recommends.
RUN printf '%s\n' \
        'Acquire::Languages "none";' \
        'APT::Get::Install-Recommends "false";' \
        'APT::Get::Install-Suggests "false";' \
    > /etc/apt/apt.conf.d/00-ulaknode

# Install tools needed to add upstream repos
RUN apt-get update && apt-get -y install --no-install-recommends \
    curl gnupg2 lsb-release ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Add upstream repos (Dovecot — Debian stable lags significantly)
RUN curl -fsSL https://repo.dovecot.org/DOVECOT-REPO-GPG-2.4 \
        | gpg --dearmor > /usr/share/keyrings/dovecot.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/dovecot.gpg] https://repo.dovecot.org/ce-2.4-latest/debian/$(lsb_release -cs) $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/dovecot.list

# Install — one apt-get per RUN so each step gets a fresh container (no
# cumulative page-cache/RSS growth across the whole install) and, if one
# ever OOMs again, the failing layer tells us exactly which package it was.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get -y install --no-install-recommends \
        curl sudo dnsutils netcat-openbsd iproute2 socat \
        libsasl2-modules lsb-release ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends postfix && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends dovecot-imapd dovecot-lmtpd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends opendkim opendkim-tools && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends opendmarc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends spamassassin spamd spamc spamass-milter && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends postfix-policyd-spf-python && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends postgrey && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends fail2ban && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get -y install --no-install-recommends unbound dns-root-data && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Seed unbound's DNSSEC trust anchor from dns-root-data's bundled copy.
# Normally a systemd ExecStartPre (unbound-anchor) does this on first boot,
# but that never runs in a container build; without a root.key at this
# path, unbound's validator module fails to init and the daemon dies
# immediately after binding its listening socket. auto-trust-anchor-file
# lets unbound self-maintain this file afterwards (RFC 5011 rollover), so
# this is a one-time seed, not something that needs redoing at container
# start.
RUN install -o unbound -g unbound -m 0644 \
        /usr/share/dns/root.key /var/lib/unbound/root.key

# Create a shared group with service members
RUN groupadd --system ulaknode-mail && \
    usermod -a -G ulaknode-mail postfix && \
    usermod -a -G ulaknode-mail dovecot && \
    usermod -a -G ulaknode-mail opendkim && \
    usermod -a -G ulaknode-mail opendmarc && \
    usermod -a -G ulaknode-mail debian-spamd && \
    usermod -a -G ulaknode-mail postgrey

# Copy configurations into default locations
COPY postfix/conf/     /etc/postfix/
COPY dovecot/conf/     /etc/dovecot/
COPY opendkim/         /etc/opendkim/
COPY opendmarc/        /etc/opendmarc/
COPY spamassassin/     /etc/spamassassin/
COPY policyd-spf/      /etc/postfix-policyd-spf-python/
COPY postgrey/         /etc/postgrey/
COPY unbound/          /etc/unbound/

# fail2ban/ only adds to the package's stock config tree (jail.d/,
# filter.d/, action.d/, fail2ban.local) — it must not replace it, since
# the package ships ~150 filters/actions we still want on disk.
COPY fail2ban/          /etc/fail2ban/

# Seed copies — used to populate fresh volumes
COPY postfix/conf/     /etc/postfix.defaults/
COPY dovecot/conf/     /etc/dovecot.defaults/
COPY opendkim/         /etc/opendkim.defaults/
COPY opendmarc/        /etc/opendmarc.defaults/
COPY spamassassin/     /etc/spamassassin.defaults/
COPY policyd-spf/      /etc/postfix-policyd-spf-python.defaults/
COPY unbound/          /etc/unbound.defaults/
# Snapshot the merged result (package defaults + our additions), not just
# our repo folder — copying only fail2ban/ here would seed a fresh volume
# with our 4 files and lose the package's stock filter/action library.
# Same for postgrey: the package ships the big whitelist_clients /
# whitelist_recipients lists; our repo only adds the .local companions.
RUN cp -r /etc/fail2ban /etc/fail2ban.defaults && \
    cp -r /etc/postgrey /etc/postgrey.defaults

# Copy scripts
COPY scripts/* /usr/local/bin/
RUN chmod 755 /usr/local/bin/*

# Create runtime directories
RUN mkdir -p /run/opendkim /run/opendmarc /run/spamassassin /run/spamass-milter /run/postgrey /run/fail2ban /run/unbound && \
    chown -R opendkim:opendkim /run/opendkim && \
    chown -R opendmarc:opendmarc /run/opendmarc && \
    chown -R debian-spamd:debian-spamd /run/spamassassin /run/spamass-milter && \
    chown -R postgrey:postgrey /run/postgrey && \
    chown -R unbound:unbound /run/unbound && \
    chgrp ulaknode-mail /run/opendkim /run/opendmarc /run/spamass-milter && \
    chmod 2770 /run/opendkim /run/opendmarc /run/spamass-milter

# Create DKIM key store
RUN mkdir -p /etc/opendkim/keys /etc/opendkim.defaults/keys && \
    chown -R opendkim:opendkim /etc/opendkim/keys /etc/opendkim.defaults/keys && \
    chmod 750 /etc/opendkim/keys /etc/opendkim.defaults/keys

# Copy entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose mail ports + the ulaknode-agent sidecar RPC port (loopback-only by
# default; see ULAKNODE_AGENT_BIND/ULAKNODE_AGENT_ALLOWED_IPS in docker-init)
EXPOSE 25 587 993 8787

HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
    CMD postfix status && dovecot status \
        && test -S /run/opendkim/opendkim.sock \
        && test -S /run/opendmarc/opendmarc.sock \
        && dig +short +time=2 +tries=1 @127.0.0.1 . NS > /dev/null \
        || exit 1

# Persistent volumes
VOLUME ["/var/mail", "/var/log", "/etc/postfix", "/etc/dovecot", "/etc/ssl/mail", \
        "/etc/opendkim", "/etc/opendmarc", "/etc/spamassassin", \
        "/etc/postfix-policyd-spf-python", "/etc/postgrey", "/etc/fail2ban", \
        "/etc/unbound"]

# Entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/docker-init"]

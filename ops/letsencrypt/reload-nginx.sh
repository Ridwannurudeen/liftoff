#!/bin/bash
# certbot deploy hook: reload nginx whenever any cert is renewed.
#
# Install on VPS:
#   sudo install -m 0755 reload-nginx.sh /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
#
# Background: cli.ini pins `authenticator = webroot`, which means certbot does NOT
# touch nginx during renewal -- so a renewed cert is not picked up until nginx
# reloads. The existing fix-nginx-listeners.sh hook only reloads when it edits a
# listener line; on a normal renewal it's a no-op. This hook guarantees a reload.

set -e
if nginx -t 2>/dev/null; then
    nginx -s reload
    logger -t certbot-reload "nginx reloaded after cert renewal"
else
    logger -t certbot-reload "nginx -t failed; SKIPPED reload to avoid breaking serving"
    exit 1
fi

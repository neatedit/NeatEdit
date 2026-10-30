#!/bin/sh
# Deploy web/ to neatedit.gt-d.cz.
#
#   scripts/deploy-site.sh          back up the live site, upload, smoke-test
#   scripts/deploy-site.sh -n       dry run: show what would change, upload nothing
#
# Nothing is ever deleted remotely. Each deploy first tars the live site to
# /root/neatedit-site-backup-<time>.tgz; the newest ten are kept. Restore with:
#   ssh root@134.209.8.62 'tar xzf /root/neatedit-site-backup-<time>.tgz -C /var/www'
set -eu

HOST=root@134.209.8.62
ROOT=/var/www/neatedit
SITE=https://neatedit.gt-d.cz

cd "$(dirname "$0")/.."

# Deploy only what is committed, so the live site can always be traced to a commit.
if [ -n "$(git status --porcelain -- web)" ]; then
    echo "web/ has uncommitted changes; commit them first:" >&2
    git status --short -- web >&2
    exit 1
fi

if [ "${1:-}" = "-n" ]; then
    rsync -rlcn --itemize-changes --exclude .DS_Store web/ "$HOST:$ROOT/" | grep -v '^\.' || echo "nothing to upload"
    exit 0
fi

stamp=$(date +%Y%m%d-%H%M%S)
ssh "$HOST" "tar czf /root/neatedit-site-backup-$stamp.tgz -C /var/www neatedit \
    && ls -1t /root/neatedit-site-backup-*.tgz | tail -n +11 | xargs -r rm -f"

rsync -rlc --chmod=D755,F644 --no-owner --no-group --exclude .DS_Store web/ "$HOST:$ROOT/"

for page in / /features/ /support/ /privacy/ /assets/site.css /assets/editor-light.png; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$SITE$page")
    echo "$code $SITE$page"
    [ "$code" = 200 ] || { echo "smoke test failed" >&2; exit 1; }
done
echo "Deployed $(git rev-parse --short HEAD)"

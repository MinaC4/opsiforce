#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

if [ ! -f yarn.lock ]; then
  node .yarn/releases/yarn-4.17.0.cjs install
fi

VITE_WEBAPP_DOMAIN=apps.192.168.1.3.nip.io \
VITE_VSCODE_DOMAIN=code.192.168.1.3.nip.io \
VITE_DB_DOMAIN=db.192.168.1.3.nip.io \
  node .yarn/releases/yarn-4.17.0.cjs workspace @opsiforce/frontend build
node .yarn/releases/yarn-4.17.0.cjs workspace @opsiforce/backend build
node .yarn/releases/yarn-4.17.0.cjs workspace @opsiforce/backend db:generate
node .yarn/releases/yarn-4.17.0.cjs workspaces focus @opsiforce/backend --production
rm -rf .k3d-build/yarn-cache
mkdir -p .k3d-build/yarn-cache
cp "$HOME"/.yarn/berry/cache/*.zip .k3d-build/yarn-cache/
echo "Staged $(find .k3d-build/yarn-cache -type f -name '*.zip' | wc -l | tr -d ' ') dependency archives for offline Linux builds."

docker build --platform linux/amd64 -f docker/Dockerfile.backend.k3d \
  -t opsiforce-backend:k3d .
docker build --platform linux/amd64 -f docker/Dockerfile.frontend.k3d \
  --build-arg VITE_WEBAPP_DOMAIN=apps.192.168.1.3.nip.io \
  --build-arg VITE_VSCODE_DOMAIN=code.192.168.1.3.nip.io \
  --build-arg VITE_DB_DOMAIN=db.192.168.1.3.nip.io \
  -t opsiforce-frontend:k3d .
docker build --platform linux/amd64 -f docker/Dockerfile.runtime-proxy \
  --build-arg PKG_PREFIX=./ -t opsiforce-runtime-proxy:k3d .
docker build --platform linux/amd64 -f docker/Dockerfile.agent \
  --build-arg OPENCODE_CONFIG=agent-config/opencode.json \
  -t opsiforce-agent:0.35.4 .

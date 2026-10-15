#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"
if [ -n "${HELM_BIN:-}" ]; then
  helm_bin=$HELM_BIN
elif command -v helm >/dev/null 2>&1; then
  helm_bin=helm
elif [ -x /private/tmp/darwin-amd64/helm ]; then
  helm_bin=/private/tmp/darwin-amd64/helm
else
  echo 'Helm 3 is required. Install Helm or set HELM_BIN to its executable.' >&2
  exit 1
fi
namespace=opsiforce

kubectl config current-context | grep -qx 'k3d-openchoreo' || {
  echo 'Refusing to deploy: current kubectl context is not k3d-openchoreo.' >&2
  exit 1
}
for image in opsiforce-backend:k3d opsiforce-frontend:k3d opsiforce-runtime-proxy:k3d opsiforce-agent:0.35.4; do
  docker image inspect "$image" >/dev/null || {
    echo "Missing local image $image. Build the images first." >&2
    exit 1
  }
done

sh deploy/k3d/bootstrap-secrets.sh
if [ "${SKIP_IMAGE_IMPORT:-0}" = "1" ]; then
  echo 'Skipping image import because the images are already present in the cluster.'
else
  k3d image import \
    opsiforce-backend:k3d \
    opsiforce-frontend:k3d \
    opsiforce-runtime-proxy:k3d \
    opsiforce-agent:0.35.4 \
    --cluster openchoreo
fi

kubectl apply -f deploy/k3d/postgres.yaml
kubectl rollout status statefulset/opsiforce-postgres -n "$namespace" --timeout=10m

"$helm_bin" upgrade --install opsiforce-infra helm/opsiforce \
  --namespace "$namespace" --create-namespace \
  -f helm/opsiforce/values.k3d.yaml --timeout=10m
# The platform PVC uses local-path with WaitForFirstConsumer. It becomes Bound
# only after the backend pod is scheduled below, so waiting on every infra
# resource here would deadlock before that release can be installed.
kubectl rollout status deployment/opsiforce-infra-valkey -n "$namespace" --timeout=5m

"$helm_bin" repo add bifrost https://maximhq.github.io/bifrost/helm-charts >/dev/null 2>&1 || true
"$helm_bin" repo update bifrost >/dev/null
"$helm_bin" upgrade --install opsiforce-bifrost bifrost/bifrost \
  --version 2.1.37 --namespace "$namespace" \
  -f helm/bifrost/values.prod.yaml \
  -f helm/bifrost/values.k3d.yaml \
  -f helm/bifrost/values.openrouter.yaml \
  --wait --timeout=15m
kubectl apply -n "$namespace" -f helm/bifrost/networkpolicy.yaml

kubectl apply -f deploy/k3d/keycloak.yaml
kubectl rollout status deployment/opsiforce-keycloak -n "$namespace" --timeout=10m

"$helm_bin" repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
"$helm_bin" repo update traefik >/dev/null
# The cluster already provides Gateway API CRDs at v1.5.0-dev. Traefik 39.0.8
# bundles v1.4.0 and the cluster's safe-upgrades policy rejects that downgrade,
# so install only Traefik's provider CRDs and let Helm reuse Gateway API.
kubectl apply -f deploy/k3d/crds/traefik-v39/
traefik_values=$(mktemp)
sed 's/@@OIDC_PLUGIN_VERSION@@/v0.19.0/g' helm/local-infra/traefik.values.yaml > "$traefik_values"
"$helm_bin" upgrade --install traefik traefik/traefik \
  --version 39.0.8 --namespace traefik --create-namespace \
  --skip-crds -f "$traefik_values" -f deploy/k3d/traefik.values.k3d.yaml \
  --wait --timeout=15m
rm -f "$traefik_values"

sh deploy/k3d/apply-gateway.sh

"$helm_bin" upgrade --install opsiforce-gotenberg helm/opsiforce-gotenberg \
  --namespace "$namespace" -f helm/opsiforce-gotenberg/values.k3d.yaml \
  --wait --timeout=10m
"$helm_bin" upgrade --install opsiforce-backend helm/opsiforce-backend \
  --namespace "$namespace" -f helm/opsiforce-backend/values.k3d.yaml \
  --wait --timeout=15m
"$helm_bin" upgrade --install opsiforce-frontend helm/opsiforce-frontend \
  --namespace "$namespace" -f helm/opsiforce-frontend/values.k3d.yaml \
  --wait --timeout=10m
"$helm_bin" upgrade --install proxy helm/opsiforce-runtime-proxies \
  --namespace "$namespace" -f helm/opsiforce-runtime-proxies/values.k3d.yaml \
  --wait --timeout=10m
"$helm_bin" upgrade --install opsiforce-proxy helm/opsiforce-proxy \
  --namespace "$namespace" -f helm/opsiforce-proxy/values.k3d.yaml \
  --wait --timeout=10m

sh deploy/k3d/install-docker-launch-agent.sh
kubectl wait -n openchoreo-control-plane --for=condition=Programmed gateway/gateway-default --timeout=5m
sh deploy/k3d/export-ca.sh

echo 'Opsiforce LAN deployment is ready.'
echo 'Open https://opsiforce.192.168.1.3.nip.io:18443 from a device on the home network.'

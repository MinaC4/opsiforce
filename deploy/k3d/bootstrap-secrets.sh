#!/bin/sh
set -eu

namespace=opsiforce
mkdir -p "$HOME/.config/opsiforce"
credentials_path="$HOME/.config/opsiforce/credentials"
umask 077

kubectl config current-context | grep -qx 'k3d-openchoreo' || {
  echo 'Refusing to create Secrets: current kubectl context is not k3d-openchoreo.' >&2
  exit 1
}
kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f - >/dev/null

ca_file=$(mktemp)
kubectl get secret cluster-gateway-ca -n openchoreo-control-plane \
  -o jsonpath='{.data.ca\.crt}' | base64 -D > "$ca_file"
kubectl create configmap opsiforce-lan-ca -n "$namespace" \
  --from-file=ca.crt="$ca_file" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create configmap opsiforce-lan-ca -n traefik \
  --from-file=ca.crt="$ca_file" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
rm -f "$ca_file"

random_hex() { openssl rand -hex 32; }

secret_value() {
  secret_name=$1
  secret_key=$2
  kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data.${secret_key}}" 2>/dev/null \
    | base64 -D 2>/dev/null || true
}

write_secret_file() {
  file_path=$1
  shift
  : > "$file_path"
  for entry in "$@"; do
    printf '%s\n' "$entry" >> "$file_path"
  done
}

apply_secret_once() {
  secret_name=$1
  file_path=$2
  if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
    kubectl create secret generic "$secret_name" -n "$namespace" \
      --from-env-file="$file_path" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  fi
  rm -f "$file_path"
}

postgres_file=$(mktemp)
if ! kubectl get secret opsiforce-postgres-credentials -n "$namespace" >/dev/null 2>&1; then
  write_secret_file "$postgres_file" \
    "postgres-password=$(random_hex)" \
    "opsiforce-password=$(random_hex)" \
    "bifrost-password=$(random_hex)" \
    "keycloak-password=$(random_hex)"
fi
if [ -s "$postgres_file" ]; then
  apply_secret_once opsiforce-postgres-credentials "$postgres_file"
else
  rm -f "$postgres_file"
fi

opsiforce_db_password=$(secret_value opsiforce-postgres-credentials opsiforce-password)
bifrost_db_password=$(secret_value opsiforce-postgres-credentials bifrost-password)
[ -n "$opsiforce_db_password" ] && [ -n "$bifrost_db_password" ] || {
  echo 'Could not read the existing database credential Secret.' >&2
  exit 1
}

database_file=$(mktemp)
write_secret_file "$database_file" \
  "DATABASE_URL=postgres://opsiforce:${opsiforce_db_password}@opsiforce-postgres:5432/opsiforce"
apply_secret_once opsiforce-database-url "$database_file"

bifrost_admin_password=$(secret_value opsiforce-bifrost-admin-auth password)
if [ -z "$bifrost_admin_password" ]; then bifrost_admin_password=$(random_hex); fi
bifrost_admin_file=$(mktemp)
write_secret_file "$bifrost_admin_file" "username=opsiforce-admin" "password=${bifrost_admin_password}"
apply_secret_once opsiforce-bifrost-admin-auth "$bifrost_admin_file"

bifrost_pg_file=$(mktemp)
write_secret_file "$bifrost_pg_file" "password=${bifrost_db_password}"
apply_secret_once opsiforce-bifrost-postgres "$bifrost_pg_file"

encryption_key=$(secret_value opsiforce-bifrost-encryption key)
if [ -z "$encryption_key" ]; then encryption_key=$(random_hex); fi
encryption_file=$(mktemp)
write_secret_file "$encryption_file" "key=${encryption_key}"
apply_secret_once opsiforce-bifrost-encryption "$encryption_file"

runtime_file=$(mktemp)
if ! kubectl get secret opsiforce-runtime-secrets -n "$namespace" >/dev/null 2>&1; then
  write_secret_file "$runtime_file" \
    "PROXY_CONTROL_TOKEN=$(random_hex)" \
    "OIDC_PLUGIN_SECRET=$(random_hex)" \
    "EXTERNAL_SERVICES_ENCRYPTION_KEY=$(random_hex)" \
    "MANAGED_OIDC_CLIENT_SECRET=$(random_hex)" \
    "BIFROST_ADMIN_USERNAME=opsiforce-admin" \
    "BIFROST_ADMIN_PASSWORD=${bifrost_admin_password}"
fi
if [ -s "$runtime_file" ]; then
  apply_secret_once opsiforce-runtime-secrets "$runtime_file"
else
  rm -f "$runtime_file"
fi

keycloak_file=$(mktemp)
if ! kubectl get secret opsiforce-keycloak-credentials -n "$namespace" >/dev/null 2>&1; then
  write_secret_file "$keycloak_file" \
    "bootstrap-admin-password=$(random_hex)" \
    "platform-client-secret=$(random_hex)" \
    "managed-client-secret=$(random_hex)" \
    "admin-user-password=$(random_hex)"
fi
if [ -s "$keycloak_file" ]; then
  apply_secret_once opsiforce-keycloak-credentials "$keycloak_file"
else
  rm -f "$keycloak_file"
fi

bootstrap_password=$(secret_value opsiforce-keycloak-credentials bootstrap-admin-password)
platform_client_secret=$(secret_value opsiforce-keycloak-credentials platform-client-secret)
managed_client_secret=$(secret_value opsiforce-keycloak-credentials managed-client-secret)
admin_user_password=$(secret_value opsiforce-keycloak-credentials admin-user-password)
oauth_file=$(mktemp)
cookie_secret=$(secret_value opsiforce-oauth2-credentials cookie-secret)
case "${#cookie_secret}" in
  16|24|32) ;;
  *) cookie_secret=$(openssl rand -hex 16) ;;
esac
oauth_client_secret=$(secret_value opsiforce-oauth2-credentials client-secret)
if [ -z "$oauth_client_secret" ]; then oauth_client_secret=$platform_client_secret; fi
write_secret_file "$oauth_file" \
  "cookie-secret=${cookie_secret}" \
  "client-secret=${oauth_client_secret}"
kubectl create secret generic opsiforce-oauth2-credentials -n "$namespace" \
  --from-env-file="$oauth_file" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
rm -f "$oauth_file"

kubectl create configmap opsiforce-keycloak-realm-template -n "$namespace" \
  --from-file=realm.json.tmpl=deploy/k3d/keycloak-realm.json.tmpl \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if ! kubectl get secret opsiforce-bifrost-provider-keys -n "$namespace" >/dev/null 2>&1; then
  if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    if [ ! -t 0 ]; then
      echo 'Set OPENROUTER_API_KEY or run this script in a terminal to enter it privately.' >&2
      exit 1
    fi
    printf 'OpenRouter API key (input hidden): ' >&2
    stty -echo
    IFS= read -r OPENROUTER_API_KEY
    stty echo
    printf '\n' >&2
  fi
  provider_file=$(mktemp)
  write_secret_file "$provider_file" "openrouter-api-key=${OPENROUTER_API_KEY}"
  apply_secret_once opsiforce-bifrost-provider-keys "$provider_file"
fi

cat > "$credentials_path" <<EOF
Opsiforce URL: https://opsiforce.192.168.1.3.nip.io:18443
Opsiforce username: opsiforce-admin
Opsiforce password: ${admin_user_password}
Keycloak admin username: admin
Keycloak admin password: ${bootstrap_password}
Bifrost dashboard username: opsiforce-admin
Bifrost dashboard password: ${bifrost_admin_password}
EOF
chmod 600 "$credentials_path"

echo "Kubernetes Secrets are ready in namespace ${namespace}."
echo "Login details were saved to ${credentials_path} (owner-only permissions)."

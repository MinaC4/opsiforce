#!/bin/sh
set -eu

ca_path="$HOME/Downloads/opsiforce-lan-ca.crt"
mkdir -p "$(dirname "$ca_path")"
kubectl config current-context | grep -qx 'k3d-openchoreo' || {
  echo 'Refusing to export a CA: current kubectl context is not k3d-openchoreo.' >&2
  exit 1
}
kubectl get secret cluster-gateway-ca -n openchoreo-control-plane \
  -o jsonpath='{.data.ca\.crt}' | base64 -D > "$ca_path"
chmod 644 "$ca_path"
echo "Public LAN CA exported to $ca_path. Import it as a trusted root on each client device."

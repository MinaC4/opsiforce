#!/bin/sh
set -eu

namespace=openchoreo-control-plane
gateway=gateway-default
secret=opsiforce-lan-gateway-tls

kubectl config current-context | grep -qx 'k3d-openchoreo' || {
  echo 'Refusing to change the Gateway: current kubectl context is not k3d-openchoreo.' >&2
  exit 1
}

kubectl apply -f deploy/k3d/gateway-routes.yaml
kubectl wait -n "$namespace" --for=condition=Ready certificate/opsiforce-lan-gateway --timeout=5m

listener_index=$(kubectl get gateway "$gateway" -n "$namespace" -o json | python3 -c '
import json, sys
gateway = json.load(sys.stdin)
print(next(i for i, listener in enumerate(gateway["spec"]["listeners"]) if listener["name"] == "https"))
')
existing_refs=$(kubectl get gateway "$gateway" -n "$namespace" -o json | python3 -c '
import json, sys
gateway = json.load(sys.stdin)
listener = next(item for item in gateway["spec"]["listeners"] if item["name"] == "https")
print(" ".join(item["name"] for item in listener.get("tls", {}).get("certificateRefs", [])))
')
case " $existing_refs " in
  *" $secret "*) ;;
  *) kubectl patch gateway "$gateway" -n "$namespace" --type=json \
       -p="[{\"op\":\"add\",\"path\":\"/spec/listeners/${listener_index}/tls/certificateRefs/-\",\"value\":{\"group\":\"\",\"kind\":\"Secret\",\"name\":\"${secret}\"}}]" ;;
esac

echo 'LAN certificate is ready and attached to gateway-default.'

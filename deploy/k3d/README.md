# Opsiforce on the existing k3d cluster

This profile targets the single-node `k3d-openchoreo` cluster on the home LAN at
`192.168.1.3`. Reserve that address in the router so the `nip.io` URLs and local
TLS certificate keep matching after network restarts.

From the repository root, `sh deploy/k3d/build-images.sh` builds the four
project images for the cluster's `linux/amd64` architecture. The deployment
script imports them into k3d before installing the Helm releases.

The profile uses the cluster's `local-path` storage class with one `ReadWriteOnce`
workspace claim, because all Opsiforce workloads are scheduled on the same node.
The claim and database data survive a host restart as long as the k3d node
container and Docker Desktop data disk are retained. Do not delete/recreate the
cluster to restart the computer; Docker restarts the existing node container.

The Kubernetes Gateway already listens on host ports `18080` and `18443`.
Use `:18443` in HTTPS links, matching existing cluster applications.

The deployment installs a per-user macOS LaunchAgent that starts Docker Desktop
when that user signs in; the existing k3d node container and workloads then
resume. On each client device, install the public LAN CA certificate as a
trusted root to use HTTPS without browser warnings. Keep the CA private key
and all Kubernetes Secrets out of this repository.

The app URLs are:

- `https://opsiforce.192.168.1.3.nip.io:18443`
- `https://bifrost.192.168.1.3.nip.io:18443`
- `https://sso.192.168.1.3.nip.io:18443`

Use the existing Gateway host ports: HTTP `18080` and HTTPS `18443`, matching
the other LAN projects. App environments use the `apps`, `code`, and `db`
subdomains of `192.168.1.3.nip.io` on HTTPS port `18443`.

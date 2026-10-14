---
kind: operations
---

# Deployment

The home-LAN deployment profile targets the existing single-node `k3d-openchoreo`
cluster. It builds the project images locally, imports them into k3d, and installs
the dependencies and Opsiforce Helm releases in order. No model runs locally;
Bifrost sends inference requests to OpenRouter.

## Deploy

From the repository root on the cluster host:

```sh
sh deploy/k3d/build-images.sh
sh deploy/k3d/deploy.sh
```

The deploy script asks for the OpenRouter API key with terminal echo disabled.
Kubernetes Secrets hold database, identity-provider, proxy and model credentials;
they are not written to Helm values or Git. The initial Opsiforce and Keycloak
login credentials are saved in `~/.config/opsiforce/credentials` with owner-only
file permissions. The platform login uses the local Keycloak account; OAuth2 Proxy
checks each platform request and forwards its role claims to the backend.

## Access from the home network

Reserve `192.168.1.3` for the cluster host in the router. The site URLs are:

- `https://opsiforce.192.168.1.3.nip.io`
- `https://bifrost.192.168.1.3.nip.io`
- `https://sso.192.168.1.3.nip.io`

The Gateway already owns host ports `18080` and `18443`. The two forwarder
containers map standard ports `80` and `443` to those listeners. On each client
device, import the public certificate authority from the cluster as a trusted
root to remove browser certificate warnings. Never copy the CA private key.

## Storage, resources and restart behavior

The profile uses `local-path` ReadWriteOnce volumes: 50 GiB for project
workspaces, 10 GiB for PostgreSQL and 1 GiB for Valkey session data. A single
ReadWriteOnce workspace claim is sufficient because the cluster has one node.
PostgreSQL stores the platform, Bifrost and Keycloak databases on its persistent
volume.

Baseline requests are intentionally modest for the existing 12-vCPU, 20-GiB
node: about 1.7 vCPU and 3.7 GiB for the always-on Opsiforce services. Each
active small agent environment requests 2 GiB and may use up to 4 GiB. The
cluster's other workloads already use memory, so avoid running many agent
environments concurrently.

The project volumes live inside the retained k3d node container. They survive
host power-off and Docker restarts while that container and Docker Desktop data
disk are kept. The deployment installs a per-user LaunchAgent to start Docker
Desktop when that user signs in; Docker's `unless-stopped` policies resume the
k3d containers and LAN forwarders. Do not delete/recreate the cluster to restart
the computer. This is restart persistence, not an off-host backup.

## Verify

After deployment, check that the Postgres StatefulSet, Keycloak, Bifrost, backend,
frontend, Gotenberg, four runtime proxies and edge proxy are Ready. Confirm the
Gateway reports `Programmed=True`, the Opsiforce HTTPRoutes are accepted, and the
TLS Certificate is Ready. Test login and one model request through OpenRouter,
then create a small project and verify its workspace PVC survives a cluster
container restart.

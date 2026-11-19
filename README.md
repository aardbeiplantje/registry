# registry

Docker registry (`registry:2`) behind an nginx proxy that serves it over IPv6 only, with basic auth and a Let's Encrypt certificate. Deployed with Docker Compose.

## Prerequisites
1. Docker Engine with Compose v2 (`docker compose`).
2. IPv6 enabled in the Docker daemon config (for example in `/etc/docker/daemon.json`).
3. DNS AAAA record for your registry host (`APP_DOMAIN`) pointing to the host IPv6 address, unless `IPV6_ADDRESS` is set explicitly.
4. A host directory for registry data at `/mnt/ssd/docker-registry` (bind-mounted into the registry container).
5. A certificate volume (`APP_CERT_VOLUME`) that holds the Let's Encrypt certificate, created by the certbot step on first run.

## Files
- `docker-compose.yml`: the `proxy` and `registry` services, the IPv6 `dmz` network and the internal network.
- `nginx.conf`: proxy configuration, bind-mounted into the proxy container.
- `docker-bake.hcl`: image build definitions. `DOCKER_REGISTRY` defaults to `local`.
- `deploy.sh`: builds images, writes the htpasswd file, recreates the stack and optionally runs certbot.

## Variables
| Variable | Required | Notes |
| --- | --- | --- |
| `APP_DOMAIN` | yes | Public host name of the registry. |
| `APP_CERT_VOLUME` | yes | Name of the certificate volume. |
| `REGISTRY_USER`, `REGISTRY_PASS` | yes | Basic auth credentials, written to `htpasswd`. |
| `REGISTRY_HTTP_SECRET` | yes | Signs upload state. Keep the same value across deploys. See below. |
| `IPV6_SUBNET`, `IPV6_GATEWAY` | yes | The `dmz` network's IPv6 subnet and gateway. |
| `IPV6_ADDRESS` | no | Address of the proxy. Defaults to the AAAA record of `APP_DOMAIN`. |
| `APP_NAME` | no | Defaults to `registry`. Used in container, volume and network names. |
| `DOCKER_REPOSITORY` | no | Defaults to `registry`. Middle part of the image name. |
| `APP_DO_CERTBOT` | no | Set to `1` to run the certbot step. |
| `APP_CERTBOT_MAIL` | with certbot | Contact address for Let's Encrypt. |
| `APP_CERTBOT_IMAGE` | no | Certbot image. Defaults to the GHCR image. `local/*` images are never pulled. |
| `APP_CERTBOT_TAG` | no | Tag for the GHCR certbot image. Defaults to `latest`. |

### REGISTRY_HTTP_SECRET
This signs the state of uploads in progress. Stored images don't depend on it. Use a long random value, for example `openssl rand -hex 32`, and keep it stable between deploys. Changing it only breaks pushes that are running during the change.

## Deploy
```
APP_DOMAIN=registry.example.com \
APP_CERT_VOLUME=registry-proxy-certs-registry \
IPV6_SUBNET=2001:db8:c::1:0/120 \
IPV6_GATEWAY=2001:db8:c::1:1 \
IPV6_ADDRESS=2001:db8:c::1:2 \
REGISTRY_HTTP_SECRET=<secret> \
REGISTRY_USER=<user> \
REGISTRY_PASS=<pass> \
bash ./deploy.sh
```

The script builds the images with `docker buildx bake -f docker-bake.hcl`, writes `htpasswd` in the project directory (mode 644, gitignored), stops the old stack and runs `docker compose up -d`.

### Certificate
The first deploy needs a certificate. Run the certbot step once, and again when the certificate needs renewing:
```
APP_DO_CERTBOT=1 \
APP_CERTBOT_MAIL=<email> \
APP_CERT_VOLUME=registry-proxy-certs-registry \
APP_DOMAIN=registry.example.com \
IPV6_SUBNET=2001:db8:c::1:0/120 \
IPV6_GATEWAY=2001:db8:c::1:1 \
IPV6_ADDRESS=2001:db8:c::1:2 \
REGISTRY_HTTP_SECRET=<secret> \
REGISTRY_USER=<user> \
REGISTRY_PASS=<pass> \
bash ./deploy.sh
```
This stops the stack, runs certbot on port 80 over IPv6, then starts the stack again. Port 80 must be reachable from the internet on `IPV6_ADDRESS`.

To use a locally built certbot image, add `APP_CERTBOT_IMAGE=local/certbot/certbot:latest`.

## Verify
```
curl -6 -i https://registry.example.com/v2/
```
Without credentials this returns `401 Unauthorized` with a `WWW-Authenticate: Basic` header. With `-u "$REGISTRY_USER:$REGISTRY_PASS"` it returns `200 OK`.

## Troubleshooting
- **TLS `internal error`:** the certificate volume is empty. Run the certbot step.
- **Login `500`:** check `docker compose logs proxy`. A `Permission denied` on `/auth/htpasswd` means the htpasswd file isn't readable by the proxy's nginx user. The file must be mode 644.
- **`denied` when pulling the certbot image:** log in to `ghcr.io`, or use `APP_CERTBOT_IMAGE` with a local image.

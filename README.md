Prerequisites
1. Docker Engine with Swarm mode enabled.
2. IPv6 enabled in Docker daemon config (for example in /etc/docker/daemon.json).
3. DNS AAAA record for your registry host (APP_DOMAIN) pointing to the host IPv6 address.
4. Sudo privileges on the host running deploy.sh (the script updates NDP/sysctl/ip6tables).
5. Swarm node label registry=1 on nodes that should run the services.

Initialize swarm (single-node example)
```
docker swarm init --default-addr-pool 10.0.0.0/8 --default-addr-pool-mask-length 24 --advertise-addr 127.0.0.1
```

Set required node label
```
docker node update --label-add registry=1 <node-hostname>
```

Important
- Do not use node.labels.registry as the label key.
- Use registry=1 because placement constraints are node.labels.registry==1.

What deploy.sh automates
- Buildx builder selection/creation and image build.
- Docker config + secret creation for nginx and htpasswd.
- Optional docker login when DOCKER_REGISTRY_* env vars are provided.
- Stack removal/redeploy.
- dmz network recreation.
- IPv6 neighbor, proxy_ndp sysctl, and ip6tables ACCEPT rule for 443.
- Optional certbot flow when APP_DO_CERTBOT=1.

Deploy
```
APP_NAME=registry \
APP_DOMAIN=registry.aardbeiplantje.link \
APP_IPV6_PREFIX=2a02:a03f:878c:eb00:f::/120 \
REGISTRY_USER=<user> \
REGISTRY_PASS=<pass> \
bash ./deploy.sh
```

Optional: issue/refresh certificate during deploy
```
APP_DO_CERTBOT=1 \
APP_CERTBOT_MAIL=<email> \
APP_CERT_VOLUME=registry-proxy-certs-registry \
APP_NAME=registry \
APP_DOMAIN=registry.aardbeiplantje.link \
APP_IPV6_PREFIX=2a02:a03f:878c:eb00:f::/120 \
REGISTRY_USER=<user> \
REGISTRY_PASS=<pass> \
bash ./deploy.sh
```

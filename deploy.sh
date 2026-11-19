#!/bin/bash

export WORKSPACE=$(readlink -f "${WORKSPACE:-${BASH_SOURCE%/*}}")
cd "$WORKSPACE" || exit $?

export APP_NAME=${APP_NAME:-registry}
export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-registry}
export REGISTRY_USER=${REGISTRY_USER?Need REGISTRY_USER}
export REGISTRY_PASS=${REGISTRY_PASS?Need REGISTRY_PASS}
export REGISTRY_HTTP_SECRET=${REGISTRY_HTTP_SECRET?Need REGISTRY_HTTP_SECRET}
export APP_CERT_VOLUME=${APP_CERT_VOLUME?Need APP_CERT_VOLUME}
export DOMAIN=${APP_DOMAIN?Need APP_DOMAIN}
export IPV6_SUBNET=${IPV6_SUBNET?Need IPV6_SUBNET (e.g. 2001:db8:c::1:0/120)}
export IPV6_GATEWAY=${IPV6_GATEWAY?Need IPV6_GATEWAY (e.g. 2001:db8:c::1:1)}

nw_name=dmz-${APP_NAME}-ipv6

echo "building multiarch images with buildx"
docker buildx use registry || \
docker buildx create \
    --use \
    --name registry \
    --platform linux/amd64,linux/arm64,linux/aarch64 \
    --driver docker-container \
    --driver-opt image=moby/buildkit:master \
    --driver-opt network=host
docker buildx bake -f docker-bake.hcl || exit $?

echo "writing htpasswd file"
export HTPASSWD_FILE=${HTPASSWD_FILE:-$WORKSPACE/htpasswd}
# readable by the proxy's nginx workers (they run as a non-root user in the
# container); the file only holds salted apr1 hashes
printf '%s:%s\n' "$REGISTRY_USER" \
    "$(printf '%s' "$REGISTRY_PASS" | openssl passwd -apr1 -stdin)" \
    > "$HTPASSWD_FILE" || exit $?
chmod 644 "$HTPASSWD_FILE" || exit $?

echo "checking for registry auth"
if [ -z "$DOCKER_REGISTRY" \
    -o -z "$DOCKER_REGISTRY_USER" \
    -o -z "$DOCKER_REGISTRY_PASS" ]; then
    echo "no registry login info, using local registry"
    export DOCKER_REGISTRY=local
else
    echo "using registry login info"
    export DOCKER_REGISTRY
    export DOCKER_REGISTRY_USER
    export DOCKER_REGISTRY_PASS
    printenv DOCKER_REGISTRY_PASS \
        |docker login \
            -u ${DOCKER_REGISTRY_USER?Need a DOCKER_REGISTRY_USER} \
            --password-stdin \
            ${DOCKER_REGISTRY?Need a DOCKER_REGISTRY} || exit $?
fi

echo "stopping old stack and removing network $nw_name, as we need to recreate it with the same IPv6"
docker compose down 2>/dev/null || true
docker network rm $nw_name 2>/dev/null || true

if [ -z "$IPV6_ADDRESS" ]; then
    IPV6=$(dig -6 $DOMAIN -t AAAA +short +retry=0 +tries=1)
    if [ $? != 0 -o -z "$IPV6" ]; then
        echo -ne "problem looking up $DOMAIN:\n$IPV6\n"
        exit 1
    fi
    export IPV6_ADDRESS=$IPV6
fi

if [ "${APP_DO_CERTBOT:-0}" -eq 1 ]; then
    export APP_CERTBOT_MAIL=${APP_CERTBOT_MAIL?Need APP_CERTBOT_MAIL}
    # the network is created here (not by compose) so certbot can bind the
    # same IPv6 address; it is removed again so compose can create it
    echo "creating network $nw_name for certbot with subnet $IPV6_SUBNET"
    docker network create \
        --driver bridge \
        --ipv6 \
        --ipam-driver default \
        --subnet "$IPV6_SUBNET" \
        --gateway "$IPV6_GATEWAY" \
        --opt com.docker.network.bridge.gateway_mode_ipv6="routed" \
        --opt com.docker.network.container_iface_prefix="dmz" \
        --opt com.docker.network.bridge.enable_icc="true" \
        --opt com.docker.network.bridge.enable_ip_masquerade="false" \
        --opt com.docker.network.bridge.enable_ip6_masquerade="false" \
        --opt com.docker.network.bridge.inhibit_ipv4="true" \
        --opt com.docker.network.driver.mtu="1500" \
        $nw_name || exit $?
    echo "checking the certificate"
    export APP_CERTBOT_IMAGE=${APP_CERTBOT_IMAGE:-ghcr.io/aardbeiplantje/certbot/certbot:${APP_CERTBOT_TAG:-latest}}
    case "$APP_CERTBOT_IMAGE" in
        local/*) certbot_pull=never ;;   # locally built image, nothing to pull
        *)       certbot_pull=always ;;
    esac
    docker run \
        -p 80:80 \
        --pull=$certbot_pull \
        --rm \
        -e CERTBOT_MAIL="$APP_CERTBOT_MAIL" \
        --network $nw_name \
        --ip6 $IPV6_ADDRESS \
        --name certbot_$APP_NAME \
        -v ${APP_CERT_VOLUME}:/certs:rw \
        "$APP_CERTBOT_IMAGE" \
            certonly \
                --agree-tos \
                --force-renewal \
                --domains "$DOMAIN" || exit $?
    echo "removing network $nw_name"
    docker network rm $nw_name || exit $?
else
    echo "no certbot"
fi

echo "make sure the container image comes from local"
export DOCKER_REGISTRY=local

echo "starting stack $APP_NAME with docker compose"
exec docker compose up -d --remove-orphans

#!/bin/bash 
export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-registry}
export REGISTRY_USER=${REGISTRY_USER?Need REGISTRY_USER}
export REGISTRY_PASS=${REGISTRY_PASS?Need REGISTRY_PASS}
export STACK_NAME=${STACK_NAME:-$APP_NAME}
printf -v now "%(%s)T" -1
export CFG_PREFIX=$STACK_NAME-$now
export STACK_CONFIG=${STACK_CONFIG:-$WORKSPACE}
ipv6_prefix=${APP_IPV6_PREFIX?Need APP_IPV6_PREFIX}

echo "creating configs and secrets with prefix $CFG_PREFIX"
docker config create \
    --template-driver golang \
    registry-proxy-config-$CFG_PREFIX \
    ${WORKSPACE}/nginx.conf
HASHED_PASS=$(printenv REGISTRY_PASS|openssl passwd -apr1 -stdin)
docker secret create \
    --template-driver golang \
    registry-auth-htpasswd-$CFG_PREFIX \
    <(echo "$REGISTRY_USER:$HASHED_PASS")

echo "checking for registry auth"
if [   -z "$DOCKER_REGISTRY" \
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
            ${DOCKER_REGISTRY?Need a DOCKER_REGISTRY}
fi

echo "removing old stack, as we need to recreate the network with same IPv6"
docker stack rm $STACK_NAME 2>/dev/null

nw_name=dmz-$STACK_NAME
if_name=${BRIDGE_IF_NAME:-dmz-${STACK_NAME}0}
echo "removing network name: $nw_name if_name: $if_name ipv6_prefix: $ipv6_prefix"
docker network rm $nw_name 2>/dev/null
docker network ls --filter name=$nw_name -q
while [ $(docker network ls --filter name=$nw_name -q|wc -l) -gt 0 ]; do
    sleep 1
done
echo "removed network $nw_name"

DOMAIN=${APP_DOMAIN?Need APP_DOMAIN}
IPV6=$(dig -6 $DOMAIN -t AAAA +short +retry=0 +tries=1)
if [ $? != 0 -o -z "$IPV6" ]; then
    echo -ne "problem looking up $DOMAIN:\n$IPV6\n"
    exit 1
fi
APP_IF_NAME=${APP_IF_NAME:-eno1}
echo "checking for network, using $APP_IF_NAME"
echo "running sysctl for proxy_ndp and add $IPV6 as neighbour"
sudo sh -x -c "ip -6 neigh add proxy $IPV6 dev $APP_IF_NAME; \
    sysctl net.ipv6.conf.default.proxy_ndp=1; \
    sysctl net.ipv6.conf.all.proxy_ndp=1; \
    ip6tables -I DOCKER -s ::/0 -d $IPV6 -p tcp --dport 443 -j ACCEPT"

if [ "${APP_DO_CERTBOT:-0}" -eq 1 ]; then
    APP_CERTBOT_MAIL=${APP_CERTBOT_MAIL?Need APP_CERTBOT_MAIL}
    # work via export ENV, as this is a possible secret, and we dont want to
    # show this in a ps or log
    echo "removing network $nw_name"
    docker network rm $nw_name
    echo "creating network $nw_name with prefix $ipv6_prefix"
    docker network create \
        --ipv6 $nw_name \
        --subnet=$ipv6_prefix \
        --ipv4=false \
        --attachable=true \
        --scope=local \
        --driver=bridge \
        -o com.docker.network.bridge.name=$APP_NAME-dmz0 \
        -o com.docker.network.container_iface_prefix=dmz \
        -o com.docker.network.bridge.gateway_mode_ipv6=routed \
        -o com.docker.network.bridge.enable_icc=true \
        -o com.docker.network.bridge.enable_ip_masquerade=false \
        -o com.docker.network.bridge.enable_ip6_masquerade=false \
        -o com.docker.network.enable_ipv6=true \
        -o com.docker.network.bridge.inhibit_ipv4=true \
        -o com.docker.network.driver.mtu=1500 \
        --ipam-driver default || exit $?
    echo "check the certtificate"
    docker run \
        -p 80:80 \
        --pull=always \
        --rm \
        -e CERTBOT_MAIL="$APP_CERTBOT_MAIL" \
        --network $nw_name \
        --ip6 $IPV6 \
        --name certbot_$APP_NAME \
        -v ${APP_CERT_VOLUME}:/certs:rw \
        ghcr.io/aardbeiplantje/certbot/certbot:${APP_CERTBOT_TAG:-latest} \
            certonly \
                --agree-tos \
                --force-renewal \
                --domains "$DOMAIN" || exit $?
    echo "removing network $nw_name"
    docker network rm $nw_name
else
    echo "no certbot"
fi

echo "creating network $nw_name with prefix $ipv6_prefix"
docker network create \
    $nw_name \
    --ipv6 \
    --ipv4 \
    --attachable \
    --scope=swarm \
    --subnet=$ipv6_prefix \
    --driver=bridge \
    -o com.docker.network.bridge.name=$if_name \
    -o com.docker.network.container_iface_prefix=dmz \
    -o com.docker.network.bridge.gateway_mode_ipv6=routed \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=false \
    -o com.docker.network.bridge.enable_ip6_masquerade=false \
    -o com.docker.network.enable_ipv6=true \
    -o com.docker.network.bridge.inhibit_ipv4=false \
    -o com.docker.network.driver.mtu=1500 \
    --ipam-driver default

echo "make sure the container image comes from local"
export DOCKER_REGISTRY=local
export DOCKER_REPOSITORY=registry

echo "stack deploy $STACK_NAME"
docker stack deploy \
    -c $WORKSPACE/registry.yml \
    --with-registry-auth \
    --detach=false \
    $STACK_NAME

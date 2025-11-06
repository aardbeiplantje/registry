#!/bin/bash 
export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-registry}
export REGISTRY_USER=${REGISTRY_USER?Need REGISTRY_USER}
export REGISTRY_PASS=${REGISTRY_PASS?Need REGISTRY_PASS}
export STACK_NAME=${STACK_NAME:-$APP_NAME}
printf -v now "%(%s)T" -1
export CFG_PREFIX=$STACK_NAME-$now
export STACK_CONFIG=${STACK_CONFIG:-$WORKSPACE}
export STACK_CERTS=${STACK_CERTS:-$WORKSPACE}
export REGISTRY_HTTP_SECRET=${REGISTRY_HTTP_SECRET:-$(uuidgen)}
docker secret create \
    --template-driver golang \
    registry-https-crt-$CFG_PREFIX \
    ${HTTPS_CRT:-$STACK_CERTS/$STACK_NAME-crt.pem}
docker secret create \
    --template-driver golang \
    registry-https-key-$CFG_PREFIX \
    ${HTTPS_KEY:-$STACK_CERTS/$STACK_NAME-key.pem}
docker config create \
    --template-driver golang \
    registry-proxy-config-$CFG_PREFIX \
    ${WORKSPACE}/nginx.conf
HASHED_PASS=$(printenv REGISTRY_PASS|openssl passwd -apr1 -stdin)
docker secret create \
    --template-driver golang \
    registry-auth-htpasswd-$CFG_PREFIX \
    <(echo "$REGISTRY_USER:$HASHED_PASS")
if [ ! -z "$DOCKER_REGISTRY" -a ! -z "$DOCKER_REGISTRY_USER" -a ! -z "$DOCKER_REGISTRY_PASS" ]; then
    export DOCKER_REGISTRY_PASS DOCKER_REGISTRY_USER DOCKER_REGISTRY
    printenv DOCKER_REGISTRY_PASS \
        |docker login -u $DOCKER_REGISTRY_USER $DOCKER_REGISTRY --password-stdin
else
    export DOCKER_REGISTRY=${DOCKER_REGISTRY:-local}
    export DOCKER_REPO=${DOCKER_REPO:-registry}
fi
export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-registry}
export DOCKER_REGISTRY

echo "clean up $STACK_NAME"
docker stack rm $STACK_NAME 2>/dev/null

if_name=${BRIDGE_IF_NAME:-dmz-${STACK_NAME}0}
nw_name=dmz-$STACK_NAME
ipv6_prefix=${IPV6_PREFIX:-fd53:7cb8:383:eb00:abcd::/120}
echo "network name: $nw_name if_name: $if_name ipv6_prefix: $ipv6_prefix"
docker network rm $nw_name 2>/dev/null
docker network ls --filter name=$nw_name -q
while [ $(docker network ls --filter name=$nw_name -q|wc -l) -gt 0 ]; do
    sleep 1
done
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

echo "stack deploy $STACK_NAME"
docker stack deploy \
    -c $WORKSPACE/registry.yml \
    --with-registry-auth \
    --detach=false \
    $STACK_NAME

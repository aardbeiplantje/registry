#!/bin/bash 
export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-docker-registry}
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
docker stack deploy \
    -c $WORKSPACE/registry.yml \
    --with-registry-auth \
    --detach=false \
    $STACK_NAME

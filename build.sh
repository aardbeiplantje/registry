#!/bin/bash

myapp="docker-registry"
APP_NAME=${APP_NAME:-$myapp}

set -eo pipefail

WORKSPACE=${BASH_SOURCE%/*}
cd $WORKSPACE

TAG_PREFIX=
if [ ! -z "$DOCKER_REGISTRY" -a ! -z "$DOCKER_REGISTRY_USER" -a ! -z "$DOCKER_REGISTRY_PASS" ]; then
    export DOCKER_REGISTRY_PASS DOCKER_REGISTRY_USER DOCKER_REGISTRY
    printenv DOCKER_REGISTRY_PASS \
        |docker login -u $DOCKER_REGISTRY_USER $DOCKER_REGISTRY --password-stdin
    DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-$myapp}
    TAG_PREFIX=$DOCKER_REGISTRY/$DOCKER_REPOSITORY/
    do_push="--push"
    do_push="$do_push --cache-to   type=registry,ref=$TAG_PREFIX$APP_NAME-buildcache:buildcache,mode=max"
    do_push="$do_push --cache-from type=registry,ref=$TAG_PREFIX$APP_NAME-buildcache:buildcache"
else
    export DOCKER_REGISTRY=${DOCKER_REGISTRY:-local}
    export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-$myapp}
    TAG_PREFIX=${TAG_PREFIX:-${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/}
    do_push="--load"
fi

DOCKER_PLATFORM=${DOCKER_PLATFORM:-linux/amd64}
export BUILDX_CONFIG=${BUILDX_CONFIG:-~/.docker/buildx}
chksum=$(printenv LOGNAME|openssl sha256 -hex)
chksum=${chksum:20:8}
my_builder=builder-$APP_NAME-$chksum
docker container rm -f buildx_buildkit_${my_builder}0 2>/dev/null || true
docker buildx use $my_builder \
    || docker buildx create \
        --platform ${DOCKER_PLATFORM} \
        --driver-opt network=host \
        --use \
        --name $my_builder


for w in proxy; do
    docker buildx build \
        --pull \
        --progress=plain \
        --network=host \
        --tag $TAG_PREFIX$APP_NAME-$w:latest \
        --platform ${DOCKER_PLATFORM} \
        --target $w-runtime \
        $WORKSPACE/ \
        $do_push
done
docker container rm -f buildx_buildkit_${my_builder}0

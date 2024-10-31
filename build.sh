#!/bin/bash

APP_NAME=${APP_NAME:-docker-registry}

set -eo pipefail

WORKSPACE=${BASH_SOURCE%/*}
cd $WORKSPACE

TAG_PREFIX=
if [ ! -z "$DOCKER_REGISTRY" -a ! -z "$DOCKER_REGISTRY_USER" -a ! -z "$DOCKER_REGISTRY_PASS" ]; then
    export DOCKER_REGISTRY_PASS DOCKER_REGISTRY_USER DOCKER_REGISTRY
    printenv DOCKER_REGISTRY_PASS \
        |docker login -u $DOCKER_REGISTRY_USER $DOCKER_REGISTRY --password-stdin
    DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-registry}
    TAG_PREFIX=$DOCKER_REGISTRY/$DOCKER_REPOSITORY/
    do_push="--push"
    do_push="$do_push --cache-to   type=registry,ref=$TAG_PREFIX$APP_NAME-proxy:buildcache,mode=max"
    do_push="$do_push --cache-from type=registry,ref=$TAG_PREFIX$APP_NAME-proxy:buildcache"
else
    export DOCKER_REGISTRY=${DOCKER_REGISTRY:-local}
    export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-registry}
    TAG_PREFIX=${TAG_PREFIX:-${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/}
    do_push="--load"
fi

export BUILDX_CONFIG=${BUILDX_CONFIG:-~/.docker/buildx}
docker buildx use $APP_NAME-builder \
  || docker buildx create --name $APP_NAME-builder --use

docker buildx build \
  --pull \
  --progress=plain \
  $(readlink -f $(pwd)) \
  --tag $TAG_PREFIX$APP_NAME-proxy:latest \
  --target proxy \
  --network=host \
  $do_push

docker buildx prune --force --filter "until=730h" --all
docker image prune -f

#!/bin/bash
 
function docker_request() {
    creds="$DOCKER_REGISTRY_USER:$DOCKER_REGISTRY_PASS"
    curl -qsSkLf -u "$creds" "https://$DOCKER_REGISTRY/v2/$1"|jq -r .
}

for r in $(docker_request _catalog|jq -cr '.repositories[]'); do 
    docker_request $r/tags/list|jq -r .
done

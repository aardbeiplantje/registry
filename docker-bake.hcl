group "default" {
  targets = ["registry-proxy-development"]
}
group "release" {
  targets = ["registry-proxy"]
}
variable "DOCKER_REGISTRY" {
  default = "ghcr.io"
}
variable "DOCKER_REPOSITORY" {
  default = "registry"
}
variable "DOCKER_TAG" {
  default = "latest"
}
target "registry-proxy" {
  pull = true
  name = "registry-proxy-${env}"
  matrix = {
    env = ["release"]
  }
  progress = ["plain", "tty"]
  tags = [
    "${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/registry-proxy:${DOCKER_TAG}",
  ]
  output = [
    "type=image,name=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/registry-proxy:${DOCKER_TAG},push=true"
  ]
  cache-to = [
    "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/registry-proxy:cache,mode=max"
  ]
  cache-from = [
    "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/registry-proxy:cache",
    "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/registry-proxy:${DOCKER_TAG}"
  ]
  buildkit = true
  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]
  context = "."
  dockerfile = "Dockerfile"
  networks = ["host"]
  platforms = [
    "linux/amd64"
  ]
}

target "registry-proxy-development" {
  pull = true
  progress = ["plain", "tty"]
  tags = [
    "local/${DOCKER_REGISTRY}/registry-proxy:${DOCKER_TAG}",
  ]
  output = [
    "type=cacheonly",
    "type=docker"
  ]
  buildkit = true
  context = "."
  dockerfile = "Dockerfile"
  networks = ["host"]
  platforms = [
    "linux/amd64"
  ]
}

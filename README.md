Setup docker swarm:
```
docker swarm init --default-addr-pool 10.0.0.0/8 --default-addr-pool-mask-length 24 --advertise-addr $IP
```
Add a node, on the manager:
```
docker swarm join-token worker
```
On the node, see https://docs.docker.com/network/overlay/ for ports:
```
firewall-cmd --add-port=2377/tcp
firewall-cmd --add-port=7946/tcp
firewall-cmd --add-port=7946/udp
firewall-cmd --add-port=4789/udp
firewall-cmd --add-rich-rule="rule protocol value=esp accept"
firewall-cmd --runtime-to-permanent
docker swarm join --token $TKN_HERE
```
Add labels:
```
docker node update --label-add docker-registry=1 $HOSTNAME
```

Build the nginx image:
```
bash ./build.sh
```

Deploy stack:
# create network for ipv6 (scope=swarm)
```
docker network create --ipv6 --subnet fd53:5729:c558:8d8f::/64 dmz-ipv6 --attachable=true --scope=swarm --driver bridge
```
# create network for ipv4 (scope=local)
```
docker network create \
    --ipv6 dmz-ipv6 \
    --attachable=true \
    --scope=local \
    --subnet=fd53:5729:c558:8d8f:a::/120 \
    --driver=bridge \
    -o com.docker.network.bridge.name=docker-dmz0 \
    -o com.docker.network.container_iface_prefix=dmz \
    -o com.docker.network.bridge.gateway_mode_ipv6=routed \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=false \
    -o com.docker.network.bridge.enable_ip6_masquerade=false \
    -o com.docker.network.enable_ipv6=1 \
    -o com.docker.network.bridge.inhibit_ipv4=true \
    -o com.docker.network.driver.mtu=1500 \
    --ipam-driver default
```

Also add the ip to the DOCKER ip6tables chain as ACCEPT:
```
ip6tables -I DOCKER -s ::/0 -d fd53:5729:c558:8d8f::/64 -p tcp --dport 443 -j ACCEPT
```

# deploy the stack
```
HTTPS_CRT=~/docker-registry-certs/docker_registry.crt \
HTTPS_KEY=~/docker-registry-certs/docker_registry.key \
APP_NAME=docker-registry \
bash ./deploy.sh
```

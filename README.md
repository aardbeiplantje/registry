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

Deploy stack:
```
HTTPS_CRT=~/docker-registry-certs/docker_registry.crt \
HTTPS_KEY=~/docker-registry-certs/docker_registry.key \
APP_NAME=docker-registry \
bash ./deploy.sh
```

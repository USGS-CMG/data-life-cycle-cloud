#!/bin/bash

DEFAULT_WORKER_COUNT=2
export MANAGER_NAME="manager"
export WORKER_COUNT=${1:-$DEFAULT_WORKER_COUNT}

docker-machine create -d virtualbox --engine-storage-driver overlay2 --virtualbox-memory "1024" --virtualbox-nat-nictype Am79C973 --virtualbox-cpu-count "1" $MANAGER_NAME

for ((n=1;n<=WORKER_COUNT;n++)); do \
  docker-machine create -d virtualbox --engine-storage-driver overlay2 --virtualbox-memory "6144" --virtualbox-nat-nictype Am79C973 --virtualbox-cpu-count "1" "worker${n}"; \
done

export MANAGER_IP
MANAGER_IP="$(docker-machine ip $MANAGER_NAME)"

docker-machine ssh $MANAGER_NAME docker swarm init --availability drain --advertise-addr $MANAGER_IP:2377

WORKER_JOIN_TOKEN="$(docker-machine ssh $MANAGER_NAME docker swarm join-token worker -q)"

for ((n=1;n<=WORKER_COUNT;n++)); do \
  docker-machine ssh worker$n docker swarm join --token $WORKER_JOIN_TOKEN $MANAGER_IP:2377; \
done

eval "$(docker-machine env $MANAGER_NAME)"

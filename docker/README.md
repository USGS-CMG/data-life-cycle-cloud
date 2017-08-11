# Docker Registry Swarm Service

## Introduction

Included within this project is a Docker private registry service. This service is
useful to have when testing your own Docker containers within the swarm. The registry
service is meant to run on a Docker Machine VM on a developer's workstation. It is
used by other DLCC projects (such as [DLCC THREDDS](https://github.com/USGS-CMG/data-life-cycle-cloud-docker-jupyterhub) and [DLCC JupyterHub](https://github.com/USGS-CMG/data-life-cycle-cloud-docker-thredds)) as a repository
for locally built Docker images to also be deployed in a Docker Swarm among a manager
and worker VM cluster.

The reason the registry is used is because when a Docker container is not available
from a accessible repository (like DockerHub or a private Docker registry), Docker
Swarm will be unable to launch a service calling for the Docker image in a way that
Docker or Docker Compose would be able to. The reason is that when Swarm starts a service,
the Docker image described in the deploy call has to be available on the machine
that is deploying the service. If the Docker image was built on node A but the
service is staring on node B, node B will not be able to find the Docker image and
will not start the service.

Instead, we can build images locally (or in a Docker Machine VM) and push it to the
private registry, which is available as a URL to all other Docker Swarm nodes in your
cluster.

## Docker Software Versions

For testing this configuration, I have the following software installed at these versions:

- Docker Machine: 0.12.10
- Docker Compose: 1.15.0
- Docker Client: 17.06.0-ce

## Creating a local Swarm Cluster ([tl;dr](#swarm-create))

When working with Docker Swarm locally, you can use [VirtualBox](https://www.virtualbox.org/)
to run your cluster. The example contained in these instructions are done in MacOS.
In this example I have one manager node and two worker nodes. In production you will
want [at least 3 manager nodes](https://docs.docker.com/engine/swarm/admin_guide/#add-manager-nodes-for-fault-tolerance).

Set the name of the manager node
```
$ MANAGER_NAME="manager"
```

Create the Manager VM.  Here I specify the VirtualBox driver using the `-d` flag.
I also specify to Docker Machine that I want to use the [overlay2 driver instead of AUFS](https://docs.docker.com/engine/userguide/storagedriver/overlayfs-driver/).
I am using the `--engine-storage-driver` flag to do so. The Manager node does not
require a lot of RAM, so I give it 1GB of RAM using the `--virtualbox-memory` flag.
I give it use of a single CPU core with the `--virtualbox-cpu-count` flag. Finally,
I specify that the VM should be using the PCnet-FAST III network driver using the
`--virtualbox-cpu-count` flag. The PCnet-FAST III network driver seems to have
[better performance on Docker Machine](https://github.com/docker/machine/issues/1942)
```
$ docker-machine create -d virtualbox --engine-storage-driver overlay2 --virtualbox-memory "1024" --virtualbox-nat-nictype Am79C973 --virtualbox-cpu-count "1" $MANAGER_NAME
Running pre-create checks...
Creating machine...
(manager) Copying /Users/developer/.docker/machine/cache/boot2docker.iso to /Users/developer/.docker/machine/machines/manager/boot2docker.iso...
(manager) Creating VirtualBox VM...
(manager) Creating SSH key...
(manager) Starting the VM...
(manager) Check network to re-create if needed...
(manager) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Detecting operating system of created instance...
Waiting for SSH to be available...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!
To see how to connect your Docker Client to the Docker Engine running on this virtual machine, run: docker-machine env manager

$ docker-machine ls
NAME      ACTIVE   DRIVER       STATE     URL                         SWARM   DOCKER        ERRORS
manager   *        virtualbox   Running   tcp://192.168.99.100:2376           v17.06.0-ce
```

Once the Manager machine is up and running (as is seen by the `docker-machine ls` command),
I can now create worker machines. Here I create two worker nodes. To create more,
using this example you can change the value for WORKER_COUNT
to the number of machines you'd like to see. Also note that the worker machine in this
example has 6GB of RAM. This allows us to deploy the THREDDS container on this machine.
THREDDS requires 4GB of RAM minimum to run properly.
```
$ WORKER_COUNT=2
$ for ((n=1;n<=WORKER_COUNT;n++)); do \
  docker-machine create -d virtualbox --engine-storage-driver overlay2 --virtualbox-memory "6144" --virtualbox-nat-nictype Am79C973 --virtualbox-cpu-count "1" "worker${n}"; \
done
Running pre-create checks...
Creating machine...
(worker1) Copying /Users/developer/.docker/machine/cache/boot2docker.iso to /Users/developer/.docker/machine/machines/worker1/boot2docker.iso...
(worker1) Creating VirtualBox VM...
(worker1) Creating SSH key...
(worker1) Starting the VM...
(worker1) Check network to re-create if needed...
(worker1) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Detecting operating system of created instance...
Waiting for SSH to be available...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!
To see how to connect your Docker Client to the Docker Engine running on this virtual machine, run: docker-machine env worker1
Running pre-create checks...
Creating machine...
(worker2) Copying /Users/isuftin/.docker/machine/cache/boot2docker.iso to /Users/isuftin/.docker/machine/machines/worker2/boot2docker.iso...
(worker2) Creating VirtualBox VM...
(worker2) Creating SSH key...
(worker2) Starting the VM...
(worker2) Check network to re-create if needed...
(worker2) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Detecting operating system of created instance...
Waiting for SSH to be available...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!
To see how to connect your Docker Client to the Docker Engine running on this virtual machine, run: docker-machine env worker2

$ docker-machine ls
NAME      ACTIVE   DRIVER       STATE     URL                         SWARM   DOCKER        ERRORS
manager   *        virtualbox   Running   tcp://192.168.99.100:2376           v17.06.0-ce
worker1   -        virtualbox   Running   tcp://192.168.99.101:2376           v17.06.0-ce
worker2   -        virtualbox   Running   tcp://192.168.99.102:2376           v17.06.0-ce
```

I will want to communicate with the machines in the swarm cluster directly and via
the Docker client on my local workstation. To do so, I set bash variables to the IPs
of the VMs.
```
$ MANAGER_IP="$(docker-machine ip $MANAGER_NAME)"
$ WORKER1_IP="$(docker-machine ip worker1)"
```

Because a Docker swarm does not yet exist,  I will need to initiate one on the manager
node. I use the `docker-machine ssh` command to send commands directly to the
manager node and use the Docker engine running on it to perform the initialization.
```
$ docker-machine ssh $MANAGER_NAME docker swarm init --availability drain --advertise-addr $MANAGER_IP:2377
Swarm initialized: current node (jytyhesbsnbf9gjj6w2151ok8) is now a manager.

To add a worker to this swarm, run the following command:

   docker swarm join --token SWMTKN-1-65t3qby5uakm2m49e0uwj5fz0sjoe372j8l8n9ri5kvrwuzfil-a4l50hb50tynngauuot32k7q0 192.168.99.100:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

In the above command you can see a random token has been generated for worker nodes
to use in order to join the swarm as workers. I want to put that token in a bash variable
to use in commands.
```
$ WORKER_JOIN_TOKEN="$(docker-machine ssh $MANAGER_NAME docker swarm join-token worker -q)"
```

Now that I have the worker token, I can have each worker join the swarm as well.
```
$ for ((n=1;n<=WORKER_COUNT;n++)); do \
  docker-machine ssh worker$n docker swarm join --token $WORKER_JOIN_TOKEN $MANAGER_IP:2377; \
done
This node joined a swarm as a worker.
This node joined a swarm as a worker.

$  docker node ls
ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS
fntlym94kz9uw229hmfqxekoj     worker2             Ready               Active
jytyhesbsnbf9gjj6w2151ok8 *   manager             Ready               Drain               Leader
zypeia6jsmt3s0b5utaxqj00f     worker1             Ready               Active
```

As you can see, I now have three nodes in my swarm. A manager and two workers.

I also want to be able to use the docker client on my workstation against the
manager node's Docker engine. After this command, any docker command I issue will
be run against the Docker engine on the manager node.
```
# Prepare local docker client to work with the manager node
eval $(docker-machine env $MANAGER_NAME)
```

### <a name="swarm-create-tldr"></a>Creating a local Swarm Cluster TL;DR

Feel free to copy and paste the following into a terminal to quickly bring up
a single manager, two worker node Docker Swarm.  

```
MANAGER_NAME="manager"
WORKER_COUNT=2

docker-machine create -d virtualbox --engine-storage-driver overlay2 --virtualbox-memory "1024" --virtualbox-nat-nictype Am79C973 --virtualbox-cpu-count "1" $MANAGER_NAME

for ((n=1;n<=WORKER_COUNT;n++)); do \
  docker-machine create -d virtualbox --engine-storage-driver overlay2 --virtualbox-memory "6144" --virtualbox-nat-nictype Am79C973 --virtualbox-cpu-count "1" "worker${n}"; \
done

MANAGER_IP="$(docker-machine ip $MANAGER_NAME)"
WORKER1_IP="$(docker-machine ip worker1)"

docker-machine ssh $MANAGER_NAME docker swarm init --availability drain --advertise-addr $MANAGER_IP:2377

WORKER_JOIN_TOKEN="$(docker-machine ssh $MANAGER_NAME docker swarm join-token worker -q)"

for ((n=1;n<=WORKER_COUNT;n++)); do \
  docker-machine ssh worker$n docker swarm join --token $WORKER_JOIN_TOKEN $MANAGER_IP:2377; \
done

eval $(docker-machine env $MANAGER_NAME)
```


Alternatively, you can run the `create-swarm.sh` bash script in the `docker/`
directory in this repository. The only argument into the script is the number of
workers you'd like to create. By default it is set to 2

```
$ cd docker/registry
$ chmod +x create-swarm.sh
$ ./create-swarm.sh 3
```

## Launching the Docker private registry as a service ([TL;DR](#service-launch))

The easiest way to launch the registry as a service is using the Docker Compose
configuration included with this project at `docker/registry/docker-compose.yml`.
Once you have a Docker Swarm running, the service can be issued using a single
command. The example here assumes you are in the top level directory of this project.

```
$ docker stack deploy registry -c docker/registry/docker-compose.yml
Creating network registry_dlcc_network
Creating service registry_registry

$ docker service ls
docker service ls
ID                  NAME                MODE                REPLICAS            IMAGE               PORTS
y9pd5pq0wwix        registry_registry   replicated          1/1                 registry:2.6.2      *:5000->5000/tcp

$ docker service logs registry_registry
registry_registry.1.m94j7fffrj5q@worker1    | time="2017-08-11T18:42:41Z" level=warning msg="No HTTP secret provided - generated random secret. This may cause problems with uploads if multiple registries are behind a load-balancer. To provide a shared secret, fill in http.secret in the configuration file or set the REGISTRY_HTTP_SECRET environment variable." go.version=go1.7.6 instance.id=d91d2708-ea8d-45c4-b5fc-d43d3930008b version=v2.6.2
registry_registry.1.m94j7fffrj5q@worker1    | time="2017-08-11T18:42:41Z" level=info msg="redis not configured" go.version=go1.7.6 instance.id=d91d2708-ea8d-45c4-b5fc-d43d3930008b version=v2.6.2
registry_registry.1.m94j7fffrj5q@worker1    | time="2017-08-11T18:42:41Z" level=info msg="Starting upload purge in 50m0s" go.version=go1.7.6 instance.id=d91d2708-ea8d-45c4-b5fc-d43d3930008b version=v2.6.2
registry_registry.1.m94j7fffrj5q@worker1    | time="2017-08-11T18:42:41Z" level=info msg="using inmemory blob descriptor cache" go.version=go1.7.6 instance.id=d91d2708-ea8d-45c4-b5fc-d43d3930008b version=v2.6.2
registry_registry.1.m94j7fffrj5q@worker1    | time="2017-08-11T18:42:41Z" level=info msg="listening on [::]:5000" go.version=go1.7.6 instance.id=d91d2708-ea8d-45c4-b5fc-d43d3930008b version=v2.6.2
```

This command uses the Docker Compose configuration to launch a service using the
[registry:2.6.2 image provided by the Docker community](https://hub.docker.com/_/registry/).
The first time you run this command, it may take some time to complete since the
Docker engine running on the node that launches the service will need to pull down
the Docker registry image from Dockerhub.

Also note that this registry is not secured. This means that communications happen
without having to log into the registry and there is no use of HTTPS.

#### *THIS IS STRICTLY FOR LOCAL DEVELOPMENT*

### <a name="service-launch"></a>Launching the Docker private registry as a service TL;DR

After changing your working directory to the root of this project, you can run the
single stack launch command.

```
docker stack deploy registry -c docker/registry/docker-compose.yml
```

## Registry communications

Typically the Docker engine that communicates with the registry is doing so from the
context of the Docker Machine VM. Therefore the Docker engine will call the registry
using localhost at port 5000 all the time.

```
$ for n in "${array[@]}"; do docker-machine ssh $n curl -s 'http://localhost:5000/v2/';done
{}{}{}
```

Each machine can curl localhost at port 5000 and get the same response even though
the registry runs only on one node. 

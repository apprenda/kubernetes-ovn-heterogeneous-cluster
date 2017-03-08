# Heterogeneous Kubernetes cluster demo

## Build images

Since we are not caching the Windows Containers images to be used for this demo, you'll need to build them on every Windows node, as follows:

### redis-master

There is no need to build an image since the official `redis:3.0-nanoserver` will be used.

### redis-slave

```sh
cd docker/redis-slave
docker build -t redis-slave:3.0-nanoserver .
```

### guestbook

```sh
cd docker/guestbook
docker build -t guestbook:v0.3-nanoserver .
```

## Deploy

Deployment may happen anywhere for as long as there's access to the Kubernetes API, as follows:

```sh
cd deploy
```

Create the services:
```sh
kubectl create -f redis-master-svc.yaml
kubectl create -f redis-slave-svc.yaml
kubectl create -f guestbook-svc.yaml
```

Now, run the Redis master instance:
```sh
kubectl create -f redis-master-deployment.yaml
```

**Wait until Redis master is running**, and run the Redis slave instances:
```sh
kubectl create -f redis-slave-deployment.yaml
```

Lastly, run the guestbook app instances:
```sh
kubectl create -f guestbook-deployment.yaml
```
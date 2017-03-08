# Heterogeneous Kubernetes cluster demo

## Download this repository to your Windows worker

In a PowerShell with Administrator privileges run:

```sh
cd C:\
Start-BitsTransfer https://github.com/apprenda/kubernetes-ovn-heterogeneous-cluster/archive/master.zip
cmd /c '"C:\Program Files\7-Zip\7z.exe" x master.zip'
rm master.zip
```

## Build images

Since we are not caching the Windows Containers images to be used for this demo, you'll need to build them on every Windows node, as follows:

### redis-master

There is no need to build an image since the official `redis:3.0-nanoserver` will be used.

### redis-slave

```sh
cd C:\kubernetes-ovn-heterogeneous-cluster-master\demo\docker\redis-slave\
docker build -t redis-slave:3.0-nanoserver .
```

### guestbook

```sh
cd C:\kubernetes-ovn-heterogeneous-cluster-master\demo\docker\guestbook\
docker build -t guestbook:v0.3-nanoserver .
```

## Deploy

Deployment may happen anywhere for as long as there's access to the Kubernetes API, as follows:

```sh
cd ~/kubernetes-ovn-heterogeneous-cluster/demo/deploy
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
kubectl get pods  # until status is Running
kubectl logs <pod-name>  # verify Redis started successfully
```
On your Windows worker node, `docker ps` should now show a running `redis:3.0-nanoserver` container.

**Wait until Redis master is running**, then run the Redis slave instances:
```sh
kubectl create -f redis-slave-deployment.yaml
```

Lastly, run the guestbook app instances:
```sh
kubectl create -f guestbook-deployment.yaml
```

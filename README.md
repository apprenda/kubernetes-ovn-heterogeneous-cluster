# Heterogeneous Kubernetes cluster on top of OVN

**Author**: Paulo Pires <pires@apprenda.com>

This document describes, step-by-step, how to provision a Kubernetes cluster comprised of:
* One Linux machine acting as Kubernetes master node and OVN central database.
* One Linux machine acting as Kubernetes worker node.
* One Windows machine acting as Kubernetes worker node.

Many thanks to the great people that helped achieve this, namely:
* Alin Serdean (Cloudbase Solutions)
* Alin Balutoiu (Cloudbase Solutions)
* Feng Min (Google)
* Peter Hornyack (Google)
* The authors of https://github.com/openvswitch/ovn-kubernetes

## TODO

The following items are to be implemented and are not sorted by importance!

* Copy CA files from master.
* `etcd` container should use a host path for storing data, in order to survive restarts.
* Add other cloud providers documentation, e.g. AWS.
* Add gateway node instructions for enabling pod containers Internet access.
* Setup OVS TLS.
* Add Windows node TLS support.

## Requirements

At the time of this writing, the instructions are meant to be run on Google Compute Engine, but apart from `gcloud` calls and a few networking details, everything detailed below should work regardless of the adopted cloud-provider.

Having that said, here are the requirements:
* Use Google Cloud Platform (GCP), namely Google Compute Engine (GCE) VMs.
  * `gcloud` CLI tool
* Linux machines(s) run Ubuntu 16.04 with latest updates.
* Windows machine(s) run Windows Server 2016 with latest updates.
* Administrator access to all VMs, i.e. `root` in Linux machines.

## Master (Linux)

### Node set-up

Let's provision the master VM:
```sh
gcloud compute instances create "sig-windows-master" \
    --zone "us-east1-d" \
    --machine-type "custom-2-2048" \
    --can-ip-forward \
    --tags "https-server" \
    --image "ubuntu-1604-xenial-v20170125" \
    --image-project "ubuntu-os-cloud" \
    --boot-disk-size "50" \
    --boot-disk-type "pd-ssd" \
```

When it's ready, SSH into it:
```sh
gcloud compute ssh --zone "us-east1-d" "sig-windows-master"
```

**ATTENTION**: From now on, it's assumed you're logged-in as `root`.

Let's install OVS/OVN:
```sh
curl -fsSL https://yum.dockerproject.org/gpg | apt-key add -
echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > sudo tee /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker.io dkms
```

```sh
cd ~
git clone https://github.com/apprenda/kubernetes-ovn-heterogeneous-cluster
cd kubernetes-ovn-heterogeneous-cluster/deb

dpkg -i openvswitch-common_2.6.2-1_amd64.deb \
openvswitch-datapath-dkms_2.6.2-1_all.deb \
openvswitch-switch_2.6.2-1_amd64.deb \
ovn-common_2.6.2-1_amd64.deb \
ovn-central_2.6.2-1_amd64.deb \
ovn-docker_2.6.2-1_amd64.deb \
ovn-host_2.6.2-1_amd64.deb \
python-openvswitch_2.6.2-1_all.deb
```

We'll need to make sure `vport_geneve` kernel module is loaded at boot:
```sh
echo vport_geneve >> /etc/modules-load.d/modules.conf
```

Finally, reboot:
```sh
reboot
```

SSH again into the machine and let's proceed.

Create the OVS bridge interface:
```sh
export TUNNEL_MODE=geneve
export LOCAL_IP=10.142.0.2
export MASTER_IP=$LOCAL_IP

ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$MASTER_IP:6642" \
  external_ids:ovn-nb="tcp:$MASTER_IP:6641" \
  external_ids:ovn-encap-ip="$LOCAL_IP" \
  external_ids:ovn-encap-type="$TUNNEL_MODE"

ovs-vsctl get Open_vSwitch . external_ids
```

You should see something like:
```
{hostname=sig-windows-master.c.apprenda-project-one.internal, ovn-encap-ip="10.142.0.2", ovn-encap-type=geneve, ovn-nb="tcp:10.142.0.2:6641", ovn-remote="tcp:10.142.0.2:6642", system-id="e7af27f6-a218-40bb-8d4f-af67600abd17"}
```

We are now ready to set-up Kubernetes master node.

### Kubernetes set-up

**ATTENTION**: From now on, it's assumed you're logged-in as `root`.

First, we need to run `etcd`, the store used by Kubernetes. The following is a one-time step only:
```sh
cd ~/kubernetes-ovn-heterogeneous-cluster/master

rm -rf tmp
mkdir tmp
cp -R make-certs openssl.cnf kubedns-* manifests systemd tmp/

export HOSTNAME=`hostname`
export K8S_VERSION=1.5.3
export K8S_POD_SUBNET=10.244.0.0/16
export K8S_NODE_POD_SUBNET=10.244.1.0/24
export K8S_SERVICE_SUBNET=10.100.0.0/16
export K8S_API_SERVICE_IP=10.100.0.1
export K8S_DNS_VERSION=1.13.0
export K8S_DNS_SERVICE_IP=10.100.0.10
export K8S_DNS_DOMAIN=cluster.local
export ETCD_VERSION=3.1.1
export MASTER_IP=10.142.0.2

# The following is needed for now, because OVS can't route from pod network to node.
export MASTER_INTERNAL_IP=10.244.1.2

sed -i"*" "s|__K8S_VERSION__|$K8S_VERSION|g" tmp/manifests/*.yaml
sed -i"*" "s|__K8S_VERSION__|$K8S_VERSION|g" tmp/systemd/kubelet.service

sed -i"*" "s|__ETCD_VERSION__|$ETCD_VERSION|g" tmp/systemd/etcd3.service

sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/manifests/*.yaml
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/systemd/kubelet.service
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/openssl.cnf

sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/manifests/proxy.yaml
sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/systemd/kubelet.service
sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/make-certs
sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/openssl.cnf

sed -i"*" "s|__K8S_API_SERVICE_IP__|$K8S_API_SERVICE_IP|g" tmp/openssl.cnf

sed -i"*" "s|__K8S_POD_SUBNET__|$K8S_POD_SUBNET|g" tmp/manifests/*.yaml
sed -i"*" "s|__K8S_SERVICE_SUBNET__|$K8S_SERVICE_SUBNET|g" tmp/manifests/*.yaml

sed -i"*" "s|__K8S_DNS_SERVICE_IP__|$K8S_DNS_SERVICE_IP|g" tmp/systemd/kubelet.service
sed -i"*" "s|__K8S_DNS_DOMAIN__|$K8S_DNS_DOMAIN|g" tmp/systemd/kubelet.service

sed -i"*" "s|__K8S_DNS_SERVICE_IP__|$K8S_DNS_SERVICE_IP|g" tmp/kubedns-service.yaml
sed -i"*" "s|__K8S_DNS_VERSION__|$K8S_DNS_VERSION|g" tmp/kubedns-deployment.yaml
sed -i"*" "s|__K8S_DNS_DOMAIN__|$K8S_DNS_DOMAIN|g" tmp/*.*

cp -R tmp/systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable etcd3
systemctl start etcd3

cd tmp
chmod +x make-certs
./make-certs
cd ..

mkdir -p /etc/kubernetes
cp -R tmp/manifests /etc/kubernetes/

systemctl enable kubelet
systemctl start kubelet

curl -Lskj -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v$K8S_VERSION/bin/linux/amd64/kubectl
chmod +x /usr/bin/kubectl

kubectl config set-cluster default-cluster --server=https://$MASTER_IP --certificate-authority=/etc/kubernetes/tls/ca.pem
kubectl config set-credentials default-admin --certificate-authority=/etc/kubernetes/tls/ca.pem --client-key=/etc/kubernetes/tls/admin-key.pem --client-certificate=/etc/kubernetes/tls/admin.pem
kubectl config set-context local --cluster=default-cluster --user=default-admin
kubectl config use-context local
```

Now, let's configure pod networking for this node:
```sh
export TOKEN=$(kubectl describe secret $(kubectl get secrets | grep default | cut -f1 -d ' ') | grep -E '^token' | cut -f2 -d':' | tr -d '\t')

ovs-vsctl set Open_vSwitch . \
  external_ids:k8s-api-server="https://$MASTER_IP" \
  external_ids:k8s-api-token="$TOKEN"

ln -fs /etc/kubernetes/tls/ca.pem /etc/openvswitch/k8s-ca.crt

apt install -y python-pip
pip install --upgrade pip

cd ~
git clone https://github.com/openvswitch/ovn-kubernetes
cd ovn-kubernetes

# Before proceeding: https://github.com/openvswitch/ovn-kubernetes/pull/86

pip install --upgrade --prefix=/usr/local --ignore-installed .

ovn-k8s-overlay master-init \
  --cluster-ip-subnet="$K8S_POD_SUBNET" \
  --master-switch-subnet="$K8S_NODE_POD_SUBNET" \
  --node-name="$HOSTNAME"

systemctl enable ovn-k8s-watcher
systemctl start ovn-k8s-watcher
```

**TODO** **must** add hwaddress to /etc/network/interfaces.

And deploy Kubernetes DNS:
```sh
cd ~/kubernetes-ovn-heterogeneous-cluster/master
kubectl create -f tmp/kubedns-deployment.yaml
kubectl create -f tmp/kubedns-service.yaml
```

**Note** though that Kubernetes DNS will only become available when a schedulable Kubernetes node joins the cluster.

By this time, the master node is ready:
```sh
kubectl get nodes
kubectl -n kube-system get pods
```

You should see something like:
```
NAME                                 READY     STATUS    RESTARTS   AGE
kube-apiserver-10.138.0.2            1/1       Running   0          9m
kube-controller-manager-10.138.0.2   1/1       Running   0          9m
kube-dns-555682531-5pp48             0/3       Pending   0          1m
kube-proxy-10.138.0.2                1/1       Running   0          9m
kube-scheduler-10.138.0.2            1/1       Running   0          9m
```

Let's proceed to set-up the worker nodes.

## Worker (Linux)

### Node set-up

Let's provision the Linux worker VM:
```sh
gcloud compute instances create "sig-windows-worker-linux" \
    --zone "us-east1-d" \
    --machine-type "custom-2-2048" \
    --can-ip-forward \
    --image "ubuntu-1604-xenial-v20170125" \
    --image-project "ubuntu-os-cloud" \
    --boot-disk-size "50" \
    --boot-disk-type "pd-ssd" \
```

When it's ready, SSH into it:
```sh
gcloud compute ssh --zone "us-east1-d" "sig-windows-worker-linux"
```

**ATTENTION**: From now on, it's assumed you're logged-in as `root`.

Let's install OVS/OVN:
```sh
curl -fsSL https://yum.dockerproject.org/gpg | apt-key add -
echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > sudo tee /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker.io dkms
```

```sh
cd ~
git clone https://github.com/apprenda/kubernetes-ovn-heterogeneous-cluster
cd kubernetes-ovn-heterogeneous-cluster/deb

dpkg -i openvswitch-common_2.6.2-1_amd64.deb \
openvswitch-datapath-dkms_2.6.2-1_all.deb \
openvswitch-switch_2.6.2-1_amd64.deb \
ovn-common_2.6.2-1_amd64.deb \
ovn-central_2.6.2-1_amd64.deb \
ovn-docker_2.6.2-1_amd64.deb \
ovn-host_2.6.2-1_amd64.deb \
python-openvswitch_2.6.2-1_all.deb
```

We'll need to make sure `vport_geneve` kernel module is loaded at boot:
```sh
echo vport_geneve >> /etc/modules-load.d/modules.conf
```

Finally, reboot:
```sh
reboot
```

SSH again into the machine, become root and let's proceed.

Create the OVS bridge interface:
```sh
export TUNNEL_MODE=geneve
export LOCAL_IP=10.142.0.3
export MASTER_IP=10.142.0.2

ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$MASTER_IP:6642" \
  external_ids:ovn-nb="tcp:$MASTER_IP:6641" \
  external_ids:ovn-encap-ip="$LOCAL_IP" \
  external_ids:ovn-encap-type="$TUNNEL_MODE"

ovs-vsctl get Open_vSwitch . external_ids
```

You should see something like:
```
{hostname=sig-windows-worker-linux-1.c.apprenda-project-one.internal, ovn-encap-ip="10.142.0.3", ovn-encap-type=geneve, ovn-nb="tcp:10.142.0.2:6641", ovn-remote="tcp:10.142.0.2:6642", system-id="c6364c4c-8069-4bfd-ace8-ec701572feb7"}
```

We are now ready to set-up Kubernetes Linux worker node.

### Kubernetes set-up

**Attention**: You **must** copy the CA keypair that's available in the master node over the following paths:
* /etc/kubernetes/tls/ca.pem
* /etc/kubernetes/tls/ca-key.pem

When it's done, proceed with the following:
```sh
cd ~/kubernetes-ovn-heterogeneous-cluster/worker/linux

rm -rf tmp
mkdir tmp
cp -R ../make-certs ../openssl.cnf ../kubeconfig.yaml manifests systemd tmp/

export HOSTNAME=`hostname`
export K8S_VERSION=1.5.3
export K8S_POD_SUBNET=10.244.0.0/16
export K8S_NODE_POD_SUBNET=10.244.2.0/24
export K8S_DNS_SERVICE_IP=10.100.0.10
export K8S_DNS_DOMAIN=cluster.local
export MASTER_IP=10.142.0.2
export LOCAL_IP=10.142.0.3

sed -i"*" "s|__K8S_VERSION__|$K8S_VERSION|g" tmp/manifests/proxy.yaml
sed -i"*" "s|__K8S_VERSION__|$K8S_VERSION|g" tmp/systemd/kubelet.service

sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/manifests/proxy.yaml
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/systemd/kubelet.service
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/openssl.cnf
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/kubeconfig.yaml

sed -i"*" "s|__LOCAL_IP__|$LOCAL_IP|g" tmp/manifests/proxy.yaml
sed -i"*" "s|__LOCAL_IP__|$LOCAL_IP|g" tmp/systemd/kubelet.service
sed -i"*" "s|__LOCAL_IP__|$LOCAL_IP|g" tmp/openssl.cnf

sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/manifests/proxy.yaml
sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/systemd/kubelet.service
sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/make-certs

sed -i"*" "s|__K8S_POD_SUBNET__|$K8S_POD_SUBNET|g" tmp/manifests/proxy.yaml

sed -i"*" "s|__K8S_DNS_SERVICE_IP__|$K8S_DNS_SERVICE_IP|g" tmp/systemd/kubelet.service
sed -i"*" "s|__K8S_DNS_DOMAIN__|$K8S_DNS_DOMAIN|g" tmp/systemd/kubelet.service

cd tmp
chmod +x make-certs
./make-certs
cd ..

cp -R tmp/manifests /etc/kubernetes/

cp tmp/kubeconfig.yaml /etc/kubernetes/

cp -R tmp/systemd/*.service /etc/systemd/system/
systemctl daemon-reload

curl -Lskj -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v$K8S_VERSION/bin/linux/amd64/kubectl
chmod +x /usr/bin/kubectl

kubectl config set-cluster default-cluster --server=https://$MASTER_IP --certificate-authority=/etc/kubernetes/tls/ca.pem
kubectl config set-credentials default-admin --certificate-authority=/etc/kubernetes/tls/ca.pem --client-key=/etc/kubernetes/tls/node-key.pem --client-certificate=/etc/kubernetes/tls/node.pem
kubectl config set-context local --cluster=default-cluster --user=default-admin
kubectl config use-context local
 ```

Now, let's configure pod networking for this node:
```sh
export TOKEN=$(kubectl describe secret $(kubectl get secrets | grep default | cut -f1 -d ' ') | grep -E '^token' | cut -f2 -d':' | tr -d '\t')

ovs-vsctl set Open_vSwitch . \
  external_ids:k8s-api-server="https://$MASTER_IP" \
  external_ids:k8s-api-token="$TOKEN"

ln -fs /etc/kubernetes/tls/ca.pem /etc/openvswitch/k8s-ca.crt

mkdir -p /opt/cni/bin && cd /opt/cni/bin
curl -Lskj -o cni.tar.gz https://github.com/containernetworking/cni/releases/download/v0.4.0/cni-v0.4.0.tgz
tar zxf cni.tar.gz
rm -f cni.tar.gz

apt install -y python-pip
pip install --upgrade pip

cd ~
git clone https://github.com/openvswitch/ovn-kubernetes
cd ovn-kubernetes

# Before proceeding: https://github.com/openvswitch/ovn-kubernetes/pull/86

pip install --upgrade --prefix=/usr/local --ignore-installed .

ovn-k8s-overlay minion-init \
  --cluster-ip-subnet="$K8S_POD_SUBNET" \
  --minion-switch-subnet="$K8S_NODE_POD_SUBNET" \
  --node-name="$HOSTNAME"
```

**TODO** **must** add hwaddress to /etc/network/interfaces.

By this time, your Linux worker node is ready to run Kubernetes workloads:
```sh
systemctl enable kubelet
systemctl start kubelet
kubectl get nodes
kubectl -n kube-system get pods
```

Let's proceed to setup the Windows worker node.

## Worker (Windows)

For the sake of simplicity when setting up Windows node, we will not be relying on TLS for now.

### Node set-up

Let's provision the Windows worker VM:
```sh
gcloud compute instances create "sig-windows-worker-windows-1" \
  --zone "us-east1-d" \
  --machine-type "custom-4-4096" \
  --can-ip-forward \
  --image "windows-server-2016-dc-v20170117" \
  --image-project "windows-cloud" \
  --boot-disk-size "50" \
  --boot-disk-type "pd-ssd" \
```

After VM is provisioned, establish a new connection to it. How one does this is out of the scope of this document.

Now, start a new Powershell session with administrator privileges and execute:
```sh
cd \
mkdir ovs
cd ovs

Start-BitsTransfer https://cloudbase.it/downloads/OpenvSwitch_prerelease.msi
Start-BitsTransfer https://cloudbase.it/downloads/k8s_ovn_service_prerelease.zip

cmd /c 'msiexec /i OpenvSwitch_prerelease.msi /qn'

netsh netkvm setparam 0 *RscIPv4 0
netsh netkvm restart 0

# You will need to reconnect your RDP session after restarting the netkvm
# driver.

Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
Install-Package -Name docker -ProviderName DockerMsftProvider
```

A reboot is mandatory:
```sh
Restart-Computer -Force
```

Re-establish connection to the VM.

Now, one needs to set-up the overlay (OVN) network. On a per node basis, copy `worker/windows/install_ovn.ps1` over to `C:\ovs` on the Windows node and edit its contents accordingly before running the Powershell script.

Then, start a new Powershell session with administrator privileges and execute:
```sh
cd C:\ovs
.\install_ovn.ps1
```

We are now ready to set-up Kubernetes Windows worker node.

### Kubernetes set-up

On a per node basis, copy `worker/windows/install_k8s.ps1` over to the Windows node and edit its contents accordingly before running the Powershell script.

Now, let's install Kubernetes:
```sh
.\install_k8s.ps1
```

**Attention**: While we don't automate Kubernetes components registration as Windows services, one will need to edit the commands below according to the specifics of the cluster in the making.

Run `kube-proxy`:
```sh
New-VMSwitch -Name KubeProxySwitch -SwitchType Internal

cd C:\kubernetes
$env:INTERFACE_TO_ADD_SERVICE_IP = "KubeProxySwitch"
.\kube-proxy.exe -v=3 --proxy-mode=userspace --hostname-override=sig-windows-worker-windows-1 --bind-address=10.142.0.5 --master=http://10.142.0.2:8080 --cluster-cidr=10.244.0.0/16
```

And the `kubelet`:
```sh
cd C:\kubernetes
$env:CONTAINER_NETWORK = "external"
.\kubelet.exe -v=3 --address=10.142.0.9 --hostname-override=10.142.0.9 --cluster_dns=10.100.0.10 --cluster_domain=cluster.local --pod-infra-container-image="apprenda/pause" --resolv-conf="" --api_servers=http://10.142.0.2:8080
```

If everything is working, you should see all three nodes and several pods in the output of these kubectl commands:
```sh
cd C:\kubernetes
.\kubectl.exe -s 10.142.0.2:8080 get nodes
.\kubectl.exe -s 10.142.0.2:8080 -n kube-system get pods
```

## Troubleshooting

Look in [ovn-kubernetes issues](https://github.com/openvswitch/ovn-kubernetes/issues) first. Some problems we found are:
* https://github.com/openvswitch/ovn-kubernetes/issues/79
* https://github.com/openvswitch/ovn-kubernetes/issues/80
* https://github.com/openvswitch/ovn-kubernetes/issues/82
* https://github.com/openvswitch/ovn-kubernetes/issues/85

## (Optional) Build packages

### OVS/OVN

As `root`, run:
```
apt update
apt install -y build-essential fakeroot dkms \
autoconf automake debhelper dh-autoreconf libssl-dev libtool \
python-all python-twisted-conch python-zopeinterface \
graphviz

cd ~
git clone https://github.com/openvswitch/ovs.git
cd ovs
git checkout branch-2.6

dpkg-checkbuilddeps

DEB_BUILD_OPTIONS='nocheck' fakeroot debian/rules binary
```

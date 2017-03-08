# Master node

## Node set-up

Let's provision the master VM:
```sh
gcloud compute instances create "sig-windows-master" \
    --zone "us-east1-d" \
    --machine-type "custom-2-2048" \
    --can-ip-forward \
    --tags "https-server" \
    --image-family "ubuntu-1604-lts" \
    --image-project "ubuntu-os-cloud" \
    --boot-disk-size "50" \
    --boot-disk-type "pd-ssd"
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

SSH again into the machine, become root and proceed to configure OVS/OVN.

**ATTENTION**:
* From now on, it's assumed you're logged-in as `root`.
* Pay attention to the environment variables below, particularly:
  * `LOCAL_IP` must be the public IP of this node

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

## Kubernetes set-up

**ATTENTION**:
* From now on, it's assumed you're logged-in as `root`.
* Pay attention to the environment variables below, particularly:
  * `MASTER_INTERNAL_IP` must be an IP within `K8S_NODE_POD_SUBNET` subnet
  * `K8S_DNS_SERVICE_IP` must be an IP within `K8S_SERVICE_SUBNET` subnet

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

# The following is needed for now, because OVS can't route from pod network to node.
export MASTER_INTERNAL_IP=10.244.1.2

sed -i"*" "s|__K8S_VERSION__|$K8S_VERSION|g" tmp/manifests/*.yaml
sed -i"*" "s|__K8S_VERSION__|$K8S_VERSION|g" tmp/systemd/kubelet.service

sed -i"*" "s|__ETCD_VERSION__|$ETCD_VERSION|g" tmp/systemd/etcd3.service

sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/manifests/*.yaml
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/systemd/kubelet.service
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/openssl.cnf

sed -i"*" "s|__MASTER_INTERNAL_IP__|$MASTER_INTERNAL_IP|g" tmp/manifests/*.yaml

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

**Attention**: the API server will take a minute or more to come up, depending on the CPUs available and networking speed. So, before proceeding make sure the API server came up. Run `kubectl get nodes` until you see something like:
```
NAME           STATUS                     AGE
pires-master   Ready,SchedulingDisabled   7s
```

After making sure the API server is up & running, you need to configure pod networking for this node:
```sh
export TOKEN=$(kubectl describe secret $(kubectl get secrets | grep default | cut -f1 -d ' ') | grep -E '^token' | cut -f2 -d':' | tr -d '\t')

ovs-vsctl set Open_vSwitch . \
  external_ids:k8s-api-server="https://$MASTER_IP" \
  external_ids:k8s-api-token="$TOKEN"

ln -fs /etc/kubernetes/tls/ca.pem /etc/openvswitch/k8s-ca.crt

apt install -y python-pip

pip install --upgrade pip

cd ~
git clone https://github.com/alinbalutoiu/ovn_alpha ovn-kubernetes
cd ovn-kubernetes

pip install --upgrade --prefix=/usr/local --ignore-installed .

ovn-k8s-overlay master-init \
  --cluster-ip-subnet="$K8S_POD_SUBNET" \
  --master-switch-subnet="$K8S_NODE_POD_SUBNET" \
  --node-name="$HOSTNAME"

systemctl enable ovn-k8s-watcher
systemctl start ovn-k8s-watcher
```

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
NAME                                         READY     STATUS    RESTARTS   AGE
kube-apiserver-sig-windows-master            1/1       Running   0          9m
kube-controller-manager-sig-windows-master   1/1       Running   0          9m
kube-dns-555682531-5pp48                     0/3       Pending   0          1m
kube-scheduler-sig-windows-master            1/1       Running   0          9m
```

[**Go back**](../README.md#cluster-deployment).

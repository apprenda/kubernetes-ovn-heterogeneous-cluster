# Gateway node

## Node set-up

Let's provision the gateway VM:
```sh
gcloud compute instances create "sig-windows-gw" \
    --zone "us-east1-d" \
    --machine-type "custom-2-2048" \
    --can-ip-forward \
    --image-family "ubuntu-1604-lts" \
    --image-project "ubuntu-os-cloud" \
    --boot-disk-size "50" \
    --boot-disk-type "pd-ssd"
```

When it's ready, SSH into it:
```sh
gcloud compute ssh --zone "us-east1-d" "sig-windows-gw"
```

**ATTENTION**:
* From now on, it's assumed you're logged-in as `root`.
* You **must** copy the CA keypair that's available in the master node over the following paths:
  * /etc/kubernetes/tls/ca.pem
  * /etc/kubernetes/tls/ca-key.pem
* Pay attention to the environment variables below, particularly:
  * `LOCAL_IP` must be the public IP of this node
  * `MASTER_IP` must be the remote public IP address of the master node
  * `GW_IP` must be the cloud provider default gateway IP address

Let's install OVS/OVN:
```sh
curl -fsSL https://yum.dockerproject.org/gpg | apt-key add -
echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > sudo tee /etc/apt/sources.list.d/docker.list

apt update
apt install -y dkms
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

SSH again into the machine and proceed to configure OVS/OVN.

Create the OVS bridge interface:
```sh
export TUNNEL_MODE=geneve
export MASTER_IP=10.142.0.2
export LOCAL_IP=10.142.0.4
export GW_IP=10.142.0.1
export HOSTNAME=`hostname`
export NIC=ens4
export K8S_VERSION=1.5.3
export K8S_POD_SUBNET=10.244.0.0/16

ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$MASTER_IP:6642" \
  external_ids:ovn-nb="tcp:$MASTER_IP:6641" \
  external_ids:ovn-encap-ip="$LOCAL_IP" \
  external_ids:ovn-encap-type="$TUNNEL_MODE"

ovs-vsctl get Open_vSwitch . external_ids

cd ~/kubernetes-ovn-heterogeneous-cluster/gateway

rm -rf tmp
mkdir tmp
cp -R ../worker/make-certs ../worker/openssl.cnf ../worker/kubeconfig.yaml systemd tmp/

sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/openssl.cnf
sed -i"*" "s|__MASTER_IP__|$MASTER_IP|g" tmp/kubeconfig.yaml

sed -i"*" "s|__LOCAL_IP__|$LOCAL_IP|g" tmp/openssl.cnf

sed -i"*" "s|__HOSTNAME__|$HOSTNAME|g" tmp/make-certs

sed -i"*" "s|__NIC__|$NIC|g" tmp/systemd/ovn-k8s-gateway-helper.service

cd tmp
chmod +x make-certs
./make-certs
cd ..

cp tmp/kubeconfig.yaml /etc/kubernetes/

cp tmp/systemd/ovn-k8s-gateway-helper.service /etc/systemd/system/

curl -Lskj -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v$K8S_VERSION/bin/linux/amd64/kubectl
chmod +x /usr/bin/kubectl

kubectl config set-cluster default-cluster --server=https://$MASTER_IP --certificate-authority=/etc/kubernetes/tls/ca.pem
kubectl config set-credentials default-admin --certificate-authority=/etc/kubernetes/tls/ca.pem --client-key=/etc/kubernetes/tls/node-key.pem --client-certificate=/etc/kubernetes/tls/node.pem
kubectl config set-context local --cluster=default-cluster --user=default-admin
kubectl config use-context local

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

pip install --upgrade --prefix=/usr/local --ignore-installed .

# This command will print "RTNETLINK answers: Network is unreachable" and
# "RTNETLINK answers: File exists"; these messages are expected.
ovn-k8s-util nics-to-bridge $NIC && dhclient br$NIC

ovn-k8s-overlay gateway-init \
  --cluster-ip-subnet "$K8S_POD_SUBNET" \
  --bridge-interface "br$NIC" \
  --physical-ip "$LOCAL_IP/20" \
  --node-name "$HOSTNAME" \
  --default-gw "$GW_IP"

systemctl daemon-reload
systemctl enable ovn-k8s-gateway-helper.service
systemctl start ovn-k8s-gateway-helper.service
```

[**Go back**](../README.md#cluster-deployment).

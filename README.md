# Heterogeneous Kubernetes cluster on top of OVN

**Author**: Paulo Pires <pires@apprenda.com>

This document describes, step-by-step, how to provision a Kubernetes cluster comprised of:
* One Linux machine acting as Kubernetes master node and OVN central database.
* One Linux machine acting as Kubernetes worker node.
* One Windows machine acting as Kubernetes worker node.
* One Linux machine acting as gateway node.

**Many thanks to the great people that helped achieve this**, namely:
* Alin Serdean (Cloudbase Solutions)
* Alin Balutoiu (Cloudbase Solutions)
* Feng Min (Google)
* Peter Hornyack (Google)
* The authors of https://github.com/openvswitch/ovn-kubernetes
* [Kubernetes SIG-Windows](https://github.com/kubernetes/community/tree/master/sig-windows)

## Requirements

At the time of this writing, the instructions are meant to be run on Google Compute Engine, but apart from `gcloud` calls and a few networking details, everything detailed below should work regardless of the adopted cloud-provider.

Having that said, here are the requirements:
* Use Google Cloud Platform (GCP), namely Google Compute Engine (GCE) VMs.
  * `gcloud` CLI tool
* Linux machines(s) run Ubuntu 16.04 with latest updates.
* Windows machine(s) run Windows Server 2016 with latest updates.
* Administrator access to all VMs, i.e. `root` in Linux machines.

## Cluster deployment

Follow these steps to deploy your cluster:
* [Deploy the master node](master), where the OVS/OVN and Kubernetes master components will run.
* [Deploy worker nodes, Linux and Windows](worker), where the Kubernetes workloads will run.
* [Deploy a gateway node](gateway), needed for pod container access to the Internet **and** for exposing services to the Internet (through services with `NodePort` load-balancer type).

## Demo application

[Heterogeneous Kubernetes cluster demo](demo).

## Troubleshooting

Some pending issues:
* [Load-Balancer service type is not supported in ovn-kubernetes](https://github.com/openvswitch/ovn-kubernetes/issues/79)

## TODO

* Automate copying CA certificate and key files from master node to all the other nodes.
* Adopt OVS TLS usage.
* Add kubelet TLS support on Windows worker node.
* Add other documenation for other cloud providers documentation, e.g. AWS.

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

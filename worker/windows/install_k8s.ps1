$K8S_PATH="C:\kubernetes"
$K8S_VERSION="1.5.3"
$HOSTNAME = hostname
$K8S_MASTER_IP = "10.142.0.2"
$K8S_DNS_SERVICE_IP = "10.100.0.10"
$K8S_DNS_DOMAIN = "cluster.local"

mkdir $K8S_PATH
cd $K8S_PATH

# Install 7z so we can extract Kubernetes binaries
Start-BitsTransfer http://www.7-zip.org/a/7z1604-x64.exe
cmd /c 'C:\kubernetes\7z1604-x64.exe /qn'
Remove-Item -Recurse -Force 7z1604-x64.exe

# Download and extract Kubernetes binaries
Start-BitsTransfer https://dl.k8s.io/v$K8S_VERSION/kubernetes-node-windows-amd64.tar.gz
cmd /c '"C:\Program Files\7-Zip\7z.exe" e kubernetes-node-windows-amd64.tar.gz'
cmd /c '"C:\Program Files\7-Zip\7z.exe" x kubernetes-node-windows-amd64.tar'
mv kubernetes\node\bin\*.exe .
Remove-Item -Recurse -Force kubernetes
Remove-Item -Recurse -Force kubernetes-node-windows-amd64*

# TODO
# Register kubelet as a service and start it
#setx -m CONTAINER_NETWORK "external"
#cmd /c 'sc create kubelet binPath= "\"C:\Program Files (x86)\Open vSwitch\bin\servicewrapper.exe\" kubelet \"C:\kubernetes\kubelet.exe\" -v=3 --hostname-override=sig-windows-worker-windows --cluster_dns=10.100.0.10 --cluster_domain=cluster.local --pod-infra-container-image=\"apprenda/pause\" --resolv-conf=\"\" --api_servers=\"http://10.142.0.2:8080\" --log-dir=\"C:\kubernetes\"" type= own start= auto error= ignore displayname= "Kubernetes Kubelet" obj= LocalSystem'

$K8S_PATH="C:\kubernetes"
$K8S_VERSION="1.5.3"

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

# TODO register kube-proxy as a service and start it

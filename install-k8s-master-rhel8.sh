#!/bin/bash

# installing k8s on RHEL8
# set CPU, RAM on virtual machine
# should do as root

# on ALL nodes:
# HOSTNAME="rhel8-k8s-<role>"
# systemctl set-hostname $HOSTNAME
# reboot now
# try dnf repolist before install
# update system before install: dnf update -y

username="toor"
docker_version=""
docker_compose_version="v2.12.2"

# FIXME higlight for echo messages
# FIXME cancel when step not succeed
# FIXME test set -e
# FIXME docker command execute without sudo

echo "Adding user"
adduser $username

echo "Enabling and starting chronyd"
systemctl start chronyd
systemctl enable chronyd

echo "Setting correct time"
chronyc makestep

#echo "Updating system"
#dnf update -y

echo "Uninstalling podman && buildah"
dnf remove -y podman buildah

echo "Set hostnames in /etc/hosts file"
cat > /etc/hosts << EOF
127.0.0.1 localhost
192.168.88.216 rhel8-k8s-master
192.168.88.219 rhel8-k8s-node01
192.168.88.220 rhel9-k8s-node02
EOF

echo "Adding repos for docker"
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
echo "Installing docker"
set -e
dnf install docker-ce --nobest -y
echo "Staring and enabling docker"
systemctl start docker.service
systemctl enable docker.service
set +e

echo "Installing iproute-tc && wget && git"
dnf install -y iproute-tc wget git

echo "Downloading and installing docker-compose"
curl -L "https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Disabling SELinux"
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux

echo "Disabling and stoping firewall"
systemctl disable firewalld
systemctl stop firewalld

echo "Disabling swap"
sed -i '/swap/d' /etc/fstab
swapoff -a

echo "Setting params for k8s"
cat >> /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

echo "Adding k8s repo"
cat << EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

echo "Installing k8s"
dnf install -y kubeadm-1.15.6-0.x86_64 kubelet-1.15.6-0.x86_64 kubectl-1.15.6-0.x86_64 --disableexcludes=kubernetes
# dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

echo "Enabling and starting k8s"
systemctl enable kubelet
systemctl start kubelet

# on MASTER node:
#kubeadm init --apiserver-advertise-address=192.168.88.216 --pod-network-cidr=192.168.10.0/24 --cri-socket /var/run/dockershim.sock 
echo "Initializing cluster"
kubeadm init --apiserver-advertise-address=192.168.88.216 --pod-network-cidr=192.168.10.0/24

echo "Creating /home/'$username'/.kube folder"
rm -rf /home/"$username"/.kube
mkdir /home/"$username"/.kube
echo "Copying config file and setting rights"
cp /etc/kubernetes/admin.conf /home/"$username"/.kube/config
chown -R $username:$username /home/"$username"/.kube

sudo -i -u $username bash << EOF
echo "Downloading calico.yaml file"
rm -f /home/'$username'/calico.yaml
wget https://docs.projectcalico.org/v3.9/manifests/calico.yaml

echo "Changing subnet in calico.yaml"
sed -i --follow-symlinks 's/192.168.0.0\/16/192.168.10.0\/24/' /home/'$username'/calico.yaml

echo "Deploying Calico network"
kubectl create -f /home/'$username'/calico.yaml

echo "Echoing join to k8s-master command"
kubeadm token create --print-join-command
EOF

echo "Changing user"
su - $username

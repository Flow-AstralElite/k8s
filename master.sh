#!/bin/bash

################################################################################
# Kubernetes Master Node Installation Script for Fedora Server
# This script installs and configures Kubernetes master node
# Run with: sudo bash install-master-node.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Kubernetes Master Node Installation${NC}"
echo -e "${GREEN}Fedora Server${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Step 1: Update system
print_step "Step 1: Updating system packages..."
dnf update -y
dnf install -y curl wget vim net-tools

# Step 2: Disable swap
print_step "Step 2: Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Disable swap in systemd
systemctl mask swap.target

# Step 3: Disable SELinux (required for Kubernetes)
print_step "Step 3: Configuring SELinux..."
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Step 4: Configure firewall
print_step "Step 4: Configuring firewall for master node..."
# Master node ports
firewall-cmd --permanent --add-port=6443/tcp  # Kubernetes API server
firewall-cmd --permanent --add-port=2379-2380/tcp  # etcd server client API
firewall-cmd --permanent --add-port=10250/tcp  # Kubelet API
firewall-cmd --permanent --add-port=10251/tcp  # kube-scheduler
firewall-cmd --permanent --add-port=10252/tcp  # kube-controller-manager
firewall-cmd --permanent --add-port=10255/tcp  # Read-only Kubelet API
firewall-cmd --permanent --add-port=8472/udp  # Flannel VXLAN
firewall-cmd --permanent --add-port=179/tcp  # Calico BGP
firewall-cmd --reload

# Step 5: Load kernel modules
print_step "Step 5: Loading required kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Step 6: Set sysctl parameters
print_step "Step 6: Configuring sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Step 7: Install container runtime (containerd)
print_step "Step 7: Installing containerd..."
dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
dnf install -y containerd.io

# Configure containerd
print_status "Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable SystemdCgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
systemctl status containerd --no-pager

# Step 8: Install Kubernetes components
print_step "Step 8: Installing Kubernetes components..."

# Add Kubernetes repository
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install Kubernetes packages
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable kubelet

# Step 9: Initialize Kubernetes cluster
print_step "Step 9: Initializing Kubernetes master node..."

# Get the IP address of the main network interface
IP_ADDR=$(hostname -I | awk '{print $1}')

print_status "Using IP address: $IP_ADDR"
print_status "Initializing cluster... This may take a few minutes..."

# Initialize cluster
kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=$IP_ADDR \
    --control-plane-endpoint=$IP_ADDR | tee /root/kubeadm-init.log

# Step 10: Set up kubeconfig
print_step "Step 10: Setting up kubeconfig..."

# Set up kubeconfig for root user
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Set up kubeconfig for regular users (if any)
if [ ! -z "$SUDO_USER" ]; then
    mkdir -p /home/$SUDO_USER/.kube
    cp -i /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
    chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube
    print_status "Kubeconfig also configured for user: $SUDO_USER"
fi

# Add kubectl completion for bash
kubectl completion bash > /etc/bash_completion.d/kubectl

# Step 11: Install network plugin
print_step "Step 11: Installing Calico network plugin..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

print_status "Waiting for Calico pods to start..."
sleep 10

# Step 12: Generate join command
print_step "Step 12: Generating join command for worker nodes..."
kubeadm token create --print-join-command > /root/join-command.sh
chmod +x /root/join-command.sh

# Also create a more detailed join info file
cat > /root/cluster-info.txt <<EOF
Kubernetes Master Node Configuration
=====================================
Master Node IP: $IP_ADDR
Installation Date: $(date)
Kubernetes Version: $(kubectl version --short 2>/dev/null | grep Server || echo "Unknown")

Join Command for Worker Nodes:
-------------------------------
$(cat /root/join-command.sh)

Configuration Files:
--------------------
- Kubeconfig: /etc/kubernetes/admin.conf
- Join command: /root/join-command.sh
- Init log: /root/kubeadm-init.log

Next Steps:
-----------
1. Wait for all pods to be in Running state:
   kubectl get pods -A

2. Verify node is Ready:
   kubectl get nodes

3. Use the join command above on worker nodes to add them to the cluster

4. Label worker nodes after they join:
   kubectl label node <worker-node-name> node-role.kubernetes.io/worker=worker
EOF

# Step 13: Display cluster information
print_step "Step 13: Verifying installation..."
sleep 5

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Master Node Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}Cluster Status:${NC}"
kubectl get nodes
echo ""

echo -e "${BLUE}System Pods Status:${NC}"
kubectl get pods -A
echo ""

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}IMPORTANT: Save this join command!${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
cat /root/join-command.sh
echo ""
echo -e "${GREEN}Join command saved to: /root/join-command.sh${NC}"
echo -e "${GREEN}Cluster info saved to: /root/cluster-info.txt${NC}"
echo ""

echo -e "${BLUE}Useful Commands:${NC}"
echo "  kubectl get nodes              # List all nodes"
echo "  kubectl get pods -A            # List all pods"
echo "  kubectl cluster-info           # Display cluster info"
echo "  cat /root/join-command.sh      # View join command"
echo ""

echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${YELLOW}Note: It may take a few minutes for all pods to be in Running state.${NC}"

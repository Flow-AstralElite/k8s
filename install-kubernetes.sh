#!/bin/bash

################################################################################
# Kubernetes Installation Script
# This script installs Kubernetes on Ubuntu/Debian systems
# Run with: sudo bash install-kubernetes.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Kubernetes Installation Script${NC}"
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

# Step 1: Update system
print_status "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Step 2: Disable swap
print_status "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 3: Load kernel modules
print_status "Loading required kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Step 4: Set sysctl parameters
print_status "Configuring sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Step 5: Install container runtime (containerd)
print_status "Installing containerd..."
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y containerd.io

# Configure containerd
print_status "Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable SystemdCgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# Step 6: Install kubeadm, kubelet, and kubectl
print_status "Installing Kubernetes components..."

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# Step 7: Initialize Kubernetes cluster (Master node only)
print_status "Do you want to initialize this node as a MASTER node? (y/n)"
read -r INIT_MASTER

if [ "$INIT_MASTER" = "y" ] || [ "$INIT_MASTER" = "Y" ]; then
    print_status "Initializing Kubernetes master node..."
    
    # Get the IP address of the main network interface
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    print_status "Using IP address: $IP_ADDR"
    print_status "Initializing cluster... This may take a few minutes..."
    
    kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$IP_ADDR | tee /root/kubeadm-init.log
    
    # Set up kubeconfig for root user
    print_status "Setting up kubeconfig..."
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    # Set up kubeconfig for regular users (if any)
    if [ ! -z "$SUDO_USER" ]; then
        mkdir -p /home/$SUDO_USER/.kube
        cp -i /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
        chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube
    fi
    
    # Install Calico network plugin
    print_status "Installing Calico network plugin..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
    
    # Extract join command
    print_status "Generating join command for worker nodes..."
    kubeadm token create --print-join-command > /root/join-command.sh
    chmod +x /root/join-command.sh
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Master Node Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Important: Save the following join command to add worker nodes:${NC}"
    echo ""
    cat /root/join-command.sh
    echo ""
    echo -e "${YELLOW}This command has been saved to: /root/join-command.sh${NC}"
    echo ""
    echo -e "${GREEN}To verify the cluster status, run:${NC}"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    
else
    print_status "Skipping master node initialization."
    echo -e "${YELLOW}This node is ready to join a cluster.${NC}"
    echo -e "${YELLOW}Run the join command provided by the master node.${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Worker Node Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
fi

print_status "Installation completed successfully!"

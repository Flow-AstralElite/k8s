#!/bin/bash

################################################################################
# Kubernetes Worker Node Installation Script for Fedora Server
# This script installs and prepares a worker node to join a Kubernetes cluster
# Run with: sudo bash install-worker-node.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Kubernetes Worker Node Installation${NC}"
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
print_step "Step 4: Configuring firewall for worker node..."
# Worker node ports
firewall-cmd --permanent --add-port=10250/tcp  # Kubelet API
firewall-cmd --permanent --add-port=30000-32767/tcp  # NodePort Services
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

# Step 9: Get worker node IP
IP_ADDR=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

# Create info file
cat > /root/worker-node-info.txt <<EOF
Kubernetes Worker Node Configuration
=====================================
Worker Node IP: $IP_ADDR
Worker Node Hostname: $HOSTNAME
Installation Date: $(date)

Status:
-------
✓ System updated
✓ Swap disabled
✓ SELinux configured
✓ Firewall configured
✓ Kernel modules loaded
✓ Sysctl parameters set
✓ Containerd installed and running
✓ Kubernetes components installed (kubelet, kubeadm, kubectl)

Next Steps:
-----------
1. Get the join command from the master node:
   - SSH to the master node
   - Run: cat /root/join-command.sh
   
2. Run the join command on this worker node:
   sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> \\
       --discovery-token-ca-cert-hash sha256:<HASH>

3. Verify on master node that this worker has joined:
   kubectl get nodes

4. Label this node (optional, run on master):
   kubectl label node $HOSTNAME node-role.kubernetes.io/worker=worker

Troubleshooting:
----------------
- Check kubelet status: systemctl status kubelet
- Check kubelet logs: journalctl -u kubelet -f
- Check containerd status: systemctl status containerd
- Test connectivity to master: telnet <MASTER-IP> 6443
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Worker Node Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}Worker Node Information:${NC}"
echo -e "  IP Address: ${GREEN}$IP_ADDR${NC}"
echo -e "  Hostname: ${GREEN}$HOSTNAME${NC}"
echo ""

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Next Step: Join the Cluster${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${BLUE}1. Get the join command from the master node:${NC}"
echo "   ssh root@<MASTER-IP>"
echo "   cat /root/join-command.sh"
echo ""
echo -e "${BLUE}2. Run the join command on this node:${NC}"
echo "   sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> \\"
echo "       --discovery-token-ca-cert-hash sha256:<HASH>"
echo ""
echo -e "${BLUE}3. Verify on master node:${NC}"
echo "   kubectl get nodes"
echo ""

echo -e "${GREEN}Configuration details saved to: /root/worker-node-info.txt${NC}"
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${YELLOW}This node is ready to join the Kubernetes cluster.${NC}"

# Step 10: Interactive join option
echo ""
read -p "Do you have the join command ready? (y/n): " HAS_JOIN

if [ "$HAS_JOIN" = "y" ] || [ "$HAS_JOIN" = "Y" ]; then
    echo ""
    echo -e "${GREEN}Please paste the join command and press Enter:${NC}"
    echo -e "${YELLOW}(Example: kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>)${NC}"
    echo ""
    read -r JOIN_COMMAND
    
    if [ ! -z "$JOIN_COMMAND" ]; then
        echo ""
        print_status "Joining the cluster..."
        eval $JOIN_COMMAND
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Successfully Joined the Cluster!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BLUE}Verify on the master node:${NC}"
        echo "  kubectl get nodes"
        echo "  kubectl get nodes -o wide"
        echo ""
    else
        print_error "No join command provided. You can join manually later."
    fi
else
    echo ""
    print_status "You can join the cluster later by running the join command from the master node."
    echo -e "${YELLOW}Don't forget to run the join command to complete the setup!${NC}"
fi

echo ""
echo -e "${GREEN}Worker node setup completed!${NC}"

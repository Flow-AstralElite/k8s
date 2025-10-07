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

# Step 7: Install container runtime (Docker)
print_step "Step 7: Installing Docker..."

# Install Docker directly from Fedora repositories
print_status "Installing Docker from Fedora repositories..."
dnf install -y docker

# Start and enable Docker service
print_status "Starting and enabling Docker service..."
systemctl start docker
systemctl enable docker

# Add current user to docker group (if not root)
if [ ! -z "$SUDO_USER" ]; then
    usermod -aG docker $SUDO_USER
    print_status "Added $SUDO_USER to docker group"
fi

# Verify Docker installation
print_status "Verifying Docker installation..."
docker --version

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
EOF

# Install Kubernetes packages
dnf install -y kubelet kubeadm kubectl

systemctl enable kubelet

# Step 9: Initialize Kubernetes cluster
print_step "Step 9: Initializing Kubernetes master node..."

# Check if cluster is already initialized
if [ -f /etc/kubernetes/admin.conf ] || [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ] || pgrep -f kube-apiserver > /dev/null; then
    echo ""
    print_warning "========================================="
    print_warning "KUBERNETES CLUSTER ALREADY EXISTS!"
    print_warning "========================================="
    echo ""
    print_status "Detected existing Kubernetes installation:"
    
    if [ -f /etc/kubernetes/admin.conf ]; then
        echo "  ✓ Admin config found: /etc/kubernetes/admin.conf"
    fi
    
    if [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
        echo "  ✓ API server manifest found"
    fi
    
    if pgrep -f kube-apiserver > /dev/null; then
        echo "  ✓ API server process is running"
    fi
    
    echo ""
    echo "OPTIONS:"
    echo "1. Reset and reinitialize (DESTRUCTIVE - will delete all data)"
    echo "2. Use existing cluster and skip to network setup"
    echo "3. Exit script"
    echo ""
    
    # Check if we can read input, if not default to option 2
    if [ -t 0 ]; then
        # Interactive terminal
        ATTEMPT=0
        while [ $ATTEMPT -lt 5 ]; do
            echo -n "Please choose an option (1/2/3): "
            read CHOICE 2>/dev/null || CHOICE=""
            
            # If read fails or empty, default to option 2 after 3 attempts
            if [ -z "$CHOICE" ]; then
                ATTEMPT=$((ATTEMPT + 1))
                echo "[WARNING] No input received (attempt $ATTEMPT/5)"
                if [ $ATTEMPT -ge 3 ]; then
                    echo "[INFO] Defaulting to option 2 (use existing cluster)"
                    CHOICE="2"
                fi
                sleep 1
            fi
            
            case $CHOICE in
                1)
                    print_warning "WARNING: This will completely reset your Kubernetes cluster!"
                    echo -n "Are you absolutely sure? Type 'YES' to confirm: "
                    read CONFIRM 2>/dev/null || CONFIRM=""
                    if [ "$CONFIRM" = "YES" ]; then
                        print_status "Resetting existing Kubernetes cluster..."
                        
                        # Stop services first
                        systemctl stop kubelet
                        
                        # Reset kubeadm
                        kubeadm reset -f
                        
                        # Clean up additional files
                        rm -rf /etc/cni/net.d
                        rm -rf /etc/kubernetes
                        rm -rf /var/lib/etcd
                        rm -rf $HOME/.kube
                        if [ ! -z "$SUDO_USER" ]; then
                            rm -rf /home/$SUDO_USER/.kube
                        fi
                        
                        # Reset iptables
                        iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
                        
                        # Restart services
                        systemctl restart docker
                        systemctl start kubelet
                        
                        print_status "Cluster reset completed. Proceeding with fresh initialization..."
                        sleep 5
                        break
                    else
                        print_error "Reset cancelled. Please choose another option."
                        continue
                    fi
                    ;;
                2)
                    print_status "Using existing cluster. Skipping initialization..."
                    
                    # Set up kubeconfig if not already done
                    if [ ! -f $HOME/.kube/config ]; then
                        mkdir -p $HOME/.kube
                        cp /etc/kubernetes/admin.conf $HOME/.kube/config
                        chown $(id -u):$(id -g) $HOME/.kube/config
                    fi
                    
                    # Set IP_ADDR for later use
                    IP_ADDR=$(hostname -I | awk '{print $1}')
                    
                    # Check existing cluster status
                    print_status "Current cluster status:"
                    kubectl get nodes
                    echo ""
                    
                    # Jump to network plugin installation
                    jump_to_network_install=true
                    break
                    ;;
                3)
                    print_status "Exiting script..."
                    exit 0
                    ;;
                "")
                    # Empty input, continue loop
                    continue
                    ;;
                *)
                    print_error "Invalid option '$CHOICE'. Please choose 1, 2, or 3."
                    ;;
            esac
        done
        
        # If we exit the loop without a valid choice, default to option 2
        if [ $ATTEMPT -ge 5 ]; then
            print_warning "Too many failed attempts. Defaulting to option 2 (use existing cluster)"
            CHOICE="2"
            
            print_status "Using existing cluster. Skipping initialization..."
            
            # Set up kubeconfig if not already done
            if [ ! -f $HOME/.kube/config ]; then
                mkdir -p $HOME/.kube
                cp /etc/kubernetes/admin.conf $HOME/.kube/config
                chown $(id -u):$(id -g) $HOME/.kube/config
            fi
            
            # Set IP_ADDR for later use
            IP_ADDR=$(hostname -I | awk '{print $1}')
            
            # Check existing cluster status
            print_status "Current cluster status:"
            kubectl get nodes
            echo ""
            
            # Jump to network plugin installation
            jump_to_network_install=true
        fi
    else
        # Non-interactive, default to option 2
        print_warning "Non-interactive mode detected. Defaulting to option 2 (use existing cluster)"
        
        print_status "Using existing cluster. Skipping initialization..."
        
        # Set up kubeconfig if not already done
        if [ ! -f $HOME/.kube/config ]; then
            mkdir -p $HOME/.kube
            cp /etc/kubernetes/admin.conf $HOME/.kube/config
            chown $(id -u):$(id -g) $HOME/.kube/config
        fi
        
        # Set IP_ADDR for later use
        IP_ADDR=$(hostname -I | awk '{print $1}')
        
        # Check existing cluster status
        print_status "Current cluster status:"
        kubectl get nodes
        echo ""
        
        # Jump to network plugin installation
        jump_to_network_install=true
    fi
else
    print_status "No existing Kubernetes installation detected. Proceeding with fresh installation..."
fi

# Initialize cluster only if not skipping
if [ "$jump_to_network_install" != "true" ]; then
    # Get the IP address of the main network interface
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    print_status "Using IP address: $IP_ADDR"
    print_status "Initializing cluster... This may take a few minutes..."
    
    # Initialize cluster
    kubeadm init \
        --pod-network-cidr=10.244.0.0/16 \
        --apiserver-advertise-address=$IP_ADDR \
        --control-plane-endpoint=$IP_ADDR | tee /root/kubeadm-init.log
fi

# Step 10: Set up kubeconfig
print_step "Step 10: Setting up kubeconfig..."

# Only setup kubeconfig if not already done or if we just initialized
if [ "$jump_to_network_install" != "true" ] || [ ! -f $HOME/.kube/config ]; then
    # Set up kubeconfig for root user
    mkdir -p $HOME/.kube
    if [ -f $HOME/.kube/config ]; then
        print_status "Backing up existing kubeconfig..."
        cp $HOME/.kube/config $HOME/.kube/config.backup.$(date +%Y%m%d_%H%M%S)
    fi
    cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    # Set up kubeconfig for regular users (if any)
    if [ ! -z "$SUDO_USER" ]; then
        mkdir -p /home/$SUDO_USER/.kube
        if [ -f /home/$SUDO_USER/.kube/config ]; then
            print_status "Backing up existing kubeconfig for $SUDO_USER..."
            cp /home/$SUDO_USER/.kube/config /home/$SUDO_USER/.kube/config.backup.$(date +%Y%m%d_%H%M%S)
        fi
        cp -f /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
        chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube
        print_status "Kubeconfig also configured for user: $SUDO_USER"
    fi
else
    print_status "Using existing kubeconfig configuration"
fi

# Add kubectl completion for bash
kubectl completion bash > /etc/bash_completion.d/kubectl

# Step 11: Install network plugin
print_step "Step 11: Installing Calico network plugin..."

# Wait for API server to be ready
print_status "Waiting for API server to be ready..."
sleep 30

# Test API server connectivity
print_status "Testing API server connectivity..."
for i in {1..10}; do
    if kubectl get nodes &>/dev/null; then
        print_status "API server is ready!"
        break
    else
        print_status "API server not ready yet, waiting... (attempt $i/10)"
        sleep 10
    fi
done

# Install Calico with retry logic
print_status "Installing Calico network plugin..."
for i in {1..3}; do
    if kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml; then
        print_status "Calico installed successfully!"
        break
    else
        print_warning "Calico installation failed (attempt $i/3), retrying in 15 seconds..."
        sleep 15
    fi
done

print_status "Waiting for Calico pods to start..."
sleep 15

# Check if we're using Docker instead of containerd and restart kubelet if needed
print_status "Ensuring kubelet is properly configured for Docker..."
if systemctl is-active --quiet docker; then
    # Create kubelet drop-in directory
    mkdir -p /etc/systemd/system/kubelet.service.d
    
    # Create drop-in file for Docker
    cat > /etc/systemd/system/kubelet.service.d/20-docker.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix:///var/run/dockershim.sock"
EOF
    
    # Reload and restart kubelet
    systemctl daemon-reload
    systemctl restart kubelet
    
    print_status "Kubelet restarted with Docker configuration"
    sleep 10
fi

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

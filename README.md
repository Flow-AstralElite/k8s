# Kubernetes Installation & Setup

This repository contains scripts and guides for installing and configuring a Kubernetes cluster on both Ubuntu/Debian and Fedora Server.

## Contents

### Ubuntu/Debian Scripts
- **install-kubernetes.sh** - Automated installation script for Kubernetes (Ubuntu/Debian)
- **NODE-CONNECTION-GUIDE.md** - Comprehensive guide for connecting worker nodes

### Fedora Server Scripts
- **install-master-node.sh** - Master node installation script for Fedora Server
- **install-worker-node.sh** - Worker node installation script for Fedora Server
- **FEDORA-INSTALLATION-GUIDE.md** - Complete guide for Fedora Server installation

## Quick Start

### For Ubuntu/Debian

1. **Install on Master Node:**
   ```bash
   sudo bash install-kubernetes.sh
   # Choose 'Y' when prompted
   ```

2. **Install on Worker Nodes:**
   ```bash
   sudo bash install-kubernetes.sh
   # Choose 'N' when prompted
   # Then run the join command from master
   ```

### For Fedora Server

1. **Install on Master Node:**
   ```bash
   sudo bash install-master-node.sh
   ```

2. **Install on Worker Nodes:**
   ```bash
   sudo bash install-worker-node.sh
   # Follow prompts to join the cluster
   ```

3. **Join Command Example:**
   ```bash
   sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> \
       --discovery-token-ca-cert-hash sha256:<HASH>
   ```

## Documentation

### Ubuntu/Debian
- **[NODE-CONNECTION-GUIDE.md](./NODE-CONNECTION-GUIDE.md)** - Complete guide for Ubuntu/Debian

### Fedora Server
- **[FEDORA-INSTALLATION-GUIDE.md](./FEDORA-INSTALLATION-GUIDE.md)** - Complete guide for Fedora Server

## System Requirements

### Supported Operating Systems
- **Ubuntu:** 20.04, 22.04, or later
- **Debian:** 11, 12, or later
- **Fedora Server:** 37, 38, 39, or later

### Hardware Requirements
- **RAM:** Minimum 2GB (4GB recommended for master, 8GB ideal)
- **CPU:** Minimum 2 cores (4 cores recommended for master)
- **Disk:** 20GB available space
- **Network:** All nodes must be able to communicate with each other on required ports

## Features

### All Scripts Include:
- ✅ Automatic system updates
- ✅ Swap disabling
- ✅ Kernel module configuration
- ✅ Containerd runtime installation
- ✅ Kubernetes components (kubeadm, kubelet, kubectl)
- ✅ Calico network plugin
- ✅ Join command generation

### Fedora-Specific Features:
- ✅ SELinux configuration
- ✅ Firewalld automatic configuration
- ✅ Separate master and worker scripts
- ✅ Interactive join process
- ✅ Detailed information files

## Support

For issues or questions, refer to the troubleshooting sections in:
- **NODE-CONNECTION-GUIDE.md** (Ubuntu/Debian)
- **FEDORA-INSTALLATION-GUIDE.md** (Fedora Server)

## Script Comparison

| Feature | Ubuntu/Debian | Fedora Server |
|---------|---------------|---------------|
| Single script for both roles | ✅ | ❌ |
| Separate scripts per role | ❌ | ✅ |
| Firewall auto-config | ❌ | ✅ |
| SELinux auto-config | N/A | ✅ |
| Interactive join | ❌ | ✅ |
| Package manager | apt | dnf |

# Kubernetes Installation Guide for Fedora Server

This guide provides step-by-step instructions for installing a Kubernetes cluster on Fedora Server using the provided scripts.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Master Node Installation](#master-node-installation)
4. [Worker Node Installation](#worker-node-installation)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)
7. [Cluster Management](#cluster-management)

---

## Prerequisites

### System Requirements

**Master Node:**
- Fedora Server 37, 38, or 39
- Minimum 2 CPU cores (4 recommended)
- Minimum 4GB RAM (8GB recommended)
- 20GB available disk space
- Static IP address

**Worker Nodes:**
- Fedora Server 37, 38, or 39
- Minimum 2 CPU cores
- Minimum 2GB RAM (4GB recommended)
- 20GB available disk space
- Static IP address

### Network Requirements

**All nodes must:**
- Have unique hostnames
- Be able to communicate with each other
- Have internet access for package downloads

**Required Ports:**

| Node Type | Port Range | Protocol | Purpose |
|-----------|------------|----------|---------|
| Master | 6443 | TCP | Kubernetes API server |
| Master | 2379-2380 | TCP | etcd server client API |
| Master | 10250 | TCP | Kubelet API |
| Master | 10251 | TCP | kube-scheduler |
| Master | 10252 | TCP | kube-controller-manager |
| Master | 179 | TCP | Calico BGP |
| Worker | 10250 | TCP | Kubelet API |
| Worker | 30000-32767 | TCP | NodePort Services |
| All | 8472 | UDP | Flannel VXLAN |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│              Kubernetes Cluster                  │
│                                                  │
│  ┌──────────────────┐                           │
│  │   Master Node    │                           │
│  │                  │                           │
│  │  • API Server    │                           │
│  │  • etcd          │                           │
│  │  • Scheduler     │                           │
│  │  • Controller    │                           │
│  │  • Calico CNI    │                           │
│  └────────┬─────────┘                           │
│           │                                      │
│           │ Control Plane                        │
│           │                                      │
│  ┌────────┴─────────────────────────┐          │
│  │                                   │          │
│  ▼                                   ▼          │
│  ┌──────────────┐         ┌──────────────┐    │
│  │ Worker Node 1│         │ Worker Node 2│    │
│  │              │         │              │    │
│  │ • Kubelet    │         │ • Kubelet    │    │
│  │ • Kube-proxy │         │ • Kube-proxy │    │
│  │ • Containerd │         │ • Containerd │    │
│  │ • Pods       │         │ • Pods       │    │
│  └──────────────┘         └──────────────┘    │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Master Node Installation

### Step 1: Prepare the Master Node

Set a hostname for the master node:

```bash
sudo hostnamectl set-hostname k8s-master
```

Edit `/etc/hosts` on all nodes to include all cluster members:

```bash
sudo vi /etc/hosts
```

Add entries:
```
192.168.1.100  k8s-master
192.168.1.101  k8s-worker1
192.168.1.102  k8s-worker2
```

### Step 2: Copy and Run the Master Script

Copy `install-master-node.sh` to the master node:

```bash
# From your local machine
scp install-master-node.sh root@k8s-master:/root/
```

SSH to the master node and run the script:

```bash
ssh root@k8s-master
cd /root
chmod +x install-master-node.sh
sudo bash install-master-node.sh
```

### Step 3: Wait for Installation

The script will:
- Update the system
- Configure firewall, SELinux, and kernel parameters
- Install containerd runtime
- Install Kubernetes components
- Initialize the master node
- Install Calico network plugin
- Generate the join command

**This process takes approximately 5-10 minutes.**

### Step 4: Save the Join Command

At the end of installation, you'll see output like:

```bash
========================================
IMPORTANT: Save this join command!
========================================

kubeadm join 192.168.1.100:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Save this command!** You'll need it for worker nodes.

The command is also saved in:
- `/root/join-command.sh`
- `/root/cluster-info.txt`

---

## Worker Node Installation

### Step 1: Prepare Each Worker Node

Set a unique hostname for each worker:

```bash
# On worker node 1
sudo hostnamectl set-hostname k8s-worker1

# On worker node 2
sudo hostnamectl set-hostname k8s-worker2
```

Edit `/etc/hosts` on each worker node (same as master):

```bash
sudo vi /etc/hosts
```

Add:
```
192.168.1.100  k8s-master
192.168.1.101  k8s-worker1
192.168.1.102  k8s-worker2
```

### Step 2: Copy and Run the Worker Script

Copy `install-worker-node.sh` to each worker node:

```bash
# From your local machine
scp install-worker-node.sh root@k8s-worker1:/root/
scp install-worker-node.sh root@k8s-worker2:/root/
```

SSH to each worker node and run the script:

```bash
ssh root@k8s-worker1
cd /root
chmod +x install-worker-node.sh
sudo bash install-worker-node.sh
```

### Step 3: Join the Cluster

**Option 1: Interactive (During Installation)**

When prompted "Do you have the join command ready? (y/n):", type `y` and paste the join command from the master node.

**Option 2: Manual (After Installation)**

Run the join command manually:

```bash
sudo kubeadm join 192.168.1.100:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

### Step 4: Repeat for Additional Workers

Repeat Steps 1-3 for each additional worker node.

---

## Verification

### On the Master Node

1. **Check node status:**
   ```bash
   kubectl get nodes
   ```
   
   Expected output:
   ```
   NAME          STATUS   ROLES           AGE   VERSION
   k8s-master    Ready    control-plane   10m   v1.28.x
   k8s-worker1   Ready    <none>          5m    v1.28.x
   k8s-worker2   Ready    <none>          3m    v1.28.x
   ```

2. **Check all pods are running:**
   ```bash
   kubectl get pods -A
   ```
   
   All pods should show `Running` status.

3. **Check cluster info:**
   ```bash
   kubectl cluster-info
   ```

4. **Check node details:**
   ```bash
   kubectl get nodes -o wide
   ```

### Label Worker Nodes (Optional)

Add worker role labels:

```bash
kubectl label node k8s-worker1 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker2 node-role.kubernetes.io/worker=worker
```

Now `kubectl get nodes` will show:
```
NAME          STATUS   ROLES           AGE   VERSION
k8s-master    Ready    control-plane   10m   v1.28.x
k8s-worker1   Ready    worker          5m    v1.28.x
k8s-worker2   Ready    worker          3m    v1.28.x
```

### Deploy Test Application

```bash
# Create a test deployment
kubectl create deployment nginx --image=nginx --replicas=3

# Expose it as a service
kubectl expose deployment nginx --port=80 --type=NodePort

# Check pods
kubectl get pods -o wide

# Check service
kubectl get svc nginx
```

Access the service:
```bash
# Get the NodePort
kubectl get svc nginx

# Access from any node
curl http://<any-node-ip>:<nodeport>
```

---

## Troubleshooting

### Issue: Token Expired

If you see "token has expired" when joining:

**On master node:**
```bash
kubeadm token create --print-join-command
```

Use the new command on worker nodes.

### Issue: Node Shows "NotReady"

1. **Check kubelet:**
   ```bash
   sudo systemctl status kubelet
   sudo journalctl -u kubelet -f
   ```

2. **Check containerd:**
   ```bash
   sudo systemctl status containerd
   ```

3. **Check network plugin (on master):**
   ```bash
   kubectl get pods -n kube-system | grep calico
   ```

### Issue: Cannot Connect to Master

1. **Verify firewall:**
   ```bash
   sudo firewall-cmd --list-all
   ```

2. **Test connectivity:**
   ```bash
   telnet <master-ip> 6443
   nc -zv <master-ip> 6443
   ```

3. **Check master API server:**
   ```bash
   sudo systemctl status kube-apiserver
   ```

### Issue: SELinux Blocking

If SELinux causes issues:

```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
```

### Issue: DNS Not Working

Check CoreDNS pods:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Reset a Node

If you need to completely reset and start over:

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube
sudo systemctl restart containerd
```

Then run the installation script again.

---

## Cluster Management

### View Cluster Resources

```bash
# All nodes
kubectl get nodes

# All pods in all namespaces
kubectl get pods -A

# All services
kubectl get svc -A

# Cluster events
kubectl get events -A

# Resource usage (requires metrics-server)
kubectl top nodes
kubectl top pods -A
```

### Node Maintenance

**Drain a node (for maintenance):**
```bash
kubectl drain k8s-worker1 --ignore-daemonsets --delete-emptydir-data
```

**Make node schedulable again:**
```bash
kubectl uncordon k8s-worker1
```

**Remove a node from cluster:**
```bash
# On master
kubectl drain k8s-worker1 --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node k8s-worker1

# On worker
sudo kubeadm reset -f
```

### Generate New Join Token

Tokens expire after 24 hours. Generate a new one:

```bash
# On master node
kubeadm token create --print-join-command
```

### Backup etcd

```bash
# On master node
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## Next Steps

### Install Metrics Server

For resource monitoring:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Install Kubernetes Dashboard

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### Install Ingress Controller

For HTTP/HTTPS routing:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
```

### Set Up Persistent Storage

Configure local or network storage for persistent volumes.

---

## Useful Commands Reference

| Command | Description |
|---------|-------------|
| `kubectl get nodes` | List all nodes |
| `kubectl get pods -A` | List all pods in all namespaces |
| `kubectl describe node <name>` | Show node details |
| `kubectl cluster-info` | Display cluster info |
| `kubectl version` | Show Kubernetes version |
| `kubeadm version` | Show kubeadm version |
| `kubectl logs <pod-name>` | View pod logs |
| `kubectl exec -it <pod> -- bash` | Execute into a pod |
| `kubectl delete pod <name>` | Delete a pod |
| `kubectl apply -f <file.yaml>` | Apply configuration |

---

## Files Created by Scripts

### Master Node:
- `/root/join-command.sh` - Join command for workers
- `/root/cluster-info.txt` - Detailed cluster information
- `/root/kubeadm-init.log` - Initialization log
- `/root/.kube/config` - Kubectl configuration

### Worker Node:
- `/root/worker-node-info.txt` - Worker node details

---

## Support & Resources

- **Kubernetes Documentation:** https://kubernetes.io/docs/
- **Fedora Documentation:** https://docs.fedoraproject.org/
- **Calico Documentation:** https://docs.tigera.io/calico/
- **Containerd Documentation:** https://containerd.io/docs/

---

**Note:** These scripts are configured for Kubernetes v1.28 on Fedora Server. Adjust repository URLs if using different versions.

#!/bin/bash
# Setup SSH keys for passwordless access between Pi1 and all other nodes

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/cluster-env.sh"

echo "========================================="
echo "Setting up SSH Keys for Pi Cluster"
echo "========================================="

# Check if we're running on the controller node
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [ "$CURRENT_IP" != "$CONTROLLER_IP" ]; then
    echo "⚠️  WARNING: This script should be run from Pi1 (controller node)"
    echo "Current IP: $CURRENT_IP"
    echo "Expected IP: $CONTROLLER_IP"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ] && [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Generating new SSH key..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "picocluster@pi1"
    echo "✅ SSH key generated"
else
    echo "✅ SSH key already exists"
fi

# Function to setup SSH key on a remote host
setup_ssh_key() {
    local ip=$1
    local hostname=$2
    
    echo -n "Setting up SSH key on $hostname ($ip)... "
    
    # First, try to connect and add to known_hosts
    ssh-keyscan -H $ip >> ~/.ssh/known_hosts 2>/dev/null
    
    # Copy SSH key
    if ssh-copy-id -o StrictHostKeyChecking=no ${CLUSTER_USER}@$ip 2>/dev/null; then
        echo "✓"
        return 0
    else
        echo "✗"
        return 1
    fi
}

# Setup SSH keys on all worker nodes
echo -e "\nSetting up SSH keys on worker nodes..."
FAILED=0

for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    WORKER_HOST=$(get_worker_host $i)
    
    if ! setup_ssh_key $WORKER_IP $WORKER_HOST; then
        FAILED=1
        echo "❌ Failed to setup SSH key on $WORKER_HOST"
        echo "   Please ensure:"
        echo "   1. $WORKER_HOST is powered on and connected to network"
        echo "   2. SSH is enabled on $WORKER_HOST"
        echo "   3. You know the password for ${CLUSTER_USER}@$WORKER_IP"
    fi
done

# Test SSH connectivity
echo -e "\nTesting SSH connectivity..."
SUCCESS=0
TOTAL=0

for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    WORKER_HOST=$(get_worker_host $i)
    TOTAL=$((TOTAL + 1))
    
    echo -n "Testing $WORKER_HOST ($WORKER_IP)... "
    if ssh -o BatchMode=yes -o ConnectTimeout=5 ${CLUSTER_USER}@$WORKER_IP "echo 'OK'" >/dev/null 2>&1; then
        echo "✓"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "✗"
    fi
done

echo -e "\n========================================="
echo "SSH Key Setup Summary"
echo "========================================="
echo "Successful connections: $SUCCESS/$TOTAL"

if [ $SUCCESS -eq $TOTAL ]; then
    echo -e "\n✅ All SSH keys configured successfully!"
    echo "You can now run setup-cluster.sh"
else
    echo -e "\n⚠️  Some connections failed."
    echo "Please fix the issues and run this script again."
    exit 1
fi
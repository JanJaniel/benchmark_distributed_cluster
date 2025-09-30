#!/bin/bash
# Update script to fetch latest code from GitHub and properly rename the directory

set -e

echo "========================================="
echo "Updating from GitHub Repository"
echo "========================================="

# Save current directory
CURRENT_DIR=$(pwd)

# Go to home directory
cd ~

# Backup old version if it exists
if [ -d "benchmark_distributed_cluster" ]; then
    echo "Backing up current version..."
    mv benchmark_distributed_cluster benchmark_distributed_cluster.backup
fi

# Download latest version
echo "Downloading latest version from GitHub..."
wget -q https://github.com/JanJaniel/benchmark_distributed_cluster/archive/refs/heads/main.zip

# Extract and rename
echo "Extracting files..."
unzip -q main.zip
mv benchmark_distributed_cluster-main benchmark_distributed_cluster

# Clean up
rm main.zip
if [ -d "benchmark_distributed_cluster.backup" ]; then
    echo "Removing backup..."
    rm -rf benchmark_distributed_cluster.backup
fi

echo "✅ Successfully updated to latest version!"
echo "📁 Location: ~/benchmark_distributed_cluster"
echo ""
echo "Next steps:"
echo "  cd ~/benchmark_distributed_cluster"
echo "  ./scripts/setup-cluster.sh  # To update all worker nodes"

# Return to original directory if it still exists
if [ -d "$CURRENT_DIR" ]; then
    cd "$CURRENT_DIR"
fi
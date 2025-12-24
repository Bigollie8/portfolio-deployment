#!/bin/bash
# Portfolio EC2 Auto-Configuration Script
# This script runs on every spot instance launch to configure the environment

set -e
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Starting Portfolio Auto-Configuration ==="
echo "Date: $(date)"

# Configuration
PERSISTENT_VOLUME_ID="vol-0bdefe80e9c243792"
MOUNT_POINT="/data"
PORTFOLIO_DIR="/opt/portfolio"
REGION="us-east-1"

# Wait for instance to be fully ready
sleep 30

# ============================================
# 1. Attach and Mount Persistent EBS Volume
# ============================================
echo "=== Attaching persistent EBS volume ==="

# Get instance ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

# Check if volume is already attached
VOLUME_STATE=$(aws ec2 describe-volumes --volume-ids $PERSISTENT_VOLUME_ID --region $REGION --query 'Volumes[0].State' --output text 2>/dev/null || echo "error")

if [ "$VOLUME_STATE" == "available" ]; then
    echo "Attaching volume $PERSISTENT_VOLUME_ID..."
    aws ec2 attach-volume --volume-id $PERSISTENT_VOLUME_ID --instance-id $INSTANCE_ID --device /dev/xvdf --region $REGION
    sleep 10
elif [ "$VOLUME_STATE" == "in-use" ]; then
    echo "Volume already attached"
else
    echo "Warning: Could not determine volume state: $VOLUME_STATE"
fi

# Wait for device to appear
echo "Waiting for volume device..."
for i in {1..30}; do
    if [ -e /dev/nvme1n1 ] || [ -e /dev/xvdf ]; then
        echo "Device found"
        break
    fi
    sleep 2
done

# Mount the volume
echo "Mounting persistent volume..."
mkdir -p $MOUNT_POINT
DEVICE=$(lsblk -o NAME,SIZE -d | grep "20G" | awk '{print "/dev/"$1}' | head -1)
if [ -n "$DEVICE" ]; then
    mount $DEVICE $MOUNT_POINT || echo "Mount failed or already mounted"
    echo "Mounted $DEVICE to $MOUNT_POINT"
else
    echo "Warning: Could not find 20G device"
fi

# ============================================
# 2. Setup Portfolio Directory
# ============================================
echo "=== Setting up portfolio directory ==="
mkdir -p $PORTFOLIO_DIR
cd $PORTFOLIO_DIR

# Copy docker-compose and nginx from persistent storage if exists
if [ -f /data/config/docker-compose.yml ]; then
    cp /data/config/docker-compose.yml $PORTFOLIO_DIR/
    cp /data/config/nginx.conf $PORTFOLIO_DIR/
    cp /data/config/.env $PORTFOLIO_DIR/ 2>/dev/null || true
fi

# ============================================
# 3. Start Docker Services
# ============================================
echo "=== Starting Docker services ==="
cd $PORTFOLIO_DIR

if [ -f docker-compose.yml ]; then
    docker-compose up -d
    echo "Docker services started"
else
    echo "Warning: docker-compose.yml not found"
fi

# ============================================
# 4. Health Check
# ============================================
echo "=== Running health checks ==="
sleep 30

for endpoint in "http://localhost/health" "http://localhost/portfolio/health"; do
    if curl -s -f $endpoint > /dev/null 2>&1; then
        echo "✓ $endpoint is healthy"
    else
        echo "✗ $endpoint is not responding"
    fi
done

echo "=== Portfolio Auto-Configuration Complete ==="
echo "Date: $(date)"

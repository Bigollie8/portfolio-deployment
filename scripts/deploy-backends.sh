#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Portfolio Backend Deployment Script  ${NC}"
echo -e "${GREEN}========================================${NC}"

# Configuration
EC2_HOST="${EC2_HOST:-}"
SSH_KEY="${SSH_KEY:-~/.ssh/portfolio.pem}"
REMOTE_DIR="/opt/portfolio"

# Check required variables
if [ -z "$EC2_HOST" ]; then
    echo -e "${RED}Error: EC2_HOST environment variable is required${NC}"
    echo "Usage: EC2_HOST=1.2.3.4 ./deploy-backends.sh"
    exit 1
fi

echo -e "${YELLOW}Deploying to: ${EC2_HOST}${NC}"

# SSH command helper
ssh_cmd() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$EC2_HOST" "$@"
}

# SCP command helper
scp_cmd() {
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$@"
}

# Step 1: Clone/Update repositories
echo -e "\n${GREEN}Step 1: Updating repositories...${NC}"
ssh_cmd << 'REMOTE_SCRIPT'
cd /opt/portfolio

# Create repos directory
mkdir -p repos
cd repos

# Clone or pull each repository
repos=(
    "terminal-portfolio"
    "rapidPhotoFlow"
    "basedSecurity_AI"
    "shippingMonitoring"
)

for repo in "${repos[@]}"; do
    if [ -d "$repo" ]; then
        echo "Updating $repo..."
        cd "$repo" && git pull && cd ..
    else
        echo "Cloning $repo..."
        # Replace with your actual git URLs
        git clone "https://github.com/yourusername/$repo.git" || echo "Clone failed for $repo"
    fi
done
REMOTE_SCRIPT

# Step 2: Copy Docker Compose and env files
echo -e "\n${GREEN}Step 2: Copying configuration files...${NC}"
scp_cmd ../docker/docker-compose.prod.yml ec2-user@"$EC2_HOST":"$REMOTE_DIR/docker-compose.yml"
scp_cmd ../docker/init-db.sql ec2-user@"$EC2_HOST":"$REMOTE_DIR/init-db.sql"

# Step 3: Build and deploy
echo -e "\n${GREEN}Step 3: Building and deploying services...${NC}"
ssh_cmd << 'REMOTE_SCRIPT'
cd /opt/portfolio

# Pull latest images and rebuild
docker-compose pull
docker-compose build --no-cache

# Stop existing containers
docker-compose down

# Start services
docker-compose up -d

# Wait for services to be healthy
echo "Waiting for services to start..."
sleep 30

# Check service status
docker-compose ps
REMOTE_SCRIPT

# Step 4: Verify deployment
echo -e "\n${GREEN}Step 4: Verifying deployment...${NC}"
ssh_cmd << 'REMOTE_SCRIPT'
echo "Checking service health..."

services=(
    "http://localhost:3001/health:Portfolio"
    "http://localhost:8080/actuator/health:Photos"
    "http://localhost:8000/health:Security"
    "http://localhost:3003/api/health:Shipping"
)

for service in "${services[@]}"; do
    url="${service%%:*}"
    name="${service##*:}"
    if curl -s -f "$url" > /dev/null 2>&1; then
        echo "✓ $name is healthy"
    else
        echo "✗ $name is not responding"
    fi
done
REMOTE_SCRIPT

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Backend deployment complete!         ${NC}"
echo -e "${GREEN}========================================${NC}"

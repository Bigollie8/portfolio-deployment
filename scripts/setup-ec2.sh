#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  EC2 Initial Setup Script             ${NC}"
echo -e "${GREEN}========================================${NC}"

# This script should be run on the EC2 instance after first connection
# Usage: ./setup-ec2.sh

# Step 1: Update system
echo -e "\n${GREEN}Step 1: Updating system packages...${NC}"
sudo yum update -y

# Step 2: Install Docker
echo -e "\n${GREEN}Step 2: Installing Docker...${NC}"
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Step 3: Install Docker Compose
echo -e "\n${GREEN}Step 3: Installing Docker Compose...${NC}"
DOCKER_COMPOSE_VERSION="v2.24.0"
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Step 4: Install additional tools
echo -e "\n${GREEN}Step 4: Installing additional tools...${NC}"
sudo yum install -y git jq htop

# Step 5: Create portfolio directory structure
echo -e "\n${GREEN}Step 5: Creating directory structure...${NC}"
sudo mkdir -p /opt/portfolio/{repos,data,logs}
sudo chown -R ec2-user:ec2-user /opt/portfolio

# Step 6: Configure Docker logging
echo -e "\n${GREEN}Step 6: Configuring Docker logging...${NC}"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
sudo systemctl restart docker

# Step 7: Install AWS CLI (if not present)
echo -e "\n${GREEN}Step 7: Checking AWS CLI...${NC}"
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
else
    echo "AWS CLI already installed"
fi

# Step 8: Create environment file template
echo -e "\n${GREEN}Step 8: Creating environment template...${NC}"
cat > /opt/portfolio/.env.example <<'EOF'
# Domain Configuration
DOMAIN=yourdomain.com

# Database
POSTGRES_USER=portfolio
POSTGRES_PASSWORD=your-secure-password
POSTGRES_DB=portfolio

# JWT/Auth
JWT_SECRET=your-jwt-secret

# Application Secrets
APP_SECRET_KEY=your-app-secret

# AWS
AWS_REGION=us-east-1
S3_BUCKET=your-photos-bucket

# OpenAI (for rapidPhotoFlow)
OPENAI_API_KEY=sk-...
EOF

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!                       ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Log out and back in for docker group to take effect"
echo "2. Copy .env.example to .env and fill in your values:"
echo "   cp /opt/portfolio/.env.example /opt/portfolio/.env"
echo "   nano /opt/portfolio/.env"
echo ""
echo "3. Clone your repositories to /opt/portfolio/repos/"
echo ""
echo "4. Copy docker-compose.yml to /opt/portfolio/"
echo ""
echo "5. Start services:"
echo "   cd /opt/portfolio && docker-compose up -d"
echo ""

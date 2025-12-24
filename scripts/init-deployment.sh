#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Portfolio Deployment Initializer     ${NC}"
echo -e "${GREEN}========================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check for required tools
check_requirements() {
    echo -e "\n${YELLOW}Checking requirements...${NC}"

    local missing=()

    command -v terraform >/dev/null 2>&1 || missing+=("terraform")
    command -v aws >/dev/null 2>&1 || missing+=("aws-cli")
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo "Please install them before continuing."
        exit 1
    fi

    echo -e "${GREEN}All requirements met!${NC}"
}

# Check AWS credentials
check_aws_credentials() {
    echo -e "\n${YELLOW}Checking AWS credentials...${NC}"

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}AWS credentials not configured or invalid${NC}"
        echo "Run 'aws configure' to set up your credentials"
        exit 1
    fi

    local identity=$(aws sts get-caller-identity)
    echo -e "${GREEN}Authenticated as:${NC}"
    echo "  Account: $(echo $identity | jq -r '.Account')"
    echo "  User:    $(echo $identity | jq -r '.Arn')"
}

# Check for terraform.tfvars
check_tfvars() {
    echo -e "\n${YELLOW}Checking Terraform configuration...${NC}"

    if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
        echo -e "${RED}terraform.tfvars not found!${NC}"
        echo ""
        echo "Please create it from the example:"
        echo "  cp $PROJECT_ROOT/terraform/terraform.tfvars.example $PROJECT_ROOT/terraform/terraform.tfvars"
        echo "  nano $PROJECT_ROOT/terraform/terraform.tfvars"
        exit 1
    fi

    echo -e "${GREEN}terraform.tfvars found${NC}"
}

# Initialize Terraform
init_terraform() {
    echo -e "\n${YELLOW}Initializing Terraform...${NC}"
    cd "$PROJECT_ROOT/terraform"
    terraform init
}

# Plan deployment
plan_deployment() {
    echo -e "\n${YELLOW}Planning deployment...${NC}"
    cd "$PROJECT_ROOT/terraform"
    terraform plan -out=tfplan
}

# Apply deployment
apply_deployment() {
    echo -e "\n${YELLOW}Ready to deploy!${NC}"
    read -p "Do you want to apply the Terraform plan? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Deployment cancelled"
        exit 0
    fi

    cd "$PROJECT_ROOT/terraform"
    terraform apply tfplan

    # Save outputs
    terraform output -json > "$PROJECT_ROOT/deployment-outputs.json"

    echo -e "\n${GREEN}Infrastructure deployed!${NC}"
    echo "Outputs saved to deployment-outputs.json"
}

# Show next steps
show_next_steps() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}  Infrastructure Deployment Complete!  ${NC}"
    echo -e "${GREEN}========================================${NC}"

    local ec2_ip=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw ec2_public_ip 2>/dev/null || echo "N/A")
    local ssh_key=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw ssh_command 2>/dev/null | grep -oP '~/.ssh/\K[^.]+' || echo "portfolio")

    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo ""
    echo "1. SSH into your EC2 instance:"
    echo "   ssh -i ~/.ssh/${ssh_key}.pem ec2-user@${ec2_ip}"
    echo ""
    echo "2. Run the setup script on EC2:"
    echo "   ./setup-ec2.sh"
    echo ""
    echo "3. Configure environment variables:"
    echo "   cp /opt/portfolio/.env.example /opt/portfolio/.env"
    echo "   nano /opt/portfolio/.env"
    echo ""
    echo "4. Deploy backends:"
    echo "   EC2_HOST=${ec2_ip} ./scripts/deploy-backends.sh"
    echo ""
    echo "5. Deploy frontends:"
    echo "   DOMAIN=yourdomain.com ./scripts/deploy-frontends.sh"
    echo ""
}

# Main
main() {
    check_requirements
    check_aws_credentials
    check_tfvars
    init_terraform
    plan_deployment
    apply_deployment
    show_next_steps
}

# Run with option to skip to specific step
case "${1:-}" in
    --plan-only)
        check_requirements
        check_aws_credentials
        check_tfvars
        init_terraform
        plan_deployment
        ;;
    --apply-only)
        cd "$PROJECT_ROOT/terraform"
        terraform apply tfplan
        show_next_steps
        ;;
    *)
        main
        ;;
esac

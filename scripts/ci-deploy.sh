#!/bin/bash
# CI/CD Deploy Script - Works on Linux/macOS
# Usage: ./ci-deploy.sh <service-name|all|frontends|backends> [--skip-tests] [--message "Deploy message"]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../services.json"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
SERVICE="${1:-all}"
SKIP_TESTS=false
MESSAGE=""

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-tests) SKIP_TESTS=true; shift ;;
        --message) MESSAGE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Check dependencies
command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed."; exit 1; }
command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required but not installed."; exit 1; }

# Load config
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

EC2_HOST=$(jq -r '.ec2.host' "$CONFIG_FILE")
EC2_USER=$(jq -r '.ec2.user' "$CONFIG_FILE")
SSH_KEY="${SSH_KEY:-$HOME/.ssh/terminal-portfolio-deploy.pem}"

# Get service list
get_services() {
    local input="$1"
    case "$input" in
        all)
            jq -r '.services | keys[]' "$CONFIG_FILE"
            ;;
        frontends)
            jq -r '.services | to_entries[] | select(.value.type == "frontend") | .key' "$CONFIG_FILE"
            ;;
        backends)
            jq -r '.services | to_entries[] | select(.value.type == "backend") | .key' "$CONFIG_FILE"
            ;;
        *)
            echo "$input" | tr ',' '\n'
            ;;
    esac
}

# Send Discord notification
send_discord() {
    local title="$1"
    local description="$2"
    local color="${3:-2278621}"

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        curl -s -H "Content-Type: application/json" \
            -d "{\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"footer\":{\"text\":\"Portfolio CI/CD\"}}]}" \
            "$DISCORD_WEBHOOK_URL" >/dev/null || true
    fi
}

# Deploy frontend
deploy_frontend() {
    local name="$1"
    log_info "Deploying frontend: $name"

    local s3_bucket=$(jq -r ".services[\"$name\"].s3Bucket" "$CONFIG_FILE")
    local cf_id=$(jq -r ".services[\"$name\"].cloudFrontId" "$CONFIG_FILE")
    local url=$(jq -r ".services[\"$name\"].url" "$CONFIG_FILE")
    local path=$(jq -r ".services[\"$name\"].path" "$CONFIG_FILE")
    local dist_dir=$(jq -r ".services[\"$name\"].distDir" "$CONFIG_FILE")
    local build_cmd=$(jq -r ".services[\"$name\"].buildCommand" "$CONFIG_FILE")
    local repo=$(jq -r ".services[\"$name\"].repo" "$CONFIG_FILE")

    # Clone and build
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    log_info "Cloning $repo..."
    git clone --depth 1 "https://github.com/$repo.git" "$temp_dir/repo"

    cd "$temp_dir/repo/$path"
    log_info "Installing dependencies..."
    npm ci || npm install

    log_info "Building..."
    eval "$build_cmd"

    log_info "Uploading to S3..."
    aws s3 sync "$dist_dir" "s3://$s3_bucket" \
        --delete \
        --cache-control "public, max-age=31536000" \
        --exclude "index.html" \
        --exclude "*.json"

    aws s3 cp "$dist_dir/index.html" "s3://$s3_bucket/index.html" \
        --cache-control "no-cache, no-store, must-revalidate"

    log_info "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation --distribution-id "$cf_id" --paths "/*" >/dev/null

    log_success "$name deployed to $url"
    send_discord "Frontend Deployed: $name" "URL: $url"
}

# Deploy backend
deploy_backend() {
    local name="$1"
    log_info "Deploying backend: $name"

    local docker_image=$(jq -r ".services[\"$name\"].dockerImage" "$CONFIG_FILE")
    local container_name=$(jq -r ".services[\"$name\"].containerName" "$CONFIG_FILE")
    local path=$(jq -r ".services[\"$name\"].path" "$CONFIG_FILE")
    local repo=$(jq -r ".services[\"$name\"].repo" "$CONFIG_FILE")

    # Clone and build
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    log_info "Cloning $repo..."
    git clone --depth 1 "https://github.com/$repo.git" "$temp_dir/repo"

    cd "$temp_dir/repo/$path"
    log_info "Building Docker image..."
    docker build -t "$docker_image:latest" .

    log_info "Saving image..."
    docker save "$docker_image:latest" -o "/tmp/$docker_image.tar"

    log_info "Transferring to EC2..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "/tmp/$docker_image.tar" "$EC2_USER@$EC2_HOST:/tmp/"

    log_info "Loading and restarting on EC2..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" << EOF
        docker load -i /tmp/$docker_image.tar
        rm /tmp/$docker_image.tar
        cd /home/ubuntu/deployment
        docker-compose stop $container_name
        docker-compose rm -f $container_name
        docker-compose up -d $container_name
EOF

    rm -f "/tmp/$docker_image.tar"
    log_success "$name deployed"
    send_discord "Backend Deployed: $name"
}

# Main
log_info "========================================"
log_info "  Portfolio CI/CD Deploy"
log_info "========================================"
log_info "Services: $SERVICE"
[[ -n "$MESSAGE" ]] && log_info "Message: $MESSAGE"
echo

SERVICES=$(get_services "$SERVICE")
DEPLOYED=()
FAILED=()

send_discord "Deployment Started" "Services: $SERVICE" 3447003

for svc in $SERVICES; do
    TYPE=$(jq -r ".services[\"$svc\"].type" "$CONFIG_FILE")

    if [[ "$TYPE" == "frontend" ]]; then
        if deploy_frontend "$svc"; then
            DEPLOYED+=("$svc")
        else
            FAILED+=("$svc")
        fi
    elif [[ "$TYPE" == "backend" ]]; then
        if deploy_backend "$svc"; then
            DEPLOYED+=("$svc")
        else
            FAILED+=("$svc")
        fi
    else
        log_warn "Unknown service type for $svc: $TYPE"
    fi
done

# Summary
echo
log_info "========================================"
log_info "  Deployment Summary"
log_info "========================================"

if [[ ${#DEPLOYED[@]} -gt 0 ]]; then
    log_success "Deployed: ${DEPLOYED[*]}"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_error "Failed: ${FAILED[*]}"
    send_discord "Deployment Failed" "Failed: ${FAILED[*]}" 15548997
    exit 1
fi

send_discord "Deployment Successful" "Deployed: ${DEPLOYED[*]}"
log_success "All deployments completed!"

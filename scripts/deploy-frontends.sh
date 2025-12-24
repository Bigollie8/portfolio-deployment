#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Portfolio Frontend Deployment Script ${NC}"
echo -e "${GREEN}========================================${NC}"

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${DOMAIN:-}"
PROJECT_PREFIX="${PROJECT_PREFIX:-portfolio-prod}"

# Check required variables
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: DOMAIN environment variable is required${NC}"
    echo "Usage: DOMAIN=example.com ./deploy-frontends.sh"
    exit 1
fi

API_URL="https://api.${DOMAIN}"

# Project configurations
declare -A PROJECTS
PROJECTS[portfolio]="../../../terminal-portfolio/frontend"
PROJECTS[photos]="../../../rapidPhotoFlow/frontend"
PROJECTS[security]="../../../basedSecurity_AI/web"
PROJECTS[shipping]="../../../shippingMonitoring/client"

# S3 bucket names
declare -A BUCKETS
BUCKETS[portfolio]="${PROJECT_PREFIX}-portfolio-frontend"
BUCKETS[photos]="${PROJECT_PREFIX}-photos-frontend"
BUCKETS[security]="${PROJECT_PREFIX}-security-frontend"
BUCKETS[shipping]="${PROJECT_PREFIX}-shipping-frontend"

# CloudFront distribution IDs (will be populated from terraform output)
declare -A CF_DISTRIBUTIONS

# Get CloudFront distribution IDs from Terraform
get_cf_distributions() {
    echo -e "${YELLOW}Getting CloudFront distribution IDs...${NC}"
    cd ../terraform
    CF_DISTRIBUTIONS[portfolio]=$(terraform output -raw cloudfront_distribution_ids | jq -r '.frontends.portfolio')
    CF_DISTRIBUTIONS[photos]=$(terraform output -raw cloudfront_distribution_ids | jq -r '.frontends.photos')
    CF_DISTRIBUTIONS[security]=$(terraform output -raw cloudfront_distribution_ids | jq -r '.frontends.security')
    CF_DISTRIBUTIONS[shipping]=$(terraform output -raw cloudfront_distribution_ids | jq -r '.frontends.shipping')
    cd ../scripts
}

# Build a frontend project
build_frontend() {
    local name=$1
    local path=$2
    local api_prefix=$3

    echo -e "\n${GREEN}Building ${name}...${NC}"

    if [ ! -d "$path" ]; then
        echo -e "${RED}Error: Directory $path not found${NC}"
        return 1
    fi

    cd "$path"

    # Create production .env file
    cat > .env.production << EOF
VITE_API_URL=${API_URL}/${api_prefix}
VITE_APP_ENV=production
EOF

    # Install dependencies and build
    npm ci
    npm run build

    cd - > /dev/null
}

# Upload to S3
upload_to_s3() {
    local name=$1
    local path=$2
    local bucket=$3

    echo -e "\n${GREEN}Uploading ${name} to S3...${NC}"

    # Determine build output directory
    local build_dir="$path/dist"
    if [ ! -d "$build_dir" ]; then
        build_dir="$path/build"
    fi

    if [ ! -d "$build_dir" ]; then
        echo -e "${RED}Error: Build directory not found for ${name}${NC}"
        return 1
    fi

    # Sync to S3
    aws s3 sync "$build_dir" "s3://${bucket}" \
        --delete \
        --cache-control "public, max-age=31536000" \
        --exclude "index.html" \
        --exclude "*.json"

    # Upload index.html and JSON with no-cache
    aws s3 cp "$build_dir/index.html" "s3://${bucket}/index.html" \
        --cache-control "no-cache, no-store, must-revalidate"

    # Upload any JSON files (like manifest) with short cache
    find "$build_dir" -name "*.json" -exec aws s3 cp {} "s3://${bucket}/" \
        --cache-control "public, max-age=300" \;

    echo -e "${GREEN}✓ Uploaded ${name} to s3://${bucket}${NC}"
}

# Invalidate CloudFront cache
invalidate_cloudfront() {
    local name=$1
    local distribution_id=$2

    if [ -z "$distribution_id" ] || [ "$distribution_id" == "null" ]; then
        echo -e "${YELLOW}Skipping CloudFront invalidation for ${name} (no distribution ID)${NC}"
        return 0
    fi

    echo -e "\n${GREEN}Invalidating CloudFront cache for ${name}...${NC}"

    aws cloudfront create-invalidation \
        --distribution-id "$distribution_id" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text

    echo -e "${GREEN}✓ Cache invalidation created for ${name}${NC}"
}

# Main deployment function
deploy_frontend() {
    local name=$1

    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  Deploying: ${name}${NC}"
    echo -e "${YELLOW}========================================${NC}"

    local path="${PROJECTS[$name]}"
    local bucket="${BUCKETS[$name]}"
    local cf_id="${CF_DISTRIBUTIONS[$name]}"

    # Build
    build_frontend "$name" "$path" "$name"

    # Upload
    upload_to_s3 "$name" "$path" "$bucket"

    # Invalidate cache
    invalidate_cloudfront "$name" "$cf_id"
}

# Parse command line arguments
DEPLOY_ALL=true
SPECIFIC_PROJECT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            DEPLOY_ALL=false
            SPECIFIC_PROJECT="$2"
            shift 2
            ;;
        --skip-cf)
            SKIP_CF=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get CloudFront distribution IDs
if [ "$SKIP_CF" != "true" ]; then
    get_cf_distributions 2>/dev/null || echo "Warning: Could not get CloudFront IDs"
fi

# Deploy
if [ "$DEPLOY_ALL" = true ]; then
    for project in "${!PROJECTS[@]}"; do
        deploy_frontend "$project"
    done
else
    if [ -z "${PROJECTS[$SPECIFIC_PROJECT]}" ]; then
        echo -e "${RED}Error: Unknown project: $SPECIFIC_PROJECT${NC}"
        echo "Available projects: ${!PROJECTS[*]}"
        exit 1
    fi
    deploy_frontend "$SPECIFIC_PROJECT"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Frontend deployment complete!        ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "URLs:"
echo "  Portfolio: https://portfolio.${DOMAIN}"
echo "  Photos:    https://photos.${DOMAIN}"
echo "  Security:  https://security.${DOMAIN}"
echo "  Shipping:  https://shipping.${DOMAIN}"

#!/bin/bash
set -e

# =============================================================================
# AWS Cleanup Script for Existing Deployments
# Cleans up BasedSecurity AI and RapidPhotoFlow AWS resources before
# redeploying with the unified portfolio infrastructure
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AWS_REGION="${AWS_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-true}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  AWS Cleanup Script for Portfolio Deploy   ${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}Region: ${AWS_REGION}${NC}"
echo -e "${YELLOW}Dry Run: ${DRY_RUN}${NC}"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}Running in DRY RUN mode - no resources will be deleted${NC}"
    echo -e "${YELLOW}Set DRY_RUN=false to perform actual cleanup${NC}"
    echo ""
fi

# Helper function to run or simulate AWS commands
run_cmd() {
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${BLUE}[DRY RUN] Would execute: $@${NC}"
    else
        eval "$@"
    fi
}

# =============================================================================
# SECTION 1: BASEDSECURITY AI CLEANUP
# =============================================================================
echo -e "\n${GREEN}=== Section 1: BasedSecurity AI Cleanup ===${NC}"

# 1.1 Check if Terraform state exists and use terraform destroy
BASEDSECURITY_TF_DIR="../../../basedSecurity_AI/plans/terraform-samples/environments/dev"
if [ -d "$BASEDSECURITY_TF_DIR/.terraform" ]; then
    echo -e "${YELLOW}Found BasedSecurity Terraform state. Attempting terraform destroy...${NC}"
    if [ "$DRY_RUN" = "false" ]; then
        cd "$BASEDSECURITY_TF_DIR"
        terraform destroy -auto-approve
        cd - > /dev/null
    else
        echo -e "${BLUE}[DRY RUN] Would run: terraform destroy -auto-approve in $BASEDSECURITY_TF_DIR${NC}"
    fi
else
    echo -e "${YELLOW}No local Terraform state found for BasedSecurity. Cleaning up manually...${NC}"
fi

# 1.2 Manual cleanup for BasedSecurity (if terraform destroy fails or state is remote-only)
echo -e "\n${YELLOW}Checking for BasedSecurity AWS resources...${NC}"

# ECS Services and Cluster
echo -e "\n${GREEN}Cleaning up ECS...${NC}"
CLUSTERS=$(aws ecs list-clusters --region $AWS_REGION --query 'clusterArns[*]' --output text 2>/dev/null || echo "")
for cluster_arn in $CLUSTERS; do
    cluster_name=$(basename $cluster_arn)
    if [[ "$cluster_name" == *"basedsecurity"* ]]; then
        echo "Found BasedSecurity cluster: $cluster_name"

        # Stop all services first
        SERVICES=$(aws ecs list-services --cluster $cluster_name --region $AWS_REGION --query 'serviceArns[*]' --output text 2>/dev/null || echo "")
        for service_arn in $SERVICES; do
            service_name=$(basename $service_arn)
            echo "  Stopping service: $service_name"
            run_cmd "aws ecs update-service --cluster $cluster_name --service $service_name --desired-count 0 --region $AWS_REGION"
            run_cmd "aws ecs delete-service --cluster $cluster_name --service $service_name --force --region $AWS_REGION"
        done

        # Delete cluster
        run_cmd "aws ecs delete-cluster --cluster $cluster_name --region $AWS_REGION"
    fi
done

# ECR Repositories
echo -e "\n${GREEN}Cleaning up ECR repositories...${NC}"
REPOS=$(aws ecr describe-repositories --region $AWS_REGION --query 'repositories[*].repositoryName' --output text 2>/dev/null || echo "")
for repo in $REPOS; do
    if [[ "$repo" == *"basedsecurity"* ]]; then
        echo "Deleting ECR repository: $repo"
        run_cmd "aws ecr delete-repository --repository-name $repo --force --region $AWS_REGION"
    fi
done

# RDS Clusters (Aurora)
echo -e "\n${GREEN}Cleaning up RDS Aurora clusters...${NC}"
DB_CLUSTERS=$(aws rds describe-db-clusters --region $AWS_REGION --query 'DBClusters[*].DBClusterIdentifier' --output text 2>/dev/null || echo "")
for cluster in $DB_CLUSTERS; do
    if [[ "$cluster" == *"basedsecurity"* ]]; then
        echo "Deleting RDS cluster: $cluster"
        # Disable deletion protection first
        run_cmd "aws rds modify-db-cluster --db-cluster-identifier $cluster --no-deletion-protection --region $AWS_REGION"
        # Delete instances first
        INSTANCES=$(aws rds describe-db-instances --region $AWS_REGION --query "DBInstances[?DBClusterIdentifier=='$cluster'].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
        for instance in $INSTANCES; do
            echo "  Deleting DB instance: $instance"
            run_cmd "aws rds delete-db-instance --db-instance-identifier $instance --skip-final-snapshot --region $AWS_REGION"
        done
        sleep 5
        run_cmd "aws rds delete-db-cluster --db-cluster-identifier $cluster --skip-final-snapshot --region $AWS_REGION"
    fi
done

# ElastiCache
echo -e "\n${GREEN}Cleaning up ElastiCache...${NC}"
CACHE_CLUSTERS=$(aws elasticache describe-replication-groups --region $AWS_REGION --query 'ReplicationGroups[*].ReplicationGroupId' --output text 2>/dev/null || echo "")
for cache in $CACHE_CLUSTERS; do
    if [[ "$cache" == *"basedsecurity"* ]]; then
        echo "Deleting ElastiCache replication group: $cache"
        run_cmd "aws elasticache delete-replication-group --replication-group-id $cache --region $AWS_REGION"
    fi
done

# ALB
echo -e "\n${GREEN}Cleaning up Load Balancers...${NC}"
ALBS=$(aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' --output text 2>/dev/null || echo "")
echo "$ALBS" | while read -r arn name; do
    if [[ "$name" == *"basedsecurity"* ]]; then
        echo "Deleting ALB: $name"
        # Delete listeners first
        LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn $arn --region $AWS_REGION --query 'Listeners[*].ListenerArn' --output text 2>/dev/null || echo "")
        for listener in $LISTENERS; do
            run_cmd "aws elbv2 delete-listener --listener-arn $listener --region $AWS_REGION"
        done
        run_cmd "aws elbv2 delete-load-balancer --load-balancer-arn $arn --region $AWS_REGION"
    fi
done

# Target Groups
TGS=$(aws elbv2 describe-target-groups --region $AWS_REGION --query 'TargetGroups[*].[TargetGroupArn,TargetGroupName]' --output text 2>/dev/null || echo "")
echo "$TGS" | while read -r arn name; do
    if [[ "$name" == *"basedsecurity"* ]]; then
        echo "Deleting Target Group: $name"
        run_cmd "aws elbv2 delete-target-group --target-group-arn $arn --region $AWS_REGION"
    fi
done

# =============================================================================
# SECTION 2: RAPIDPHOTOFLOW CLEANUP
# =============================================================================
echo -e "\n${GREEN}=== Section 2: RapidPhotoFlow Cleanup ===${NC}"

# Check for RapidPhotoFlow Terraform state
RAPIDPHOTO_TF_DIR="../../../rapidPhotoFlow/terraform"
if [ -f "$RAPIDPHOTO_TF_DIR/terraform.tfstate" ]; then
    echo -e "${YELLOW}Found RapidPhotoFlow Terraform state. Attempting terraform destroy...${NC}"
    if [ "$DRY_RUN" = "false" ]; then
        cd "$RAPIDPHOTO_TF_DIR"
        terraform destroy -auto-approve
        cd - > /dev/null
    else
        echo -e "${BLUE}[DRY RUN] Would run: terraform destroy -auto-approve in $RAPIDPHOTO_TF_DIR${NC}"
    fi
fi

echo -e "\n${YELLOW}Checking for RapidPhotoFlow AWS resources...${NC}"

# ECS for RapidPhotoFlow
echo -e "\n${GREEN}Cleaning up RapidPhotoFlow ECS...${NC}"
for cluster_arn in $CLUSTERS; do
    cluster_name=$(basename $cluster_arn)
    if [[ "$cluster_name" == *"rpf"* ]] || [[ "$cluster_name" == *"rapidphoto"* ]] || [[ "$cluster_name" == *"photo"* ]]; then
        echo "Found RapidPhotoFlow cluster: $cluster_name"
        SERVICES=$(aws ecs list-services --cluster $cluster_name --region $AWS_REGION --query 'serviceArns[*]' --output text 2>/dev/null || echo "")
        for service_arn in $SERVICES; do
            service_name=$(basename $service_arn)
            echo "  Stopping service: $service_name"
            run_cmd "aws ecs update-service --cluster $cluster_name --service $service_name --desired-count 0 --region $AWS_REGION"
            run_cmd "aws ecs delete-service --cluster $cluster_name --service $service_name --force --region $AWS_REGION"
        done
        run_cmd "aws ecs delete-cluster --cluster $cluster_name --region $AWS_REGION"
    fi
done

# ECR for RapidPhotoFlow
echo -e "\n${GREEN}Cleaning up RapidPhotoFlow ECR...${NC}"
for repo in $REPOS; do
    if [[ "$repo" == *"rpf"* ]] || [[ "$repo" == *"rapidphoto"* ]] || [[ "$repo" == *"photo"* ]]; then
        echo "Deleting ECR repository: $repo"
        run_cmd "aws ecr delete-repository --repository-name $repo --force --region $AWS_REGION"
    fi
done

# RDS for RapidPhotoFlow
echo -e "\n${GREEN}Cleaning up RapidPhotoFlow RDS...${NC}"
DB_INSTANCES=$(aws rds describe-db-instances --region $AWS_REGION --query 'DBInstances[*].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
for instance in $DB_INSTANCES; do
    if [[ "$instance" == *"rpf"* ]] || [[ "$instance" == *"rapidphoto"* ]] || [[ "$instance" == *"photo"* ]]; then
        echo "Deleting RDS instance: $instance"
        run_cmd "aws rds modify-db-instance --db-instance-identifier $instance --no-deletion-protection --region $AWS_REGION 2>/dev/null || true"
        run_cmd "aws rds delete-db-instance --db-instance-identifier $instance --skip-final-snapshot --region $AWS_REGION"
    fi
done

# Cognito User Pools
echo -e "\n${GREEN}Cleaning up Cognito...${NC}"
POOLS=$(aws cognito-idp list-user-pools --max-results 60 --region $AWS_REGION --query 'UserPools[*].[Id,Name]' --output text 2>/dev/null || echo "")
echo "$POOLS" | while read -r id name; do
    if [[ "$name" == *"rpf"* ]] || [[ "$name" == *"rapidphoto"* ]] || [[ "$name" == *"photo"* ]]; then
        echo "Deleting Cognito User Pool: $name"
        # Delete domain first
        DOMAIN=$(aws cognito-idp describe-user-pool --user-pool-id $id --region $AWS_REGION --query 'UserPool.Domain' --output text 2>/dev/null || echo "")
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "None" ]; then
            run_cmd "aws cognito-idp delete-user-pool-domain --domain $DOMAIN --user-pool-id $id --region $AWS_REGION"
        fi
        run_cmd "aws cognito-idp delete-user-pool --user-pool-id $id --region $AWS_REGION"
    fi
done

# API Gateway
echo -e "\n${GREEN}Cleaning up API Gateway...${NC}"
APIS=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[*].[ApiId,Name]' --output text 2>/dev/null || echo "")
echo "$APIS" | while read -r id name; do
    if [[ "$name" == *"rpf"* ]] || [[ "$name" == *"rapidphoto"* ]] || [[ "$name" == *"photo"* ]]; then
        echo "Deleting API Gateway: $name"
        run_cmd "aws apigatewayv2 delete-api --api-id $id --region $AWS_REGION"
    fi
done

# =============================================================================
# SECTION 3: SHARED RESOURCES CLEANUP
# =============================================================================
echo -e "\n${GREEN}=== Section 3: Shared Resources Cleanup ===${NC}"

# CloudFront Distributions
echo -e "\n${GREEN}Cleaning up CloudFront distributions...${NC}"
DISTRIBUTIONS=$(aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,Comment]' --output text 2>/dev/null || echo "")
echo "$DISTRIBUTIONS" | while read -r id comment; do
    if [[ "$comment" == *"basedsecurity"* ]] || [[ "$comment" == *"rapidphoto"* ]] || [[ "$comment" == *"rpf"* ]]; then
        echo "Found CloudFront distribution: $id ($comment)"
        echo -e "${YELLOW}  CloudFront must be disabled before deletion. This may take 15-20 minutes.${NC}"
        if [ "$DRY_RUN" = "false" ]; then
            # Get current config
            ETAG=$(aws cloudfront get-distribution-config --id $id --query 'ETag' --output text)
            aws cloudfront get-distribution-config --id $id --query 'DistributionConfig' > /tmp/cf-config.json
            # Disable distribution
            jq '.Enabled = false' /tmp/cf-config.json > /tmp/cf-config-disabled.json
            aws cloudfront update-distribution --id $id --if-match $ETAG --distribution-config file:///tmp/cf-config-disabled.json
            echo "  Distribution disabled. You must wait for status 'Deployed' before deletion."
            echo "  Run this script again after 15-20 minutes to complete deletion."
        fi
    fi
done

# S3 Buckets
echo -e "\n${GREEN}Cleaning up S3 buckets...${NC}"
BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text 2>/dev/null || echo "")
for bucket in $BUCKETS; do
    if [[ "$bucket" == *"basedsecurity"* ]] || [[ "$bucket" == *"rapidphoto"* ]] || [[ "$bucket" == *"rpf"* ]]; then
        echo "Deleting S3 bucket: $bucket"
        run_cmd "aws s3 rm s3://$bucket --recursive --region $AWS_REGION"
        run_cmd "aws s3api delete-bucket --bucket $bucket --region $AWS_REGION"
    fi
done

# Secrets Manager
echo -e "\n${GREEN}Cleaning up Secrets Manager...${NC}"
SECRETS=$(aws secretsmanager list-secrets --region $AWS_REGION --query 'SecretList[*].[Name,ARN]' --output text 2>/dev/null || echo "")
echo "$SECRETS" | while read -r name arn; do
    if [[ "$name" == *"basedsecurity"* ]] || [[ "$name" == *"rapidphoto"* ]] || [[ "$name" == *"rpf"* ]]; then
        echo "Deleting secret: $name"
        run_cmd "aws secretsmanager delete-secret --secret-id $arn --force-delete-without-recovery --region $AWS_REGION"
    fi
done

# CloudWatch Log Groups
echo -e "\n${GREEN}Cleaning up CloudWatch Log Groups...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --region $AWS_REGION --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
for lg in $LOG_GROUPS; do
    if [[ "$lg" == *"basedsecurity"* ]] || [[ "$lg" == *"rapidphoto"* ]] || [[ "$lg" == *"rpf"* ]]; then
        echo "Deleting log group: $lg"
        run_cmd "aws logs delete-log-group --log-group-name $lg --region $AWS_REGION"
    fi
done

# =============================================================================
# SECTION 4: VPC CLEANUP (Run last due to dependencies)
# =============================================================================
echo -e "\n${GREEN}=== Section 4: VPC Cleanup ===${NC}"

# Get VPCs to clean up
VPCS=$(aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output text 2>/dev/null || echo "")
echo "$VPCS" | while read -r vpc_id name; do
    if [[ "$name" == *"basedsecurity"* ]] || [[ "$name" == *"rapidphoto"* ]] || [[ "$name" == *"rpf"* ]]; then
        echo "Cleaning up VPC: $vpc_id ($name)"

        # Delete NAT Gateways
        NATS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null || echo "")
        for nat in $NATS; do
            echo "  Deleting NAT Gateway: $nat"
            run_cmd "aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $AWS_REGION"
        done

        # Delete VPC Endpoints
        ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null || echo "")
        for ep in $ENDPOINTS; do
            echo "  Deleting VPC Endpoint: $ep"
            run_cmd "aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep --region $AWS_REGION"
        done

        # Delete Security Groups (except default)
        SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
        for sg in $SGS; do
            echo "  Deleting Security Group: $sg"
            run_cmd "aws ec2 delete-security-group --group-id $sg --region $AWS_REGION"
        done

        # Delete Subnets
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'Subnets[*].SubnetId' --output text 2>/dev/null || echo "")
        for subnet in $SUBNETS; do
            echo "  Deleting Subnet: $subnet"
            run_cmd "aws ec2 delete-subnet --subnet-id $subnet --region $AWS_REGION"
        done

        # Detach and delete Internet Gateway
        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null || echo "")
        for igw in $IGWS; do
            echo "  Detaching and deleting Internet Gateway: $igw"
            run_cmd "aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc_id --region $AWS_REGION"
            run_cmd "aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $AWS_REGION"
        done

        # Delete Route Tables (except main)
        RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'RouteTables[?Associations[?Main!=`true`]].RouteTableId' --output text 2>/dev/null || echo "")
        for rt in $RTS; do
            echo "  Deleting Route Table: $rt"
            run_cmd "aws ec2 delete-route-table --route-table-id $rt --region $AWS_REGION"
        done

        # Finally delete VPC
        echo "  Deleting VPC: $vpc_id"
        run_cmd "aws ec2 delete-vpc --vpc-id $vpc_id --region $AWS_REGION"
    fi
done

# =============================================================================
# SECTION 5: TERRAFORM STATE CLEANUP
# =============================================================================
echo -e "\n${GREEN}=== Section 5: Terraform State Backend Cleanup ===${NC}"

# BasedSecurity Terraform state bucket
STATE_BUCKET="basedsecurity-terraform-state-466954108373"
if aws s3api head-bucket --bucket $STATE_BUCKET 2>/dev/null; then
    echo "Found Terraform state bucket: $STATE_BUCKET"
    run_cmd "aws s3 rm s3://$STATE_BUCKET --recursive --region $AWS_REGION"
    run_cmd "aws s3api delete-bucket --bucket $STATE_BUCKET --region $AWS_REGION"
fi

# DynamoDB lock table
LOCK_TABLE="basedsecurity-terraform-locks"
if aws dynamodb describe-table --table-name $LOCK_TABLE --region $AWS_REGION 2>/dev/null; then
    echo "Found Terraform lock table: $LOCK_TABLE"
    run_cmd "aws dynamodb delete-table --table-name $LOCK_TABLE --region $AWS_REGION"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Cleanup Complete!                        ${NC}"
echo -e "${GREEN}============================================${NC}"

if [ "$DRY_RUN" = "true" ]; then
    echo -e "\n${YELLOW}This was a DRY RUN. No resources were deleted.${NC}"
    echo -e "${YELLOW}To perform actual cleanup, run:${NC}"
    echo -e "${BLUE}  DRY_RUN=false ./cleanup-existing-aws.sh${NC}"
else
    echo -e "\n${GREEN}Resources have been cleaned up.${NC}"
    echo -e "${YELLOW}Note: Some resources (CloudFront, RDS) may take several minutes to fully delete.${NC}"
    echo -e "${YELLOW}Check AWS Console to verify all resources are removed.${NC}"
fi

echo -e "\n${BLUE}Next steps:${NC}"
echo "1. Verify cleanup in AWS Console"
echo "2. Run terraform init in aws-portfolio-deployment/terraform"
echo "3. Run terraform plan to preview new infrastructure"
echo "4. Run terraform apply to deploy unified infrastructure"

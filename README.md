# AWS Portfolio Deployment Plan

Cost-effective deployment for demo portfolio projects.

## Projects Included

| Project | Type | Port | Database |
|---------|------|------|----------|
| terminal-portfolio | Node.js/Express | 3001 | SQLite |
| rapidPhotoFlow | Java Spring Boot | 8080 | PostgreSQL |
| rapidPhotoFlow AI | Node.js/Express | 3002 | - |
| basedSecurity_AI | Python/FastAPI | 8000 | PostgreSQL + Redis |
| shippingMonitoring | Node.js/Express | 3003 | SQLite |

## Architecture Overview

```
                    ┌─────────────────┐
                    │   CloudFront    │
                    │   (CDN + SSL)   │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
   ┌──────────┐       ┌──────────┐       ┌──────────┐
   │    S3    │       │    S3    │       │   ALB    │
   │ Frontend │       │  Photos  │       │  → EC2   │
   │ (static) │       │ Storage  │       │ Backends │
   └──────────┘       └──────────┘       └──────────┘
```

## Estimated Monthly Cost: $10-20

- EC2 t3.small (spot): ~$5-8/month
- S3 + CloudFront: ~$2-5/month
- Route 53: ~$0.50/domain
- RDS t3.micro (if needed): ~$13/month (optional - can use SQLite)

## Deployment Steps

### Phase 1: Infrastructure Setup (Terraform)

1. Create VPC with public subnet
2. Create S3 buckets for frontends
3. Create CloudFront distributions
4. Launch EC2 instance with Docker
5. Configure Route 53 DNS

### Phase 2: Backend Deployment

1. SSH into EC2
2. Clone repositories
3. Run docker-compose with all services
4. Configure Traefik for routing

### Phase 3: Frontend Deployment

1. Build each React app with production API URLs
2. Upload to S3 buckets
3. Invalidate CloudFront cache

## Quick Deployment (Recommended)

Use the unified deployment scripts for easy deployments:

```powershell
# Show available commands
.\scripts\quick-deploy.ps1 help

# Deploy a single frontend
.\scripts\quick-deploy.ps1 portfolio

# Deploy all frontends
.\scripts\quick-deploy.ps1 all-frontends

# Deploy everything
.\scripts\quick-deploy.ps1 all
```

### Available Services

| Service | Type | URL |
|---------|------|-----|
| portfolio | Frontend | https://portfolio.basedsecurity.net |
| photos | Frontend | https://photos.basedsecurity.net |
| security | Frontend | https://security.basedsecurity.net |
| shipping | Frontend | https://shipping.basedsecurity.net |
| portfolio-backend | Backend | via API gateway |
| photos-backend | Backend | via API gateway |
| security-backend | Backend | via API gateway |
| shipping-backend | Backend | via API gateway |
| status-page | Backend | via API gateway |

### Advanced Usage

For more control, use the main deploy script directly:

```powershell
# Deploy with options
.\scripts\deploy.ps1 -Service portfolio -SkipBuild
.\scripts\deploy.ps1 -Service frontends -SkipInvalidation
```

## Directory Structure

```
aws-portfolio-deployment/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc.tf
│   ├── ec2.tf
│   ├── s3.tf
│   ├── cloudfront.tf
│   └── route53.tf
├── docker/
│   └── docker-compose.prod.yml
├── scripts/
│   ├── deploy.ps1           # Main deployment script
│   ├── quick-deploy.ps1     # Simplified deployment helper
│   ├── deploy-config.json   # Service configuration
│   ├── deploy-frontends.sh  # Legacy bash script
│   ├── deploy-backends.sh   # Legacy bash script
│   └── setup-ec2.sh
└── README.md
```

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "portfolio"
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
  default     = "prod"
}

# Subdomains for each project
variable "subdomains" {
  description = "Subdomain configuration"
  type = map(object({
    name        = string
    description = string
  }))
  default = {
    portfolio = {
      name        = "portfolio"
      description = "Terminal Portfolio"
    }
    photos = {
      name        = "photos"
      description = "RapidPhotoFlow"
    }
    security = {
      name        = "security"
      description = "BasedSecurity AI"
    }
    shipping = {
      name        = "shipping"
      description = "Shipping Monitoring"
    }
    api = {
      name        = "api"
      description = "Backend API Gateway"
    }
  }
}

# EC2 Configuration
variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small" # 2 vCPU, 2GB RAM - good for all backends
}

variable "ec2_use_spot" {
  description = "Use spot instances for cost savings"
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
}

# Database Configuration
variable "use_rds" {
  description = "Use RDS PostgreSQL instead of local PostgreSQL container"
  type        = bool
  default     = false # Start with containerized DB, upgrade if needed
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# Secrets (should be in terraform.tfvars or AWS Secrets Manager)
variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

variable "openai_api_key" {
  description = "OpenAI API key for RapidPhotoFlow"
  type        = string
  sensitive   = true
  default     = ""
}

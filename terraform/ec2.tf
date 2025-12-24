# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for EC2 (S3 access, ECR, CloudWatch)
resource "aws_iam_role_policy" "ec2" {
  name = "${local.name_prefix}-ec2-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.photos.arn,
          "${aws_s3_bucket.photos.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# EC2 Instance (Standard)
resource "aws_instance" "backend" {
  count = var.ec2_use_spot ? 0 : 1

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(local.user_data_script)

  tags = {
    Name = "${local.name_prefix}-backend"
  }
}

# EC2 Spot Instance (Cost Optimized)
resource "aws_spot_instance_request" "backend" {
  count = var.ec2_use_spot ? 1 : 0

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  spot_type            = "persistent"
  wait_for_fulfillment = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(local.user_data_script)

  tags = {
    Name = "${local.name_prefix}-backend-spot"
  }
}

# User data script to setup Docker and clone repos
locals {
  user_data_script = <<-EOF
    #!/bin/bash
    set -e

    # Update system
    dnf update -y

    # Install Docker
    dnf install -y docker git
    systemctl start docker
    systemctl enable docker

    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Add ec2-user to docker group
    usermod -aG docker ec2-user

    # Create app directory
    mkdir -p /opt/portfolio
    chown ec2-user:ec2-user /opt/portfolio

    # Clone repositories (as ec2-user)
    cd /opt/portfolio

    # Create environment file
    cat > /opt/portfolio/.env << 'ENVFILE'
    # Database
    POSTGRES_USER=portfolio
    POSTGRES_PASSWORD=${var.db_password}
    POSTGRES_DB=portfolio
    DATABASE_URL=postgresql://portfolio:${var.db_password}@postgres:5432/portfolio

    # JWT
    JWT_SECRET=${var.jwt_secret}
    APP_SECRET_KEY=${var.jwt_secret}

    # OpenAI (for RapidPhotoFlow)
    OPENAI_API_KEY=${var.openai_api_key}

    # AWS
    AWS_REGION=${var.aws_region}
    S3_BUCKET=${aws_s3_bucket.photos.id}

    # Domain
    DOMAIN=${var.domain_name}
    ENVFILE

    # Signal completion
    echo "EC2 setup complete" > /opt/portfolio/setup-complete.txt
  EOF
}

# Elastic IP for consistent public IP
resource "aws_eip" "backend" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-backend-eip"
  }
}

# Associate EIP with instance
resource "aws_eip_association" "backend" {
  instance_id   = var.ec2_use_spot ? aws_spot_instance_request.backend[0].spot_instance_id : aws_instance.backend[0].id
  allocation_id = aws_eip.backend.id
}

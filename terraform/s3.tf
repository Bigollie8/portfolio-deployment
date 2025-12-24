# S3 Bucket for Frontend Static Sites
resource "aws_s3_bucket" "frontends" {
  for_each = toset(["portfolio", "photos", "security", "shipping"])
  bucket   = "${local.name_prefix}-${each.key}-frontend"

  tags = {
    Name    = "${local.name_prefix}-${each.key}-frontend"
    Purpose = "Static frontend hosting"
  }
}

# S3 Bucket for Photo Storage (RapidPhotoFlow)
resource "aws_s3_bucket" "photos" {
  bucket = "${local.name_prefix}-photo-storage"

  tags = {
    Name    = "${local.name_prefix}-photo-storage"
    Purpose = "Photo storage for RapidPhotoFlow"
  }
}

# Block public access for frontends (served via CloudFront)
resource "aws_s3_bucket_public_access_block" "frontends" {
  for_each = aws_s3_bucket.frontends
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for photos bucket
resource "aws_s3_bucket_public_access_block" "photos" {
  bucket = aws_s3_bucket.photos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Website configuration for frontend buckets
resource "aws_s3_bucket_website_configuration" "frontends" {
  for_each = aws_s3_bucket.frontends
  bucket   = each.value.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html" # SPA fallback
  }
}

# CORS for photo bucket (for direct uploads)
resource "aws_s3_bucket_cors_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = [
      "https://${var.subdomains.photos.name}.${var.domain_name}",
      "http://localhost:5173" # Development
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "frontends" {
  name                              = "${local.name_prefix}-frontend-oac"
  description                       = "OAC for frontend S3 buckets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 Bucket Policy to allow CloudFront access
resource "aws_s3_bucket_policy" "frontends" {
  for_each = aws_s3_bucket.frontends
  bucket   = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${each.value.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontends[each.key].arn
          }
        }
      }
    ]
  })
}

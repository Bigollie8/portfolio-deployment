output "ec2_public_ip" {
  description = "Public IP of the backend EC2 instance"
  value       = aws_eip.backend.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of the backend EC2 instance"
  value       = aws_eip.backend.public_dns
}

output "frontend_urls" {
  description = "URLs for all frontend applications"
  value = {
    for key, dist in aws_cloudfront_distribution.frontends :
    key => "https://${var.subdomains[key].name}.${var.domain_name}"
  }
}

output "api_url" {
  description = "URL for the API gateway"
  value       = "https://${var.subdomains.api.name}.${var.domain_name}"
}

output "s3_buckets" {
  description = "S3 bucket names"
  value = {
    frontends = { for k, v in aws_s3_bucket.frontends : k => v.id }
    photos    = aws_s3_bucket.photos.id
  }
}

output "cloudfront_distribution_ids" {
  description = "CloudFront distribution IDs (for cache invalidation)"
  value = {
    frontends = { for k, v in aws_cloudfront_distribution.frontends : k => v.id }
    api       = aws_cloudfront_distribution.api.id
  }
}

output "ssh_command" {
  description = "SSH command to connect to EC2"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.backend.public_ip}"
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════╗
    ║              Portfolio Deployment Complete!                   ║
    ╚══════════════════════════════════════════════════════════════╝

    Frontend URLs:
    ├── Portfolio:  https://${var.subdomains.portfolio.name}.${var.domain_name}
    ├── Photos:     https://${var.subdomains.photos.name}.${var.domain_name}
    ├── Security:   https://${var.subdomains.security.name}.${var.domain_name}
    └── Shipping:   https://${var.subdomains.shipping.name}.${var.domain_name}

    API URL:        https://${var.subdomains.api.name}.${var.domain_name}

    EC2 Instance:   ${aws_eip.backend.public_ip}
    SSH Command:    ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.backend.public_ip}

    Next Steps:
    1. SSH into EC2 and run: cd /opt/portfolio && docker-compose up -d
    2. Build frontends and upload to S3
    3. Invalidate CloudFront caches

  EOT
}

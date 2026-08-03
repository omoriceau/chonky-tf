output "images_bucket_name" {
  value = module.images_bucket.bucket_name
}

output "images_base_url" {
  value = "https://${local.img_domain_name}/"
}

output "cloudfront_distribution_domain" {
  description = "CloudFront's own domain — the DNS-only Cloudflare CNAME for img_domain_name points here"
  value       = aws_cloudfront_distribution.img.domain_name
}

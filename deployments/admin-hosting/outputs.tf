output "site_url" {
  value = "https://${var.domain_name}"
}

output "bucket_name" {
  value = module.hosting.bucket_name
}

output "bucket_arn" {
  value = module.hosting.bucket_arn
}

output "distribution_id" {
  value = module.hosting.distribution_id
}

output "distribution_arn" {
  value = module.hosting.distribution_arn
}

output "distribution_domain_name" {
  value = module.hosting.distribution_domain_name
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.this.certificate_arn
}

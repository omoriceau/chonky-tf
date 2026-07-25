output "images_bucket_name" {
  value = module.images_bucket.bucket_name
}

output "images_base_url" {
  value = "https://${module.images_bucket.bucket_name}.s3.${var.region}.amazonaws.com/img/"
}

# Plain S3 REST endpoints only carry a cert for *.s3.<region>.amazonaws.com,
# not a custom hostname — Cloudflare must be the one terminating TLS for
# <env>-img.chonkycat.ca, so the record has to be proxied (orange cloud),
# unlike the DNS-only records used for ACM-validated CloudFront domains
# elsewhere in this repo (e.g. deployments/admin-hosting).
output "cloudflare_cname_instructions" {
  description = "DNS record to add in Cloudflare so <env>-img.chonkycat.ca serves this bucket"
  value       = <<-EOT
    Add a CNAME record in the chonkycat.ca Cloudflare zone:
      Name:   ${var.env}-img
      Target: ${module.images_bucket.bucket_name}.s3.${var.region}.amazonaws.com
      Proxy:  Proxied (orange cloud)
  EOT
}

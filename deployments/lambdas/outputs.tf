output "commit_sha" {
  description = "chonky-cat-be commit currently deployed"
  value       = module.chonkycat_be.commit_sha
}

output "checkout_dir" {
  description = "Local path chonky-cat-be was checked out into"
  value       = module.chonkycat_be.checkout_dir
}

output "products_api_url" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["ProductsApi"]
}

output "users_api_url" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["UsersApi"]
}

output "orders_api_url" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["OrdersApi"]
}

output "cart_api_url" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["CartApi"]
}

output "payments_api_url" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["PaymentsApi"]
}

output "webhook_api_url" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["WebhookApi"]
}

output "event_bus_arn" {
  value = data.aws_cloudformation_stack.chonkychonk_products.outputs["EventBusArn"]
}

output "api_custom_domain_status" {
  description = "Whether <env>-api.chonkycat.ca (or api.chonkycat.ca for production) got attached to the API Gateway, or why not"
  value = local.custom_domain_enabled ? (
    "Attached: https://${local.api_domain_name} -> ${aws_api_gateway_domain_name.api[0].cloudfront_domain_name} (base path mapping onto ${local.rest_api_id}, stage ${var.env})"
    ) : (
    "NOT attached — cloudflare_api_token and/or cloudflare_zone_id were not supplied, so this module has no way to create the Cloudflare DNS records ACM's cert validation and the domain's CNAME both need. Set TF_VAR_cloudflare_api_token and TF_VAR_cloudflare_zone_id (Cloudflare Zone.DNS-edit token + the chonkycat.ca zone id) and re-apply to attach ${local.api_domain_name}."
  )
}

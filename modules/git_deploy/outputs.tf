output "commit_sha" {
  description = "Commit currently deployed"
  value       = trimspace(data.local_file.commit_sha.content)
}

output "checkout_dir" {
  description = "Local path the repo was checked out into"
  value       = var.checkout_dir
}

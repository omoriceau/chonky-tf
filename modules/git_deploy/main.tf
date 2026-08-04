terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

locals {
  # Sibling file next to checkout_dir, not inside it — checkout_dir gets
  # reset --hard/clean on every apply, which would wipe anything written
  # under it.
  commit_file = "${var.checkout_dir}.commit"
}

# Pulls repo_url's branch into checkout_dir (cloning fresh if it isn't a repo
# yet, otherwise fetch + reset --hard so checkout_dir always matches the
# remote branch tip) and hands off to deploy_command. Two provisioners
# because they need different working directories: the git step addresses
# checkout_dir explicitly via `-C`, deploy_command runs relative to it.
resource "null_resource" "deploy" {
  triggers = {
    force_redeploy = var.force_redeploy
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      if [ -d "${var.checkout_dir}/.git" ]; then
        git -C "${var.checkout_dir}" fetch origin "${var.branch}"
        git -C "${var.checkout_dir}" reset --hard "origin/${var.branch}"
        git -C "${var.checkout_dir}" clean -fd
      else
        rm -rf "${var.checkout_dir}"
        git clone --branch "${var.branch}" --single-branch "${var.repo_url}" "${var.checkout_dir}"
      fi
      git -C "${var.checkout_dir}" rev-parse HEAD > "${local.commit_file}"
    EOT
  }

  provisioner "local-exec" {
    command     = var.deploy_command
    working_dir = var.checkout_dir
    environment = var.env_vars
  }
}

# depends_on forces this to be read during apply (after null_resource.deploy
# writes it) rather than at plan time, which is how a data source picks up a
# value that's only known once a provisioner has run.
data "local_file" "commit_sha" {
  filename   = local.commit_file
  depends_on = [null_resource.deploy]
}

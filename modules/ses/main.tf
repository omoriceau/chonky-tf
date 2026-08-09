data "aws_caller_identity" "current" {}

# ==============================================================================
# DOMAIN IDENTITY + VERIFICATION
# ==============================================================================
resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

# proxied = false is required: SES verification/DKIM lookups must resolve
# directly (DNS-only), not through Cloudflare's proxy, same reasoning as the
# ACM validation record in deployments/custom-domain/main.tf.
resource "cloudflare_record" "verification" {
  zone_id = var.cloudflare_zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  content = aws_ses_domain_identity.this.verification_token
  ttl     = 60
  proxied = false
}

resource "aws_ses_domain_identity_verification" "this" {
  domain     = aws_ses_domain_identity.this.id
  depends_on = [cloudflare_record.verification]
}

# ==============================================================================
# DKIM (Easy DKIM)
# ==============================================================================
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# SES always returns exactly 3 DKIM tokens, but their values aren't known
# until apply — for_each requires known keys at plan time, so this uses
# count (which only needs the count, not the values) instead.
resource "cloudflare_record" "dkim" {
  count = 3

  zone_id = var.cloudflare_zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  content = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"
  ttl     = 60
  proxied = false
}

# ==============================================================================
# CUSTOM MAIL FROM DOMAIN — SPF alignment for better deliverability, matters
# more for newsletter sending than pure transactional mail.
# ==============================================================================
resource "aws_ses_domain_mail_from" "this" {
  domain                 = aws_ses_domain_identity.this.domain
  mail_from_domain       = "mail.${var.domain_name}"
  behavior_on_mx_failure = "UseDefaultValue"
}

resource "cloudflare_record" "mail_from_mx" {
  zone_id  = var.cloudflare_zone_id
  name     = aws_ses_domain_mail_from.this.mail_from_domain
  type     = "MX"
  content  = "feedback-smtp.${var.region}.amazonses.com"
  priority = 10
  ttl      = 60
  proxied  = false
}

resource "cloudflare_record" "mail_from_spf" {
  zone_id = var.cloudflare_zone_id
  name    = aws_ses_domain_mail_from.this.mail_from_domain
  type    = "TXT"
  content = "v=spf1 include:amazonses.com ~all"
  ttl     = 60
  proxied = false
}

# ==============================================================================
# BOUNCE / COMPLAINT TRACKING — SNS topics + a configuration set wired to
# SES's event publishing, so bounces/complaints are observable instead of
# silently eroding sender reputation (matters most for the newsletter).
# ==============================================================================
# Customer-managed key, not the AWS-managed alias/aws/sns key: the AWS-managed
# key's policy doesn't grant other services (e.g. SES) kms:GenerateDataKey /
# kms:Decrypt, which makes SES fail to publish bounce/complaint events to an
# alias/aws/sns-encrypted topic. A CMK with an explicit policy is required.
data "aws_iam_policy_document" "sns_kms" {
  count = var.enable_bounce_complaint_tracking ? 1 : 0

  statement {
    sid       = "EnableRootAccountAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowSESPublishToSNS"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "sns" {
  count               = var.enable_bounce_complaint_tracking ? 1 : 0
  description         = "CMK for ${var.name_prefix} SES bounce/complaint SNS topics (${var.env})"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.sns_kms[0].json
}

resource "aws_kms_alias" "sns" {
  count         = var.enable_bounce_complaint_tracking ? 1 : 0
  name          = "alias/${var.name_prefix}-ses-sns-${var.env}"
  target_key_id = aws_kms_key.sns[0].key_id
}

resource "aws_sns_topic" "bounces" {
  count             = var.enable_bounce_complaint_tracking ? 1 : 0
  name              = "${var.name_prefix}-ses-bounces-${var.env}"
  kms_master_key_id = aws_kms_key.sns[0].key_id
}

resource "aws_sns_topic" "complaints" {
  count             = var.enable_bounce_complaint_tracking ? 1 : 0
  name              = "${var.name_prefix}-ses-complaints-${var.env}"
  kms_master_key_id = aws_kms_key.sns[0].key_id
}

data "aws_iam_policy_document" "sns_publish_from_ses" {
  for_each = var.enable_bounce_complaint_tracking ? { bounces = aws_sns_topic.bounces[0].arn, complaints = aws_sns_topic.complaints[0].arn } : {}

  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [each.value]

    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "bounces" {
  count  = var.enable_bounce_complaint_tracking ? 1 : 0
  arn    = aws_sns_topic.bounces[0].arn
  policy = data.aws_iam_policy_document.sns_publish_from_ses["bounces"].json
}

resource "aws_sns_topic_policy" "complaints" {
  count  = var.enable_bounce_complaint_tracking ? 1 : 0
  arn    = aws_sns_topic.complaints[0].arn
  policy = data.aws_iam_policy_document.sns_publish_from_ses["complaints"].json
}

# Admin alert subscriptions — email endpoint subscriptions require the
# recipient to click a confirmation link AWS emails them; until confirmed,
# the subscription sits in "PendingConfirmation" and receives nothing.
resource "aws_sns_topic_subscription" "bounces_admin_email" {
  count     = var.enable_bounce_complaint_tracking && var.admin_alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.bounces[0].arn
  protocol  = "email"
  endpoint  = var.admin_alert_email
}

resource "aws_sns_topic_subscription" "complaints_admin_email" {
  count     = var.enable_bounce_complaint_tracking && var.admin_alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.complaints[0].arn
  protocol  = "email"
  endpoint  = var.admin_alert_email
}

resource "aws_sesv2_configuration_set" "this" {
  configuration_set_name = "${var.name_prefix}-ses-${var.env}"
}

resource "aws_sesv2_configuration_set_event_destination" "bounce" {
  count                  = var.enable_bounce_complaint_tracking ? 1 : 0
  configuration_set_name = aws_sesv2_configuration_set.this.configuration_set_name
  event_destination_name = "bounce-to-sns"

  event_destination {
    enabled              = true
    matching_event_types = ["BOUNCE"]

    sns_destination {
      topic_arn = aws_sns_topic.bounces[0].arn
    }
  }
}

resource "aws_sesv2_configuration_set_event_destination" "complaint" {
  count                  = var.enable_bounce_complaint_tracking ? 1 : 0
  configuration_set_name = aws_sesv2_configuration_set.this.configuration_set_name
  event_destination_name = "complaint-to-sns"

  event_destination {
    enabled              = true
    matching_event_types = ["COMPLAINT"]

    sns_destination {
      topic_arn = aws_sns_topic.complaints[0].arn
    }
  }
}

# ==============================================================================
# SANDBOX TEST RECIPIENTS — SES sandbox mode requires every recipient address
# to be individually verified. Used for the DEV_EMAIL redirect target and any
# other addresses you want to test delivery to before requesting production
# access.
# ==============================================================================
resource "aws_ses_email_identity" "sandbox_recipients" {
  for_each = toset(var.sandbox_test_recipients)
  email    = each.value
}

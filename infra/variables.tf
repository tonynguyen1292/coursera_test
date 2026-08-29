variable "project_name" {
  description = "Prefix for resource names and the value of the Project tag."
  type        = string
  default     = "wa-mining"
}

variable "region" {
  description = "Region for the bucket and the budget. CloudFront is global."
  type        = string
  default     = "ap-southeast-2"
}

variable "api_origin_domain" {
  description = <<-EOT
    Host that CloudFront proxies /api/* to. Today this is the existing Netlify
    deployment, which means the AWS front end is fully functional before any
    AWS backend exists. When the Lambda/API Gateway tier lands, changing this
    one value repoints the API with no frontend rebuild -- the whole reason
    the API is a second CloudFront origin rather than a cross-origin fetch.
    Host only, no scheme and no trailing slash.
  EOT
  type        = string
  default     = "wa-mining.netlify.app"

  validation {
    condition     = !can(regex("^https?://", var.api_origin_domain))
    error_message = "Give the host only, without a scheme (e.g. wa-mining.netlify.app)."
  }
}

variable "budget_notification_email" {
  description = <<-EOT
    Where budget alerts go. Required: this stack refuses to stand up billable
    resources without somewhere to shout. AWS emails a subscription
    confirmation the first time -- the alarm is inert until it is accepted.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "monthly_budget_usd" {
  description = <<-EOT
    Monthly cost ceiling for the alarm, in USD. This stack should cost
    approximately nothing -- CloudFront's 1 TB/month free tier is perpetual,
    not a 12-month allowance, and S3 at this size is cents. A low number is
    the point: the alarm exists to catch a mistake, so it should fire long
    before the bill matters.
  EOT
  type        = number
  default     = 5

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "Budget must be greater than zero."
  }
}

variable "price_class" {
  description = <<-EOT
    CloudFront edge coverage. PriceClass_All is every edge location;
    PriceClass_100 is North America and Europe only and is cheaper per GB.
    Defaulting to All because the audience for this demo is in Australia,
    which PriceClass_100 excludes -- the cheaper option would make the site
    slower for exactly the people meant to see it.
  EOT
  type        = string
  default     = "PriceClass_All"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "Must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}

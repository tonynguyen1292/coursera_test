output "site_url" {
  description = "The live site. Open this after the first deploy."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket_name" {
  description = "Target for `aws s3 sync` of the built frontend bundle."
  value       = aws_s3_bucket.frontend.id
}

output "distribution_id" {
  description = "Needed to invalidate the cache after a deploy."
  value       = aws_cloudfront_distribution.site.id
}

output "deploy_command" {
  description = <<-EOT
    Copy-paste deploy. Build with VITE_API_BASE_URL unset so the bundle falls
    back to same-origin and the /api/* behaviour does the routing.
  EOT
  value = join("\n", [
    "npm --prefix ../frontend ci && npm --prefix ../frontend run build",
    "aws s3 sync ../frontend/dist s3://${aws_s3_bucket.frontend.id} --delete",
    "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.site.id} --paths '/*'",
  ])
}

output "api_origin" {
  description = "Where /api/* currently goes. Change var.api_origin_domain to repoint it."
  value       = var.api_origin_domain
}

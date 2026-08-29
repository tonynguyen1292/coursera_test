# Origin Access Control -- the current mechanism for letting CloudFront read
# a private bucket. It supersedes Origin Access Identity, which is legacy and
# does not support SSE-KMS.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-frontend-oac"
  description                       = "CloudFront to the private frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.project_name}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless paths to /index.html (default behaviour only)"
  publish = true
  code    = file("${path.module}/functions/spa-rewrite.js")
}

# AWS-managed policies, looked up by name rather than pasted as UUIDs so the
# intent is readable and the ids cannot drift.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Forwards everything the viewer sent EXCEPT Host. That exception matters:
# the API origin is a different host from the distribution, and forwarding
# the CloudFront Host header would make the origin fail to route the request
# to the right site.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.project_name} frontend + API seam"
  default_root_object = "index.html"
  price_class         = var.price_class

  # Origin 1: the private bucket holding the built React bundle.
  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Origin 2: whatever currently serves the API. Pointing this at the live
  # Netlify deployment means the browser only ever talks to the CloudFront
  # domain, so requests are same-origin and no CORS headers are needed
  # anywhere -- the frontend bundle is byte-identical to the one Netlify
  # builds, because client.ts falls back to window.location.origin when
  # VITE_API_BASE_URL is unset.
  origin {
    origin_id   = "api"
    domain_name = var.api_origin_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Static bundle: cache hard, and rewrite client-side routes.
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  # API: never cache, forward everything the viewer sent, and allow the write
  # verbs so this behaviour does not have to be revisited when the API grows
  # past read-only.
  #
  # This is the seam. When the Lambda/API Gateway tier lands, only
  # var.api_origin_domain changes -- no frontend rebuild, no redeploy of the
  # bundle, no CORS to introduce.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # The default *.cloudfront.net certificate. Note that minimum_protocol_version
  # cannot be set alongside it -- CloudFront pins the policy for its own
  # certificate and the provider rejects the combination. It becomes settable
  # (and worth setting to TLSv1.2_2021) at the same time a custom domain
  # arrives (WMDP2-20), which needs an acm_certificate_arn issued in us-east-1
  # plus an aliases list -- see the provider alias in versions.tf.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Deliberately no custom_error_response block. See the comment in
  # functions/spa-rewrite.js: those apply distribution-wide and would rewrite
  # genuine API 404s into the app shell.
}

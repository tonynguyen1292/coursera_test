data "aws_caller_identity" "current" {}

# S3 bucket names are globally unique across every AWS account on earth, so
# "wa-mining-frontend" is long gone. Suffixing with the account id keeps the
# name deterministic (no random_id in state to churn) while guaranteeing it
# is ours.
locals {
  bucket_name = "${var.project_name}-frontend-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "frontend" {
  bucket = local.bucket_name
}

# The bucket is never a website endpoint and never public. Viewers reach it
# only through CloudFront, which authenticates with Origin Access Control.
# S3 static-website hosting would require a public bucket and would bypass
# the distribution entirely -- a second, unprotected front door to the same
# objects.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning is on so a bad `aws s3 sync --delete` is recoverable. The
# lifecycle rule below stops that turning into unbounded storage growth.
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # Every deploy replaces the whole bundle, so old versions pile up fast.
  # Thirty days is long enough to roll back a bad release and short enough
  # that the bucket never becomes a cost line.
  rule {
    id     = "expire-noncurrent-bundles"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.frontend]
}

# Grants exactly one thing: this one distribution may read objects. The
# SourceArn condition is what makes it specific -- without it, any CloudFront
# distribution in any AWS account could read the bucket.
data "aws_iam_policy_document" "frontend_oac" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_oac.json

  # The policy names the distribution and the distribution names the bucket.
  # Terraform resolves the cycle on its own, but the public access block must
  # land first or S3 can briefly reject the policy.
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

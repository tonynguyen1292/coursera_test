terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Sydney. There is no Perth region; ap-southeast-2 is the closest. CloudFront
# itself is global and does not live in a region, so this only governs the
# bucket and the budget.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Repo      = "WA_Mining"
    }
  }
}

# Kept for later, not used yet. The moment a custom domain is added
# (WMDP2-20), its ACM certificate MUST be issued in us-east-1 -- CloudFront
# reads certificates from that region and nowhere else, regardless of where
# the rest of the stack lives. Declaring the alias now means adding the
# certificate later is a resource, not a refactor.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Repo      = "WA_Mining"
    }
  }
}

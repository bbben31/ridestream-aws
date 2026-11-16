# Credentials come from the environment, never from this file:
# on your workstation, `export AWS_PROFILE=ridestream-dev` after `aws sso login`.

provider "aws" {
  region = var.aws_region

  # Every resource that supports tags gets these three (ADR-005).
  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}

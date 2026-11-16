# Which Terraform and which providers this configuration needs.
# The exact provider versions that were installed are recorded in
# .terraform.lock.hcl, which is committed.

terraform {
  # 1.11 is the first release where S3 state locking without DynamoDB
  # (use_lockfile) is generally available. See ADR-005.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x, never 7.x without a decision
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

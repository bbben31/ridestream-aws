variable "aws_region" {
  description = "AWS region for every resource."
  type        = string
  default     = "eu-west-2"
}

variable "project" {
  description = "Project name: first part of every resource name, and the Project tag."
  type        = string
  default     = "ridestream"
}

variable "env" {
  description = "Environment name: second part of every resource name, and the Env tag."
  type        = string
  default     = "dev"
}

variable "github_sub_prefix" {
  description = "Start of the OIDC subject claim GitHub issues for this repository. Read it with: gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string

  # Repositories created after 15 July 2026 use the immutable format, with
  # the numeric owner and repository IDs after each name. Only that format
  # is accepted: a name-only subject could be reissued to a new owner of a
  # recycled name.
  validation {
    condition     = can(regex("^repo:[^@/:]+@[0-9]+/[^@/:]+@[0-9]+$", var.github_sub_prefix))
    error_message = "Expected the immutable format: repo:OWNER@OWNER-ID/REPO@REPO-ID."
  }
}

variable "github_environment" {
  description = "GitHub environment whose jobs may assume the deploy role."
  type        = string
  default     = "dev"
}

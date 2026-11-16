# The role `terraform apply` uses in the pipeline. Only jobs that run in
# the GitHub environment (and so passed its approval) can assume it.
#
# Permissions, in three layers (ADR-007):
#   1. PowerUserAccess: every service except IAM, Organizations and Account.
#   2. The policy below: IAM, but only for ridestream-dev-* roles and
#      policies, and only if the role carries the workload boundary.
#   3. Explicit denies, so the pipeline can't change what this directory
#      created: these roles, the boundary, the OIDC provider, the state
#      bucket's settings and history.

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    sid     = "GitHubEnvironment"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["${var.github_sub_prefix}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${local.name_prefix}-github-deploy"
  description          = "Assumed by GitHub Actions jobs in the ${var.github_environment} environment to run terraform apply."
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "deploy_power_user" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

locals {
  workload_roles    = "${local.iam_arn}:role/${local.name_prefix}-*"
  workload_policies = "${local.iam_arn}:policy/${local.name_prefix}-*"

  # What this directory creates in IAM. The pipeline may read these and
  # nothing else.
  bootstrap_iam = [
    "${local.iam_arn}:role/${local.name_prefix}-github-*",
    "${local.iam_arn}:policy/${local.name_prefix}-github-*",
    "${local.iam_arn}:policy/${local.name_prefix}-workload-boundary",
    aws_iam_openid_connect_provider.github.arn,
  ]
}

data "aws_iam_policy_document" "deploy_iam" {
  #checkov:skip=CKV_AWS_356:Only the read-only statement (iam:Get*, iam:List*) uses "*". Terraform must read IAM to plan, and list actions accept no narrower resource.
  # Terraform reads every resource before it plans a change.
  statement {
    sid       = "ReadIam"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Creating a role, or changing what a role is allowed to do, is only
  # permitted when the role carries the workload boundary. That is what
  # stops the pipeline from creating a role more powerful than itself.
  statement {
    sid    = "ChangeBoundedRolePermissions"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePermissionsBoundary",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [local.workload_roles]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  # Actions that don't change a role's permissions, so IAM offers no
  # boundary condition for them.
  statement {
    sid    = "MaintainRoles"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = [local.workload_roles]
  }

  statement {
    sid    = "ManagePolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [local.workload_policies]
  }

  # Handing a role to a service (a Lambda function's execution role, for
  # example) needs PassRole on that role.
  statement {
    sid       = "PassRolesToServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.workload_roles]
  }

  # An explicit Deny beats every Allow, including the ones above whose
  # ridestream-dev-* pattern also matches the bootstrap names.
  statement {
    sid         = "ProtectBootstrapIam"
    effect      = "Deny"
    not_actions = ["iam:Get*", "iam:List*"]
    resources   = local.bootstrap_iam
  }

  statement {
    sid    = "ProtectStateBucketSettings"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketAcl",
    ]
    resources = [aws_s3_bucket.state.arn]
  }

  # Old state versions are the recovery path: the pipeline can't purge them.
  statement {
    sid       = "ProtectStateHistory"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  # This configuration's own state is changed by hand only.
  statement {
    sid       = "ProtectBootstrapState"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${local.bootstrap_state_key}*"]
  }
}

resource "aws_iam_policy" "deploy_iam" {
  name        = "${local.name_prefix}-github-deploy-iam"
  description = "IAM permissions and guardrails for the GitHub deploy role."
  policy      = data.aws_iam_policy_document.deploy_iam.json
}

resource "aws_iam_role_policy_attachment" "deploy_iam" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_iam.arn
}

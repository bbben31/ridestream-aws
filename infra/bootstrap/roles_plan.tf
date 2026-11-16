# The role pull request checks use: it can read, so `terraform plan` works,
# and it can change nothing except the dev state lock.

data "aws_iam_policy_document" "plan_trust" {
  statement {
    sid     = "GitHubPullRequests"
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

    # Exact match, no wildcard: only jobs of this repository that were
    # started by a pull_request event and use no GitHub environment.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["${var.github_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${local.name_prefix}-github-plan"
  description          = "Assumed by GitHub Actions on pull requests to run terraform plan. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600 # 1 hour, the minimum
}

# AWS-managed policy: Get*, List* and Describe* across the account.
resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# `terraform plan` takes the state lock, which means creating and deleting
# one object next to the state file. That is the only write this role has.
data "aws_iam_policy_document" "plan_state_lock" {
  statement {
    sid       = "DevStateLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${local.dev_state_key}.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state_lock.json
}

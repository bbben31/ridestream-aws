# Permissions boundary for every role the pipeline creates (Lambda
# execution roles, the simulator task role, and so on).
#
# A boundary grants nothing. It is a ceiling: a role can do only what BOTH
# its own policies AND its boundary allow. Each role's own policy stays
# least-privilege; this only caps the worst case.
#
# The list is the services in docs/architecture.md. When a role's policy
# looks right but the call is denied, check here first.

data "aws_iam_policy_document" "workload_boundary" {
  #checkov:skip=CKV_AWS_111:A boundary is a ceiling, not a grant. Each role's own policy names its resources.
  #checkov:skip=CKV_AWS_356:Same reason as CKV_AWS_111.
  #checkov:skip=CKV_AWS_109:Same reason as CKV_AWS_111.
  statement {
    sid    = "ServicesWorkloadsMayUse"
    effect = "Allow"
    actions = [
      "athena:*",
      "cloudwatch:*",
      "dynamodb:*",
      "ecr:*",
      "events:*",
      "firehose:*",
      "geo:*",
      "geo-routes:*",
      "glue:BatchGet*",
      "glue:Get*",
      "kinesis:*",
      "lambda:InvokeFunction",
      "logs:*",
      "s3:*",
      "sns:*",
      "sqs:*",
      "xray:*",
    ]
    resources = ["*"]
  }

  # No workload has a reason to touch Terraform state.
  statement {
    sid     = "NeverTerraformState"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${local.name_prefix}-workload-boundary"
  description = "Permissions boundary required on every role created by the GitHub deploy role."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}

# Lets AWS accept sign-in tokens issued by GitHub Actions.
#
# An account can hold only one provider per URL. It grants nothing by
# itself: access comes from the trust policies of the roles that name it
# (roles_plan.tf and roles_deploy.tf).

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The audience ("aud" claim) a token must carry. The official
  # aws-actions/configure-aws-credentials action asks GitHub for this value.
  client_id_list = ["sts.amazonaws.com"]

  # No thumbprint_list: AWS checks GitHub's certificate against its own
  # trusted certificate authorities, and the argument is optional since
  # AWS provider 5.81.
}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
}

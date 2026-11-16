# Values used by more than one file.

# Who am I signed in as? Gives the account ID at run time, so it is never
# written into a file.
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.env}" # ridestream-dev
  account_id  = data.aws_caller_identity.current.account_id
  iam_arn     = "arn:aws:iam::${local.account_id}"

  # State file locations inside the bucket. envs/dev uses dev_state_key in
  # its backend block (session 3); this configuration uses the bootstrap one.
  dev_state_key       = "dev/terraform.tfstate"
  bootstrap_state_key = "bootstrap/terraform.tfstate"
}

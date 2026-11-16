# TFLint settings, used by the pre-commit hook and (from session 3) by CI.
# Download the plugins once per machine with: tflint --init

# Rules about the Terraform language itself: unused variables, missing
# version constraints, deprecated syntax.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Rules that know AWS: invalid instance types, malformed ARNs and similar
# mistakes that `terraform validate` can't see.
plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

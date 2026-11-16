# Bootstrap

The few resources that must exist before the pipeline can run, and that the
pipeline is not allowed to change. Applied by hand, by a person signed in
through IAM Identity Center. Never destroyed.

| File | Creates |
| --- | --- |
| `state.tf` | The S3 bucket for Terraform state: versioned, encrypted, private, TLS only |
| `oidc.tf` | The GitHub Actions OIDC identity provider |
| `roles_plan.tf` | `ridestream-dev-github-plan`: read-only, for pull request checks |
| `roles_deploy.tf` | `ridestream-dev-github-deploy`: for `terraform apply` in the `dev` GitHub environment |
| `boundary.tf` | `ridestream-dev-workload-boundary`: the ceiling for every role the pipeline creates |

Why two roles and a boundary: [ADR-007](../../docs/adr/007-github-oidc-roles.md).

## State

This configuration's state is in the bucket it creates, under
`bootstrap/terraform.tfstate`. The dev environment's state is under
`dev/terraform.tfstate`.

The bucket name ends in random characters and is not written in the code.
Find it with:

```
aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'ridestream-dev-tfstate-')].Name" \
  --output text
```

## Working on it

```
aws sso login --profile ridestream-dev
export AWS_PROFILE=ridestream-dev
cd infra/bootstrap
terraform init -backend-config="bucket=<bucket name>"
terraform plan
```

Read the plan, then run `terraform apply` yourself. Never run
`terraform destroy` here: every other state file lives in this bucket, and
the bucket has `prevent_destroy` set for that reason.

## If GitHub sign-in is refused

The roles trust one exact subject each. Compare the trust policy with what
GitHub issues for the repository:

```
gh api repos/bbben31/ridestream-aws/actions/oidc/customization/sub --jq .sub_claim_prefix
```

The value must equal `github_sub_prefix` in `github.auto.tfvars`. Renaming
or transferring the repository changes it.

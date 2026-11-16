# Values the next steps need. Read one with: terraform output -raw <name>
# The ARNs contain the account ID, so they are shown in your terminal and
# stored as GitHub variables in session 3, never written into a file.

output "state_bucket_name" {
  description = "S3 bucket that holds Terraform state. Passed to terraform init as the backend bucket."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Role for pull request checks (terraform plan)."
  value       = aws_iam_role.plan.arn
}

output "deploy_role_arn" {
  description = "Role for jobs in the GitHub environment (terraform apply)."
  value       = aws_iam_role.deploy.arn
}

output "workload_boundary_arn" {
  description = "Set as permissions_boundary on every IAM role created in infra/envs."
  value       = aws_iam_policy.workload_boundary.arn
}

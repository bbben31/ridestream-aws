# RideStream — rules for Claude Code

## About
Ride-hailing location platform on AWS, rebuilt from scratch by
Ben-Salem Banguena as a portfolio project. I must be able to explain
every line, so teach as you go. An Azure version will follow, so keep
business logic free of AWS imports.

## Environment
- Ubuntu 26.04, AWS region eu-west-2, AWS profile ridestream-dev (SSO)
- Terraform with the AWS provider; Python 3.14 (Lambda runtime python3.14)
- Powertools for AWS Lambda; pytest + moto for tests; ruff for linting
- GitHub Actions with OIDC: no stored AWS keys

## Rules
- Run terraform plan only. Never run terraform apply or destroy: I do that.
- Never write secrets, access keys or account IDs into files.
- When I share code I wrote, review it before rewriting it, and explain why.
- Keep changes small: one task per session.
- Business logic goes in plain Python modules with no boto3 or Lambda
  imports; AWS code stays in thin adapters and handlers.
- Follow the conventions: Conventional Commits, ridestream-dev-<component>
  names, Project/Env/ManagedBy tags on every resource.
- Record design decisions in docs/adr/.
- At the end of each session, update docs/handoff.md: done, decisions,
  open problems, next step.

## Commands
- make fmt | make lint | make test | make plan ENV=dev

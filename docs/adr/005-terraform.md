# ADR-005: Use Terraform for all infrastructure

- Status: Accepted (2026-11-10)
- Date: 2026-11-10
- Related: ADR-001, NFR-07, NFR-12, project conventions

## Context

Every RideStream resource must be defined in code and deployed by GitHub
Actions with OIDC, never by hand. The dev environment is created and
destroyed every building session, so a full rebuild must be fast and
repeatable (NFR-12). Every resource carries the `Project`, `Env` and
`ManagedBy` tags.

Two plans beyond v1 also bear on the choice:

- **Phase 2 (from February 2027):** the same system on Azure, compared
  build for build with the AWS version.
- **Week 12:** the HashiCorp Terraform Associate exam.

## Options

1. **Terraform (HashiCorp).** One language (HCL) and one workflow
   (`plan`, then `apply`) for AWS and Azure. The AWS provider sets tags on
   every resource through `default_tags`. A `plan` shows exactly what will
   change before anything does, which suits a pull request comment. State
   must be stored and locked; the S3 backend now locks natively, without a
   DynamoDB table. Licensed under the Business Source License since 2023,
   which allows RideStream's use.
2. **OpenTofu.** The open-source fork of Terraform, compatible with it for
   RideStream's needs. Rejected only because the exam, the job market and
   most documentation use Terraform. Switching later is straightforward.
3. **AWS CloudFormation.** Native, with state managed by AWS and no backend
   to run. But it only covers AWS, so the Azure version would need a
   different tool, and the comparison would partly be a comparison of
   tools. Its preview of changes (change sets) is less direct than a
   Terraform plan.
4. **AWS CDK.** Infrastructure in Python, compiled to CloudFormation. Strong
   for application teams, but AWS-only like CloudFormation, and it adds a
   layer between the code and what is deployed.

## Decision

**Use Terraform for all infrastructure, with this setup:**

- **Versions.** Require Terraform 1.11 or later (native S3 locking became
  generally available in 1.11). Pin the AWS provider to a major version.
- **State.** One S3 bucket, encrypted, versioned, with public access
  blocked, and `use_lockfile = true` in the backend. No DynamoDB lock table.
  The state key is per environment (`dev/terraform.tfstate`).
- **Bootstrap.** The state bucket and the GitHub OIDC deploy role are
  created once by a small separate configuration (`infra/bootstrap/`) that
  you apply by hand. They are never destroyed with dev, which is why NFR-07
  says "only the state bucket remains".
- **Bucket name.** It must be globally unique, so it ends with a random
  suffix. The account ID is never written into a file.
- **Tags.** `default_tags` in the AWS provider sets `Project=ridestream`,
  `Env` and `ManagedBy=terraform` on every resource. Names follow
  `ridestream-dev-<component>`.
- **Layout.** Reusable modules in `infra/modules/` (`data`, `ingest`, `api`,
  `auth`, `events`, `analytics`, `observability`), wired together in
  `infra/envs/dev/`.
- **Workflow.** Every pull request runs `fmt`, `validate`, tflint, checkov
  and `plan`, and posts the plan as a comment. Merging to `main` runs
  `apply` after your approval in a GitHub environment. Claude Code may run
  `plan`, never `apply` or `destroy`.

## Consequences

**Positive**

- The same tool and workflow for the Azure version, so phase 2 compares the
  clouds, not the tools.
- The plan-then-apply workflow gives a reviewable record of every change.
- Daily practice for the Terraform Associate exam.
- Tags can't be forgotten: the provider applies them.

**Negative**

- **State is your responsibility.** A lost or corrupted state file means
  re-importing resources. Versioning on the state bucket is the recovery
  path.
- **A bootstrap step outside the pipeline.** The state bucket and deploy
  role can't create themselves. They are created once, by hand, and
  documented in the README.
- **Provider lag.** A brand-new AWS feature can reach the Terraform provider
  after CloudFormation. Nothing RideStream needs is affected today.
- **Licence.** The Business Source License restricts building competing
  products, not using Terraform. If that ever changes, OpenTofu is a
  drop-in path.

## References

Checked on 10 November 2026.

- S3 backend and native locking: https://developer.hashicorp.com/terraform/language/backend/s3
- Terraform 1.11 upgrade guide (S3 native locking GA): https://developer.hashicorp.com/terraform/language/v1.11.x/upgrade-guides
- AWS Prescriptive Guidance, Terraform backend: https://docs.aws.eu/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html

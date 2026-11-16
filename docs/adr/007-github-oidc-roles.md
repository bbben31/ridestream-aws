# ADR-007: Two GitHub OIDC roles and a permissions boundary

- Status: Proposed
- Date: 2026-11-16
- Related: ADR-005 (refines its "OIDC deploy role"), NFR-11, project conventions

## Context

ADR-005 says GitHub Actions deploys with OIDC and that `infra/bootstrap/`
creates "the OIDC deploy role". Writing it raised three questions that
ADR-005 doesn't answer.

1. **Who may assume it.** The pipeline has two jobs with very different
   needs: `terraform plan` on every pull request, and `terraform apply`
   after approval in the `dev` GitHub environment. The repository is
   public.
2. **What it may do.** The pipeline creates IAM roles for Lambda functions
   and the simulator task. A principal that can create roles and attach
   policies can give itself any permission, so "everything except admin"
   means little without a further control.
3. **Which token subject to trust.** GitHub changed the default subject
   (`sub`) claim in 2026. Repositories created after 15 July 2026, which
   includes this one, get `repo:OWNER@OWNER-ID/REPO@REPO-ID:…` with
   immutable numeric IDs, not `repo:OWNER/REPO:…`.

## Options

1. **One role with AdministratorAccess, trusted for the whole repository**
   (`repo:…:*`). The usual tutorial setup. Any workflow run, including a
   pull request that edits the workflow file, gets administrator rights
   before anyone approves anything. The approval gate would be decoration.
2. **One role, trusted only for the `dev` environment.** Safe for apply,
   but pull request jobs couldn't sign in, so there would be no plan
   comment, or the plan job would have to run inside the gated environment.
3. **Two roles: read-only for pull requests, deploy for the environment.**
   Each trust policy matches one exact subject. A pull request can read the
   account and nothing else.
4. **For the deploy role's permissions:** (a) AdministratorAccess;
   (b) a hand-written list of every action the project needs;
   (c) PowerUserAccess plus IAM limited to project-named roles that carry
   a permissions boundary.
   - (a) is simple, and defensible in a single-purpose sandbox account, but
     the pipeline could then rewrite its own trust policy or delete the
     state bucket.
   - (b) is the ideal end state, but the list isn't knowable before the
     services are built, and every new resource type would stall on a
     by-hand bootstrap change.
   - (c) keeps day-to-day work unblocked and closes the escalation path.

## Decision

**Option 3 with 4(c).**

- **`ridestream-dev-github-plan`.** Trusts exactly
  `<prefix>:pull_request`. Has the AWS-managed `ReadOnlyAccess` policy, and
  may create and delete one object: the dev state lock.
- **`ridestream-dev-github-deploy`.** Trusts exactly
  `<prefix>:environment:dev`. Has `PowerUserAccess` (all services except
  IAM, Organizations and Account) and a project policy that:
  - allows creating roles named `ridestream-dev-*`, and changing their
    permissions, only when the role carries the
    `ridestream-dev-workload-boundary` permissions boundary;
  - allows managing policies named `ridestream-dev-*` and passing those
    roles to services;
  - denies every change to what bootstrap created: both roles, their
    policies, the boundary, the OIDC provider, the state bucket's settings,
    old state versions and bootstrap's own state file.
- **`ridestream-dev-workload-boundary`.** The ceiling for every role the
  pipeline creates: the services in `docs/architecture.md`, no IAM, and no
  access to the state bucket.
- **Subject.** The prefix is read from GitHub
  (`gh api repos/OWNER/REPO/actions/oidc/customization/sub`), kept in
  `github.auto.tfvars`, and matched with `StringEquals`. Only the immutable
  format is accepted. The audience must be `sts.amazonaws.com`.
- **Bootstrap stays outside the pipeline.** Changes to it are applied by
  hand with the Identity Center administrator session.

## Consequences

**Positive**

- A pull request, even one that changes the workflow, can't change
  anything in AWS. The approval gate is enforced by AWS, not only by
  GitHub.
- The pipeline can't raise its own permissions, remove its guardrails or
  create IAM users and access keys.
- If the GitHub account or repository name were ever recycled, the new
  owner's tokens would carry different IDs and be refused.

**Negative**

- **Every IAM role in `infra/envs/` must set `permissions_boundary`.**
  Forgetting it fails the apply with AccessDenied. tflint or a checkov
  custom rule could catch this earlier; not planned yet.
- **A new AWS service means a by-hand bootstrap change** to add it to the
  boundary. A correct role policy that is still denied usually means this.
- **The plan role can read everything in the account**, including data in
  DynamoDB and S3 and the state files. Acceptable because all data is
  simulated and no secrets are stored anywhere. It would not be acceptable
  as-is for an account holding real customer data.
- **PowerUserAccess is still broad** outside IAM: the deploy role could
  create any non-IAM resource. Narrowing it to the services actually used
  is week 10 hardening, informed by IAM Access Analyzer.
- **Renaming or transferring the repository breaks sign-in** until
  `github_sub_prefix` is updated and bootstrap is applied again.
- Pull requests from forks get no OIDC token from GitHub, so outside
  contributors would see no plan comment. No change is needed for that.

## References

Checked on 16 November 2026.

- GitHub changelog, immutable subject claims: https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/
- GitHub OpenID Connect reference: https://docs.github.com/en/actions/reference/security/oidc
- IAM permissions boundaries: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html

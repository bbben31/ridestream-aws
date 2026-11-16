# Infrastructure

All RideStream infrastructure is Terraform (ADR-005).

| Directory | Purpose | Applied by |
| --- | --- | --- |
| `bootstrap/` | State bucket, GitHub OIDC provider, plan and deploy roles, workload permissions boundary. Created once, never destroyed. See its README. | By hand |
| `modules/` | Reusable modules: `data`, `ingest`, `api`, `auth`, `events`, `analytics`, `observability`. | Not applied directly |
| `envs/dev/` | The dev environment: wires the modules together. | GitHub Actions |

`bootstrap/` exists. The other directories are added as each part is built.

Every IAM role created under `envs/` must set `permissions_boundary` to the
`ridestream-dev-workload-boundary` policy, or the pipeline is refused
permission to create it (ADR-007).

# Infrastructure

All RideStream infrastructure is Terraform (ADR-005).

| Directory | Purpose | Applied by |
| --- | --- | --- |
| `bootstrap/` | State bucket, GitHub OIDC provider, deploy role. Created once, never destroyed. | By hand |
| `modules/` | Reusable modules: `data`, `ingest`, `api`, `auth`, `events`, `analytics`, `observability`. | Not applied directly |
| `envs/dev/` | The dev environment: wires the modules together. | GitHub Actions |

The directories are added as each part is built. None exists yet.

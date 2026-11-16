# RideStream

A ride-hailing location platform on AWS. Simulated taxis stream their
positions, riders book the nearest available taxi inside a London service
area, and every trip feeds an analytics store.

> **Status: in progress.** The design is complete. The repository skeleton
> and delivery pipeline are being built now. Nothing is deployed yet.

## Design

- [Requirements](docs/requirements.md)
- [Architecture](docs/architecture.md)
- [Architecture decision records](docs/adr/)

| ADR | Decision |
| --- | --- |
| [001](docs/adr/001-portable-business-logic.md) | Business logic kept free of cloud SDKs (ports and adapters) |
| [002](docs/adr/002-database-dynamodb.md) | DynamoDB for taxis and trips |
| [003](docs/adr/003-kinesis-ingestion.md) | Kinesis Data Streams for position ingestion |
| [004](docs/adr/004-service-area-and-routing.md) | Service-area check in code; Amazon Location for driving times |
| [005](docs/adr/005-terraform.md) | Terraform for all infrastructure |
| [006](docs/adr/006-simulator-runtime.md) | One simulator image, local or on Fargate |
| [007](docs/adr/007-github-oidc-roles.md) | Two GitHub OIDC roles (plan, deploy) and a permissions boundary |

## Repository layout

```
docs/                  requirements, architecture, ADRs, handoff notes
infra/                 Terraform (see infra/README.md)
src/ridestream_core/   business logic, no cloud imports
src/ridestream_aws/    AWS adapters (boto3)
tests/                 pytest tests
```

## Development

Requires Python 3.14, [uv](https://docs.astral.sh/uv/), Terraform 1.11 or
later and [pre-commit](https://pre-commit.com/).

```
uv sync              # create the virtual environment
pre-commit install   # run the checks on every commit
make help            # list the commands
make lint test       # what CI runs
```

## Background

RideStream is a new design of the idea behind a 2023 IIT Madras group
capstone, the "Location Based Taxi Aggregator". What that system did, and
how RideStream differs, is recorded in
[docs/baseline-2023.md](docs/baseline-2023.md).

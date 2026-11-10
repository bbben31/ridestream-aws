# ADR-002: Use DynamoDB for taxi positions and trips

- Status: Accepted (2026-11-10)
- Date: 2026-11-09
- Related: ADR-001 (portability), FR-06, FR-10, FR-12, FR-19, NFR-01,
  NFR-05, NFR-07, `docs/requirements.md`

## Context

RideStream stores two kinds of operational data:

1. **Taxis:** the latest position, status and type of each of about 1,000
   taxis. Written 200 times a second (NFR-01), read on every booking to find
   candidates near a pickup point (FR-10).
2. **Trips:** created on each booking, updated a few times through the
   lifecycle, read by id and by rider history (FR-18, FR-19).

The deciding requirements are:

- **An atomic claim (FR-12, NFR-05).** Two bookings must never take the same
  taxi. The database must offer a conditional write: "set `ON_TRIP` only if
  the status is still `AVAILABLE`."
- **Proximity search (FR-10).** Find available taxis of a given type near a
  point.
- **Cost (NFR-07).** About $0 when destroyed and ≤ $1/day when deployed but
  idle. The dev environment is created and destroyed every session.
- **Fixed constraints.** Lambdas run outside a VPC with no NAT gateway. No
  stored secrets. Everything is deployed by Terraform from GitHub Actions
  with OIDC.

Background: the 2023 capstone ran MongoDB on a self-managed EC2 instance.
A self-managed server doesn't fit the constraints above, so the choice is
between three managed options.

## Options

### A. Amazon DynamoDB (on-demand)

- Serverless, with IAM authentication and a public AWS endpoint. Lambdas
  reach it without a VPC, and nothing needs a password.
- Billed per request, so it costs nothing when idle. On-demand prices were
  cut by 50 % in November 2024. The US East example price is $0.625 per
  million writes.
- Conditional writes (`ConditionExpression`) are built in. The atomic claim
  is a single `UpdateItem` call.
- **No geospatial queries.** Proximity search must be built with geohash
  cells, and query patterns must be designed up front.
- A native Terraform resource. Created and destroyed in seconds.

### B. Amazon DocumentDB (MongoDB-compatible)

- Has native proximity queries (`$nearSphere`, `$geoNear`) on a 2dsphere
  index. Only GeoJSON points are indexed, which is all RideStream needs for
  taxis.
- **Clusters only run inside a VPC.** Lambdas would have to join the VPC.
  They would then need VPC endpoints (billed per hour, per AZ) or a NAT
  gateway to reach Kinesis, EventBridge and Amazon Location. That breaks a
  fixed decision.
- **No scale to zero.** The serverless option has a minimum of 0.5 DCU. At
  the US East example rate of $0.0822 per DCU-hour, that's about $30 a month
  if left running, before storage and I/O. The ≤ $1/day idle target only
  holds if the cluster is destroyed every session, and creating a cluster
  takes far longer than creating a table.
- Database connections (pooling and limits per DCU) have to be managed from
  Lambda.

### C. MongoDB Atlas (on AWS, eu-west-2)

- The richest geospatial support of the three, and the only option that
  runs unchanged on both AWS and Azure.
- **The free tier (M0) is capped at 100 operations per second.** NFR-01
  alone needs 200 writes per second. The next tier, Flex, is capped at
  $30 a month with a hard limit of 500 ops/s. Above that, dedicated
  clusters start at about $57 a month.
- Supports AWS IAM authentication, so the Lambdas need no password. But:
  - Lambdas outside a VPC have no fixed IP addresses, so the Atlas IP
    access list would have to allow `0.0.0.0/0` and rely on authentication
    alone.
  - The `mongodbatlas` Terraform provider authenticates with Atlas API
    credentials, which would have to be stored in GitHub. That breaks
    "no stored secrets".
- A second vendor: separate billing outside AWS Budgets and the
  `Project=ridestream` cost tags, a separate account, and another thing to
  explain in an "AWS" portfolio project.

## Decision

**Use DynamoDB in on-demand mode** for both taxis and trips.

- **Taxis table:** partition key `taxi_id`. Holds status, type, position and
  the geohash cell. A global secondary index (GSI) on the geohash cell
  serves the proximity search.
- **Trips table:** partition key `trip_id`. A GSI on `rider_id` with the
  creation time as sort key serves the trip history.
- **The atomic claim:** `UpdateItem` on the taxi with
  `ConditionExpression: status = AVAILABLE`. If the condition fails, the
  adapter's `claim()` returns `False`, and the core tries the next candidate
  (ADR-001).
- **Proximity search:** the core works out which geohash cells cover the
  search ring (ADR-001). The adapter queries the GSI for those cells. The
  table's key design stays in the adapter.

The full key design, geohash precision and index projections are settled in
week 3, when the ingestion Lambda is built.

## Why not the others

- **DocumentDB** solves proximity search natively, but forces the Lambdas
  into a VPC, adds VPC endpoints or a NAT gateway, has a running cost with no
  scale-to-zero, and is slow to create and destroy every session. The
  geospatial feature it offers is the one RideStream needs least: the
  geohash maths is a few dozen lines of tested Python in the core.
- **MongoDB Atlas** is the strongest option for portability, and that is a
  real argument against this decision. It is rejected because its free tier
  can't take the write load, its networking forces either an open access
  list or private networking that would put the Lambdas in a VPC, its
  Terraform provider
  needs stored credentials, and its billing sits outside AWS. ADR-001
  already keeps the business logic portable, so DynamoDB's lock-in is
  limited to one adapter.

## Consequences

**Positive**

- No servers, no VPC, no passwords: the database fits every fixed decision.
- Costs nothing when idle, and a table is created or destroyed in seconds,
  which suits the destroy-every-session rule.
- NFR-05 rests on one well-documented DynamoDB feature, conditional writes.
  The week 4 concurrency test proves it.
- Building the proximity search with geohash cells is good interview
  material: it shows how to design for access patterns rather than rely on
  a database feature.

**Negative**

- **Access patterns must be known in advance.** A new query, such as "trips
  by driver", may need a new GSI. The requirements list every query, which
  limits this risk.
- **Hot cells.** Central London cells hold more taxis than outer ones. At
  200 writes/s in total this is far below DynamoDB's per-partition limits,
  but the geohash precision must be chosen with it in mind (week 3).
- **Write cost at load.** 720,000 position writes an hour cost about $0.45
  at the US East example price. A GSI write can double that whenever an
  indexed or projected attribute changes. Mitigations to test in week 3:
  - project only the cell, status and type into the GSI, so it is written
    only when a taxi changes cell or status, not on every position update
  - in the ingestion Lambda, keep only the latest position per taxi in each
    batch
- **The Azure port needs a new adapter**, backed by a store with conditional
  writes. Which one is decided in phase 2, as the roadmap says.

## References

Prices are AWS's US East examples, checked on 9 November 2026. Confirm the
eu-west-2 rates in the AWS Pricing Calculator before NFR-07 is measured.

- DynamoDB on-demand pricing: https://aws.amazon.com/dynamodb/pricing/on-demand/
- DynamoDB on-demand price reduction (Nov 2024): https://aws.amazon.com/blogs/database/new-amazon-dynamodb-lowers-pricing-for-on-demand-throughput-and-global-tables
- DocumentDB geospatial queries: https://docs.aws.amazon.com/documentdb/latest/developerguide/geospatial.html
- DocumentDB connections from outside a VPC: https://docs.aws.amazon.com/documentdb/latest/developerguide/connect-from-outside-a-vpc.html
- DocumentDB pricing (serverless): https://aws.amazon.com/documentdb/pricing/
- MongoDB Atlas Free and Flex cluster limits: https://mongodb.com/docs/atlas/reference/free-shared-limitations/

# The 2023 baseline: IIT Madras cloud capstone

RideStream builds on the "Location Based Taxi Aggregator", the cloud
capstone of the IIT Madras Advanced Certification programme (group 1,
May 2023). It is a reference for what the system is expected to do, not a
template: RideStream's design decisions are made on their own merits in
the ADRs. This document records what the 2023 system did and how
RideStream differs. It is based on the group's report, architecture
diagram, code and CloudFormation templates.

## What the 2023 system did

| Component | Implementation |
| --- | --- |
| Simulator | Python on an EC2 `t2.micro` (Amazon Linux 2), started by hand over SSH. 50 taxis sent a position every second; 5 users every 5 seconds. |
| Stream | One Kinesis data stream, in `us-east-1`. |
| Ingestion handler | Lambda (Python 3.9), triggered by Kinesis. For each record it called the database handler Lambda synchronously. |
| Database handler | Lambda (Python 3.7) in a VPC. One function that routed every database operation by a `requestType` field. |
| Database | MongoDB 4.4 installed by hand on an EC2 `t2.micro`. A legacy `2d` index and `$near` found the nearest taxis. |
| Registration handler | Lambda with a public function URL. Registered taxis (name, plate number, type) and users (name, email). |
| Trip booking handler | Lambda with a public function URL. Given a user's email and a taxi type (`Basic`, `Deluxe`, `Luxury` or `All`), it returned the 3 nearest taxis to the user's last streamed position. |
| Infrastructure | Five CloudFormation stacks created by hand, plus manual console steps (VPC settings, function URLs, Kinesis trigger). Tested with Postman. |

Positions were plain numbers on an invented grid (50 ≤ x ≤ 60,
40 ≤ y ≤ 80), not real coordinates. Each taxi's and user's latest position
was overwritten; no history was kept.

## Ideas RideStream shares with 2023

- **The pipeline shape:** simulator → Kinesis → ingestion Lambda → database,
  with separate entry points for registration and booking.
- **Taxi types** `Basic`, `Deluxe` and `Luxury`, and the option to ask for
  any type (`All` in 2023).
- **Identities:** a taxi is identified by its plate number, a rider by email.
- **Latest position only** in the operational database. RideStream sends the
  full history to S3 for analytics instead.
- **Nearest taxi by distance** as the starting point of matching.
- **The simulator's movement model:** a random heading and distance at each
  step, turning back at the boundary.
- **Keeping database code apart from request handling** (the 2023 database
  handler). RideStream keeps the idea but makes it an in-process module
  rather than a separate Lambda (ADR-001).

## What RideStream changes

| # | 2023 | 2026 | Why | Where |
| --- | --- | --- | --- | --- |
| 1 | Booking returned the 3 nearest taxis. No assignment, no availability | One taxi is assigned and claimed atomically | Two riders could be sent the same taxi | FR-10–13, NFR-05, ADR-002 |
| 2 | No trip record | Trip lifecycle, cancellation, history | A booking needs a state and an owner | FR-14–19 |
| 3 | Public function URLs with no sign-in | API Gateway with Cognito and roles | Anyone could register or book | FR-01–03, NFR-06 |
| 4 | Lambda calling Lambda for every Kinesis record; failures ignored (the handler always returned success) | Batch processing in one function, partial-batch failure reporting, dead-letter queue | Lost records went unnoticed; one extra network hop and invocation per record | ADR-001, week 3 |
| 5 | MongoDB on EC2: listening on all addresses, port 27017 open, password and private IP hard-coded | DynamoDB with IAM authentication | No server to patch; no stored credentials | ADR-002 |
| 6 | Database Lambda inside a VPC | No VPC, no NAT gateway | Simpler and cheaper; nothing needs one | ADR-002 |
| 7 | IAM roles with `AdministratorAccess` | One least-privilege role per function | Limits the damage of any bug or leak | NFR-06 |
| 8 | Invented grid, legacy `2d` index | Real London latitude and longitude, geohash cells, a service-area geofence | Real data; the boundary is enforced by the system, not only by the simulator | FR-07, FR-10, ADR-004 |
| 9 | Simulator: taxis only moved north-east (heading 0–90°) and piled up at the boundary; a constant partition key (`Taxi`/`user`); one `PutRecord` per message | Movement in all directions; partition key = taxi id; batched writes | Realistic spread; ordering per taxi; room to scale past one shard | Week 3 |
| 10 | Users streamed their position; booking used the last one | The pickup point is sent with the booking | Less traffic; the rider chooses the pickup point | FR-08 |
| 11 | Geospatial index created on every booking request | Indexes defined in Terraform | Schema belongs in infrastructure code, not the request path | ADR-002 |
| 12 | Registration checked for duplicates, then inserted (two separate steps) | Conditional insert | Two simultaneous registrations could both succeed | FR-01–02 |
| 13 | CloudFormation by hand, console clicks, SSH with key pairs | Terraform, deployed by GitHub Actions with OIDC; no manual steps | Repeatable, reviewable, rebuilt every session | Week 2 |
| 14 | No tests, logging by `print`, no monitoring | pytest, Powertools, CloudWatch dashboard and alarms | Evidence that it works, and visibility when it doesn't | NFR-10, NFR-11 |
| 15 | Python 3.7 and 3.9, `us-east-1` hard-coded | Python 3.14, `eu-west-2` from configuration | Supported runtimes; London region | — |
| 16 | No notifications; analytics (SageMaker, QuickSight) designed but not built in the time available | SNS email on booking; Firehose, S3 and Athena | Completes the platform | FR-17, FR-22–23 |

## Scale

| | 2023 | 2026 target |
| --- | --- | --- |
| Taxis | 50, every second | 1,000, every 5 seconds |
| Records per second | about 51 | 200 (NFR-01) |

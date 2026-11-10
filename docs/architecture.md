# RideStream — architecture

Status: v1 design · Week 1 · 10 November 2026. Each element links back to
the requirements (`docs/requirements.md`) and the ADRs (`docs/adr/`).

The diagrams are written in Mermaid, which GitHub draws directly from this
file. They live in the repository next to the code, and every change to them
shows up in a pull request like any other change. A polished image with AWS
icons is planned for the README in week 10.

## 1. System overview

```mermaid
flowchart LR
    subgraph Producers
        SIM["Simulator<br/>laptop, or Fargate task for load tests<br/>(ADR-006)"]
    end

    subgraph Ingestion
        KDS[("Kinesis Data Streams<br/>1 shard, key = taxi_id<br/>(ADR-003)")]
        ING["Ingestion Lambda<br/>position + service-area check<br/>(ADR-003, ADR-004)"]
        FAIL[["SQS on-failure queue<br/>alarm if not empty"]]
    end

    subgraph Data
        TAXIS[("DynamoDB: taxis<br/>latest position, status,<br/>geohash cell, in_service_area")]
        TRIPS[("DynamoDB: trips<br/>lifecycle, history by rider")]
    end

    USERS["Riders, drivers, admins<br/>(API clients)"]

    subgraph API
        COG["Cognito user pool<br/>rider / driver / admin groups"]
        APIGW["API Gateway HTTP API<br/>JWT authorizer"]
        BOOK["API Lambdas<br/>bookings, trips, admin"]
        LOC["Amazon Location<br/>route matrix (driving times)<br/>(ADR-004)"]
    end

    subgraph Events
        EB{{"EventBridge<br/>service-area and trip events"}}
        SNS["SNS<br/>booking emails"]
    end

    subgraph Analytics
        FH["Firehose"]
        S3[("S3<br/>raw positions, Parquet,<br/>30-day expiry")]
        ATH["Glue Catalog + Athena<br/>saved queries"]
    end

    SIM -- "PutRecords" --> KDS
    KDS --> ING
    ING -- "conditional position write" --> TAXIS
    ING -- "left / entered area" --> EB
    ING -. "failed batches" .-> FAIL
    KDS --> FH --> S3 --> ATH

    USERS -- "sign in" --> COG
    USERS -- "HTTPS + token" --> APIGW
    APIGW --> BOOK
    BOOK -- "find cells, atomic claim" --> TAXIS
    BOOK -- "create / update" --> TRIPS
    BOOK -- "rank up to 10 taxis" --> LOC
    BOOK -- "trip events" --> EB
    EB -- "TripAssigned" --> SNS
```

Not shown: CloudWatch (logs, metrics, traces, dashboard and alarms for every
component, NFR-11) and the deployment path (section 4).

## 2. Ingesting a position

1. The simulator sends positions in batches with `PutRecords`, using the taxi
   id as the partition key, so each taxi's positions stay in order.
2. Lambda reads a batch from the stream (up to 100 records, or 1 second).
3. For each record, the core works out the geohash cell and checks the
   position against the Greater London polygon (ADR-004).
4. The DynamoDB adapter writes the position only if it's newer than the
   stored one, and never touches `status` (ADR-003).
5. If `in_service_area` changed, a `TaxiLeftServiceArea` or
   `TaxiEnteredServiceArea` event goes to EventBridge.
6. The function reports any failed records. Only those are retried, at most
   twice. A batch that still fails is recorded in the SQS queue, which raises
   an alarm.
7. Firehose reads the same stream independently and writes every position to
   S3 for Athena.

## 3. Booking a taxi

```mermaid
sequenceDiagram
    autonumber
    actor R as Rider
    participant API as API Gateway
    participant B as Booking Lambda (core + adapters)
    participant T as DynamoDB taxis
    participant L as Amazon Location
    participant TR as DynamoDB trips
    participant EB as EventBridge

    R->>API: POST /bookings (pickup, taxi type) + token
    API->>API: Validate token (Cognito, rider group)
    API->>B: Request
    B->>B: Pickup inside service area? (core)
    B->>T: Query AVAILABLE taxis in geohash cells (1, 2, then 3 km)
    T-->>B: Up to 10 candidates
    B->>L: Route matrix: candidates to pickup
    L-->>B: Driving times (or failure: rank by straight line)
    loop Best candidate first
        B->>T: Claim: status AVAILABLE to ON_TRIP, only if still AVAILABLE
        T-->>B: Success, or condition failed (taken by another booking)
    end
    alt A taxi was claimed
        B->>TR: Create trip (ASSIGNED)
        B->>EB: TripAssigned
        B-->>R: 201 Created: trip id, taxi, estimated arrival
    else No taxi available
        B->>TR: Record trip (NO_DRIVER_AVAILABLE)
        B-->>R: 200 OK: no driver available
    end
```

The claim in step 9 is the conditional write that makes double booking
impossible (NFR-05). Two simultaneous bookings can both pick the same taxi,
but only one claim succeeds. The other moves on to its next candidate.

## 4. Deployment and access

```mermaid
flowchart LR
    DEV["You<br/>Ubuntu, SSO profile"] -- "pull request" --> GH["GitHub repository"]
    GH --> GHA["GitHub Actions<br/>fmt, lint, tests, checkov,<br/>terraform plan comment"]
    GHA -- "OIDC: short-lived credentials" --> ROLE["Deploy role<br/>in ridestream-dev"]
    ROLE -- "terraform apply<br/>after your approval" --> AWS["RideStream dev environment"]
    ROLE --- STATE[("S3 state bucket<br/>native locking<br/>(ADR-005)")]
    BOOT["infra/bootstrap<br/>applied once, by hand"] -. "creates" .-> ROLE
    BOOT -. "creates" .-> STATE
```

No AWS keys are stored anywhere. You sign in with SSO. The pipeline gets
short-lived credentials through OIDC, and each Lambda and the simulator task
has its own least-privilege role.

## 5. Component summary

| Component | Service | Decided in |
| --- | --- | --- |
| Simulator | Container: local, or Fargate task | ADR-006 |
| Position stream | Kinesis Data Streams, provisioned, 1 shard | ADR-003 |
| Ingestion | Lambda, Python 3.14, Powertools | ADR-001, ADR-003 |
| Service-area check | Core Python, Greater London GeoJSON | ADR-004 |
| Operational data | DynamoDB on-demand: taxis, trips | ADR-002 |
| Sign-in | Cognito user pool with groups | FR-01–03 |
| API | API Gateway HTTP API, JWT authorizer, Lambda | FR-09–21 |
| Driving times | Amazon Location route matrix | ADR-004 |
| Events and notifications | EventBridge, SNS email | FR-07, FR-17 |
| Analytics | Firehose, S3 (Parquet), Glue Catalog, Athena | FR-22–23 |
| Observability | CloudWatch logs, metrics, dashboard, alarms; X-Ray traces | NFR-11 |
| Infrastructure and delivery | Terraform, GitHub Actions with OIDC | ADR-005 |

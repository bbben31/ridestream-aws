# ADR-001: Keep business logic free of cloud SDKs

- Status: Accepted (2026-11-09)
- Date: 2026-11-09
- Related: NFR-10 (portability), NFR-05 (no double booking), `docs/requirements.md`

## Context

RideStream is built on AWS first. From February 2027 the same system will be
ported to Azure. The comparison between the two builds is a deliverable in
itself, so the less code changes between them, the more meaningful the
comparison.

The rules that make RideStream work don't depend on any cloud:

- geohash maths (which cells to search for a pickup point and radius)
- matching (filter, rank, fall back, try the next candidate)
- the trip and taxi lifecycles (which transitions are allowed, and for whom)
- input validation (coordinates, service area, taxi type)

If these rules are written directly inside Lambda handlers around boto3 calls:

- every test of a business rule needs moto or a real AWS account
- the Azure port becomes a rewrite rather than a port
- the most important logic in the project gets mixed up with event parsing,
  retries and SDK error handling, which makes it harder to read and to
  explain in an interview

## Decision

Split the code into three layers, using the *ports and adapters*
(hexagonal) pattern.

**1. Core: `src/ridestream_core/`.** Plain Python: standard library, plus pure
Python libraries with no cloud SDK if one is ever needed. It contains the
rules listed above, plus:

- **Domain types** as dataclasses: `Taxi`, `Trip`, `Position`,
  `BookingRequest`, and domain events such as `TripAssigned`. The core never
  sees a DynamoDB item or an EventBridge payload.
- **Ports** as `typing.Protocol` classes. These are the interfaces the core
  needs from the outside world, named in business terms:
  - `TaxiDirectory`: `available_taxis_in_cells(cells, taxi_type)` and
    `claim(taxi_id, trip_id) -> bool`
  - `TripRepository`: `save(trip)`, `get(trip_id)`, `history(rider_id)`
  - `DrivingTimeEstimator`: `estimate(origins, destination) -> list[Duration]`
  - `EventPublisher`: `publish(event)`
  - `Clock`: `now()`, so tests control time

**2. Adapters: `src/ridestream_aws/`.** One class per port, implemented
with boto3: DynamoDB, the Amazon Location route matrix, EventBridge. This is
the only place that imports boto3. The Azure version will add a
`src/ridestream_azure/` package next to it.

**3. Handlers: `services/<name>/handler.py`.** Thin Lambda entry points.
Each one parses the incoming event, builds the adapters, calls the core,
and turns the result into a response. Powertools (logging, tracing,
metrics) is used here and in the adapters, never in the core.

### Where the line falls

- **Geohash cell calculation is core. Querying those cells is the adapter's
  job.** The core decides *which* cells to search, and the adapter decides
  *how* to read them from DynamoDB. That keeps the table's key design out of
  the core.
- **`claim()` must be atomic.** That is part of the port's contract, not an
  AWS detail. The core relies on it to guarantee NFR-05, and any adapter,
  on any cloud, must implement it with a conditional write or an equivalent.
  If `claim()` returns `False`, the core moves to the next candidate.
- **Fallback is core.** If `DrivingTimeEstimator` raises, the core falls back
  to straight-line ranking (FR-11). The adapter only reports the failure.

### Enforcement

A pytest test walks every module in `src/ridestream_core/` and fails if any
of them imports `boto3`, `botocore`, `aws_lambda_powertools` or
`ridestream_aws`. It runs in CI on every pull request. A test rather than a
lint rule: it's a few lines of plain Python, easy to explain, and needs no
special configuration.

## Alternatives considered

1. **Business logic directly in handlers.** It's the fastest to write and
   what most tutorials show. Rejected: every test needs moto, the Azure port
   becomes a rewrite, and the matching and booking logic would be mixed up
   with boto3 error handling.
2. **A dependency-injection framework.** Rejected: too much machinery for
   about five ports. Passing adapters to functions by hand (constructor
   arguments) is enough, and easier to explain.
3. **A multi-cloud abstraction library, or one generic `Storage` interface.**
   Rejected: generic interfaces end up as the lowest common denominator and
   hide what matters, such as the atomic claim. Ports named after business
   needs say exactly what each adapter must provide.
4. **Abstracting the infrastructure too (one IaC codebase for both clouds).**
   Rejected: Terraform stays separate for each cloud. Portability applies to
   application code, not to infrastructure definitions.

## Consequences

**Positive**

- Business rules are tested by fast unit tests with in-memory fakes of the
  ports, without moto or AWS. moto is only needed for adapter tests.
- The Azure port reuses `ridestream_core` unchanged and adds adapters and
  handlers only. How much code is reused becomes a number in the write-up.
- The concurrency guarantee (NFR-05) is stated in one place: the
  `claim()` contract.
- Each layer can be explained on its own in an interview.

**Negative**

- More files, and one level of indirection between handler and logic.
- **Leaky ports** are a risk: a port that ends up shaped around DynamoDB
  (for example, taking a key-condition expression) quietly defeats the
  design. To limit it, port methods take and return domain types only, and
  each port is reviewed when its first adapter is written.
- Every Lambda package must include `ridestream_core`. Decide how in week 2:
  bundled into each function's zip, or shared as a Lambda layer. Bundling
  is simpler, and is preferred unless package size becomes a problem.
- The repository layout in the 90-day plan changes: `src/ridestream_core/`
  and `src/ridestream_aws/` are added, and `services/` keeps only handlers
  and the simulator.

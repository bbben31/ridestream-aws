# RideStream — requirements

Status: draft v0.2 · Week 1 · 10 November 2026

## 1. Purpose and scope

RideStream is a new design of the idea behind the 2023 IIT Madras cloud
capstone, the "Location Based Taxi Aggregator". The 2023 system is a
reference for what is expected (`docs/baseline-2023.md`), not a template:
these requirements stand on their own.

RideStream is a ride-hailing location platform for London. Simulated taxis
stream their positions to AWS. Riders book the nearest available taxi of the
type they want, drivers carry out the trip, and every trip feeds an analytics
store.

It is a portfolio project. It has one environment (dev), which is created
for each building session and destroyed at the end of it. It has no real
users.

## 2. Actors

| Actor | Description |
| --- | --- |
| Rider | Signs in, books a taxi, follows and cancels their own trips, sees their trip history. |
| Driver | Signs in, is linked to one taxi, sets availability, moves an assigned trip through its stages. |
| Admin | Views the fleet and all trips, cancels any trip, suspends and reinstates drivers. Has API access only, no user interface. |
| Simulator | A system actor. Sends taxi positions and drives scripted rider and driver behaviour for tests. |

## 3. Functional requirements

### Accounts and access

- **FR-01** A rider can register and sign in.
- **FR-02** A driver can register and sign in. Each driver is linked to one
  taxi with one type: `basic`, `deluxe` or `luxury`.
- **FR-03** Each user belongs to exactly one role (rider, driver, admin), and
  each API operation is allowed only for the roles listed in this document.

### Positions and availability

- **FR-04** A driver can set their taxi to `AVAILABLE` or `OFFLINE`.
- **FR-05** While a taxi is not `OFFLINE`, its position is sent every 5 seconds.
- **FR-06** The system keeps the latest position and status of every taxi.
- **FR-07** A taxi outside the London service area is excluded from matching
  until it re-enters the area. Leaving and re-entering the area are
  published as events.
- **FR-08** Riders do not stream their position. The pickup location is sent
  with the booking request.

### Booking and matching

- **FR-09** A rider can request a booking with a pickup location and a taxi
  type (`basic`, `deluxe`, `luxury`, or `any`, as in 2023). A pickup outside
  the service area is rejected.
- **FR-10** Matching finds `AVAILABLE` taxis of the requested type near the
  pickup point by straight-line distance. It searches in widening rings
  (1 km, 2 km, then 3 km at most) and keeps up to 10 candidates.
- **FR-11** The candidates are ranked by one of two strategies, chosen by
  configuration:
  - `driving_time`: estimated driving time to the pickup point (the default)
  - `straight_line`: distance as the crow flies

  If the routing service fails or is throttled, matching falls back to
  `straight_line` and logs that it did.
- **FR-12** The best-ranked taxi is assigned automatically. Claiming the taxi
  is atomic: a taxi can never be assigned to two active trips. If the claim
  fails because another booking took the taxi, matching tries the next
  candidate.
- **FR-13** If no taxi can be assigned within the maximum radius, the request
  ends at once with `NO_DRIVER_AVAILABLE`. Nothing is queued.

### Trip progress

- **FR-14** The assigned driver can mark the trip as arrived, started and
  completed, following the lifecycle in section 4.
- **FR-15** A rider can cancel their trip before it is `IN_PROGRESS`. An admin
  can cancel any trip that has not reached an end state. Drivers cannot
  cancel in v1.
- **FR-16** When a trip ends (`COMPLETED` or `CANCELLED`), its taxi becomes
  `AVAILABLE` again, unless the taxi has been suspended or set `OFFLINE`.
- **FR-17** A rider is notified when their booking is confirmed (SNS email).

### Queries

- **FR-18** A booking can be read by its rider, its assigned driver and admins.
- **FR-19** A rider can list their own trip history, newest first.
- **FR-20** An admin can list the fleet (taxi, type, status, last position)
  and list trips filtered by state.
- **FR-21** An admin can suspend and reinstate a driver. A suspended taxi is
  never matched.

### Analytics

- **FR-22** All position updates and trip events are stored for analytics.
- **FR-23** Saved queries report: rides per hour, demand by area, and average
  wait time (`REQUESTED` → `DRIVER_ARRIVED`).

## 4. Lifecycles

### Trip

```
REQUESTED ──match──▶ ASSIGNED ──driver arrives──▶ DRIVER_ARRIVED ──start──▶ IN_PROGRESS ──complete──▶ COMPLETED
    │                    │                              │
    │ no taxi            │ rider/admin cancel           │ rider/admin cancel        (admin can also cancel IN_PROGRESS)
    ▼                    ▼                              ▼
NO_DRIVER_AVAILABLE   CANCELLED                      CANCELLED
```

| From | Event | To | Allowed |
| --- | --- | --- | --- |
| REQUESTED | taxi claimed | ASSIGNED | system |
| REQUESTED | no taxi within max radius | NO_DRIVER_AVAILABLE | system |
| ASSIGNED | arrive | DRIVER_ARRIVED | assigned driver |
| DRIVER_ARRIVED | start | IN_PROGRESS | assigned driver |
| IN_PROGRESS | complete | COMPLETED | assigned driver |
| ASSIGNED, DRIVER_ARRIVED | cancel | CANCELLED | rider (own trip), admin |
| IN_PROGRESS | cancel | CANCELLED | admin |

End states: `COMPLETED`, `CANCELLED`, `NO_DRIVER_AVAILABLE`. Any transition
not in the table is rejected.

### Taxi

| From | Event | To | Allowed |
| --- | --- | --- | --- |
| OFFLINE | go available | AVAILABLE | driver |
| AVAILABLE | go offline | OFFLINE | driver |
| AVAILABLE | claimed by a booking | ON_TRIP | system (atomic, FR-12) |
| ON_TRIP | trip ends | AVAILABLE | system |
| any | suspend | SUSPENDED | admin |
| SUSPENDED | reinstate | OFFLINE | admin |

A driver can go `OFFLINE` only from `AVAILABLE`, not during a trip. Only
`AVAILABLE` taxis inside the service area are matched.

## 5. Non-functional requirements

| ID | Requirement | Target | How it's measured |
| --- | --- | --- | --- |
| NFR-01 | Ingestion throughput | 200 position updates/s (1,000 taxis × every 5 s) for 1 hour | Zero Kinesis write throttles (`WriteProvisionedThroughputExceeded`), DLQ empty |
| NFR-02 | Headroom | Find the ceiling, aiming for 1,000 updates/s (one shard's record limit) | Week 6 load test, reported as a result rather than pass/fail |
| NFR-03 | Position freshness | p95 ≤ 10 s from send to visible in DynamoDB | Kinesis iterator age, plus send vs write timestamps |
| NFR-04 | Booking latency | `POST /bookings` p95 < 500 ms with `straight_line`; p95 < 800 ms with `driving_time` (provisional) | API Gateway latency metric at 5 bookings/s |
| NFR-05 | No double booking | 0 taxis assigned twice | Concurrency test: 100 simultaneous bookings for 10 available taxis → exactly 10 `ASSIGNED`, 90 `NO_DRIVER_AVAILABLE` |
| NFR-06 | Security | Every endpoint needs a valid Cognito token and the right role; no stored secrets; least-privilege IAM role per function; encryption at rest everywhere; all inputs validated | Tests for unauthenticated and wrong-role calls; checkov; IAM Access Analyzer |
| NFR-07 | Cost | Destroyed: about $0 (only the Terraform state bucket remains). Deployed and idle: ≤ $1/day. One-hour load test at NFR-01: ≤ $5 (estimated $0.50–$1 plus Lambda; ADR-004). Monthly: within the $30 working budget and $50 ceiling | AWS Budgets, Cost Explorer filtered by the `Project=ridestream` tag |
| NFR-08 | Availability | Single region (eu-west-2), relying on the multi-AZ design of managed services. No DR and no uptime target | Stated, not tested |
| NFR-09 | Data retention | DynamoDB keeps the latest position per taxi only. Raw positions in S3 expire after 30 days. Kinesis keeps data for 24 h (default) | S3 lifecycle rule, stream settings |
| NFR-10 | Portability | Business logic (matching, geohash, lifecycles, validation) has no AWS imports and is unit tested without AWS | Lint rule or test that fails on `boto3` imports in core modules; core test coverage ≥ 80 % |
| NFR-11 | Observability | Structured logs, traces and metrics; a dashboard showing iterator age, Lambda errors and booking p95; alarms sent through SNS | Dashboard screenshot in `docs/results/` |
| NFR-12 | Rebuildability | The dev environment is rebuilt from nothing through the pipeline in ≤ 20 minutes (provisional) | Timed pipeline run |

## 6. Out of scope (v1)

- Payments, fares and surge pricing
- Driver-accept flow (offer, timeout, next driver). This is the first future extension.
- Queuing requests when no taxi is available
- Ratings, chat, ride-sharing, scheduled rides
- Any real mobile or web app: the API and simulator are the interface
- Driver onboarding, licence and vehicle checks
- Cities other than London; multi-region; disaster recovery
- A production environment
- Push notifications to real devices (SNS email only)

## 7. Assumptions and open questions

### Assumptions

- A position record is about 200 bytes of JSON (taxi id, lat, lon,
  timestamp, status, type).
- The service area is one simplified polygon of Greater London.
- Simulated taxis move with a simple model (random walk or straight segments),
  not along real roads. Driving times still come from real London road data.

### Open questions

- **Resolved by ADR-004:** per-position tracking and geofencing in Amazon
  Location would cost about $46–$116 per load-test hour. The service-area
  check runs in the core instead; Amazon Location is used only for driving
  times.
- **Route matrix quota.** Each booking costs about 10 routes. The default
  quota (5 requests/s) caps driving-time bookings at about 5/s unless it's
  raised.
- **NFR-04 driving-time target (800 ms)** is a guess until measured in week 4.
- **Search radius (1/2/3 km)** is a starting point, to be tuned with the
  simulator.

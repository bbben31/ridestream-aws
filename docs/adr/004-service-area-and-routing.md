# ADR-004: Check the service area in the core; use Amazon Location for driving times only

- Status: Accepted (2026-11-10)
- Date: 2026-11-10
- Related: ADR-001, ADR-002, ADR-003, FR-07, FR-09, FR-11, NFR-04,
  NFR-07, `docs/requirements.md`

## Context

Two requirements involve geography beyond "which cells are near this point":

- **The service area (FR-07, FR-09).** A taxi outside London must not be
  matched, and a pickup outside London must be rejected. The service area is
  one fixed polygon, Greater London, that changes rarely if ever.
- **Driving time (FR-11).** Up to 10 candidate taxis are ranked by estimated
  driving time to the pickup point, using real roads and traffic.

The first plan used Amazon Location Service for both: every position written
to a **tracker** linked to a **geofence collection**, with entry and exit
events sent to EventBridge, and the **route matrix** for driving times.

### What per-position tracking would cost

Amazon Location bills per position written to a tracker and again per
position evaluated against geofences. AWS's own fleet-tracking example
(September 2026) found that sending every position to Amazon Location was
about 87 % of the whole bill, for a fleet of 20 vehicles.

The pricing tables couldn't be read reliably for eu-west-2, so here is an
estimate from that example: 20 vehicles reporting every 5 seconds for
10 hours a day, 22 days a month, cost about $204 a month in tracker writes
and geofence evaluations. That is about $0.06–$0.16 per 1,000 positions,
depending on how many positions it counted.

RideStream's load test sends 720,000 positions an hour (NFR-01): roughly
**$46–$116 per hour** for tracking and geofencing alone. That's 10 to 20
times NFR-07's limit of $5 per load-test hour. Even if the estimate were
ten times too high, it would still break the target. The free tier
(200,000 positions written and 200,000 evaluated) wouldn't cover a single
load-test hour.

## Options

1. **Tracker and geofences for every position (the first plan).** Fully
   managed, with entry and exit events for free. Rejected on cost, as above.
2. **Tracker with filtering.** A distance-based filter drops updates for
   taxis that barely moved, but positions are still billed as they are
   written, and taxis in a city move constantly. Cheaper, still far too
   expensive at 200 positions a second.
3. **Send only positions near the boundary to Amazon Location** (the
   "proximity" pattern from the AWS example). Cuts the volume, but adds a
   second boundary check to decide what to send, which is the problem
   itself.
4. **Point-in-polygon check in the core.** The ingestion Lambda checks each
   position against the Greater London polygon in plain Python. It costs
   nothing per position, works offline in unit tests, and moves unchanged to
   Azure (ADR-001).

## Decision

**The service-area check runs in the core. Amazon Location is used only for
driving times.**

### Service area

- The Greater London boundary is stored in the repository as a GeoJSON
  polygon, simplified to a few hundred points. It must come from an openly
  licensed source, such as the ONS boundaries under the Open Government
  Licence, credited in the README.
- `ridestream_core.geo` gets `in_service_area(position) -> bool`, a standard
  ray-casting point-in-polygon test, with unit tests for points inside,
  outside, near the edge and on known London landmarks.
- The ingestion Lambda stores `in_service_area` with each taxi's position
  (ADR-003's position write). Matching ignores taxis where it is false
  (FR-07).
- When the value changes, the ingestion Lambda publishes a
  `TaxiLeftServiceArea` or `TaxiEnteredServiceArea` event to EventBridge, so
  the rest of the design keeps its events. Only transitions are published,
  so the volume is tiny.
- The booking API uses the same function to reject pickups outside the area
  (FR-09).

### Driving times

- Ranking uses the Amazon Location Routes API (`CalculateRouteMatrix`): up
  to 10 candidate taxis as origins and the pickup point as the destination,
  so about 10 routes per booking. It authenticates with the Lambda's IAM
  role, so there is no API key to store.
- This sits behind the `DrivingTimeEstimator` port (ADR-001). If the call
  fails or is throttled, matching falls back to straight-line ranking
  (FR-11).
- The load test uses `straight_line` (requirements, NFR-04), so it creates no
  routing charges. Functional tests run a few hundred bookings, which is a
  few thousand routes. That's a small cost either way, and may be covered
  by the routing free tier (10,000 routes a month). Check which free-tier
  offer applies to the account.
- The default quota of 5 route-matrix requests a second limits bookings
  that use driving time to about 5 a second. That's enough for v1, and it
  is recorded in the requirements.

## Consequences

**Positive**

- The largest cost in the design disappears. NFR-07's $5 per load-test hour
  becomes realistic: about $0.03 for Kinesis and $0.45–$0.90 for DynamoDB
  writes (US East example prices), plus Lambda.
- The service-area rule is ordinary tested Python in the core. It runs on
  every position at no extra cost, and the Azure port reuses it unchanged.
- Amazon Location is used where it adds real value: road data and traffic,
  which can't sensibly be built in-house.

**Negative**

- **No managed geofencing:** no tracker history, and no geofence collection
  to edit in the console. Changing the service area means changing a file
  and deploying.
- **Accuracy depends on the polygon.** A simplified boundary can misjudge
  positions a few metres either side of the real border. That's acceptable
  for a service area.
- **Point-in-polygon on every position costs Lambda time.** For one polygon
  of a few hundred points it is microseconds, but it's checked in the week 6
  load test.
- The original plan's "Amazon Location tracker and geofences" no longer
  appears in the architecture. The README explains why, with the cost
  estimate above.

## References

Checked on 10 November 2026.

- Fleet tracking cost example (AWS IoT blog): https://aws.amazon.com/blogs/iot/tracking-fleets-in-real-time-with-aws-iot-core-and-amazon-location-service/
- Amazon Location pricing and free tier: https://aws.amazon.com/location/pricing
- Trackers pricing: https://docs.aws.amazon.com/location/latest/developerguide/trackers-pricing.html
- Routes pricing: https://docs.aws.amazon.com/location/latest/developerguide/routes-pricing.html
- Routes quotas: https://docs.aws.amazon.com/location/latest/developerguide/routes-quota-usage.html

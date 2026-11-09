# Handoff

## 2026-11-09 · Week 1 — design · requirements

### Done
- Week 0 closed: SSO with MFA, `ridestream-dev` profile, both budgets working.
- `docs/requirements.md` v0.1: 23 functional requirements, trip and taxi
  lifecycles, 12 measurable NFRs, out of scope, open questions.
- Checked current Kinesis limits and pricing, and Amazon Location
  routing quotas and billing units.

### Decisions
- Auto-assign in v1. Driver-accept is the first future extension.
- Two state machines (trip and taxi). The conditional write moves a taxi
  from `AVAILABLE` to `ON_TRIP`.
- Matching: geohash pre-filter (1/2/3 km rings, up to 10 candidates), then
  ranking by driving time (route matrix), falling back to straight-line.
- No taxi in range → `NO_DRIVER_AVAILABLE` at once. No queue.
- Riders don't stream their position. The pickup point comes with the booking.
- Kinesis provisioned, one shard: about $0.025/h while running (US East
  example prices) versus about $0.10/h on-demand Standard. 200 records/s is
  20 % of the shard's record limit.
- Cost requirement rewritten: about $0 when destroyed, ≤ $1/day when idle,
  ≤ $5 per load-test hour (provisional). Working budget raised to $30, with
  the $50 ceiling unchanged.

### Open problems
- Amazon Location prices in eu-west-2 (tracker positions written, geofence
  evaluations, route matrix routes) aren't confirmed. They may be the largest
  cost at 720,000 positions/hour. Needed before ADR-004.
- The route-matrix default quota (5 requests/s) caps bookings at about 5/s.
- The plan and context `.md` files sit untracked in the repo root. Move them
  out before the repo goes public in week 3.

### To do this week
1. Review and commit `docs/requirements.md`.
2. Raise the working budget to $30 in AWS Budgets.
3. Master CV, in a new "Master CV" chat.
4. SAA-C03 study, about 5 h.
5. ADR-001 (portability): your first draft, then challenge.
6. ADRs 002–006, then the architecture diagram.
7. Before week 3: move the personal docs out of the repo.

### Next step
Write the first draft of ADR-001 and bring it to the Week 1 chat.

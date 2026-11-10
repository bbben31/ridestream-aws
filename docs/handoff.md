# Handoff

## 2026-11-10 · Week 1 — design · architecture diagram

### Done
- Week 1 work committed on `docs/week1-design` and pushed.
- `docs/architecture.md`: system overview, ingestion steps, booking
  sequence (with the atomic claim), deployment and access, component
  summary. Diagrams in Mermaid, checked by rendering them.

### Decisions
- Diagrams are Mermaid in the repository, drawn by GitHub and reviewed in
  pull requests like code, instead of draw.io for now. A polished image with
  AWS icons is made for the README in week 10.

### Next step
Review `docs/architecture.md`, commit it on `docs/week1-design`, then open
the week 1 pull request into `main`. Week 2 (16–22 Nov): repository
skeleton, Terraform bootstrap and state, OIDC and the pipeline.

## 2026-11-10 · Week 1 — design · ADR-005 and ADR-006

### Done
- ADR-002, ADR-003 and ADR-004 accepted.
- `docs/adr/005-terraform.md` and `docs/adr/006-simulator-runtime.md`
  written (status: Proposed).

### Decisions
- ADR-005 (proposed): Terraform ≥ 1.11 for everything. S3 state bucket
  (encrypted, versioned, random-suffix name) with native locking
  (`use_lockfile`), no DynamoDB lock table. `infra/bootstrap/` creates the
  state bucket and OIDC deploy role once, by hand, and is never destroyed.
  `default_tags` sets Project/Env/ManagedBy.
- ADR-006 (proposed): one simulator image. Locally for development; as a
  one-off Fargate task (0.25 vCPU, 0.5 GB, ARM) for load tests, in a
  minimal Terraform VPC with a public subnet, no NAT, outbound-only security
  group, and a task role limited to `kinesis:PutRecords`.

### Update
- ADR-005 and ADR-006 accepted. All six week 1 ADRs are accepted.
- Week 1 work committed on `docs/week1-design`.

### Next step
The architecture diagram, the last week 1 deliverable. Then one pull
request to merge `docs/week1-design` into `main` at the end of the week.

## 2026-11-10 · Week 1 — design · ADR-004

### Done
- `docs/adr/004-service-area-and-routing.md` written (status: Proposed).
- Requirements: FR-07 adds service-area events; NFR-07 load-test estimate
  updated; the Amazon Location price question is resolved.

### Decisions
- ADR-004 (proposed): the service-area check is a point-in-polygon test in
  the core, on every position, against a Greater London GeoJSON polygon.
  Transitions are published to EventBridge. Amazon Location is used only for
  driving times (`CalculateRouteMatrix`, about 10 routes per booking, IAM
  auth, straight-line fallback).
- Why: per-position tracker writes and geofence evaluations would cost an
  estimated $46–$116 per load-test hour, 10–20 times NFR-07.

### Open problems
- eu-west-2 unit prices for Amazon Location couldn't be read; the estimate
  comes from AWS's own fleet-tracking cost example. The decision holds even
  if it is ten times too high.
- Source an openly licensed Greater London boundary (e.g. ONS, Open
  Government Licence) in week 5.

### Next step
Review ADR-002 to ADR-004. Then ADR-005 (Terraform vs CloudFormation) and
ADR-006 (simulator runtime).

## 2026-11-10 · Week 1 — design · baseline revisions and ADR-003

### Done
- Requirements v0.2: starts from the 2023 baseline; FR-09 brings back the
  2023 "any type" option.
- ADR-001 and ADR-002: context sections now start from what 2023 did.
- Baseline: notes that SageMaker and QuickSight were designed but not built.
- `docs/adr/003-kinesis-ingestion.md` written (status: Proposed).

### Decisions
- The 2023 authorship and plan-table questions are closed. RideStream
  improves the existing solution.
- ADR-003 (proposed): keep Kinesis provisioned, one shard, 24 h retention.
  Fixes: partition key = `taxi_id`, `PutRecords` batches, no
  Lambda-to-Lambda, partial batch failures with bisect, finite retries
  (2) and record age (300 s), SQS on-failure destination with an alarm,
  timestamp-conditional position writes.

### Update
- The 2023 solution is a reference for what is expected, not a template.
  ADRs decide on their own merits; 2023 appears only as short background.
  ADR-001, ADR-002, ADR-003, the requirements and the baseline reworded.
- ADR-003 retitled "Use Kinesis Data Streams for position ingestion".

### Next step
Review ADR-002 and ADR-003. Then ADR-004 (Amazon Location: geofence and
routing), which needs the eu-west-2 prices confirmed first.

## 2026-11-09 · Week 1 — design · 2023 baseline

### Done
- Read the 2023 capstone archive: report, diagram, code, templates.
- `docs/baseline-2023.md`: what the capstone did, what RideStream keeps,
  16 changes with the requirement or ADR that covers each.

### Decisions
- Keep: pipeline shape, taxi types plus "any type", plate number and email
  as identities, latest-position-only storage, the simulator's movement
  model, database code kept apart from handlers.

### Open problems
- The archive's `databasehandler/.git/config` holds a GitHub token for the
  2023 account: revoke it, and don't share the zip as it is.

### Next step
Revise the requirements, ADR-001 and ADR-002 so each starts from the 2023
baseline. Then ADR-003 (Kinesis: kept from 2023, with fixes).

## 2026-11-09 · Week 1 — design · ADR-002

### Done
- ADR-001 accepted and committed.
- `docs/adr/002-database-dynamodb.md` written (status: Proposed), waiting
  for your review.
- Checked current DynamoDB on-demand pricing, DocumentDB serverless minimum
  capacity and VPC model, and MongoDB Atlas Free/Flex limits.

### Decisions
- ADR-002 (proposed): DynamoDB on-demand for taxis and trips. A geohash-cell
  GSI serves proximity search; the claim is `UpdateItem` with
  `ConditionExpression: status = AVAILABLE`.
- Rejected: DocumentDB (VPC only, 0.5 DCU minimum ≈ $30/month, slow to
  rebuild) and MongoDB Atlas (M0 capped at 100 ops/s, open access list,
  stored Terraform credentials, billing outside AWS).
- Interview preparation is kept out of the design work and done
  separately later (week 11 mock interviews).
- Commits: one commit per accepted deliverable, on a branch
  (`docs/week1-design`), merged to `main` by one pull request at the end of
  the week. Not one commit per edit.
- Requirements and ADRs build on the 2023 IIT Madras capstone: each one
  states what the capstone did, what changes and why. Waiting for the
  capstone material to revise them.

### Open problems
- Position writes cost about $0.45/h at load (US East), up to double with
  GSI writes. Test the GSI projection and batch de-duplication in week 3.
- Key design and geohash precision: week 3.
- The project instructions in claude.ai still have the old items 3 and 8:
  paste section 1 of the context document.

### Next step
Review ADR-002. Then ADR-003 (Kinesis vs SQS): Claude drafts, you review.

## 2026-11-09 · Week 1 — design · ADR-001

### Done
- `docs/requirements.md` and this handoff committed.
- `docs/adr/001-portable-business-logic.md` written and accepted.

### Decisions
- **New way of working:** Claude writes the first draft of each deliverable
  and you review it, unless you say otherwise for a task. This replaces
  "I write the first draft" in the project instructions.
- ADR-001 (accepted): ports and adapters. `src/ridestream_core/` has no
  cloud SDKs, `src/ridestream_aws/` holds the boto3 adapters, and
  `services/<name>/handler.py` holds thin handlers. A pytest test enforces
  the import rule. `claim()` must be atomic as part of its contract.
- Handoff and project status are updated after each deliverable, not only
  at the end of a session.

### Open problems
- Lambda packaging for the core (bundled into each zip or shared as a
  layer): decide in week 2.

### To do this week
1. ~~Review and commit `docs/requirements.md`.~~ Done.
2. Raise the working budget to $30 in AWS Budgets.
3. Master CV, in a new "Master CV" chat. Bring your role-by-role LinkedIn
   details: the project already has the IIT Madras title, PhD dates and
   certifications.
4. SAA-C03 study, about 5 h.
5. ~~Review ADR-001.~~ Accepted.
6. ADRs 002–006, then the architecture diagram. (002 drafted.)
7. Before week 3: move the personal docs out of the repo.

### Next step
ADR-002 (DynamoDB vs DocumentDB vs MongoDB Atlas): Claude drafts, you review.

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

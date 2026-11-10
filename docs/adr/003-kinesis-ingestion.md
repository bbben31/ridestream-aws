# ADR-003: Use Kinesis Data Streams for position ingestion

- Status: Accepted (2026-11-10)
- Date: 2026-11-10
- Related: ADR-001, ADR-002, FR-05, FR-22, NFR-01, NFR-03, NFR-07,
  `docs/baseline-2023.md` (changes 4 and 9)

## Context

RideStream needs:

- 200 position updates per second (NFR-01), visible within 10 seconds
  (NFR-03).
- **Two consumers of the same data:** the ingestion Lambda (latest position
  in DynamoDB) and, from week 9, Firehose (full history in S3, FR-22).
- **Per-taxi ordering:** an older position must never overwrite a newer one.
- Low cost while deployed, and nothing when destroyed (NFR-07).
- **No silent data loss:** every failed record is retried or recorded.

Background: the 2023 capstone also used Kinesis, with a constant partition
key, one Lambda call per record and failures ignored. Those are the
mistakes the decision below avoids.

## Options

1. **Kinesis Data Streams, provisioned, one shard.** Several consumers
   read the same records independently. Order is kept per partition key.
   Records can be re-read for 24 hours. One shard takes 1,000 records/s, five
   times the target. About $0.025 an hour under load and $0.015 an hour idle
   while deployed (US East example prices).
2. **Kinesis on-demand.** No shard to manage, but at RideStream's small
   records it costs about four times more (each record is billed as at least
   1 KB, plus a per-stream hourly charge). The Advantage mode has an
   account-wide minimum far above RideStream's volume. Rejected in the
   requirements cost analysis.
3. **Amazon SQS to Lambda.** Billed per request, so nothing when idle. But
   each message goes to one consumer: feeding Firehose too would need SNS in
   front of two queues. Standard queues don't keep order, so a retried old
   position could overwrite a newer one. FIFO queues keep order per group but
   have lower throughput limits and a higher price. Messages can't be
   replayed once deleted.
4. **The simulator writes straight to DynamoDB, or to an API.** Rejected:
   no buffer when the database slows down, no second consumer for analytics,
   and the producers become tied to the database.

## Decision

**Use Kinesis Data Streams in provisioned mode, with one shard and 24-hour
retention, configured as follows:**

1. **Partition key = `taxi_id`.** Each taxi's positions stay in order, and
   taxis spread evenly if shards are ever added.
2. **The simulator sends batches** with `PutRecords` instead of one
   `PutRecord` per message.
3. **The ingestion Lambda does the work itself:** it decodes the batch and
   writes through the core and the DynamoDB adapter (ADR-001). No
   Lambda-to-Lambda calls.
4. **Failures are reported, retried and kept**, using the event source
   mapping settings:
   - `ReportBatchItemFailures`: the function returns the records that failed,
     and only those are retried.
   - `BisectBatchOnFunctionError`: a batch that crashes the function is split
     in half to isolate the bad record.
   - `MaximumRetryAttempts` and `MaximumRecordAgeInSeconds` are set to finite
     values. The defaults retry until the record expires, which can block a
     shard for the whole retention period. A position older than a few
     minutes is worthless anyway. Starting values: 2 retries, 300 seconds.
   - An **on-failure destination** (SQS queue), with a CloudWatch alarm when
     it holds any message. It receives the details of the failed batch
     (shard and sequence numbers), not the records themselves. The records
     can be re-read from the stream within the 24-hour retention.
5. **Stale writes are rejected.** The DynamoDB update succeeds only if the
   incoming timestamp is newer than the stored one, so retries and
   reordering can't move a taxi backwards. The update touches position
   attributes only, never `status`, so it can't interfere with the atomic
   claim (ADR-002).
6. **Starting batch settings:** batch size 100, batching window 1 second.
   Tuned against NFR-03 in the week 6 load test.
7. **Firehose reads the same stream** in week 9, as a second consumer.

## Consequences

**Positive**

- Per-taxi ordering, two independent consumers and 24-hour replay come with
  the service rather than being built.
- One shard has five times the headroom of NFR-01, which gives the week 6
  load test a clear ceiling to measure.
- No record is lost without trace: it is either written, retried, or
  recorded in the failure queue with an alarm.

**Negative**

- **An hourly cost while deployed** (about $0.36 a day idle), accepted in
  NFR-07 and limited by destroying dev after each session.
- **The shard is a capacity unit to manage.** Above about 5,000 taxis at one
  update every 5 seconds, the stream needs more shards. Out of scope for v1.
- **The failure queue holds pointers, not records.** Replay must happen
  within 24 hours. An S3 failure destination would keep the full records,
  but alarming on an SQS queue is simpler; revisit if replay becomes
  important.

## References

Checked on 10 November 2026. Prices are AWS's US East examples.

- Kinesis quotas and limits: https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html
- Kinesis Data Streams pricing: https://aws.amazon.com/kinesis/data-streams/pricing/
- Lambda Kinesis event source mapping parameters: https://docs.aws.amazon.com/lambda/latest/dg/services-kinesis-parameters.html
- Lambda on-failure destinations for Kinesis: https://docs.aws.amazon.com/lambda/latest/dg/kinesis-on-failure-destination.html

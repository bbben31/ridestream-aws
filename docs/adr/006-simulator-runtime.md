# ADR-006: Run the simulator locally for development and on Fargate for load tests

- Status: Accepted (2026-11-10)
- Date: 2026-11-10
- Related: ADR-003, ADR-005, NFR-01, NFR-02, NFR-07, NFR-12

## Context

The simulator produces the system's input: 1,000 taxis sending a position
every 5 seconds (NFR-01), and up to five times that to find the ceiling
(NFR-02). It also drives scripted riders and drivers for functional tests.

It has two different jobs:

- **Development and functional tests:** short runs, started and stopped
  often, with quick code changes in between.
- **Load tests:** runs of an hour or more that must be steady, repeatable
  and measured from inside AWS, so the results describe RideStream rather
  than a home internet connection.

Background: the 2023 simulator ran on an EC2 instance, set up and started by
hand over SSH.

## Options

1. **Your laptop only.** Free and quick to change. But a home connection,
   a laptop that sleeps and an SSO session that expires all make an hour-long
   load test unreliable, and the results would measure your network too.
2. **AWS Fargate (ECS task).** Runs the same container image as on your
   laptop, with no server to patch or SSH into. Billed per second while
   running. A small task (0.25 vCPU, 0.5 GB, ARM) costs about $0.01 an hour
   at US East example prices. Fargate needs a VPC, but a public subnet with
   an internet gateway is enough to reach Kinesis: no NAT gateway.
3. **EC2 instance.** Works, but brings back what RideStream avoids: an
   operating system to patch, SSH access and an instance that is easy to
   forget running.
4. **Lambda.** Free when idle, but a function runs for at most 15 minutes,
   so a continuous one-hour stream would need chained invocations and
   timing workarounds.

## Decision

**One container image, run in two places:**

- **Locally (Docker or plain Python)** for development and functional tests,
  using your `ridestream-dev` SSO profile.
- **On Fargate as a one-off ECS task** (`run-task`, not a long-running
  service) for load tests. Started and stopped by a `make` target, never
  left running.

Setup:

- **Image:** built from `services/simulator/`, stored in an ECR repository
  with a lifecycle rule that keeps only the last few images.
- **Task:** 0.25 vCPU and 0.5 GB on ARM (Graviton) to start, raised only if
  the load test shows the simulator is the bottleneck. Settings come from
  environment variables: number of taxis, interval, duration.
- **Network:** a minimal VPC created by Terraform with one public subnet and
  an internet gateway. The task gets a public IP to reach Kinesis and ECR.
  Its security group allows outbound traffic only. No NAT gateway.
- **Permissions:** a task role allowed only `kinesis:PutRecords` on the
  RideStream stream, plus the standard execution role to pull the image and
  write logs. No credentials in the image.
- **Logs:** CloudWatch Logs, with the simulator reporting records sent,
  throttles and errors every minute, to compare with the stream's metrics.
- **Behaviour (both places):** positions inside the Greater London polygon
  (ADR-004), movement in any direction, partition key = taxi id, batched
  `PutRecords` with retries for throttled records (ADR-003).

## Consequences

**Positive**

- Load-test results come from inside AWS and can be repeated with one
  command.
- No servers: nothing to patch, no SSH keys, nothing left running between
  tests.
- Evidence of containers on ECS and Fargate, with a least-privilege task
  role, at a cost of pennies per test.
- The same image runs locally and in AWS, so what you test is what runs.

**Negative**

- **More infrastructure:** ECR, an ECS cluster, a task definition and a small
  VPC. All in Terraform and destroyed with dev, but more for the week 3
  build.
- **A public IP on the task.** Billed per hour while the task runs, and the
  task is reachable from nothing because its security group allows no
  inbound traffic.
- **Image build and push** become a pipeline step.
- One 0.25 vCPU task may not reach the NFR-02 ceiling of 1,000 records a
  second. If it doesn't, the load test runs more tasks or a larger one.

## References

Checked on 10 November 2026.

- AWS Fargate pricing: https://aws.amazon.com/fargate/pricing/

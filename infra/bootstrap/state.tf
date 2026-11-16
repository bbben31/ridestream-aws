# The S3 bucket that holds Terraform state: this configuration's own state
# and the dev environment's. It is the one resource that is never destroyed.

# Bucket names are global across all AWS customers, so the name ends with
# 8 random hex characters. They are generated once and kept in state.
resource "random_id" "state_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second bucket. CloudTrail already records every change to this bucket's settings. Revisit in week 10.
  #checkov:skip=CKV_AWS_144:Cross-region replication is for disaster recovery. Dev state can be rebuilt by importing, and versioning covers a bad write.
  #checkov:skip=CKV_AWS_145:SSE-S3 is enough here. State holds no secrets by design, and a customer KMS key costs $1 a month and adds a key policy to maintain.
  #checkov:skip=CKV2_AWS_62:Nothing needs to react to state file changes.
  bucket = "${local.name_prefix}-tfstate-${random_id.state_suffix.hex}"

  # Terraform refuses any plan that would delete this bucket.
  lifecycle {
    prevent_destroy = true
  }
}

# Keep every earlier version of the state file. This is the recovery path
# if a state file is corrupted or overwritten (ADR-005).
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 encrypts new objects by default. Stating it makes the choice visible.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3: keys owned and managed by S3
    }
  }
}

# All four switches on: no ACL and no bucket policy can make this public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Turn ACLs off altogether. Access is decided by IAM and the bucket policy.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Old versions would pile up for ever. Keep the 10 most recent earlier
# versions whatever their age, and delete others 90 days after they were
# replaced.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {} # every object in the bucket

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    # Deleting an object in a versioned bucket leaves a "delete marker".
    # Every released state lock leaves one. Remove a marker once no older
    # version sits behind it.
    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Noncurrent-version rules only make sense once versioning is on.
  depends_on = [aws_s3_bucket_versioning.state]
}

# Refuse any request that doesn't use TLS.
data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  # Changing a bucket policy and the public access block at the same moment
  # can fail, so do them in order.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

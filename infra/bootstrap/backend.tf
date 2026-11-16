# Where this configuration keeps its own state.
#
# This file starts life as backend.tf.disabled, because the bucket doesn't
# exist until the first apply. The first apply therefore writes state to a
# local file. Afterwards the file is renamed to backend.tf and
# `terraform init -migrate-state` copies the state into the bucket.
#
# The bucket name is not written here: it is passed at init time with
#   -backend-config="bucket=<name>"
# (see README.md in this directory).

terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # lock with a .tflock object in the bucket, no DynamoDB
  }
}

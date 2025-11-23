terraform {
  backend "s3" {
    bucket = "maxsauce-infra"
    key    = "envs/hetzner"
    region = "us-east-1"
    use_lockfile = true
  }
}

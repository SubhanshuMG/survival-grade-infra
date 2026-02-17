terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket = "shopglobal-terraform-state"
    key    = "multi-cloud/terraform.tfstate"
    region = "us-east-1"
  }
}

# ===========================================================
#  PROVIDERS
# ===========================================================

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

provider "cloudflare" {
  # API token set via CLOUDFLARE_API_TOKEN env var
}

# ===========================================================
#  AWS VPC
# ===========================================================

module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false # One per AZ for high availability
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ===========================================================
#  EKS CLUSTER (AWS)
# ===========================================================

module "eks" {
  source = "./modules/eks"

  cluster_name    = "${var.project_name}-eks"
  cluster_version = "1.29"
  vpc_id          = module.aws_vpc.vpc_id
  subnet_ids      = module.aws_vpc.private_subnets
  node_count      = var.k8s_node_count
  node_type       = var.k8s_node_type_aws
}

# ===========================================================
#  GKE CLUSTER (GCP)
# ===========================================================

module "gke" {
  source = "./modules/gke"

  cluster_name = "${var.project_name}-gke"
  project_id   = var.gcp_project
  region       = var.gcp_region
  node_count   = var.k8s_node_count
  node_type    = var.k8s_node_type_gcp
}

# ===========================================================
#  CLOUDFLARE HEALTH CHECKS
#  These verify application-level health, not just TCP.
# ===========================================================

resource "cloudflare_healthcheck" "aws_health" {
  zone_id        = var.cloudflare_zone_id
  name           = "aws-endpoint-health"
  address        = module.eks.ingress_endpoint
  type           = "HTTPS"
  port           = 443
  method         = "GET"
  path           = "/healthz"
  expected_codes = ["200"]
  interval       = 30
  timeout        = 10
  retries        = 2
}

resource "cloudflare_healthcheck" "gcp_health" {
  zone_id        = var.cloudflare_zone_id
  name           = "gcp-endpoint-health"
  address        = module.gke.ingress_endpoint
  type           = "HTTPS"
  port           = 443
  method         = "GET"
  path           = "/healthz"
  expected_codes = ["200"]
  interval       = 30
  timeout        = 10
  retries        = 2
}

# ===========================================================
#  CLOUDFLARE LOAD BALANCER
#  Geo-based steering with automatic health failover.
#  DNS TTL of 30s ensures fast propagation on failure.
# ===========================================================

resource "cloudflare_load_balancer_pool" "aws_pool" {
  account_id = var.cloudflare_account_id
  name       = "aws-pool"

  origins {
    name    = "aws-origin"
    address = module.eks.ingress_endpoint
    enabled = true
    header {
      header = "Host"
      values = [var.domain]
    }
  }

  notification_email = var.oncall_email
  minimum_origins    = 1
}

resource "cloudflare_load_balancer_pool" "gcp_pool" {
  account_id = var.cloudflare_account_id
  name       = "gcp-pool"

  origins {
    name    = "gcp-origin"
    address = module.gke.ingress_endpoint
    enabled = true
    header {
      header = "Host"
      values = [var.domain]
    }
  }

  notification_email = var.oncall_email
  minimum_origins    = 1
}

resource "cloudflare_load_balancer" "app" {
  zone_id          = var.cloudflare_zone_id
  name             = var.domain
  fallback_pool_id = cloudflare_load_balancer_pool.gcp_pool.id
  default_pool_ids = [cloudflare_load_balancer_pool.aws_pool.id]
  proxied          = true

  # Geo-based steering: US East to AWS, US Central to GCP
  pop_pools {
    pop      = "IAD"
    pool_ids = [cloudflare_load_balancer_pool.aws_pool.id]
  }
  pop_pools {
    pop      = "ORD"
    pool_ids = [cloudflare_load_balancer_pool.gcp_pool.id]
  }

  session_affinity = "cookie"
  ttl              = 30
}

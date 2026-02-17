# 🚨 Survival-Grade Cloud Architecture (SGCA)

### Designing Systems That Survive Regional Collapse, Provider Failure & Digital Fragmentation

> If your cloud provider disappeared tomorrow, would your system survive?

This repository contains the **complete, working implementation** of a Survival-Grade Cloud Architecture: a multi-cloud active-active setup across AWS and GCP with independent DNS failover, cross-cloud data replication, provider-agnostic identity, and automated blackout testing.

This is not a proof-of-concept. It's a production-ready blueprint used as the companion repo to the blog post:
**[The Global Cloud Blackout](https://yourblog.hashnode.dev/the-global-cloud-blackout)**

---

## What This Solves

Most "highly available" architectures fail under these real-world scenarios:

| Threat Model | Example | Does Multi-AZ Survive? |
|---|---|---|
| **Regional Infrastructure Collapse** | us-east-1 power/network failure | ❌ No |
| **Control Plane Failure** | AWS IAM, API, Console unreachable | ❌ No |
| **DNS / Routing Disruption** | BGP hijack, DNS provider outage | ❌ No |
| **Geopolitical Isolation** | Sanctions, sovereign data laws, account suspension | ❌ No |

This architecture survives **all four**.

---

## Architecture Overview

```
┌─── Cloudflare DNS (Independent) ────────────────────────┐
│   Health-based routing │ TTL: 30s │ NS1 as backup DNS   │
└────────────┬────────────────────────────┬───────────────┘
             │                            │
┌────────────▼────────────┐  ┌────────────▼────────────┐
│     AWS EKS (Primary)    │  │    GCP GKE (Secondary)   │
│                          │  │                          │
│  ArgoCD Agent            │  │  ArgoCD Agent            │
│  Application Pods        │  │  Application Pods        │
│  Keycloak (Auth)         │  │  Keycloak (Auth)         │
│  Vault (Secrets)         │  │  Vault (Secrets)         │
│                          │  │                          │
│  CockroachDB Node (x3)  │  │  CockroachDB Node (x3)  │
│  Kafka Broker            │  │  Kafka Broker            │
│  S3 (Objects)            │  │  GCS (Objects, synced)   │
└──────────────────────────┘  └──────────────────────────┘
```

**4 Layers:**

1. **Global Traffic Authority** — Cloudflare + NS1 dual DNS, health-based failover, 30s TTL
2. **Active-Active Compute** — EKS + GKE, ArgoCD GitOps from single repo, Kustomize overlays
3. **Data Survival** — CockroachDB cross-cloud replication, Kafka MirrorMaker 2, S3↔GCS sync
4. **Identity Independence** — Keycloak on both clouds backed by shared CockroachDB, Vault for secrets

---

## Repository Structure

```
survival-grade-infra/
├── terraform/                          # Infrastructure as Code
│   ├── main.tf                         # Multi-cloud providers + Cloudflare LB
│   ├── variables.tf                    # All configurable parameters
│   ├── outputs.tf                      # Cluster endpoints, DNS records
│   └── modules/
│       ├── eks/                        # AWS EKS cluster module
│       ├── gke/                        # GCP GKE cluster module
│       └── dns/                        # Cloudflare DNS + health checks
│
├── k8s/                                # Kubernetes Manifests
│   ├── base/                           # Shared base manifests
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml             # App deployment with topology spread
│   │   ├── service.yaml                # ClusterIP + Ingress with TLS
│   │   ├── cockroachdb-multicloud.yaml # CockroachDB StatefulSet
│   │   └── keycloak.yaml               # Identity layer
│   ├── overlays/                       # Cloud-specific Kustomize patches
│   │   ├── aws/kustomization.yaml      # ECR registry, AWS Kafka brokers
│   │   └── gcp/kustomization.yaml      # GCR registry, GCP Kafka brokers
│   └── argocd/                         # GitOps Application definitions
│       ├── app-aws.yaml
│       └── app-gcp.yaml
│
├── src/
│   └── storage-sync/
│       └── sync-worker.py              # Event-driven S3 ↔ GCS replication
│
├── ci/
│   └── .github/workflows/
│       └── multi-cloud-deploy.yaml     # Build, sign, push to ECR + GCR
│
├── chaos/
│   ├── blackout-test.sh                # Full 6-phase blackout drill
│   └── dns-failover-test.sh            # Quick DNS failover smoke test
│
└── docker/
    └── Dockerfile                      # Multi-stage production image
```

---

## Prerequisites

- AWS account with EKS permissions
- GCP project with GKE permissions
- Cloudflare account (Pro plan or higher for Load Balancing)
- Terraform >= 1.5
- kubectl, kustomize, ArgoCD CLI
- Docker, Cosign
- GitHub repository with OIDC configured for AWS and GCP

---

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/yourusername/survival-grade-infra.git
cd survival-grade-infra

# Copy and fill in your values
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 2. Provision Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates: AWS VPC + EKS, GCP GKE, Cloudflare health checks + load balancer.

### 3. Install ArgoCD on Both Clusters

```bash
# AWS cluster
kubectl config use-context aws-eks
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f k8s/argocd/app-aws.yaml

# GCP cluster
kubectl config use-context gcp-gke
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f k8s/argocd/app-gcp.yaml
```

### 4. Deploy CockroachDB

```bash
# On both clusters
kubectl apply -f k8s/base/cockroachdb-multicloud.yaml

# Initialize the cluster (run once from either cloud)
kubectl exec -it cockroachdb-0 -- cockroach init --insecure
```

### 5. Deploy Keycloak

```bash
kubectl apply -f k8s/base/keycloak.yaml
```

### 6. Run Your First Blackout Drill

```bash
cd chaos
chmod +x blackout-test.sh
./blackout-test.sh
```

---

## Resilience Metrics

Track these quarterly:

| Metric | What It Measures | Target |
|---|---|---|
| **Cloud Exit Time (CET)** | Time to fully operate from alternate provider | < 2 minutes |
| **Control Plane Dependency Index (CPDI)** | % of infra tied to single cloud APIs | < 30% |
| **Data Replication Confidence Score (DRCS)** | Verified via blackout drill data integrity tests | > 99% |

---

## Resilience Maturity Model

| Tier | Architecture | Survives |
|---|---|---|
| Tier 0 | Multi-AZ | Single AZ failure |
| Tier 1 | Multi-Region | Region failure |
| Tier 2 | Multi-Cloud Passive | Provider outage (manual failover) |
| **Tier 3** | **Multi-Cloud Active-Active** | **Provider outage (automatic)** |
| Tier 4 | Sovereign Split | Geopolitical isolation |

This repo implements **Tier 3** with foundations for Tier 4.

---

## Cost Estimate

Rough monthly cost for running this architecture:

| Component | Monthly Cost (USD) |
|---|---|
| AWS EKS (3x t3.xlarge) | ~$500 |
| GCP GKE (3x e2-standard-4) | ~$450 |
| CockroachDB storage (600Gi total) | ~$120 |
| Cloudflare Pro + Load Balancing | ~$25 |
| Container registries (ECR + GCR) | ~$20 |
| **Total** | **~$1,115/month** |

The cost of a single hour of downtime for a business processing $2M/day is ~$83,000. This architecture pays for itself after preventing 49 minutes of outage.

---

## Blog Post

This repo is the companion to the full technical article:
**[The Global Cloud Blackout: Designing Systems That Survive Regional Collapse, Provider Failure & Digital Fragmentation](https://yourblog.hashnode.dev/the-global-cloud-blackout)**

---

## License

MIT License. Use it, fork it, make your systems survive.

---

## Contributing

Found an improvement? Open a PR. Found a bug during your blackout drill? Open an issue. Let's make cloud resilience accessible to every engineering team.

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "shopglobal"
}

variable "aws_region" {
  description = "AWS region for primary cloud"
  type        = string
  default     = "us-east-1"
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for secondary cloud"
  type        = string
  default     = "us-central1"
}

variable "domain" {
  description = "Application domain name"
  type        = string
  default     = "app.shopglobal.com"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare DNS zone ID"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "k8s_node_count" {
  description = "Number of Kubernetes nodes per cloud"
  type        = number
  default     = 3
}

variable "k8s_node_type_aws" {
  description = "AWS EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "k8s_node_type_gcp" {
  description = "GCP machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "oncall_email" {
  description = "Email for health check notifications"
  type        = string
  default     = "oncall@shopglobal.com"
}

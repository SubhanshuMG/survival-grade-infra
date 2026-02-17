variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "node_count" { type = number }
variable "node_type" { type = string }

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    primary = {
      desired_size   = var.node_count
      min_size       = var.node_count
      max_size       = var.node_count * 2
      instance_types = [var.node_type]

      labels = {
        role = "primary"
      }
    }
  }

  # Enable IRSA for pod-level IAM
  enable_irsa = true
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ingress_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

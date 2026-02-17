output "eks_cluster_endpoint" {
  description = "AWS EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "AWS EKS cluster name"
  value       = module.eks.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GCP GKE cluster API endpoint"
  value       = module.gke.cluster_endpoint
}

output "gke_cluster_name" {
  description = "GCP GKE cluster name"
  value       = module.gke.cluster_name
}

output "cloudflare_lb_hostname" {
  description = "Cloudflare Load Balancer hostname"
  value       = cloudflare_load_balancer.app.name
}

output "aws_pool_id" {
  description = "Cloudflare AWS pool ID (used in blackout drills)"
  value       = cloudflare_load_balancer_pool.aws_pool.id
}

output "gcp_pool_id" {
  description = "Cloudflare GCP pool ID (used in blackout drills)"
  value       = cloudflare_load_balancer_pool.gcp_pool.id
}

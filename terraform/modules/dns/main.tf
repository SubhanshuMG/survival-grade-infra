# DNS module: Secondary DNS provider (NS1) as backup for Cloudflare
#
# Cloudflare is the primary DNS + load balancer (configured in main.tf).
# This module sets up NS1 as an independent secondary that can take over
# if Cloudflare itself experiences an outage.
#
# To use this module, you'll need an NS1 account and API key.
# Set the NS1_APIKEY environment variable before running terraform.

variable "domain" { type = string }
variable "aws_endpoint" { type = string }
variable "gcp_endpoint" { type = string }

# Uncomment and configure when you have an NS1 account:
#
# terraform {
#   required_providers {
#     ns1 = {
#       source  = "ns1-terraform/ns1"
#       version = "~> 2.0"
#     }
#   }
# }
#
# provider "ns1" {
#   # API key set via NS1_APIKEY env var
# }
#
# resource "ns1_zone" "app" {
#   zone = var.domain
# }
#
# resource "ns1_record" "app" {
#   zone   = ns1_zone.app.zone
#   domain = var.domain
#   type   = "A"
#
#   answers {
#     answer = var.aws_endpoint
#     meta = {
#       up = true
#     }
#   }
#
#   answers {
#     answer = var.gcp_endpoint
#     meta = {
#       up = true
#     }
#   }
#
#   filters {
#     filter = "up"
#   }
#
#   filters {
#     filter = "select_first_n"
#     config = {
#       N = 1
#     }
#   }
# }

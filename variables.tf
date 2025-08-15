variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "aws_account_id" {
  type = string
}
variable "project_name" {
  type    = string
  default = "homework"
}

# # # # # # # # #
# EKS variables #
# # # # # # # # #
variable "eks_network_prefix" {
  type    = string
  default = "150"
}

variable "eks_node_type" {
  type    = string
  default = "t3.small"
}

variable "eks_ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}

variable "eks_min_nodes" {
  type        = number
  description = "Minimum size of autoscaling group"
  default     = 2
}
variable "eks_max_nodes" {
  type        = number
  description = "Maximum size of autoscaling group"
  default     = 5
}

variable "eks_asg_desired_capacity" {
  type        = number
  description = "Desired size of autoscaling group"
  default     = 2
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.33"
}

variable "eks_public_endpoint_cidr" {
  type    = string
  default = ""
}
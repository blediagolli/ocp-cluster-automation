variable "cluster_name" {
  description = "Name of the OpenShift cluster"
  type        = string
}

variable "base_domain" {
  description = "Route53 base domain (hosted zone)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use (max 3)"
  type        = list(string)
  default     = []
}

variable "master_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes (0 for compact)"
  type        = number
  default     = 0
}

variable "master_instance_type" {
  description = "EC2 instance type for masters"
  type        = string
  default     = "m5.xlarge"
}

variable "worker_instance_type" {
  description = "EC2 instance type for workers"
  type        = string
  default     = "m5.xlarge"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 120
}

variable "root_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "ami_id" {
  description = "AMI ID to boot instances from (discovery ISO AMI or base RHCOS)"
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "Name of existing EC2 key pair for SSH access"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key material (creates a new key pair if ssh_key_name is empty)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

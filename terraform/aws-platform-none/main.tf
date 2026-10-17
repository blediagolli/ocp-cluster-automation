terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    data.aws_availability_zones.available.names, 0,
    min(3, length(data.aws_availability_zones.available.names))
  )

  common_tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "openshift-cluster"                         = var.cluster_name
    "managed-by"                                = "terraform"
  })

  all_node_ids = concat(
    aws_instance.master[*].id,
    aws_instance.worker[*].id,
  )

  master_private_ips = aws_instance.master[*].private_ip
  worker_private_ips = aws_instance.worker[*].private_ip
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_route53_zone" "base" {
  name = var.base_domain
}

# ── VPC ──

resource "aws_vpc" "cluster" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc"
  })
}

resource "aws_internet_gateway" "cluster" {
  vpc_id = aws_vpc.cluster.id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-igw"
  })
}

# ── Subnets ──

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.cluster.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-public-${local.azs[count.index]}"
  })
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.cluster.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-private-${local.azs[count.index]}"
  })
}

# ── NAT Gateway (one per AZ for HA) ──

resource "aws_eip" "nat" {
  count  = length(local.azs)
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nat-${local.azs[count.index]}"
  })
}

resource "aws_nat_gateway" "cluster" {
  count         = length(local.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.cluster]
}

# ── Route Tables ──

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cluster.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.cluster.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.cluster[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-private-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── SSH Key Pair ──

resource "aws_key_pair" "cluster" {
  count      = var.ssh_key_name == "" && var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.cluster_name}-key"
  public_key = var.ssh_public_key

  tags = local.common_tags
}

locals {
  key_name = var.ssh_key_name != "" ? var.ssh_key_name : (
    length(aws_key_pair.cluster) > 0 ? aws_key_pair.cluster[0].key_name : ""
  )
}

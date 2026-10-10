# ── Security Groups ──

resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "OpenShift cluster inter-node traffic"
  vpc_id      = aws_vpc.cluster.id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# All traffic between cluster nodes
resource "aws_vpc_security_group_ingress_rule" "cluster_internal" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "All inter-node traffic"
}

# API server from anywhere
resource "aws_vpc_security_group_ingress_rule" "api" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  description       = "Kubernetes API"
}

# Machine config server (bootstrap)
resource "aws_vpc_security_group_ingress_rule" "mcs" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 22623
  to_port           = 22623
  ip_protocol       = "tcp"
  description       = "Machine config server"
}

# HTTPS ingress
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS ingress"
}

# HTTP ingress
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP ingress"
}

# SSH
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH access"
}

# NodePort range
resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  description       = "NodePort services"
}

# VXLAN (OVN-Kubernetes)
resource "aws_vpc_security_group_ingress_rule" "vxlan" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 4789
  to_port                      = 4789
  ip_protocol                  = "udp"
  description                  = "VXLAN overlay"
}

# Geneve (OVN-Kubernetes)
resource "aws_vpc_security_group_ingress_rule" "geneve" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 6081
  to_port                      = 6081
  ip_protocol                  = "udp"
  description                  = "Geneve overlay"
}

# All outbound
resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

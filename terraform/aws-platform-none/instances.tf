# ── EC2 Instances ──

# Use latest RHCOS AMI if no AMI specified (for initial provisioning before
# discovery ISO is available). These instances will be re-imaged by sushy
# with the discovery ISO once InfraEnv generates it.
data "aws_ami" "rhcos" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["531415883065"] # Red Hat

  filter {
    name   = "name"
    values = ["rhcos-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  boot_ami = var.ami_id != "" ? var.ami_id : (
    length(data.aws_ami.rhcos) > 0 ? data.aws_ami.rhcos[0].id : ""
  )
}

resource "aws_instance" "master" {
  count                  = var.master_count
  ami                    = local.boot_ami
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.private[count.index % length(local.azs)].id
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = local.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(local.common_tags, {
    Name             = "${var.cluster_name}-master-${count.index}"
    "sushy-managed"  = "true"
    "cluster-role"   = "master"
    "cluster-name"   = var.cluster_name
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = local.boot_ami
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.private[count.index % length(local.azs)].id
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = local.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(local.common_tags, {
    Name             = "${var.cluster_name}-worker-${count.index}"
    "sushy-managed"  = "true"
    "cluster-role"   = "worker"
    "cluster-name"   = var.cluster_name
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ── S3 Bucket for ISO conversion (used by sushy-emulator) ──

resource "aws_s3_bucket" "discovery" {
  bucket        = "${var.cluster_name}-discovery-iso"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-discovery-iso"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "discovery" {
  bucket = aws_s3_bucket.discovery.id

  rule {
    id     = "cleanup"
    status = "Enabled"
    filter {}
    expiration {
      days = 7
    }
  }
}

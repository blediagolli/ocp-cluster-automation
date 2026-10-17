# ── Outputs ──

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.cluster.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.cluster.cidr_block
}

output "api_url" {
  description = "Kubernetes API URL"
  value       = "https://api.${var.cluster_name}.${var.base_domain}:6443"
}

output "console_url" {
  description = "OpenShift console URL"
  value       = "https://console-openshift-console.apps.${var.cluster_name}.${var.base_domain}"
}

output "api_nlb_dns" {
  description = "API NLB DNS name"
  value       = aws_lb.api.dns_name
}

output "ingress_nlb_dns" {
  description = "Ingress NLB DNS name"
  value       = aws_lb.ingress.dns_name
}

output "s3_bucket" {
  description = "S3 bucket for discovery ISO conversion"
  value       = aws_s3_bucket.discovery.id
}

# ── Master instance details ──

output "master_instance_ids" {
  description = "EC2 instance IDs for masters"
  value       = aws_instance.master[*].id
}

output "master_private_ips" {
  description = "Private IPs of master instances"
  value       = aws_instance.master[*].private_ip
}

output "master_mac_addresses" {
  description = "Primary MAC addresses of master instances"
  value       = aws_instance.master[*].primary_network_interface_id
}

# ── Worker instance details ──

output "worker_instance_ids" {
  description = "EC2 instance IDs for workers"
  value       = aws_instance.worker[*].id
}

output "worker_private_ips" {
  description = "Private IPs of worker instances"
  value       = aws_instance.worker[*].private_ip
}

# ── Helm chart values generator ──

output "helm_values" {
  description = "Generated values for the openshift-provisioning Helm chart"
  value = yamlencode({
    provision = { include = true }
    cluster = {
      name       = var.cluster_name
      baseDomain = var.base_domain
      platform   = "none"
      imageSetRef = ""
      networkType = "OVNKubernetes"
    }
    none = {
      apiVIPs              = []
      ingressVIPs          = []
      provisionRequirements = {
        controlPlaneAgents = var.master_count
        workerAgents       = var.worker_count
      }
    }
    networking = {
      clusterNetwork = [{ cidr = "10.128.0.0/14", hostPrefix = 23 }]
      serviceNetwork = ["172.30.0.0/16"]
      machineNetwork = [{ cidr = var.vpc_cidr }]
    }
  })
}

# ── Sushy emulator config ──

output "sushy_instance_config" {
  description = "JSON config for sushy-emulator instance mapping"
  value = jsonencode({
    instances = merge(
      { for i, inst in aws_instance.master : inst.id => {
        uuid = "${var.cluster_name}-master-${i}"
        role = "master"
        name = "${var.cluster_name}-master-${i}"
      }},
      { for i, inst in aws_instance.worker : inst.id => {
        uuid = "${var.cluster_name}-worker-${i}"
        role = "worker"
        name = "${var.cluster_name}-worker-${i}"
      }}
    )
  })
}

# ── BareMetalHost values for Helm chart ──

output "baremetal_hosts_values" {
  description = "Host entries for the Helm chart's baremetal.hosts / none.hosts values"
  value = [
    for i, inst in aws_instance.master : {
      name           = "${var.cluster_name}-master-${i}"
      role           = "master"
      bootMACAddress = "generated-by-aws"
      bmcAddress     = "redfish-virtualmedia+https://sushy-ec2.${var.cluster_name}.svc:8000/redfish/v1/Systems/${inst.id}"
      instance_id    = inst.id
      private_ip     = inst.private_ip
    }
  ]
}

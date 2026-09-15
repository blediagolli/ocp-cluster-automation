#!/usr/bin/env bash
set -euo pipefail

# Generates provision.yaml values for the Helm chart from Terraform outputs.
# Run after `terraform apply` in this directory.
#
# Usage:
#   ./generate-provision-values.sh <cluster-name> <base-domain> <image-set-ref> <ssh-pub-key>
#
# Example:
#   ./generate-provision-values.sh aws-none-prod sandbox3321.opentlc.com img4.22.13-x86-64-appsub "ssh-ed25519 AAAA..."

CLUSTER_NAME="${1:?Usage: $0 <cluster-name> <base-domain> <image-set-ref> <ssh-pub-key>}"
BASE_DOMAIN="${2:?Missing base domain}"
IMAGE_SET_REF="${3:?Missing image set ref}"
SSH_PUB_KEY="${4:?Missing SSH public key}"

echo "Collecting Terraform outputs..."

MASTER_IDS=($(terraform output -json master_instance_ids | jq -r '.[]'))
S3_BUCKET=$(terraform output -raw s3_bucket)
VPC_CIDR=$(terraform output -raw vpc_cidr)

# Get MAC addresses from AWS (Terraform doesn't expose them directly)
echo "Fetching MAC addresses from AWS..."
REGION=$(terraform output -raw 2>/dev/null || grep 'region' terraform.tfvars 2>/dev/null | head -1 | awk -F'"' '{print $2}' || echo "us-east-2")

declare -a MACS
for id in "${MASTER_IDS[@]}"; do
    mac=$(aws ec2 describe-instances \
        --instance-ids "$id" \
        --query 'Reservations[0].Instances[0].NetworkInterfaces[0].MacAddress' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "unknown")
    MACS+=("$mac")
done

OUTPUT_FILE="../../clusters/prod/${CLUSTER_NAME}/provision.yaml"

cat > "$OUTPUT_FILE" << EOF
provision:
  include: true

cluster:
  name: ${CLUSTER_NAME}
  baseDomain: ${BASE_DOMAIN}
  platform: none
  environment: prod
  clusterSet: default
  imageSetRef: ${IMAGE_SET_REF}
  networkType: OVNKubernetes
  sshPublicKey: "${SSH_PUB_KEY}"

fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22

masters:
  count: 3

workers:
  count: 0

none:
  apiVIPs: []
  ingressVIPs: []
  provisionRequirements:
    controlPlaneAgents: ${#MASTER_IDS[@]}
    workerAgents: 0

networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: ${VPC_CIDR}

baremetal:
  bmc:
    username: admin
    password: password
  hosts:
EOF

for i in "${!MASTER_IDS[@]}"; do
    cat >> "$OUTPUT_FILE" << EOF
    - name: ${CLUSTER_NAME}-master-${i}
      role: master
      bootMACAddress: "${MACS[$i]}"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.${CLUSTER_NAME}.svc:8000/redfish/v1/Systems/${MASTER_IDS[$i]}"
EOF
done

echo ""
echo "Generated: ${OUTPUT_FILE}"
echo ""
echo "Sushy emulator config (apply to cluster):"
echo ""

# Also generate the sushy ConfigMap
cat << EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sushy-ec2-config
  namespace: ${CLUSTER_NAME}
data:
  instances.json: |
    {
      "instances": {
EOF

for i in "${!MASTER_IDS[@]}"; do
    COMMA=""
    if [ $i -lt $(( ${#MASTER_IDS[@]} - 1 )) ]; then COMMA=","; fi
    cat << EOF
        "${MASTER_IDS[$i]}": {
          "uuid": "${CLUSTER_NAME}-master-${i}",
          "role": "master"
        }${COMMA}
EOF
done

cat << EOF
      }
    }
---
apiVersion: v1
kind: Secret
metadata:
  name: sushy-ec2-aws-creds
  namespace: ${CLUSTER_NAME}
type: Opaque
stringData:
  region: ${REGION}
  aws_access_key_id: \${AWS_ACCESS_KEY_ID}
  aws_secret_access_key: \${AWS_SECRET_ACCESS_KEY}
  s3_bucket: ${S3_BUCKET}
EOF

echo ""
echo "Next steps:"
echo "  1. Review ${OUTPUT_FILE}"
echo "  2. git add / commit / push the provision.yaml"
echo "  3. Apply sushy-emulator deployment + config to the cluster namespace"
echo "  4. ArgoCD will pick up the cluster and start provisioning"

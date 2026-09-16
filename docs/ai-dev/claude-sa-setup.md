# Claude Automation ServiceAccount Setup

Long-lived ServiceAccount and kubeconfig for the hub cluster, so Claude Code sessions can authenticate without a manual `oc login` each time.

## What was created

### Namespace

```
claude-automation
```

### ServiceAccount

```
claude-admin (in claude-automation namespace)
```

### ClusterRoleBinding

```
cluster-admin -> system:serviceaccount:claude-automation:claude-admin
```

### Long-lived token Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: claude-admin-token
  namespace: claude-automation
  annotations:
    kubernetes.io/service-account.name: claude-admin
type: kubernetes.io/service-account-token
```

This secret type is automatically populated with a token by the OpenShift token controller. Unlike bound tokens (which expire), this token persists until the secret is deleted.

### Kubeconfig

Written to `~/.kube/claude-hub-kubeconfig` with:

- Cluster: hub cluster API server (`insecure-skip-tls-verify: true`)
- User: `claude-admin` using the SA token
- Context: `hub-cluster`

## Usage

```bash
KUBECONFIG=~/.kube/claude-hub-kubeconfig oc whoami
KUBECONFIG=~/.kube/claude-hub-kubeconfig oc get nodes
```

## Recreating (if cluster is reprovisioned)

```bash
# Log in with a fresh token first, then:
oc create namespace claude-automation
oc create serviceaccount claude-admin -n claude-automation
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:claude-automation:claude-admin

cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: claude-admin-token
  namespace: claude-automation
  annotations:
    kubernetes.io/service-account.name: claude-admin
type: kubernetes.io/service-account-token
EOF

# Extract token and write kubeconfig
TOKEN=$(oc get secret claude-admin-token -n claude-automation -o jsonpath='{.data.token}' | base64 -d)
SERVER=$(oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}')

cat > ~/.kube/claude-hub-kubeconfig <<KUBEEOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: ${SERVER}
  name: hub-cluster
contexts:
- context:
    cluster: hub-cluster
    user: claude-admin
  name: hub-cluster
current-context: hub-cluster
users:
- name: claude-admin
  user:
    token: ${TOKEN}
KUBEEOF

chmod 600 ~/.kube/claude-hub-kubeconfig
```

## Revoking access

```bash
oc delete secret claude-admin-token -n claude-automation
oc delete serviceaccount claude-admin -n claude-automation
oc adm policy remove-cluster-role-from-user cluster-admin system:serviceaccount:claude-automation:claude-admin
oc delete namespace claude-automation
rm ~/.kube/claude-hub-kubeconfig
```

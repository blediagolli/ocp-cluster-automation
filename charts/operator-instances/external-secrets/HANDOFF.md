# external-secrets

Platform-level ExternalSecret CRs for cluster-wide secrets (ingress certs, OIDC, pull secrets) synced from Vault via the ClusterSecretStore.

**App-specific secrets should live in the app's own chart, not here.**

## What it does

Templates `ExternalSecret` resources from a `secrets` list in values. Each entry specifies the target secret name, namespace, type, and which Vault KV path/properties to pull from. The chart references a `ClusterSecretStore` (defaulting to `vault`, created by the `vault-server` platform-config chart).

## Values structure

```yaml
secretStoreRef:
  name: vault                    # default ClusterSecretStore name
  kind: ClusterSecretStore

secrets:
  - include: true
    name: my-tls-cert            # name of the K8s Secret created
    namespace: openshift-ingress  # target namespace
    type: kubernetes.io/tls       # secret type (Opaque if omitted)
    refreshInterval: 1h           # how often to re-sync from Vault
    vault:
      path: secret/data/clusters/my-cluster/ingress-cert
      properties:
        - secretKey: tls.crt      # key in the K8s Secret
          property: tls.crt       # key in the Vault KV entry
        - secretKey: tls.key
          property: tls.key
```

Per-secret `secretStoreRef` override is supported — omit to use the chart-level default.

## Dependencies

- `external-secrets-operator` must be deployed via operator-deployment
- `ClusterSecretStore` must exist (created by vault-server chart with `secretStore.include: true`)
- Vault must have the KV paths populated and the Kubernetes auth role configured

## Testing

```bash
helm template test charts/operator-instances/external-secrets/ -f <values-file>
```

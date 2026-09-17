# ACS Secured Cluster Setup

The `acs-secured-cluster` chart deploys a SecuredCluster CR, an init bundle generation job, and the necessary RBAC. The env-level config (`env/dev/operator-instances.yaml`) handles most defaults including `secretMode: "generate"` and `centralEndpoint`.

## Resource tuning for small clusters

ACS defaults are designed for production — sensor requests 2 CPU, Central requests 1.5 CPU, and scanner replicas default to 2-3. On small/workshop clusters, override in `operator-instances.yaml`:

```yaml
securedCluster:
  sensor:
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2
        memory: 4Gi
  scannerV4:
    scannerComponent: Disabled    # delegate scanning to Central
  admissionControl:
    listenOnCreates: false         # disable webhook overhead
    listenOnUpdates: false
    listenOnEvents: false
  perNode:
    collector:
      imageFlavor: Slim            # smaller collector images
```

For Central on the hub, override in `clusters/mgt/acm-hub/operator-instances.yaml`:

```yaml
central:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
  scanner:
    analyzer:
      scaling:
        minReplicas: 1
        maxReplicas: 3
  scannerV4:
    indexer:
      scaling:
        minReplicas: 1
    matcher:
      scaling:
        minReplicas: 1
```

## Init bundle secrets

The init bundle generation job (`secretMode: "generate"`) calls Central's API and applies the `kubectlBundle` response. This creates three secrets: `sensor-tls`, `collector-tls`, `admission-control-tls`.

**Do NOT manually create `tls-cert-*` secrets.** ACS 4.11 creates these internally from the legacy init bundle secrets. Manually creating partial `tls-cert-*` secrets triggers a CA consistency check failure that blocks operator reconciliation entirely. If you see the error `runtime-retrieved TLS secrets are not consistent (are signed by different CAs)`, delete all `tls-cert-*` secrets and restart the operator pod.

## Init bundle timing

The init bundle job is an ArgoCD PostSync hook. It requires Central to be reachable. If Central is down (e.g. Pending due to resource pressure), the job retries for 5 minutes then fails. Fix Central first, then re-sync the ArgoCD app to re-trigger the PostSync hook.

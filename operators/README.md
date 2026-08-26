# Operator and cluster configuration

This directory manages day-2 operators for clusters provisioned or registered by
this repository.

## Layout

- `../base/operators/` contains reusable operator installation and instance resources.
- `components/operator-profiles/` contains OpenShift-version compatibility patches.
- `targets/<operator-profile>/<cluster-type>/` contains complete deployable targets.
- `../clusters/acm-hub.redhat.com/applicationsets/multi-cluster-config-appset.yaml`
  fans targets out to cluster inventory files in Git.

Each operator separates OLM installation from operator instances:

```text
../base/operators/<name>/
  install/
  instances/default/
```

The target path and destination are selected by the `operator` and `cluster` fields in
each inventory file:

```text
operator.managed=true in `clusters/<environment>/<cluster>/operator-conf.yaml`
operator.clusterType=hub|prod|dev
operator.profile=ocp-4.22|ocp-4.21
cluster.address=<registered Argo CD cluster server>
```

Only inventory files included by the ApplicationSet are selected. Provisioning remains
owned by the ACM provisioning ApplicationSet, and existing ACM policies must not
manage the same Subscription or custom resource as an operator target.

The ACM hub must have a `ManagedClusterSet` named `vmware`, because the provisioning
chart assigns managed clusters to that set and the GitOps registration placement binds
to it.

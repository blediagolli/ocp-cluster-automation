# openshift-apiserver — Handoff

**Date:** 2026-09-04

## What it does
Manages the cluster-wide `APIServer` CR (`config.openshift.io/v1`). Configures audit policy profile, custom audit rules, serving certificates, TLS security profile, etcd encryption, and CORS origins.

## What was done
- Created new from gap analysis
- A duplicate `apiserver-config` chart was also created then deleted — this chart absorbed both
- Supports audit profiles: Default, WriteRequestBodies, AllRequestBodies, None
- Custom audit rules for fine-grained resource-level control
- Named serving certificates for custom API hostnames
- etcd encryption (aescbc)

## Current state
- **Disabled** (`apiServer.include: false`) — not enabled on any cluster
- Not tested on cluster

## Outstanding
- Enable per cluster to set audit profile and encryption
- Named certificates require TLS secrets to exist first
- Consider adding `clientCA` support for mutual TLS

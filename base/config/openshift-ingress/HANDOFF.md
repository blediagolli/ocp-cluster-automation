# openshift-ingress — Handoff

**Modified:** 2026-09-04 (deep dive agents)

## What it does

Configures the OpenShift Ingress Controller and related services. Templates:
- **IngressController** — placement (infra nodes), replicas, endpoint publishing strategy, access logging, TLS security profile, HTTP/2, HSTS, default certificate, additional domains
- **Service** — NodePort/LoadBalancer with configurable ports and traffic policy

## What changed this session

- Added TLS security profile configuration (custom cipher suites, min TLS version)
- Added HTTP/2 toggle
- Added HSTS header configuration
- Added default certificate support (reference a TLS secret)
- Added multi-domain IngressController support via `domains` list
- Added access logging configuration (syslog destination)
- Added Service template with traffic policy control

## Current state

- Active on hub and clusters (in ApplicationSet shared config list)
- Controller and service default to `include: false`

## Outstanding

- Configure TLS profile per security requirements
- Set up custom default certificate if using non-default wildcard
- Configure access logging destination if using syslog collector

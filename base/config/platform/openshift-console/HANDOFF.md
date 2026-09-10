# openshift-console — Handoff

**Date:** 2026-09-04

## What it does

Manages the cluster `Console` CR (`config.openshift.io/v1`) and `ConsoleLink` resources. Configures custom branding (logo, product name), developer catalog (categories, type filtering), notification banners, and custom links in the console UI (HelpMenu, UserMenu, ApplicationMenu, NamespaceDashboard).

## What was done

- Created new this session by the deep-dive audit agent
- Two templates: `console.yaml` (Console CR) and `consolelinks.yaml` (ConsoleLink loop)
- All fields are optional and conditional — empty defaults produce a minimal CR
- Passes helm lint

## Current state

- **Not enabled** on any cluster (`include: false`)
- Not listed in any ApplicationSet — needs to be added to `cluster-config.yaml` before use

## Outstanding

- Add to `cluster-config.yaml` ApplicationSet when ready to deploy
- Enable per-cluster in `conf.yaml` with branding/notification values

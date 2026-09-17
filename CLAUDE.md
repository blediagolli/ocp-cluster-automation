# CLAUDE.md

## Public repo sync

This repo syncs to a sanitized public copy via `.github/workflows/sync-release.yml`.
The sanitization script (`.github/scripts/sanitize.sh`) replaces org-specific values
and secrets with placeholders, and `.github/sanitize.env` holds the non-secret values.

### Secret coverage check

When adding or modifying values files (`values.yaml`, `operator-instances.yaml`,
`platform-config.yaml`, `provision.yaml`, or any file under `clusters/`, `env/`,
or `teams/`) that contain:

- **New secrets** (passwords, tokens, client secrets, API keys): add the secret to
  `.github/scripts/sanitize.sh` section 4 (secret replacements) with a `CHANGEME_`
  placeholder, add the env var name to the `required_vars` array, and add the
  corresponding GitHub Actions secret name to the `env:` blocks in
  `.github/workflows/sync-release.yml` (both the sanitization step and verify step).

- **New org-specific values** (domains, cluster names, email addresses, AWS resource
  IDs, storage classes, bucket names): add the value to `.github/sanitize.env` and
  add a replacement line to `.github/scripts/sanitize.sh` section 3 with a `YOUR_`
  or descriptive placeholder.

- **New dev-only files or directories** that should not appear in the public repo:
  add them to section 1 of `.github/scripts/sanitize.sh`.

After making sanitize changes, remind the user to also update the placeholder table
in the README section of `sanitize.sh` (section 5) if new user-facing placeholders
were introduced.

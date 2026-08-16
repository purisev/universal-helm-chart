# Security Policy

## Supported versions

Security fixes land on the current release line: the `release-<X.Y.Z>` branch matching the version currently published to `oci://ghcr.io/purisev/universal-helm-chart`. Older release lines do not receive backported fixes.

## Reporting a vulnerability

Report privately through [GitHub's private vulnerability reporting](https://github.com/purisev/universal-helm-chart/security/advisories/new) — do not open a public issue or PR for a security report.

Include what's affected (the template, the rendered resource, the values that trigger it), the impact, and reproduction steps if you have them.

There's no formal SLA; this is a best-effort, single-maintainer project. Expect an initial response within a few days.

## Scope

In scope:

- Chart logic that renders an insecure manifest from reasonable input — e.g. a default that's more permissive than it should be, a template that silently drops a security-relevant field, a values combination that produces broken RBAC/NetworkPolicy/PodSecurityContext output.
- Supply-chain issues with how the chart itself is built and published (`.github/workflows/release.yaml`, the OCI artifact on GHCR).

Out of scope — report these upstream instead:

- Vulnerabilities in the controllers this chart integrates with but doesn't ship (KEDA, cert-manager, External Secrets Operator, Gateway API implementations, Argo CD, Prometheus/VictoriaMetrics operators, etc.).
- Vulnerabilities in container images you point `image.repository`/`image.tag` at — this chart doesn't choose or vet application images.
- Insecure values *you* set — e.g. disabling `securityContext` hardening, granting broad RBAC `rules`. The chart's defaults are the thing in scope, not every possible override.

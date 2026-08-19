# 020 — `tpl`-evaluated hostnames and parentRefs

- **Status:** Accepted
- **Date:** 2026-08-19

## Context

`values.yaml` authors need hostnames and Gateway API refs that vary by
release, most commonly a per-namespace or per-environment hostname such
as `{{ .Release.Namespace }}.example.com`. Until now, `templates/ingress.yaml`,
`templates/httproute.yaml`, `templates/grpcroute.yaml`,
`templates/tlsroute.yaml`, and `templates/referencegrant.yaml` emitted
these values straight from `.Values`, with no `tpl` pass. A Go-template
expression written there reached the rendered manifest as a literal
string, and the Kubernetes API server rejected it (invalid DNS label,
invalid resource name). Users had no way to parameterize these fields
short of maintaining a separate values file per environment.

## Decision

Evaluate the following fields through Helm's `tpl` function against the
root release context, at every render site (singleton and plural-map
forms alike):

- Ingress `hosts` (map keys) and `tls[].hosts[]`.
- HTTPRoute / GRPCRoute / TLSRoute `hostnames[]`.
- `parentRefs[].name` / `.namespace` / `.sectionName`, shared by all three
  route kinds through `uhc.gatewayParentRefs`.
- ReferenceGrant `from[].namespace` and `to[].name`, through two new
  helpers, `uhc.referenceGrantFrom` / `uhc.referenceGrantTo`.

`tpl` on a plain string with no `{{ }}` is a no-op, so every site
templates unconditionally. There's no `if strings.Contains "{{"` gate.

**Explicitly out of scope**, left untouched: backend/service-name fields
(Ingress `defaultBackend.serviceName`, path-level `serviceName`,
`backendRefs[].name` via `uhc.gatewayBackendRefs`), and the
`*RouteRuleSpec` helpers in general. Per-workload `deployments` /
`statefulSets` shorthand `httpRoute` / `grpcRoute` / `tlsRoute` blocks
carry no `hostnames`/`parentRefs` of their own. Those only live on the
singleton or plural-map entries (see
[ADR 009](009-dual-networking-stack.md)), so no per-workload
merge-section changes were needed either.

Two fields get a post-`tpl` empty-string `fail`. Kubernetes structurally
requires a non-empty value there, and today's presence-only `fail`
guards (checking the raw list/map isn't empty, never individual entry
content) would let a template that evaluates to `""` sail through
unnoticed: `parentRefs[].name` (via `uhc.gatewayParentRefs`) and TLSRoute
`hostnames[]` entries (TLSRoute matches purely by SNI, so an empty entry
is unambiguously broken). Every other touched field gets no such guard:
Ingress `host`/`tls[].hosts[]`, HTTPRoute/GRPCRoute `hostnames[]`, and
ReferenceGrant `from[].namespace`/`to[].name` are all optional overall,
an empty Ingress `host` is legitimately valid Kubernetes ("match all
hosts"), and the API server already rejects a genuinely broken value
clearly enough. Adding a chart-side guard everywhere would be scope
creep beyond fixing the literal-`{{ }}` bug, per
[ADR 013](013-schema-driven-validation.md)'s "templates render, don't
over-validate" default for anything the schema or API server can
already catch.

Ingress `host` is a YAML map key, not a plain scalar. Only the *emitted*
value is templated. `keys .Values.ingress.hosts | sortAlpha` and the
`index` lookup that pairs a key with its path config both keep using the
raw, untemplated key string. Templating the key itself would mean
rendering every host up front to re-key the map, a bigger change not
needed to stop a literal `{{ }}` from reaching the API server. One
consequence: sort order across multiple templated hosts follows the
literal source text, not the rendered hostname. That's cosmetic, not
functional, and worth stating here so it doesn't read as an oversight.

### Resolving the tension with ADR 013

[ADR 013](013-schema-driven-validation.md)'s schema-conventions section
states an intent, not yet implemented, that hostname fields should
eventually get "a standard DNS pattern" in `values.schema.json`. A
literal pre-render regex would reject every legitimate `{{ }}` value this
ADR now supports. This ADR formally amends that line: **hosts, hostnames,
parentRefs.name, and the templatable ReferenceGrant fields are exempt
from any future `values.schema.json` DNS-pattern constraint.** If
DNS-shape validation on these fields is wanted later, it must run
**post-render**: a template-side `fail` using `regexMatch` on the
already-`tpl`'d value. That's a deliberate, documented exception to
ADR 013's general "no regex in templates" rule, justified because the
schema literally cannot see a value that only exists after render. It's
never a `values.schema.json` `pattern`.

## Consequences

**What this enables:**

- Per-namespace/per-environment hostnames and refs from one shared
  `values.yaml`, no more literal-`{{ }}`-in-manifest rejections, no
  separate values file per environment just to vary a hostname.

**What it costs:**

- `tpl` is now a pattern in this chart; it wasn't used anywhere before
  this change. The scope here is deliberately narrow: hosts/hostnames
  and parentRefs/ReferenceGrant identity fields only, not "every string
  field." Any future extension should get its own ADR rather than
  assuming this one's scope silently grows.
- A `tpl`'d value has access to the full render context (`.Values`,
  `.Release`, `.Chart`, `.Capabilities`, `.Files`, `.Template`). That's
  standard `tpl` behavior, not a new trust boundary beyond what chart
  authors already extend to anyone who can write `values.yaml`.
- The empty-guard asymmetry above (two fields guarded, the rest not) is
  intentional, not an inconsistency. It's documented here so a future
  reader doesn't try to "fix" it into either full coverage or none.

## Alternatives considered

- **Do nothing; tell users to `--set` fully-resolved hostnames per
  environment, or maintain one values file per environment.** Rejected:
  defeats the point of a shared, reusable `values.yaml`.
- **Gate each `tpl` call behind `if strings.Contains "{{"`.** Rejected:
  `tpl` on a plain string is already a safe no-op, so the gate adds
  complexity for no behavior change.
- **Validate hostname shape in `values.schema.json` pre-render.**
  Rejected: this is the exact tension the "Resolving the tension"
  section above resolves. A pre-render pattern breaks templated values.

## References

- `templates/_gateway.tpl`: `uhc.gatewayParentRefs`,
  `uhc.referenceGrantFrom`, `uhc.referenceGrantTo`.
- `templates/ingress.yaml`, `templates/httproute.yaml`,
  `templates/grpcroute.yaml`, `templates/tlsroute.yaml`,
  `templates/referencegrant.yaml`: the render sites.
- [ADR 013](013-schema-driven-validation.md): schema-driven validation,
  amended by the "Resolving the tension" section above.
- [ADR 009](009-dual-networking-stack.md): confirms hostnames/parentRefs
  live only on singleton/plural-map entries, never per-workload
  shorthand.
- [ADR 019](019-explicit-atomic-list-defaults.md): the `parentRefs`
  group/kind pre-fill logic this change sits next to in
  `uhc.gatewayParentRefs`.

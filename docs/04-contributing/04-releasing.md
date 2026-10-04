# Releasing

The chart is published to GHCR as an OCI artifact under the maintainer's namespace (`oci://ghcr.io/purisev/universal-helm-chart` for this repo; `${{ github.repository_owner }}` for forks — see [Forks](#forks) below). Two CI workflows under [`.github/workflows/`](https://github.com/purisev/universal-helm-chart/blob/main/.github/workflows) handle the publishing automatically.

## Cutting a release (tagged build)

1. **Check `Chart.yaml`.** The `version` field is pinned to the in-flight release line and must already match the version you want to publish — don't bump per-PR.

   The `version-pins` CI job checks this for you, and checks that the version in `Chart.yaml` is also the one every Argo CD `targetRevision`, Flux `tag`, `helm install --version` and schema URL under `docs/` names. Given a ref that names a version — a `release-X.Y.Z` branch or a `vX.Y.Z` tag — it additionally holds `Chart.yaml` to that version. CI hands it the branch a PR targets, the branch it comes from and the tag, so the release PR asserts the version too rather than only the PRs into the release branch. Run it locally with:

   ```bash
   TARGET_REFS=release-<X.Y.Z> bash .github/scripts/check-version-pins.sh
   ```

   It runs on every CI run, and the branch preview build in `ci.yaml` will not publish while it is red. `release.yaml` runs it again on the tag itself, where the ref is the version the artifact is about to carry, so a chart cannot reach GHCR under a version that is not the one inside it. The migration guide and the ADRs are skipped, since naming older versions is what they are for.

2. **Date the release in `CHANGELOG.md`.** Every user-visible change goes under the heading of the in-flight version as it lands, and the heading reads `## <X.Y.Z> - unreleased` until the release. Replace `unreleased` with the release date. The `version-pins` CI job fails while `CHANGELOG.md` has no notes for the version in `Chart.yaml`, and `release.yaml` refuses a tag whose section is still marked `unreleased`. Print the notes a release will carry with:

   ```bash
   bash .github/scripts/release-notes.sh
   ```

3. **Tag and push** from the matching release branch:

   ```bash
   git checkout release-<X.Y.Z>
   git tag v<X.Y.Z>
   git push origin v<X.Y.Z>
   ```

4. **CI takes over.** [`release.yaml`](https://github.com/purisev/universal-helm-chart/blob/main/.github/workflows/release.yaml) runs on `v*` tags: it lints, runs the unittest suite, checks the tag against `Chart.yaml` and the docs, reads the release notes from `CHANGELOG.md`, packages the chart, pushes the artifact to `oci://ghcr.io/<your-github-namespace>` (the workflow resolves your namespace from `${{ github.repository_owner }}`), and signs it keylessly via [Sigstore/cosign](https://docs.sigstore.dev/) — no key management, the signature is tied to this repo's GitHub Actions OIDC identity. It then publishes the GitHub Release for the tag with the notes from `CHANGELOG.md` and three assets: the packaged chart, its Sigstore signature bundle (`.sigstore.json`) and its build provenance (`.intoto.jsonl`). A release that already exists for the tag gets the notes and the assets added to it.
5. **Verify the artifact:**

   ```bash
   helm pull oci://ghcr.io/purisev/universal-helm-chart --version <X.Y.Z>
   ```

6. **Verify the signature** (optional, proves the artifact was actually built by this repo's `release.yaml` and not pushed by hand or from a fork):

   ```bash
   cosign verify \
     --certificate-identity-regexp "^https://github.com/purisev/universal-helm-chart/" \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     ghcr.io/purisev/universal-helm-chart:<X.Y.Z>
   ```

   The chart attached to the GitHub Release verifies the same way against its own bundle, and its provenance with the GitHub CLI:

   ```bash
   cosign verify-blob \
     --bundle universal-helm-chart-<X.Y.Z>.tgz.sigstore.json \
     --certificate-identity-regexp "^https://github.com/purisev/universal-helm-chart/" \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     universal-helm-chart-<X.Y.Z>.tgz

   gh attestation verify universal-helm-chart-<X.Y.Z>.tgz --repo purisev/universal-helm-chart
   ```

## Branch builds (PR previews)

[`ci.yaml`](https://github.com/purisev/universal-helm-chart/blob/main/.github/workflows/ci.yaml) can also publish a preview artifact, tagged `<chart-version>-<branch-slug>` — for example `<X.Y.Z>-feat-xyz`. It's gated behind the `publish-preview` label (not automatic on every PR) and only runs once linting/tests have actually passed. Apply the label to a non-draft, non-fork PR to trigger it. Reviewers can then pull it directly without cloning:

```bash
helm template demo oci://ghcr.io/purisev/universal-helm-chart --version <X.Y.Z>-feat-xyz -f my-values.yaml
```

## What gets published

The OCI artifact contains only what chart consumers need: `Chart.yaml`, `templates/`, `values.yaml`, `values.yaml.example`, `values.schema.json`, `README.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `SECURITY.md`. Everything else (`docs/`, `tests/`, `test/`, `.github/`) is excluded via [`.helmignore`](https://github.com/purisev/universal-helm-chart/blob/main/.helmignore).

## Forks

Both workflows resolve the GHCR namespace from `${{ github.repository_owner }}`, so a fork publishes to `oci://ghcr.io/<your-github-user>/universal-helm-chart` automatically — no workflow edits required. Tag a release on your fork's `release-<X.Y.Z>` branch the same way and `release.yaml` runs against your own GHCR namespace using your repo's `GITHUB_TOKEN`.

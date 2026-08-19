# Quickstart

The minimal viable `values.yaml`:

```yaml
deployments:
  api:
    image:
      repository: nginx
      tag: "1.27"
    service:
      ports:
        http:
          port: 80
```

Install:

```bash
helm install demo oci://ghcr.io/purisev/universal-helm-chart --version 3.1.0 -f values.yaml
```

A complete copy-and-deploy version of this scenario, including Argo CD and Flux manifests, lives at [`../02-examples/01-minimal/`](../02-examples/01-minimal/).

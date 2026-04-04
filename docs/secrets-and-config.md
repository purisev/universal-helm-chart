# Secrets & Config

## ConfigMaps

Three types of ConfigMaps are supported:

```mermaid
classDiagram
    class PerWorkloadConfigMap {
        trigger: deployments.name.createConfigmap = true
        name: fullname-workloadName
        data: deployments.name.configData
    }
    class PerStatefulSetConfigMap {
        trigger: statefulSets.name.createConfigmap = true
        name: fullname-workloadName
        data: statefulSets.name.configData
    }
    class ChartLevelConfigMap {
        trigger: configMaps.name.enabled = true
        name: fullname-name
        data: configMaps.name.data
        mountPath: optional — enables auto-mount
        defaultMode: optional file permissions
        readOnly: true by default
    }
```

Prefer **chart-level ConfigMaps** (`configMaps.*`) for new work — they support auto-mount and are the most flexible. Per-workload ConfigMaps (`createConfigmap: true`) exist for backward compatibility.

### Chart-level ConfigMap example

```yaml
configMaps:
  app-config:
    enabled: true
    mountPath: /etc/config       # auto-mount into all containers at this path
    readOnly: true               # default
    data:
      config.json: |
        {"broker": "mqtt://broker:1883", "timeout": 30}
      settings.yaml: |
        log_level: info

  scripts:
    enabled: true
    mountPath: /scripts
    defaultMode: 0755            # make files executable
    data:
      entrypoint.sh: |
        #!/bin/sh
        exec java -jar app.jar

  feature-flags:
    enabled: true
    # no mountPath — use via envConfigMaps (envFrom injection)
    data:
      FEATURE_NEW_UI: "true"
      FEATURE_DARK_MODE: "false"
```

---

## ConfigMap auto-mount

When a chart-level ConfigMap has `mountPath` set, the chart automatically generates a `Volume` and injects a `VolumeMount` into every container of every workload.

```mermaid
flowchart TD
    CM["configMaps.app-config\nmountPath: /etc/config"]
    CM --> VOL["Volume: cm-app-config\n(configMap: fullname-app-config)"]
    VOL --> MNT["VolumeMount in every container\nmountPath: /etc/config\nreadOnly: true"]

    OPT1["inherit.configMapMount: false"]
    OPT2["inherit.configMapMount:\n  app-config: false"]
    OPT1 -- "disables ALL auto-mounts\nfor this workload" --> MNT
    OPT2 -- "disables only app-config\nauto-mount for this workload" --> MNT
```

```yaml
deployments:
  worker:
    enabled: true
    inherit:
      configMapMount: false       # skip all auto-mounts for this workload

  api:
    enabled: true
    inherit:
      configMapMount:
        scripts: false            # skip only the 'scripts' configMap auto-mount
```

---

## ExternalSecrets Operator (ESO)

```mermaid
flowchart LR
    SS["secretStores.vault-store\nenabled: true"]
    SS --> SSR["SecretStore/fullname-vault-store\n(or ClusterSecretStore)"]
    SSR -- "JWT auth\n(IRSA / Workload Identity)" --> PROV["External provider\nVault / AWS / GCP"]
    ES["externalSecrets.db-creds\nenabled: true"]
    ES --> ESR["ExternalSecret/fullname-db-creds"]
    ESR -- "secretStoreRef" --> SSR
    ESR -- "ESO controller\nfetches & syncs" --> SEC["Secret/db-creds"]
    SEC -- "consumed via" --> ENV["envSecrets[]\nOR envFrom"]
```

### SecretStore — Vault (JWT auth)

```yaml
secretStores:
  vault-store:
    enabled: true
    kind: SecretStore          # or ClusterSecretStore
    provider:
      vault:
        server: https://vault.example.com
        path: secret
        version: v2
        auth:
          jwt:
            mountPath: jwt
            role: my-app-role
            audiences:
              - vault
            expirationSeconds: 600
```

### SecretStore — AWS (IRSA)

```yaml
secretStores:
  aws-store:
    enabled: true
    provider:
      aws:
        service: SecretsManager   # or ParameterStore
        region: us-east-1
        auth:
          jwt:
            audiences:
              - sts.amazonaws.com
```

### SecretStore — GCP (Workload Identity)

```yaml
secretStores:
  gcp-store:
    enabled: true
    provider:
      gcpsm:
        projectID: my-gcp-project
        auth:
          workloadIdentity:
            clusterLocation: us-central1
            clusterName: my-cluster
```

The `serviceAccountRef` defaults to `serviceAccount.name` in all providers.

### ExternalSecret

```yaml
externalSecrets:
  db-creds:
    enabled: true
    secretStore: vault-store     # references secretStores key
    storeKind: SecretStore       # SecretStore | ClusterSecretStore
    refreshInterval: 1h
    targetName: db-creds         # K8s Secret name (default: map key)

    # Fetch individual keys
    data:
      - remoteKey: my-app/db
        secretKey: DB_PASSWORD
        property: password

    # Or fetch entire secret
    dataFrom:
      - remoteKey: my-app/config
```

### data vs dataFrom

| Mode | Values key | When to use |
|---|---|---|
| Individual keys | `data[]` with `remoteRef.property` | Need only a subset of a remote secret's keys |
| Full extract | `dataFrom[]` with `extract` | Need all keys from a remote secret as-is |

### ESO API version auto-detection

The chart detects the installed ESO version via `.Capabilities.APIVersions.Has "external-secrets.io/v1"`:
- ESO ≥ 0.10 → uses `external-secrets.io/v1`
- ESO < 0.10 → uses `external-secrets.io/v1beta1`
- Offline renders (`helm template` without `--kube-version`) → falls back to `v1beta1`

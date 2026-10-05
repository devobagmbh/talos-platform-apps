# Component `observability/snmp-exporter`

[snmp_exporter](https://github.com/prometheus/snmp_exporter) is the Prometheus
**multi-target SNMP exporter**. A scraper calls `GET /snmp?target=<device>&module=<module>&auth=<auth>`;
the exporter queries that device over SNMP and returns the result as Prometheus
metrics. It serves devices that expose their health only through SNMP, such as a NAS.

- It stores nothing and alerts on nothing.
- It exposes raw upstream metric names.
- It carries no credentials: SNMP credentials come from a consumer-supplied Secret
  (see [Credentials contract](#credentials-contract)).

Published as an independently versioned OCI artifact (ADR-0009). Related ADRs:
ADR-0039 (NAS monitoring, status **proposed**), ADR-0024 (workload/config
freeze-line), ADR-0030 (catalog adoption criterion).

The component provides the `snmp-device-metrics` capability
(`compatibility.yaml`, `swap_class: consumer-change`): no alternative serves
`GET /snmp`, so a swap moves the consumer's scrape wiring.

## Contents

A `kind: helm` wrapper over the `prometheus-snmp-exporter` chart
(`https://prometheus-community.github.io/helm-charts`, version `9.18.1`, appVersion
`v0.30.1`, image `quay.io/prometheus/snmp-exporter:v0.30.1`), plus
`manifests/00-namespace.yaml` and `manifests/10-serviceaccount.yaml`. The rendered
workload (`grep '^kind:' rendered/manifest.yaml`) is:

- `ConfigMap` `snmp-exporter`: the module definitions, key `snmp.yaml`.
- `Service` `snmp-exporter` (ClusterIP, port `9116`).
- `Deployment` `snmp-exporter` (one replica).
- `ServiceAccount` `snmp-exporter` (`automountServiceAccountToken: false`; the chart's
  own has no automount switch).
- A dedicated `snmp-exporter` `Namespace`.

The render contains **no** `Secret`, `Role`/`RoleBinding`, CRD, `ServiceMonitor`,
`Probe`, `ScrapeConfig` or `NetworkPolicy`.

### Modules

`helm/snmp-exporter.yaml` owns the module list. Its `config` value carries the
`modules:` of the upstream `snmp.yml` for the pinned version and nothing else: no
`auths`, no community, no user name, no password. List the shipped modules with:

```shell
yq -r '.values.config' helm/snmp-exporter.yaml | yq '.modules | keys'
```

The module definitions are byte-for-byte upstream lines, not a re-serialization (see
[Maintainer notes](#maintainer-notes)).

## Credentials contract

The consumer supplies a `Secret` named **`snmp-exporter-auth`** in the
`snmp-exporter` namespace with one key, **`auths.yml`**. The workload mounts it
read-only at `/etc/snmp-auth/auths.yml` and starts the exporter with a second
`--config.file` pointing at it; the exporter merges both files into one
configuration. The Secret never enters the signed artifact
(`customization.yaml`: `provided_refs.secret`, `required.secret_keys`).

The value of `auths.yml` is an `auths:` map. Every entry MUST set all of these
explicitly:

| Field | Required value |
|---|---|
| `version` | `3` |
| `security_level` | `authPriv` |
| `auth_protocol` | `SHA256` or `SHA512` |
| `priv_protocol` | `AES` (AES-128) or stronger: `AES192`, `AES192C`, `AES256`, `AES256C` |

An omitted field does not fail: the exporter starts each entry from its own defaults
(SNMPv2c, community `public`, `noAuthNoPriv`, MD5, DES), so an incomplete entry still
loads and the pod still reports Healthy while the device is queried with weak or
no security. The protocol values are the exporter's spellings, without hyphens.

Use a dedicated **read-only** SNMP user. Synthetic example (all values are
placeholders):

```yaml
auths:
  nas_ro:
    version: 3
    security_level: authPriv
    username: <read-only-snmp-user>
    password: <auth-passphrase>
    auth_protocol: SHA512
    priv_protocol: AES256
    priv_password: <priv-passphrase>
```

A scraper selects an entry with `auth=nas_ro` and a module with `module=<module>`.
`/config` redacts the secret fields.

## Consumer-facing surface

Renaming or removing any of these is a **breaking change** and needs a major bump
with a migration note:

- The Service `snmp-exporter` and its port `9116` (port name `http`).
- The label `platform.devoba.de/component: snmp-exporter` on the Service and the
  Deployment (the pod template carries it too). It is declared under
  `exposed_selectors` in `customization.yaml`.
- The Secret name `snmp-exporter-auth`, its key `auths.yml` and its mount path.
- The module names in `helm/snmp-exporter.yaml`.

## Network obligations (consumer)

The exporter's `target` parameter is not validated. Anyone who can reach the
exporter can make it send **authenticated SNMPv3 packets** to a host they control,
which exposes known-plaintext material for the credentials' passphrases. The
catalog ships **no `NetworkPolicy`** (decided); the consumer MUST add one that
restricts both directions:

- **Egress:** DNS plus `<NAS>:161/udp` only, so a forged `target` cannot leave the
  cluster.
- **Ingress:** the scraper only, on port `9116`. Ingress limits who can trigger a
  scrape, not where it goes, so it does not replace the egress rule.

`/-/reload` is served on the same port, so the ingress rule covers it as well.

## Operations and failure modes

- **Secret `snmp-exporter-auth` absent:** the pod stays in `ContainerCreating`. The
  chart's volume is not optional (`templates/deployment.yaml:147-152`, no
  `optional` field).
- **Secret present, key `auths.yml` missing or empty:** the exporter finds zero
  `auths` and exits with status 1, so the pod goes `CrashLoopBackOff`.
- **Credential rotation, and a release that only changes modules:** the exporter
  re-reads its files only on `SIGHUP` or `POST /-/reload`. The pod template carries
  no checksum annotation (`templates/deployment.yaml:23-24` renders `annotations: {}`),
  so neither change rolls the pod. After the kubelet has refreshed the mounted
  files, send `POST /-/reload` to the Service or restart the pod.
- **Reloader sidecar:** `configmapReload` is off. It would watch the ConfigMap only,
  never the credentials Secret.

## Resources and security posture

- Requests: cpu `10m`, memory `32Mi`. Limits: memory `128Mi`, no CPU limit, because
  a scrape waits on the device and throttling would turn that into a timeout.
- Pod and container run non-root (`65534`) with `seccompProfile: RuntimeDefault`;
  the container sets `allowPrivilegeEscalation: false`, drops `ALL` capabilities
  and uses a read-only root filesystem. The exporter writes nothing at runtime, so
  no writable volume is mounted.

## Namespace & Pod Security

The component ships a dedicated `snmp-exporter` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule) with
`pod-security.kubernetes.io/enforce: restricted`, derived from the rendered
`securityContext`, plus the `platform.devoba.de/{sub-layer,component}` ownership
labels. `task scan:psa-conformance` checks the declared level against the render.

The Application's destination namespace MUST be `snmp-exporter`.

## Sync-wave

`0`, the catalog default. The component has no catalog-internal dependencies.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/snmp-exporter:<X.Y.Z>
```

Git tag: `observability/snmp-exporter-vX.Y.Z`.

## Metric names

The exporter emits **raw upstream metric names**. The catalog applies no
relabeling. Any mapping to a different naming scheme (for example `synology_*`) is
consumer-layer relabeling, decided in talos-platform-docs#183 (open).

## Out of scope

Alert rules, dashboards, `Probe`/`ScrapeConfig` resources, relabeling, and the
`NetworkPolicy` (the consumer's obligation above) are not part of this component.

## Maintainer notes

The module slice in `helm/snmp-exporter.yaml` was extracted from the upstream
`snmp.yml` at tag `v0.30.1` (sha256
`4e03eb0b87f44c1489c2bbc651550931c1ae9df8f4553e08640ca1a22b9c22d4`, from
`https://raw.githubusercontent.com/prometheus/snmp_exporter/v0.30.1/snmp.yml`)
with:

```shell
awk 'BEGIN{keep["synology"]=1;keep["if_mib"]=1;keep["ucd_system_stats"]=1;keep["ucd_memory"]=1;keep["hrStorage"]=1} /^modules:/{inm=1; print; next} inm && /^[^ ]/{inm=0} inm && /^  [A-Za-z0-9_]+:/{k=$1; sub(":","",k); on=(k in keep)} inm&&on{print}' snmp.yml
```

Do not use a YAML re-serializer: it turns the integer `enum_values` keys into
strings. A chart bump means re-extracting from the upstream tag that matches the new
appVersion, then updating the tag and sha256 in the `config` comment.

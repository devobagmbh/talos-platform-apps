# Component `observability/snmp-exporter`

[snmp_exporter](https://github.com/prometheus/snmp_exporter) is the Prometheus
**multi-target SNMP exporter**. A scraper calls `GET /snmp?target=<device>&module=<module>&auth=<auth>`;
the exporter queries that device over SNMP and returns the result as Prometheus
metrics. It serves devices that expose their health only through SNMP, such as a NAS.

- It stores nothing and alerts on nothing.
- It exposes raw upstream metric names.
- It ships nine vendor-neutral modules and one extension point for consumer-mounted
  module packs (see [Extension point](#extension-point-module-packs)).
- It carries no credentials: SNMP credentials come from a consumer-supplied Secret
  (see [Credentials contract](#credentials-contract)).

Published as an independently versioned OCI artifact (ADR-0009). Related ADRs,
held in `talos-platform-docs`: ADR-0039 (NAS monitoring) and ADR-0030 (catalog
adoption criterion), both status **proposed**; ADR-0024 (workload/config
freeze-line).

The component provides the `snmp-device-metrics` capability
(`compatibility.yaml`, `swap_class: consumer-change`): no alternative serves
`GET /snmp`, so a swap moves the consumer's scrape wiring.

## Contents

A `kind: helm` wrapper over the `prometheus-snmp-exporter` chart
(`https://prometheus-community.github.io/helm-charts`, version `9.18.1`, appVersion
`v0.30.1`, image
`quay.io/prometheus/snmp-exporter:v0.30.1@sha256:e5fd5e8b43ace6c088fe9bf0b37b7fff0e04380bee352be7ec41b853a4dd5859`),
plus
`manifests/00-namespace.yaml` and `manifests/10-serviceaccount.yaml`. The rendered
workload (`grep '^kind:' rendered/manifest.yaml`, see
[Commands](#commands)) is:

- `ConfigMap` `snmp-exporter`: the nine core module definitions, key `snmp.yaml`.
- `Service` `snmp-exporter` (ClusterIP, port `9116`).
- `Deployment` `snmp-exporter` (one replica).
- `ServiceAccount` `snmp-exporter` (`automountServiceAccountToken: false`; the chart's
  own has no automount switch).
- A dedicated `snmp-exporter` `Namespace`.

The render contains **no** `Secret`, `Role`/`RoleBinding`, CRD, `ServiceMonitor`,
`Probe`, `ScrapeConfig` or `NetworkPolicy`.

### Modules

`helm/snmp-exporter.yaml` owns the core module list: exactly nine vendor-neutral
modules, all from the upstream `snmp.yml` for the pinned version.

| Module | Scope |
|---|---|
| `hrDevice` | Host Resources MIB device status, errors and processor load |
| `hrStorage` | Host Resources MIB storage and memory |
| `hrSystem` | Host Resources MIB system uptime, users and processes |
| `if_mib` | interface counters (IF-MIB) |
| `ip_mib` | IPv4 interface table (IP-MIB) |
| `system` | SNMPv2-MIB system group (description, uptime, name, location) |
| `ucd_la_table` | UCD-SNMP load averages |
| `ucd_memory` | UCD-SNMP memory |
| `ucd_system_stats` | UCD-SNMP CPU and system statistics |

The core ships no vendor module (no `synology`), no `ups_mib`, and no
`hrSWRun*` / `hrSWInstalled*` module. Its `config` value carries the `modules:` of
the upstream `snmp.yml` and nothing else: no `auths`, no community, no user name, no
password. List the shipped modules with:

```shell
yq -r '.values.config' helm/snmp-exporter.yaml | yq '.modules | keys'
```

The module definitions are byte-for-byte upstream lines, not a re-serialization (see
[Maintainer notes](#maintainer-notes)). A vendor module arrives as a module pack
through the [extension point](#extension-point-module-packs).

## Credentials contract

The consumer supplies a `Secret` named **`snmp-exporter-auth`** in the
`snmp-exporter` namespace with one key, **`auths.yml`**. The workload mounts it
read-only at `/etc/snmp-auth/auths.yml` and starts the exporter with a second
`--config.file` pointing at it; the exporter merges all config files, including the
[module-pack glob](#extension-point-module-packs), into one configuration. The
Secret never enters the signed artifact (`customization.yaml`:
`provided_refs.secret`, `required.secret_keys`).

The value of `auths.yml` is an `auths:` map. Every entry MUST set all of these
explicitly:

| Field | MUST | RECOMMENDED |
|---|---|---|
| `version` | `3` | |
| `security_level` | `authPriv` | |
| `auth_protocol` | `SHA256`, `SHA512`, or plain `SHA` under the named-risk-assumption rule below | `SHA256` or `SHA512` |
| `priv_protocol` | not `DES`; `AES` (AES-128) or stronger: `AES192`, `AES192C`, `AES256`, `AES256C` | |

`version: 3`, `security_level: authPriv`, an explicit `auth_protocol` and
`priv_protocol`, and the passwords MUST be set on every entry. Plain `SHA` (SHA-1)
MAY be used only when the device offers nothing stronger, and the consumer MUST
record that as a named risk assumption (ADR-0039).

An omitted field does not fail: the exporter starts each entry from its own defaults
(SNMPv2c, community `public`, `noAuthNoPriv`, MD5, DES), so an incomplete entry still
loads and the pod still reports Healthy while the device is queried with weak or
no security. The protocol values are the exporter's spellings, without hyphens
(`SHA256`, `SHA512`, `AES256`, ...).

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

## Extension point (module packs)

The core starts the exporter with a third `--config.file`, the glob
`/etc/snmp-modules/*/*.yaml`. A **module pack** is a set of `modules:` definitions
that a consumer mounts into that glob; the core mounts nothing for packs. Rules:

- One directory per pack: each pack MUST be mounted at exactly
  `/etc/snmp-modules/<pack>`. A pack MUST NOT be mounted at the root
  `/etc/snmp-modules`: a ConfigMap mounted there exposes the `..data` directory
  and duplicates every key, so the exporter crash-loops on duplicate modules.
- A pack mount MUST NOT use `subPath`: a `subPath` mount never receives updates.
- A pack is a ConfigMap only, and every ConfigMap key in a pack MUST end in
  `.yaml`. A `.yml` key does not match the glob and is skipped silently.
- A pack file MUST contain only the top-level key `modules:`. It MUST NOT contain
  `auths:` or `version:`. The exporter merges `auths` from every matched file, so
  a pack `auths.public_v2` would become the default for a scrape without `auth=`
  (SNMPv2c, community `public`, where an unknown auth is otherwise rejected with
  HTTP 400), a pack reusing a consumer auth name would crash-loop the exporter, and
  credentials in a pack ConfigMap would bypass the `snmp-exporter-auth` Secret
  contract. Scrapers MUST pass `auth=` explicitly.
- Module names MUST be unique across the core and all packs. A duplicate key is
  fatal at start.
- A pack volume name MUST NOT be `config` or `snmp-auth` (the core's own
  volumes), and a pack `mountPath` MUST be unique: it MUST NOT equal `/config`,
  `/etc/snmp-auth` or another pack's path.
- A consumer that overrides the container `args` MUST keep all three
  `--config.file` entries. Dropping the glob entry makes mounted packs ignored
  silently (no log); dropping the auths entry makes the exporter exit with
  status 1; dropping `/config/snmp.yaml` loses the core modules.
- A pack volume SHOULD be OPTIONAL (`configMap.optional: true`). An absent or
  empty glob only logs a warning, and the exporter starts with the core modules.

Because the consumer patches the Deployment in the signed base, the patch is a
strategic-merge patch with **no `target:` selector**; it names the workload by
kind, name and namespace in its body, because a `target:` selector that matches
nothing is a silent no-op. The container is addressed by name, not by index. A
synthetic example (all values are placeholders):

```yaml
# consumer Application source (consumer repo)
source:
  kustomize:
    patches:
      - patch: |
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: snmp-exporter
            namespace: snmp-exporter
          spec:
            template:
              spec:
                containers:
                  - name: snmp-exporter
                    volumeMounts:
                      - name: <pack>
                        mountPath: /etc/snmp-modules/<pack>
                        readOnly: true
                volumes:
                  - name: <pack>
                    configMap:
                      name: <pack ConfigMap>
                      optional: true
```

A second pack adds another volume and volumeMount pair; the patches compose.
`volumes` merge on `name` and `volumeMounts` merge on `mountPath`, which is why
each pack needs its own volume name and its own mountPath: a patch mount with a
new name at an existing mountPath replaces the existing mount.

**Reload obligation.** Changed pack content takes effect only after the kubelet
has refreshed the mounted files and the consumer sends `POST /-/reload` (or
restarts the pod). A failed reload keeps the old configuration, but the next
restart crash-loops on the same content. The ingress `NetworkPolicy` MUST admit
the sender of the reload (see [Network obligations](#network-obligations-consumer)).
Verify the loaded modules with `GET /config`, which returns the YAML as
`text/plain` with secrets redacted.

## Consumer-facing surface

Renaming or removing any of these is a **breaking change** (`!` plus a
`BREAKING CHANGE:` footer; while the component is 0.x this bumps the minor) and
needs a migration note:

- The Service `snmp-exporter` and its port `9116` (port name `http`).
- The Deployment name `snmp-exporter`, the namespace `snmp-exporter` and the
  container name `snmp-exporter`: the pack patch addresses them by name.
- The core volume names `config` and `snmp-auth`, reserved against pack volumes.
- The label `platform.devoba.de/component: snmp-exporter` on the Service and the
  Deployment (the pod template carries it too). It is declared under
  `exposed_selectors` in `customization.yaml`.
- The Secret name `snmp-exporter-auth`, its key `auths.yml` and its mount path.
- The nine core module names in `helm/snmp-exporter.yaml`.
- The module-pack glob `/etc/snmp-modules/*/*.yaml` and the one-directory-per-pack
  rule (mountPath `/etc/snmp-modules/<pack>`).

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

`/-/reload` is served on the same port, so the ingress rule MUST also admit the
sender of any reload request.

## Operations and failure modes

- **Secret `snmp-exporter-auth` absent:** the pod stays in `ContainerCreating`. The
  Secret volume in the render has no `optional` field.
- **Secret present, key `auths.yml` missing or empty:** the exporter finds zero
  `auths` and exits with status 1, so the pod goes `CrashLoopBackOff`.
- **Credential rotation, and a release that only changes modules:** the exporter
  re-reads its files only on `SIGHUP` or `POST /-/reload`. The pod template in the
  render carries `annotations: {}`, so no checksum annotation changes and neither
  change rolls the pod. The consumer MUST, after the kubelet has refreshed the
  mounted files, send `POST /-/reload` to the Service or restart the pod. Without
  it the pod keeps the old configuration and stays Healthy, with no error.
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

The core exposes the **raw upstream metric names** of its nine modules and applies
no renaming. Renaming happens in a module pack (at generator time) or in consumer
relabeling, never in the core.

## Migration from v0.1.0

v0.2.0 is a **breaking** release. The `synology` module is removed from the core.
A consumer that scrapes `module=synology` on v0.1.0 MUST move to a Synology module
pack, mounted through the [extension point](#extension-point-module-packs); the
core ships none. The `if_mib`, `ucd_system_stats`, `ucd_memory` and `hrStorage`
modules are unchanged.

- **What the break looks like:** scrapes with `module=synology` fail (scrape
  error, target down) while the pod stays Healthy.
- **Ordering:** v0.1.0 has no module-pack glob, so a pack patch has no effect
  there; the pack patch can ship in the same sync as the version bump. The pack
  ConfigMap MUST exist before the v0.2.0 pod starts (same Application or an
  earlier sync-wave); otherwise the optional volume starts empty, the exporter
  starts with only the core modules, and `POST /-/reload` is needed after the
  ConfigMap appears.
- **A self-authored pack that keeps the v0.1.0 behaviour** MUST name its module
  `synology` and use the upstream v0.30.1 `synology` block verbatim; the series
  names then stay the same.
- **Metric names exposed by a pack are that pack's contract** and may differ from
  the v0.1.0 raw names.

## Out of scope

Alert rules, dashboards, `Probe`/`ScrapeConfig` resources, relabeling, and the
`NetworkPolicy` (the consumer's obligation above) are not part of this component.

## Maintainer notes

### Commands

The commands in this README run from the component directory,
`sub-layers/observability/components/snmp-exporter/`, and read `rendered/`, which
is gitignored: generate it first with
`task render:one -- observability/snmp-exporter` (from the repository root).

### Modules extraction and image digest

The module slice in `helm/snmp-exporter.yaml` was extracted from the upstream
`snmp.yml` at tag `v0.30.1` (sha256
`4e03eb0b87f44c1489c2bbc651550931c1ae9df8f4553e08640ca1a22b9c22d4`, from
`https://raw.githubusercontent.com/prometheus/snmp_exporter/v0.30.1/snmp.yml`)
with:

```shell
awk 'BEGIN{keep["hrDevice"]=1;keep["hrStorage"]=1;keep["hrSystem"]=1;keep["if_mib"]=1;keep["ip_mib"]=1;keep["system"]=1;keep["ucd_la_table"]=1;keep["ucd_memory"]=1;keep["ucd_system_stats"]=1} /^modules:/{inm=1; print; next} inm && /^[^ ]/{inm=0} inm && /^  [^ ]+:/{k=$1; sub(":$","",k); on=(k in keep)} inm&&on{print}' snmp.yml
```

The module-level key pattern is `[^ ]+` rather than `[A-Za-z0-9_]+` on purpose:
upstream has a module named `tplink-ddm`, directly after `system`, and a
word-character pattern would absorb its lines into `system`. Then each extracted
block, minus the 4-space indent of the values block scalar, MUST equal the same
slice of upstream.

Do not use a YAML re-serializer: it turns the integer `enum_values` keys into
strings. A chart bump means re-extracting from the upstream tag that matches the new
appVersion, then updating the tag and sha256 in the `config` comment, **and**
refreshing the image tag and digest in `image.tag`. The digest is the multi-arch
index of the tag, read from the registry (`docker-content-digest` header; replace
`v0.30.1` with the new tag):

```shell
curl -sI -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
  https://quay.io/v2/prometheus/snmp-exporter/manifests/v0.30.1
```

The chart has no digest field, so a stale digest keeps running the old image
without error.

### Re-check after a chart bump

- The Secret volume in the render has no `optional` field.
- The pod template in the render has no checksum annotation.
- The rendered `app.kubernetes.io/version` label still equals `version.app` in
  `compatibility.yaml`.
- The Deployment and container are still named `snmp-exporter` and the core
  volumes are still `config` (mounted at `/config`) and `snmp-auth`, because every
  pack patch addresses them by name.

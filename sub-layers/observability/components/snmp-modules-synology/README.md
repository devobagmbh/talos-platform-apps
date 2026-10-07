# Component `observability/snmp-modules-synology`

A **module pack** for the [`observability/snmp-exporter`](../snmp-exporter/README.md)
core: the `synology` module for Synology DSM devices, generated from the Synology
MIBs with the pinned snmp_exporter generator, with the platform's metric names. It
is a configuration artifact: one `ConfigMap`, no workload.

- The module covers system, disk, RAID, UPS, SMART, services, storage I/O, space I/O
  and iSCSI LUN objects: 209 metrics, one module named `synology`.
- The module is **generated**, never hand-edited. Only metric names, two scales and
  six label-text types differ from the upstream v0.30.1 `synology` module.
- The pack ships **no `Namespace`**: the core is the sole claimant of the
  `snmp-exporter` namespace. It ships no `Secret`, no credentials and no `auths:`.

Published as an independently versioned OCI artifact (ADR-0009). Related ADRs, held
in `talos-platform-docs`: ADR-0039 (NAS monitoring), status **proposed**, and
ADR-0024 (workload/config freeze-line). The pack provides no capability
(`capabilities: []` in `compatibility.yaml`): it is configuration of the core, so
there is nothing to swap, and `version.sot` is `none` because no workload or chart
version exists to track.

## Contents

`manifests/00-configmap.yaml` renders exactly one resource:

- `ConfigMap` `snmp-modules-synology` in namespace `snmp-exporter`, with the single
  key **`synology.yaml`** (a literal block scalar holding the generated module file).

The key MUST end in `.yaml`: the core reads `/etc/snmp-modules/*/*.yaml`, and a
`.yml` key would be skipped silently. The file contains only the top-level key
`modules:`. It MUST NOT contain `auths:` or `version:`: the exporter merges `auths`
from every matched file, so a pack `auths` entry would become the default for a
scrape without `auth=`, and credentials in a pack ConfigMap would bypass the core's
credentials contract. Check the rendered value:

```shell
yq -r 'select(.kind=="ConfigMap") | .data["synology.yaml"]' rendered/manifest.yaml | yq -c 'keys'
```

The output MUST be `["modules"]`. The commands in this README run from the component
directory and read `rendered/`, which is gitignored: generate it first with
`task render:one -- observability/snmp-modules-synology` from the repository root.

## Consumer obligations

The consumer wires the pack into the **Application of the core exporter**, not into
an Application of the pack. The pack Application only delivers the `ConfigMap`; the
mount is a patch on the core's `Deployment`. The patch is a strategic-merge patch
with **no `target:` selector** (a `target:` that matches nothing is a silent no-op);
it names the workload by kind, name and namespace in its body, and addresses the
container by name:

```yaml
# consumer Application source for the core exporter (consumer repo)
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
                      - name: snmp-modules-synology
                        mountPath: /etc/snmp-modules/synology
                        readOnly: true
                volumes:
                  - name: snmp-modules-synology
                    configMap:
                      name: snmp-modules-synology
                      optional: true
```

Rules for the patch:

- The volume AND the volumeMount MUST be named `snmp-modules-synology`, and the
  `mountPath` MUST be exactly `/etc/snmp-modules/synology`. It MUST NOT use
  `subPath`: a `subPath` mount never receives updates.
- The names `config` and `snmp-auth` (volumes) and the paths `/config` and
  `/etc/snmp-auth` (mounts) belong to the core and MUST NOT be reused. Volumes merge
  on `name` and volumeMounts on `mountPath`.
- The volume SHOULD stay `optional: true`: without the ConfigMap the exporter starts
  with only the core modules.
- A consumer that overrides the container `args` MUST keep all three `--config.file`
  entries of the core, including the module-pack glob.
- Scrapers MUST pass `auth=` explicitly. The pack carries no auth entry; an unknown
  auth is rejected by the exporter, and the credentials come from the core's
  Secret contract.

**Ordering.** The pack ConfigMap MUST exist before the v0.2.0 pod starts, so deliver
it in the same Application as the core or at an earlier sync-wave. The pack's own
catalog position is sync-wave `1`, after the core at `0`: with that default order the
pod starts first, the optional volume starts empty, and `POST /-/reload` is needed
once the ConfigMap exists.

**Reload obligation.** Changed pack content takes effect only after the kubelet has
refreshed the mounted file and the consumer sends `POST /-/reload` to the core
Service (or restarts the pod). A failed reload keeps the old configuration, and the
next restart crash-loops on the same content. Verify with `GET /config`: it lists the
module `synology` as `text/plain` with secrets redacted.

**Core version.** The pack requires `observability/snmp-exporter` `>=v0.2.0`.
Mounting it into a core **older than v0.2.0** crash-loops the exporter: those
versions still define a module `synology`, and a duplicate module key is fatal at
start.

## Metric names

The names are decided at generator time, by one rule, so a scraper needs no
relabeling:

- New name = `synology_` + snake_case of the upstream object name; acronym runs stay
  one word (`iSCSI` becomes `iscsi`, `LUN` `lun`, `IO` `io`, `SMART` `smart`).
  Names match `^synology_[a-z0-9_]+$` and are unique within the module.
- Counters end in `_total`.
- Enum-typed objects stay plain integer gauges; the pack never sets `EnumAsInfo` or
  `EnumAsStateSet`.
- A unit suffix and a `scale` appear only where
  [`generator/generator.yml`](generator/generator.yml) sets them explicitly.

[`generator/generator.yml`](generator/generator.yml) is the mapping: the generator
input, with one entry per object, committed next to the module it produced. There is
no mapping table here. Changing a metric name, a label name or the module name is a
**breaking change** for every consumer (`!` plus a `BREAKING CHANGE:` footer; while
the component is 0.x this bumps the minor).

Type overrides (`DisplayString` instead of the upstream `OctetString`, which the
exporter renders as hex such as `0x4469736B2031`):

- `diskID`, `diskName`, `diskRole` (`SYNOLOGY-DISK-MIB`), renamed
  `synology_disk_id`, `synology_disk_name`, `synology_disk_role`.
- `iSCSILUNName`, `iSCSILUNUUID`, `iSCSILUNType` (`SYNOLOGY-ISCSILUN-MIB`), renamed
  `synology_iscsi_lun_name`, `synology_iscsi_lun_uuid`, `synology_iscsi_lun_type`.

`diskID` is the lookup label of every per-disk series, so disk labels read as text.
OIDs, indexes and label names are unchanged by these overrides.

Scale overrides:

- `diskRemainLife` becomes `synology_disk_remaining_life_ratio`, scale `0.01`: the
  value is a ratio. A device-reported `-1` becomes `-0.01`.
- `iSCSILUNThinProvisionVolFreeMBs` becomes
  `synology_iscsi_lun_thin_provision_volume_free_bytes`, scale `1048576`
  (MiB to bytes).

**Label names** (the complete set, all as in upstream): `diskID`, `diskIndex`,
`diskSMARTInfoIndex`, `iSCSILUNInfoIndex`, `raidIndex`, `raidName`,
`serviceInfoIndex`, `serviceName`, `spaceIODevice`, `spaceIOIndex`,
`storageIODevice`, `storageIOIndex`. A string-typed metric (`DisplayString`,
`OctetString`) carries its text in a label named after the **renamed metric**, for
example `synology_model_name{synology_model_name="<model>"} 1`.

## Generator inputs

The module in `manifests/00-configmap.yaml` is the unmodified output of the
generator for [`generator/generator.yml`](generator/generator.yml). That file is the
upstream v0.30.1 `synology` section (walk, lookups and the upstream overrides
unchanged) plus the pack's name, scale and type overrides.

| Input | Value |
|---|---|
| Generator | `prometheus/snmp_exporter` generator `v0.30.1` |
| Generator image | `localhost/snmp-generator:v0.30.1`, built from the upstream `generator/Dockerfile` at tag `v0.30.1` |
| Synology MIB archive | `Synology_MIB_File.zip`, sha256 `13c29b6c13a70495f02e054dff00ebf9498be54729157258eb72e06530edd825` |
| MIB archive source | `https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_MIB_File.zip` |
| Base MIBs | net-snmp tag `v5.9`, `https://raw.githubusercontent.com/net-snmp/net-snmp/v5.9/mibs/<NAME>.txt`, saved under the bare name |

Base MIBs the Synology MIBs import, with the sha256 of the file as saved:

| Base MIB | sha256 |
|---|---|
| `SNMPv2-SMI` | `ece2355fc8b6140af702f86d77bd3f7398d80375fc6278c3e30ff3a31b53e0b7` |
| `SNMPv2-TC` | `c1379575e6a0ad25b2d7da68294153c1fd79750827376f2aa6323d072d73f0b8` |
| `SNMPv2-MIB` | `b4f8ef130f580b86d2b6bc890564e46100785f589431df76954e878a7b166e11` |
| `NET-SNMP-MIB` | `b0460053145ec563a026ccc7e792ab9ebb370c6aab3d57a9f95f3964cdd9d399` |
| `NET-SNMP-TC` | `bf111deffcc7c36262d2e47ff8fd7d49eee8a3f1bdad6236367660da6854a233` |

Build the generator image and generate. `<workdir>` is a new, empty directory that
holds `generator.yml` and `mibs/` (the 16 `.txt` files of the archive, extracted flat
with `unzip -j`, plus the five base MIBs); the archive MUST be treated as untrusted
data and nothing in it executed:

```shell
curl -fsSLO https://raw.githubusercontent.com/prometheus/snmp_exporter/v0.30.1/generator/Dockerfile
podman build --build-arg REPO_TAG=v0.30.1 -t snmp-generator:v0.30.1 -f Dockerfile .
unzip -j -d <workdir>/mibs Synology_MIB_File.zip
cp generator/generator.yml <workdir>/generator.yml
podman run --rm -v "<workdir>":/opt:Z localhost/snmp-generator:v0.30.1 generate
```

The generator reads `/opt/generator.yml` with `MIBDIRS=mibs` and writes
`<workdir>/snmp.yml`. That file, unchanged, is the value of the key `synology.yaml`
(indented by four spaces under the literal block scalar). **There is no strip
step:** the input has no `auths:` key, so the generator writes only `modules:`, and
a YAML re-serializer MUST NOT be used on the output (it rewrites the integer
`enum_values` keys). The generator writes the scale `1048576` as `1.048576e+06`,
which is the same YAML float.

The generator image is not bit-reproducible (a floating Debian base, `go install`).
The reproducibility check is the baseline: generating from the unmodified upstream
section yields the upstream `synology` module byte for byte (1476 lines, 209 metrics).

## Verify the pack against upstream

A maintainer verifies the pack on every change to the generator input or the
generator version. Fetch the upstream `snmp.yml` at tag `v0.30.1` (sha256
`4e03eb0b87f44c1489c2bbc651550931c1ae9df8f4553e08640ca1a22b9c22d4`, from
`https://raw.githubusercontent.com/prometheus/snmp_exporter/v0.30.1/snmp.yml`) and
extract its `synology` module without a re-serializer:

```shell
awk '/^modules:/{inm=1;next} inm&&/^[^ ]/{inm=0} inm&&/^  [^ ]+:/{k=$1;sub(":$","",k);on=(k=="synology")} inm&&on{print}' snmp.yml | { echo 'modules:'; cat; } > upstream-synology.yml
yq -r 'select(.kind=="ConfigMap") | .data["synology.yaml"]' rendered/manifest.yaml > pack-synology.yml
```

The pack equals upstream when, with `name`, `help` and `scale` removed everywhere
and `type` ignored for exactly the six objects above, the two modules are
identical: the same `oid` set, the same `labelname` set, the same walk, 209 metrics
and the same structure. Compare the parsed documents, not the text:

```shell
norm='del(.modules.synology.metrics[] | .name, .help, .scale) | (.. | objects | select(has("oid")) | select(.oid | IN("1.3.6.1.4.1.6574.2.1.1.2","1.3.6.1.4.1.6574.2.1.1.7","1.3.6.1.4.1.6574.2.1.1.12","1.3.6.1.4.1.6574.104.1.1.2","1.3.6.1.4.1.6574.104.1.1.3","1.3.6.1.4.1.6574.104.1.1.17")) | .type) = "-"'
diff <(yq -c "$norm" upstream-synology.yml) <(yq -c "$norm" pack-synology.yml) && echo equivalent
```

The exporter loads the pack: `snmp_exporter --dry-run` with the core configuration,
a fixture auths file and the pack file MUST exit 0.

## Namespace & Pod Security

The pack declares no `Namespace` and runs no pod, so it carries no Pod Security
level. The Application's destination namespace MUST be `snmp-exporter`, the
namespace the core owns.

## Sync-wave

`1`: after `observability/snmp-exporter` at `0`. The catalog-internal dependency is
`observability/snmp-exporter` (`>=v0.2.0`); see the ordering note above for the
first start.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/snmp-modules-synology:<X.Y.Z>
```

Git tag: `observability/snmp-modules-synology-vX.Y.Z`.

## Out of scope

Other vendors' modules, alert rules, dashboards, scrape-time relabeling, and the
`job` / `instance` values of a scrape.

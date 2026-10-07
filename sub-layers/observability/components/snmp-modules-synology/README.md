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
credentials contract. The check is in [Maintainer notes](#maintainer-notes).

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

**Ordering.** The pack ConfigMap MUST exist before the core pod starts, so that the
exporter reads the pack at start. The pack's own catalog position is sync-wave `1`,
after the core at `0`, so a consumer that keeps the catalog order does **not** meet
this: the pod starts first, the optional volume starts empty and the exporter serves
only the core modules until one `POST /-/reload` is sent after the ConfigMap exists
and the kubelet has refreshed the mount. A consumer avoids that step by moving the
pack to a sync-wave before the core's, or by delivering the pack in the same
Application as the core.

**Reload obligation.** Changed pack content takes effect only after the kubelet has
refreshed the mounted file and the consumer sends `POST /-/reload` to the core
Service (or restarts the pod). A failed reload keeps the old configuration, and the
next restart crash-loops on the same content. Verify with `GET /config`: it lists the
module `synology` as `text/plain` with secrets redacted.

**Core version.** The pack requires `observability/snmp-exporter` `>=v0.2.0`. A
v0.1.0 core does not load the pack: it has no module-pack glob, so the mounted
ConfigMap has no effect there. A consumer who adds the glob to a v0.1.0 core by hand
makes the exporter fail at start instead, because that core still defines a module
`synology` and a duplicate module key is fatal (see the core README, Migration from
v0.1.0).

## Metric names

The names are decided at generator time, by one rule plus a set of pinned rows, so a
scraper needs no relabeling:

- New name = `synology_` + snake_case of the upstream object name; acronym runs stay
  one word (`iSCSI` becomes `iscsi`, `LUN` `lun`, `IO` `io`, `SMART` `smart`, `UUID`
  `uuid`, `ID` `id`, `LA` `la`, `MAC` `mac`). Names match `^synology_[a-z0-9_]+$` and
  are unique within the module.
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

Eleven objects deviate from the rule and are pinned by an explicit name in
`generator.yml`:

- `upgradeAvailable` becomes `synology_upgrade_available_status`.
- `diskTemperature` becomes `synology_disk_temperature_celsius`.
- `raidFreeSize` becomes `synology_raid_free_bytes`, `raidTotalSize` becomes
  `synology_raid_size_bytes`.
- The four 64-bit byte counters become `synology_storage_io_read_bytes_total`
  (`storageIONReadX`), `synology_storage_io_written_bytes_total`
  (`storageIONWrittenX`), `synology_space_io_read_bytes_total` (`spaceIONReadX`) and
  `synology_space_io_written_bytes_total` (`spaceIONWrittenX`). The 32-bit
  `storageIONRead` / `storageIONWritten` and `spaceIONRead` / `spaceIONWritten` keep
  the mechanical names (`synology_storage_io_n_read_total` and so on).
- `upsInfoEffciency` becomes `synology_ups_info_efficiency`: the upstream object
  name carries a typo, which the metric name corrects.
- `diskRemainLife` and `iSCSILUNThinProvisionVolFreeMBs` are pinned together with a
  scale, below.

Type overrides (`DisplayString` instead of the upstream `OctetString`, which the
exporter renders as hex such as `0x4469736B2031`):

- `diskID`, `diskName`, `diskRole` (`SYNOLOGY-DISK-MIB`), renamed
  `synology_disk_id`, `synology_disk_name`, `synology_disk_role`.
- `iSCSILUNName`, `iSCSILUNUUID`, `iSCSILUNType` (`SYNOLOGY-ISCSILUN-MIB`), renamed
  `synology_iscsi_lun_name`, `synology_iscsi_lun_uuid`, `synology_iscsi_lun_type`.

`diskID` is the lookup label of every per-disk series, so disk labels read as text.
OIDs, indexes and label names are unchanged by these overrides.

Scale overrides:

- `diskRemainLife` becomes `synology_disk_remaining_life_ratio`, scale `0.01`. The
  MIB describes the object only as the estimated remaining life of each disk and
  states no unit; the scale reads the device value as a percentage.
- `iSCSILUNThinProvisionVolFreeMBs` becomes
  `synology_iscsi_lun_thin_provision_volume_free_bytes`, scale `1048576`
  (MiB to bytes).

**Label names** (the complete set, all as in upstream): `diskID`, `diskIndex`,
`diskSMARTInfoIndex`, `iSCSILUNInfoIndex`, `raidIndex`, `raidName`,
`serviceInfoIndex`, `serviceName`, `spaceIODevice`, `spaceIOIndex`,
`storageIODevice`, `storageIOIndex`. A string-typed metric (`DisplayString`,
`OctetString`) carries its text in a label named after the **renamed metric**, for
example `synology_model_name{synology_model_name="<model>"} 1`.

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

## Maintainer notes

The module in `manifests/00-configmap.yaml` is the unmodified output of the
generator for [`generator/generator.yml`](generator/generator.yml). That file is the
upstream v0.30.1 `synology` section (walk, lookups and the upstream overrides
unchanged, everything above its `Pack additions` marker) plus the pack's name, scale
and type overrides.

### Conventions of the commands

All commands run from the **repository root** in one shell session and address every
file by path, so nothing is downloaded into the repository. `WORKDIR` is a new,
empty scratch directory outside the repository:

```shell
COMP=sub-layers/observability/components/snmp-modules-synology
WORKDIR="$(mktemp -d)"
```

`yq` is only used to convert YAML to JSON and to pick one ConfigMap value; the
logic is `jq`. The commands need the jq-syntax `yq` (kislyuk/yq, the Python wrapper
over `jq`) that `devbox.json` provides: `yq --version` in the devbox shell prints
`yq 3.x`. The Go `yq` (mikefarah) has a different expression language and does not
run them.

### Generator inputs

| Input | Value |
|---|---|
| Generator | `prometheus/snmp_exporter` generator `v0.30.1` |
| Generator image | `localhost/snmp-generator:v0.30.1`, built from the upstream `generator/Dockerfile` at tag `v0.30.1` |
| Synology MIB archive | `Synology_MIB_File.zip` from `https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_MIB_File.zip` |
| Base MIBs | net-snmp tag `v5.9`, `https://raw.githubusercontent.com/net-snmp/net-snmp/v5.9/mibs/<NAME>.txt`, saved under the bare name |

The archive MUST be treated as untrusted data: it is verified against its sha256,
unpacked flat and never executed.

### Generate the module

Build the generator image once (the image is not bit-reproducible: a floating
Debian base, `go install`):

```shell
mkdir "$WORKDIR/image"
curl -fsSL -o "$WORKDIR/image/Dockerfile" https://raw.githubusercontent.com/prometheus/snmp_exporter/v0.30.1/generator/Dockerfile
podman build --build-arg REPO_TAG=v0.30.1 -t snmp-generator:v0.30.1 -f "$WORKDIR/image/Dockerfile" "$WORKDIR/image"
```

Download the MIBs and verify them. `$WORKDIR/mibs` ends up with the 16 `.txt` files
of the archive (extracted flat with `unzip -j`) plus the five base MIBs:

```shell
mkdir "$WORKDIR/dl" "$WORKDIR/mibs"
curl -fsSL -o "$WORKDIR/dl/Synology_MIB_File.zip" https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_MIB_File.zip
for n in SNMPv2-SMI SNMPv2-TC SNMPv2-MIB NET-SNMP-MIB NET-SNMP-TC; do
  curl -fsSL -o "$WORKDIR/mibs/$n" "https://raw.githubusercontent.com/net-snmp/net-snmp/v5.9/mibs/$n.txt"
done
cat > "$WORKDIR/dl/SHA256SUMS" <<'EOF'
13c29b6c13a70495f02e054dff00ebf9498be54729157258eb72e06530edd825  dl/Synology_MIB_File.zip
ece2355fc8b6140af702f86d77bd3f7398d80375fc6278c3e30ff3a31b53e0b7  mibs/SNMPv2-SMI
c1379575e6a0ad25b2d7da68294153c1fd79750827376f2aa6323d072d73f0b8  mibs/SNMPv2-TC
b4f8ef130f580b86d2b6bc890564e46100785f589431df76954e878a7b166e11  mibs/SNMPv2-MIB
b0460053145ec563a026ccc7e792ab9ebb370c6aab3d57a9f95f3964cdd9d399  mibs/NET-SNMP-MIB
bf111deffcc7c36262d2e47ff8fd7d49eee8a3f1bdad6236367660da6854a233  mibs/NET-SNMP-TC
EOF
(cd "$WORKDIR" && shasum -a 256 -c dl/SHA256SUMS)
unzip -q -j -d "$WORKDIR/mibs" "$WORKDIR/dl/Synology_MIB_File.zip"
```

Generate, and write the output into the ConfigMap:

```shell
cp "$COMP/generator/generator.yml" "$WORKDIR/generator.yml"
podman run --rm -v "$WORKDIR":/opt:Z localhost/snmp-generator:v0.30.1 generate
{ sed -n '1,/^  synology.yaml: |$/p' "$COMP/manifests/00-configmap.yaml"; sed '/./s/^/    /' "$WORKDIR/snmp.yml"; } > "$WORKDIR/00-configmap.yaml"
mv "$WORKDIR/00-configmap.yaml" "$COMP/manifests/00-configmap.yaml"
```

The generator reads `/opt/generator.yml` with `MIBDIRS=mibs` and writes
`$WORKDIR/snmp.yml`. That file, unchanged, is the value of the key `synology.yaml`
(indented by four spaces under the literal block scalar). **There is no strip
step:** the input has no `auths:` key, so the generator writes only `modules:`, and
a YAML re-serializer MUST NOT be used on the output (it rewrites the integer
`enum_values` keys). The generator writes the scale `1048576` as `1.048576e+06`,
which is the same YAML float.

The reproducibility check is the baseline: generating from the unmodified upstream
section yields the upstream `synology` module byte for byte (209 metrics).

### Verify the pack against upstream

Verify the pack on every change to the generator input or the generator version.
Render the component, take the value of the ConfigMap key, and check that the file
holds only the top-level key `modules:` (the command MUST print exactly
`modules:`):

```shell
task render:one -- observability/snmp-modules-synology
mkdir "$WORKDIR/verify"
yq -j 'select(.kind=="ConfigMap") | .data["synology.yaml"]' "$COMP/rendered/manifest.yaml" > "$WORKDIR/verify/pack-synology.yml"
cmp "$WORKDIR/verify/pack-synology.yml" "$WORKDIR/snmp.yml"
grep -E '^[^ #]' "$WORKDIR/verify/pack-synology.yml"
```

`cmp` MUST print nothing: the rendered value equals the generator output.

Fetch the upstream `snmp.yml` at tag `v0.30.1` and extract its `synology` module
without a re-serializer:

```shell
curl -fsSL -o "$WORKDIR/verify/snmp.yml" https://raw.githubusercontent.com/prometheus/snmp_exporter/v0.30.1/snmp.yml
echo "4e03eb0b87f44c1489c2bbc651550931c1ae9df8f4553e08640ca1a22b9c22d4  $WORKDIR/verify/snmp.yml" | shasum -a 256 -c -
awk '/^modules:/{inm=1;next} inm&&/^[^ ]/{inm=0} inm&&/^  [^ ]+:/{k=$1;sub(":$","",k);on=(k=="synology")} inm&&on{print}' "$WORKDIR/verify/snmp.yml" | { echo 'modules:'; cat; } > "$WORKDIR/verify/upstream-synology.yml"
```

The pack equals upstream when, with `name`, `help` and `scale` removed everywhere
and `type` ignored for exactly the six objects under Type overrides above, the two
modules are identical: the same `oid` set, the same `labelname` set, the same walk,
209 metrics and the same structure. Compare the parsed documents, not the text; the
command MUST print `equivalent`:

```shell
norm='del(.modules.synology.metrics[] | .name, .help, .scale) | (.. | objects | select(has("oid")) | select(.oid | IN("1.3.6.1.4.1.6574.2.1.1.2","1.3.6.1.4.1.6574.2.1.1.7","1.3.6.1.4.1.6574.2.1.1.12","1.3.6.1.4.1.6574.104.1.1.2","1.3.6.1.4.1.6574.104.1.1.3","1.3.6.1.4.1.6574.104.1.1.17")) | .type) = "-"'
diff <(yq . "$WORKDIR/verify/upstream-synology.yml" | jq -S -c "$norm") <(yq . "$WORKDIR/verify/pack-synology.yml" | jq -S -c "$norm") && echo equivalent
```

The names follow the rules above when the next command prints nothing (a duplicate
name, a name outside `^synology_[a-z0-9_]+$`, or a counter without `_total` or a
non-counter with it):

```shell
yq . "$WORKDIR/verify/pack-synology.yml" | jq -r '.modules.synology.metrics | ((map(.name) | group_by(.) | map(select(length > 1)[0])[]), (.[] | select(.name | test("^synology_[a-z0-9_]+$") | not) | .name), (.[] | select((.type == "counter") != (.name | endswith("_total"))) | .name))'
```

The exporter loads the pack: `snmp_exporter --dry-run` with the core configuration,
a fixture auths file and the pack file MUST exit 0. The commands use the exporter
image digest pinned by the core and a fixture community that is not a credential.
A dry run proves that the files parse and merge, not that the glob matched the pack:

```shell
mkdir -p "$WORKDIR/dry/modules/synology"
task render:one -- observability/snmp-exporter
yq -j 'select(.kind=="ConfigMap") | .data["snmp.yaml"]' sub-layers/observability/components/snmp-exporter/rendered/manifest.yaml > "$WORKDIR/dry/snmp.yaml"
printf '%s\n' 'auths:' '  fixture:' '    version: 2' '    community: fixture' > "$WORKDIR/dry/auths.yml"
cp "$WORKDIR/verify/pack-synology.yml" "$WORKDIR/dry/modules/synology/synology.yaml"
podman run --rm -v "$WORKDIR/dry":/dry:ro,Z quay.io/prometheus/snmp-exporter@sha256:e5fd5e8b43ace6c088fe9bf0b37b7fff0e04380bee352be7ec41b853a4dd5859 --dry-run --config.file=/dry/snmp.yaml --config.file=/dry/auths.yml '--config.file=/dry/modules/*/*.yaml'
```

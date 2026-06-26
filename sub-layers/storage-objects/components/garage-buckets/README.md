# Component `storage-objects/garage-buckets`

A Kubernetes `Job` that provisions S3 buckets and registers
**consumer-supplied** access keys in a running [Garage](../garage/) instance via
the Garage admin HTTP API v2. There is **no** Bucket CRD — this Job is the only
provisioning mechanism. It imports pre-known keys; it does **not** generate keys
and writes no secret material back anywhere.

## What ships

| Resource | Function |
|---|---|
| `ServiceAccount garage-buckets` | Pod identity for the Job. No RBAC — the Job touches no Kubernetes API, only the Garage admin HTTP API. |
| `ConfigMap garage-buckets-provision` | The catalog-owned `provision.sh` (signed workload, never consumer-patched). |
| `Job garage-buckets` | Runs `provision.sh` once per Argo sync (sync-wave 10), then exits. Idempotent. |

The `garage` namespace is **not** shipped here — it is the shared namespace
declared by the sibling component `storage-objects/garage` (sole-claimant rule).

## Mechanism (Garage admin API v2)

The script talks to the admin API on port `3903` with
`Authorization: Bearer <adminToken>`. For every `{name, key_alias}` entry in the
consumer's `buckets.yaml`:

1. **Bucket** — `GET /v2/GetBucketInfo?globalAlias=<name>`; on `404`,
   `POST /v2/CreateBucket {"globalAlias":"<name>"}`. The bucket **UUID** is
   extracted from the response `.id`.
2. **Key** — `GET /v2/GetKeyInfo?id=<accessKeyId>`; on `404`,
   `POST /v2/ImportKey {"accessKeyId":…,"secretAccessKey":…,"name":<alias>}`
   (import of consumer-supplied known material; supported by Garage v2.3.0).
3. **Grant** — `POST /v2/AllowBucketKey {"bucketId":<uuid>,"accessKeyId":…,
   "permissions":{"read":true,"write":true,"owner":false}}` — called
   unconditionally with the bucket **UUID** (`.id`), never the globalAlias;
   `AllowBucketKey` is itself idempotent.

**Idempotency** is GET-then-create/import: a second Job run exits `0` with no
duplicates. Reference: the
[Garage admin API v2 spec](https://garagehq.deuxfleurs.fr/api/garage-admin-v2.json)
and the
[admin-API reference manual](https://garagehq.deuxfleurs.fr/documentation/reference-manual/admin-api/).

## Image

`curlimages/curl:8.21.0` — minimal (Alpine-based, ~10 MiB), maintained by the
curl project, runs non-root, and ships an HTTP client. It carries no `jq`; the
script extracts the single flat `.id` field from the bucket response with POSIX
`grep`/`sed`, which keeps the image minimal and avoids pulling a heavier
`curl+jq` third-party image that publishes only `:latest`-style tags. Pinned to a
concrete release tag (`8.21.0`) — never `:latest`.

## Pod Security

The `garage` namespace enforces `pod-security.kubernetes.io/enforce: baseline`,
but the pod is authored to satisfy **restricted**, so it is admissible under any
baseline-or-stricter level the consumer chooses:

- pod `securityContext`: `runAsNonRoot: true`, `runAsUser: 65532` (non-zero),
  `seccompProfile.type: RuntimeDefault`;
- container `securityContext`: `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true` with a writable
  `emptyDir` mounted at `/tmp`.

## Consumer obligations

The catalog ships **no** default bucket list — the bucket names are consumer
composition. The consumer MUST supply:

### `ConfigMap garage-buckets-config` (mounted at `/etc/garage-buckets/`)

Key `buckets.yaml` — a block-style list mapping each bucket name to the
key-alias that gets read+write on it:

```yaml
buckets:
  - name: <bucket-name>
    key_alias: <key-alias>
  - name: <bucket-name>
    key_alias: <key-alias>
```

### `Secret garage-buckets-secret`

- Key `adminToken` — read via `secretKeyRef` into `GARAGE_ADMIN_TOKEN` (Bearer
  auth to the admin API).
- Per-alias key material, mounted as a volume at `/etc/garage-keys/`, following
  the convention `<alias>.access-key-id` and `<alias>.secret-key` — i.e. for a
  `key_alias: <key-alias>` entry, the keys `<key-alias>.access-key-id` and
  `<key-alias>.secret-key`.

> **GK prefix required.** Every `<alias>.access-key-id` MUST start with `GK`
> (the Garage access-key-id convention). The script validates this and exits
> non-zero with an actionable error on a non-`GK` id.

These secrets are synced into the cluster from Vault via
`secrets/external-secrets` — they are never committed to the catalog.

## Sync-wave position

`sync-wave: "10"` — needs an active Garage (wave 0) and the consumer's key
material synced via `secrets/external-secrets`.

## Bootstrap caveats

On a **fresh cluster** the Garage admin API (wave 0) MAY not be ready when this
Job runs at wave 10 — Garage must first finish `garage layout apply` before the
admin API serves bucket/key calls. If the Job reaches terminal `Failed` before
Garage is ready, the operator triggers a force-resync of this component after
confirming Garage is healthy:

```sh
kubectl -n garage exec <garage-pod> -- garage status
```

The Job is idempotent (GET-then-create/import guards), so a re-run is always
safe. Note also that the `Force=true,Replace=true` sync-option means an Argo
resync **mid-run** can kill and recreate the Job, leaving a transient
partial-provisioning window; because the Job is additive and idempotent, this
self-heals on the next completion.

## Disaster recovery

After a **Garage Raft restore**, force-resync this component. The provisioning
Job re-runs idempotently (the GET-then-import guards make every call a no-op when
state already matches) and re-registers any access keys missing from the restored
snapshot. This component **never deletes bucket data** — it is additive-only
(`CreateBucket` / `ImportKey` / `AllowBucketKey`, `owner: false`, no delete
calls), so a resync after a restore can only re-create missing buckets and
re-register missing keys, never remove anything.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-buckets:vX.Y.Z
```

## Related ADRs

- [ADR-0007 — Platform Object Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0011 — Secrets Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0024 — Customization Contract](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
- [ADR-0025 — ArgoCD Credentials (no PAT)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)

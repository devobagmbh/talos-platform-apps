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

The catalog ships **no** default bucket list — the bucket names (e.g.
`tf-state`, `mimir-blocks`) are consumer composition. The consumer MUST supply:

### `ConfigMap garage-buckets-config` (mounted at `/etc/garage-buckets/`)

Key `buckets.yaml` — a block-style list mapping each bucket name to the
key-alias that gets read+write on it:

```yaml
buckets:
  - name: tf-state
    key_alias: seeder-tf
  - name: mimir-blocks
    key_alias: obs-mimir
```

### `Secret garage-buckets-secret`

- Key `adminToken` — read via `secretKeyRef` into `GARAGE_ADMIN_TOKEN` (Bearer
  auth to the admin API).
- Per-alias key material, mounted as a volume at `/etc/garage-keys/`, following
  the convention `<alias>.access-key-id` and `<alias>.secret-key`. For the
  example above: `seeder-tf.access-key-id`, `seeder-tf.secret-key`,
  `obs-mimir.access-key-id`, `obs-mimir.secret-key`.

> **GK prefix required.** Every `<alias>.access-key-id` MUST start with `GK`
> (the Garage access-key-id convention). The script validates this and exits
> non-zero with an actionable error on a non-`GK` id.

These secrets are synced into the cluster from Vault via
`secrets/external-secrets` — they are never committed to the catalog.

## Sync-wave position

`sync-wave: "10"` — needs an active Garage (wave 0) and the consumer's key
material synced via `secrets/external-secrets`.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-buckets:vX.Y.Z
```

## Related ADRs

- [ADR-0007 — Platform Object Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0011 — Secrets Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0024 — Customization Contract](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
- [ADR-0025 — ArgoCD Credentials (no PAT)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)

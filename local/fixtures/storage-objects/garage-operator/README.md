# `storage-objects/garage-operator` — local E2E fixtures

Consumer-owned resources the catalog does **not** ship (ADR-0023/0024): the
`garage.rajsingh.info` CRs an operator-owned Garage cluster is made of. They exist so
the operator pair can be exercised end to end on the local Talos test cluster.

`task local:fixtures` is **not** used here. It derives the namespace from the
component's Argo `Application` destination — `garage-operator`, the operator's own
namespace, which is part of the artifact's namespace contract and MUST NOT hold
consumer workloads. These fixtures name their namespace (`garage-e2e`) explicitly and
are applied with plain `kubectl apply -f`.

## Apply

The bootstrap admin token is a **generated dev secret** and is deliberately not
committed. Create it first — the value never reaches a process argument list and is
never echoed:

```sh
val=$(head -c 32 /dev/urandom | od -An -v -tx1 | tr -d ' \n')
printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ntype: Opaque\ndata:\n  %s: %s\n' \
  e2e-admin-token garage-e2e admin-token "$(printf '%s' "$val" | base64 | tr -d '\n')" \
  | kubectl apply -f -
unset val
```

Then apply the manifests in filename order:

```sh
kubectl apply -f local/fixtures/storage-objects/garage-operator/manifests/
```

Without that Secret the `GarageCluster` stays `phase: Pending` with
`StorageTopologyReady=False (WaitingForLayoutSync)` — the operator cannot reach
Garage's Admin API to apply the cluster layout. `GarageAdminToken` CRs mint *further*
tokens through that same API, so the first one has to be pre-created.

## What the fixtures cover

| File | Purpose |
|---|---|
| `00-namespace.yaml` | `garage-e2e`, the consumer-side workload namespace |
| `10-garagecluster.yaml` | single-node cluster, authored at the **deprecated v1beta1** version so a read-back at v1beta2 exercises the conversion webhook |
| `20-garagebuckets.yaml` | `e2e-data` (the key is granted it) and `e2e-denied` (it is not) |
| `30-garagekey.yaml` | an S3 key scoped to `e2e-data`, credentials minted into the `e2e-app-s3` Secret |

The two buckets exist as a pair on purpose: a put/get that succeeds against the only
bucket in the cluster proves nothing about the permission model.

## Note on pod rollout

Operator-generated StatefulSets carry `updateStrategy: OnDelete`. After changing a
`GarageCluster` field the operator writes a new config and updates the StatefulSet,
but the running pod keeps the old one until it is deleted — see the component README
§ Failure modes.

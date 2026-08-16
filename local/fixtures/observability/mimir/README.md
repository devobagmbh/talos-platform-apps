# Local mimir fixtures

Everything the local Talos test cluster needs to run `observability/mimir` end to end —
in its shipped single-node default **and** in the HA shape a three-node consumer runs.

## Why this is a fixture directory, not `local/argo-apps/`

`task local:apply -- observability` fans out **every** file in `local/argo-apps/observability/`.
Mimir is eight workloads, one of which reserves 4 GiB, so putting it there would attach the
whole stack to every unrelated observability E2E on an 8 GiB node. The two Applications here
are applied by hand instead.

## Contents

| File | Applied by | What it is |
|---|---|---|
| `manifests/runtime-config.yaml` | `task local:fixtures` / `task local:s3-backend` | the consumer-owned non-secret S3 scalars (`mimir-runtime-config`) |
| `manifests/memcached.yaml` | same | a single memcached the query-path cache tests point at — the catalog ships none |
| `argo-app.yaml` | manual | mimir in its **shipped default** shape (auto-sync) |
| `argo-app-ha.yaml` | manual | mimir in the **HA** shape (manual sync, replica patches) |

The credential Secret `mimir-runtime-secret` is **not** in this directory. `task
local:s3-backend` mints it from the garage access key it provisions, so no credential is
ever committed.

## Single-node run (the shipped default)

```sh
task local:up
task local:s3-backend -- observability/mimir 0.0.0-dev
task local:publish    -- observability/mimir 0.0.0-dev
TAG=0.0.0-dev REGISTRY=kind-registry.registry.svc.cluster.local:5000/talos-platform-apps \
  envsubst < local/fixtures/observability/mimir/argo-app.yaml | kubectl apply -f -
```

## Three-node run (the HA shape)

The HA shape needs three schedulable nodes. `talosctl` cannot resize a cluster, so a
one-node cluster has to go first:

```sh
task local:down
LOCAL_WORKERS=2 task local:up          # control plane + 2 workers = 3 schedulable nodes
task local:s3-backend -- observability/mimir 0.0.0-dev
task local:publish    -- observability/mimir 0.0.0-dev
TAG=0.0.0-dev REGISTRY=kind-registry.registry.svc.cluster.local:5000/talos-platform-apps \
  envsubst < local/fixtures/observability/mimir/argo-app-ha.yaml | kubectl apply -f -
argocd app sync observability-mimir-ha
```

Then, and only after every ingester reports `ACTIVE` in the ring, raise the replication
factors and bump the pod-template annotation in the same step:

```sh
kubectl -n mimir patch cm mimir-runtime-config --type merge \
  -p '{"data":{"INGESTER_REPLICATION_FACTOR":"3","STORE_GATEWAY_REPLICATION_FACTOR":"3"}}'
# bump config-generation in argo-app-ha.yaml (1 -> 2), re-apply, sync again
```

Two syncs, not one: replicas first, factors second. The reverse makes ring quorum
unreachable — the state issue #379 fixed.

## Things that will cost you an hour if you skip them

- **Apply exactly one of the two Applications.** Both target the same namespace and the
  same objects; running them together makes two Argo Applications fight over the same
  resources. Delete one before applying the other.
- **The local garage is a single pod on `emptyDir`.** Draining or stopping its node
  destroys the object store, which voids any node-loss result you were measuring. Check
  which node it is on before you drain anything.
- **The default StorageClass is node-pinned** (`local-path-provisioner`). A PVC binds its
  pod to one node for good, so "add a node" does not free a pod that is `Pending` on
  anti-affinity — its PVC still points at the old node. Delete the PVC, or use a
  network-attached StorageClass, when testing that recovery path.
- **A third ingester stuck `Pending` on three nodes is correct** when a fourth replica was
  requested: hard anti-affinity is doing its job. Read `kubectl describe pod` before
  concluding otherwise — free memory alone does not distinguish anti-affinity from a taint
  or a PVC node affinity.

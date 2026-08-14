# Fixtures — `task test:rbac-narrowing`

Committed inputs for the red-green binding of `task validate:rbac-narrowing`
(the RBAC-narrowing contract, apps#795). None of these is a catalog component: they
never render, publish or ship. Each directory has the *shape* of one, so the test
drives the real gate over it through the `RBAC_COMPONENT_DIRS` seam and the gate takes
exactly the code path it takes in CI.

The manifest is `manifest.yaml`, not `rendered/manifest.yaml`, because `.gitignore`
excludes `**/rendered/` globally and the lefthook `no-rendered` job blocks committing
it — the test therefore also sets `RBAC_MANIFEST_REL`. That seam exists for this
reason alone and is never set for a real run.

Every negative differs from `valid/` in exactly ONE respect and is asserted on its own
failure token, so reverting the single check it targets makes it pass:

| Directory | The one difference | Expected verdict |
|---|---|---|
| `valid` | — | accepted |
| `fixed` | declares `class: fixed` | accepted, reporting the skip |
| `widened` | a verb added to the rendered role | `GOLDEN DRIFT` |
| `narrowed` | a rule removed from the rendered role | `GOLDEN DRIFT` |
| `cluster-scoped-add` | a cluster-scoped rule grew, golden updated, declared cost not | `INERT SET MISMATCH` |
| `unclassified` | a resource absent from the scope map | `UNCLASSIFIED RESOURCE` |
| `resource-names` | a rule carrying `resourceNames` | `UNJUDGEABLE … (resourceNames)` |
| `aggregation-rule` | the role carries `aggregationRule`, rules unchanged | `UNJUDGEABLE … (aggregationRule)` |
| `non-resource-urls` | a `nonResourceURLs` rule, golden unchanged | `UNJUDGEABLE … (nonResourceURLs)` |
| `wildcard-verb` | a `*` verb, golden and cost updated to match | `UNJUDGEABLE … (wildcard)` |
| `no-manifest` | no render present | `MANIFEST MISSING` |
| `wrong-role-name` | the declaration names an absent role | `CLUSTERROLE NOT FOUND` |
| `duplicate-role` | the declared name appears in two documents | `DUPLICATE CLUSTERROLE` |
| `readme-stale` | the declared inert resource moved below the section boundary | `README PARITY` |
| `readme-no-role` | the section names the ClusterRole**Binding**, never the role | `README PARITY` |
| `bad-class` | a `class` outside the enum | `BAD CLASS` |
| `scope-bad-value.yaml` | a scope value outside `cluster\|namespaced` | `INVALID SCOPE VALUE` |

Two arms deserve their own note. The four `UNJUDGEABLE` shapes each assert their **own**
parenthesized discriminator: with one shared token, three of the four terms could be
deleted with every arm still green — and `aggregationRule` / `nonResourceURLs` rules
contribute no triples, so golden parity cannot catch them either. That combination is a
silent **accept** of a widened grant. `readme-no-role` exists because the ClusterRole
name is a strict prefix of the ClusterRoleBinding name the same section documents
deleting, so a bare substring match would report parity that is not there.

`scope.yaml` is the hermetic scope map every arm runs against. It deliberately omits
`batch|cronjobs`, which is the whole oracle of the `unclassified` arm — keying that arm
on the production `catalog/rbac-resource-scope.yaml` would let an unrelated PR that
legitimately adds `cronjobs` there flip this test.

`cluster-scoped-add` is the failure this contract exists for: an upstream chart bump
adds a cluster-scoped rule, a reviewer accepts the grant into the golden, and the
component README's cost statement is silently wrong for every narrowing consumer.

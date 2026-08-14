# Fixture component (rbac-narrowing test)

Fixture for `task test:rbac-narrowing`. Not a real catalog component.

## Security posture

### Namespace-scoped operation (supported consumer overlay)

A consumer MAY drop the cluster-wide binding and bind
`ClusterRole/fixture-manager-role` per namespace instead. What that costs: `nodes`
(`get`/`list`) becomes inaccessible, because a `RoleBinding` to a `ClusterRole`
grants nothing on cluster-scoped resources. (Stale on purpose: the declaration also
calls a second resource inert, and this section no longer names it.)

## Section boundary

Guards the gate's section extraction: this heading MUST end the section above, so a
resource named only here does not count as documented. `storageclasses` is mentioned
here on purpose — the declaration calls it inert, the narrowing section above no longer
names it, and this occurrence must NOT satisfy the parity check. Drop the extraction's
terminator and this fixture goes green, which is what binds it.

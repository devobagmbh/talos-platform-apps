# Fixture component (rbac-narrowing test)

Fixture for `task test:rbac-narrowing`. Not a real catalog component.

## Security posture

### Namespace-scoped operation (supported consumer overlay)

A consumer MAY drop `ClusterRoleBinding/fixture-manager-rolebinding` and bind the
shipped role per namespace instead — without ever naming the role it must `roleRef`. What that costs: `nodes`
(`get`/`list`) and `storageclasses` (`get`) become inaccessible, because a
`RoleBinding` to a `ClusterRole` grants nothing on cluster-scoped resources.

## Section boundary

Guards the gate's section extraction: this heading MUST end the section above, so a
resource named only here does not count as documented.

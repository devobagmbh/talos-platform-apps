# METADATA
# title: No inline secrets
# description: |
#   Rendered manifests MUST NOT contain kind: Secret with non-empty data or
#   stringData fields. Inline secrets in the catalog repo are a supply-chain
#   risk: they land in git history and OCI artifacts even if later deleted.
#
#   SOPS-encrypted secrets decrypt at apply-time (not rendered into manifest.yaml),
#   and ESO emits kind: ExternalSecret (not Secret), so both are out of scope
#   at render-time — a rendered Secret with non-empty data is always inline.
#
#   No type:-based exclusion: type is attacker-controllable and does not make
#   inline data safe. A kubernetes.io/service-account-token Secret with non-empty
#   data is still a violation.
#
#   Scope: depth-1 Object recursion (Object.spec.forProvider.manifest).
#
#   Transitional grandfather set (FROZEN — net-new exemptions require a linked
#   retirement issue #350; a diff GROWING this set is a blocking reviewer finding;
#   rename-in-place of an existing entry is allowed to track upstream chart renames).
# scope: package
# custom:
#   severity: critical
#   related_resources:
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md
package apps.no_inline_secrets

import rego.v1

# depth-1 only; do NOT extract to lib/ — per "ein Rego-File pro Regel" + --combine isolation (issue #236).
_targets contains t if { t := input }

_targets contains t if {
	input.kind == "Object"
	t := input.spec.forProvider.manifest
}

# Grandfather set — FROZEN; TODO(#350): externalize via ESO; remove entries on completion.
# Keyed (namespace, name). Empirically derived from `task render` probe (issue #236).
_grandfathered_secrets := {
	# harbor — chart renders placeholder secret values; externalize via ESO (issue #350)
	["harbor", "harbor-core"],
	["harbor", "harbor-jobservice"],
	["harbor", "harbor-registry"],
	["harbor", "harbor-registry-htpasswd"],
	["harbor", "harbor-trivy"],
	# crossview — inline credentials; externalize via ESO (issue #350)
	["crossview", "crossview-secrets"],
}

_is_grandfathered(t) if {
	[t.metadata.namespace, t.metadata.name] in _grandfathered_secrets
}

# Violation: Secret with non-empty data
deny contains msg if {
	some t in _targets
	t.kind == "Secret"
	count(object.get(t, "data", {})) > 0
	not _is_grandfathered(t)
	msg := sprintf(
		"Secret/%s (ns=%s) has non-empty data. Inline secrets must not be committed — use ESO ExternalSecret or SOPS-encrypted source instead.",
		[t.metadata.name, t.metadata.namespace],
	)
}

# Violation: Secret with non-empty stringData
deny contains msg if {
	some t in _targets
	t.kind == "Secret"
	count(object.get(t, "stringData", {})) > 0
	not _is_grandfathered(t)
	msg := sprintf(
		"Secret/%s (ns=%s) has non-empty stringData. Inline secrets must not be committed — use ESO ExternalSecret or SOPS-encrypted source instead.",
		[t.metadata.name, t.metadata.namespace],
	)
}

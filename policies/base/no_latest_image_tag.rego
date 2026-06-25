# METADATA
# title: No :latest image tags
# description: |
#   Container images MUST be pinned to an explicit tag or digest — no `:latest`
#   tag, no implicit default tag. Rationale: reproducible rollouts, no silent
#   drift on image pull.
#
#   Scope: depth-1 Object recursion (Object.spec.forProvider.manifest).
# scope: package
# custom:
#   severity: high
#   related_resources:
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md
package base.no_latest_image_tag

import rego.v1

# depth-1 only; do NOT extract to lib/ — per "ein Rego-File pro Regel" + --combine isolation (issue #236).
_targets contains t if { t := input }

_targets contains t if {
	input.kind == "Object"
	t := input.spec.forProvider.manifest
}

_workload_kinds := {
	"Pod",
	"Deployment",
	"StatefulSet",
	"DaemonSet",
	"Job",
	"ReplicaSet",
	"ReplicationController",
}

# Per-target container extractor — avoids cross-target mixing when _targets has >1 member.
# Returns a set of container objects for the given target.
_containers_for_target(t) := cs if {
	t.kind in _workload_kinds
	regular := object.get(t.spec, ["template", "spec", "containers"], object.get(t.spec, "containers", []))
	inits := object.get(t.spec, ["template", "spec", "initContainers"], object.get(t.spec, "initContainers", []))
	cs := {c | some c in regular} | {c | some c in inits}
}

_containers_for_target(t) := cs if {
	t.kind == "CronJob"
	regular := t.spec.jobTemplate.spec.template.spec.containers
	inits := object.get(t.spec.jobTemplate.spec.template.spec, "initContainers", [])
	cs := {c | some c in regular} | {c | some c in inits}
}

# Violation: image ends with :latest
deny contains msg if {
	some t in _targets
	some c in _containers_for_target(t)
	image := c.image
	endswith(image, ":latest")
	msg := sprintf(
		"%s/%s — container '%s' uses ':latest' image tag (image=%s). Pin to a specific version.",
		[t.kind, t.metadata.name, c.name, image],
	)
}

# Violation: no tag, no digest (implicit :latest)
deny contains msg if {
	some t in _targets
	some c in _containers_for_target(t)
	image := c.image
	not _has_explicit_tag_or_digest(image)
	msg := sprintf(
		"%s/%s — container '%s' has no explicit tag or digest (image=%s). Pin to a specific version or digest.",
		[t.kind, t.metadata.name, c.name, image],
	)
}

# Helper: image has either a ":TAG" suffix or a "@sha256:..." digest
_has_explicit_tag_or_digest(image) if {
	contains(image, "@sha256:")
}

_has_explicit_tag_or_digest(image) if {
	# strip optional registry+repo prefix, check whether ":" is in the last path segment
	parts := split(image, "/")
	last := parts[count(parts) - 1]
	contains(last, ":")
}

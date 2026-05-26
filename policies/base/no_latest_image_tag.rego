# METADATA
# title: No :latest image tags
# description: |
#   Container-Images müssen explizit gepinnt sein — kein `:latest`-Tag,
#   kein impliziter Default-Tag. Begründung: Reproduzierbare Rollouts,
#   keine stille Drift bei Image-Pull.
# scope: package
# custom:
#   severity: high
#   related_resources:
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md
package base.no_latest_image_tag

import rego.v1

# Workload-Kinds, die Container-Specs tragen
_workload_kinds := {
	"Pod",
	"Deployment",
	"StatefulSet",
	"DaemonSet",
	"Job",
	"ReplicaSet",
	"ReplicationController",
}

# Extrahiert alle Container (inkl. initContainers) aus den unterstützten Kinds.
_containers contains container if {
	input.kind in _workload_kinds
	some container in object.get(input.spec, ["template", "spec", "containers"], object.get(input.spec, "containers", []))
}

_containers contains container if {
	input.kind in _workload_kinds
	some container in object.get(input.spec, ["template", "spec", "initContainers"], object.get(input.spec, "initContainers", []))
}

# CronJob hat einen zusätzlichen jobTemplate-Wrapper.
_containers contains container if {
	input.kind == "CronJob"
	some container in input.spec.jobTemplate.spec.template.spec.containers
}

_containers contains container if {
	input.kind == "CronJob"
	some container in input.spec.jobTemplate.spec.template.spec.initContainers
}

# Verstoß: Image endet auf :latest
deny contains msg if {
	some container in _containers
	image := container.image
	endswith(image, ":latest")
	msg := sprintf(
		"%s/%s — container '%s' uses ':latest' image tag (image=%s). Pin to a specific version.",
		[input.kind, input.metadata.name, container.name, image],
	)
}

# Verstoß: kein Tag, kein Digest (impliziter :latest)
deny contains msg if {
	some container in _containers
	image := container.image
	not _has_explicit_tag_or_digest(image)
	msg := sprintf(
		"%s/%s — container '%s' has no explicit tag or digest (image=%s). Pin to a specific version or digest.",
		[input.kind, input.metadata.name, container.name, image],
	)
}

# Hilfsfunktion: Image hat entweder einen ":TAG"-Suffix oder einen "@sha256:..."-Digest
_has_explicit_tag_or_digest(image) if {
	contains(image, "@sha256:")
}

_has_explicit_tag_or_digest(image) if {
	# strip optional registry+repo, dann checken ob ein ":" im letzten Pfad-Segment
	parts := split(image, "/")
	last := parts[count(parts) - 1]
	contains(last, ":")
}

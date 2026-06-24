# METADATA
# title: Required resource limits
# description: |
#   Every container in a workload MUST declare resources.requests.cpu,
#   resources.requests.memory, and resources.limits.memory.
#   Missing resource declarations allow unbounded resource consumption,
#   which can cause OOM evictions and noisy-neighbour effects on shared nodes.
#
#   Scope: depth-1 Object recursion (Object.spec.forProvider.manifest).
#   ephemeralContainers are out of scope — not Helm-rendered.
#
#   Transitional grandfather set (FROZEN — net-new exemptions require a linked
#   retirement issue #349; a diff GROWING this set is a blocking reviewer finding;
#   rename-in-place of an existing entry is allowed to track upstream chart renames).
# scope: package
# custom:
#   severity: high
#   related_resources:
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md
package base.required_resource_limits

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

# Grandfather set — FROZEN; TODO(#349): retire by setting resources on each workload.
# Keyed (namespace, kind, name). Empirically derived from `task render` probe (issue #236).
_grandfathered_workloads := {
	["tetragon", "DaemonSet", "tetragon"],
	["cert-manager", "Deployment", "cert-manager-cainjector"],
	["cert-manager", "Deployment", "cert-manager"],
	["cert-manager", "Deployment", "cert-manager-webhook"],
	["external-secrets", "Deployment", "external-secrets-cert-controller"],
	["external-secrets", "Deployment", "external-secrets-webhook"],
	["kube-state-metrics", "Deployment", "kube-state-metrics"],
	["metrics-server", "Deployment", "metrics-server"],
	["alloy", "DaemonSet", "alloy"],
	["monitoring", "Deployment", "prometheus-operator-kube-p-operator"],
	["monitoring", "Job", "prometheus-operator-kube-p-admission-create"],
	["monitoring", "Job", "prometheus-operator-kube-p-admission-patch"],
	["kubevirt", "Deployment", "virt-operator"],
	["cdi", "Deployment", "cdi-operator"],
	["synology-csi", "StatefulSet", "synology-csi-controller"],
	["synology-csi", "DaemonSet", "synology-csi-node"],
	["democratic-csi", "DaemonSet", "democratic-csi-node"],
	["democratic-csi", "Deployment", "democratic-csi-controller"],
	["harbor", "Deployment", "harbor-core"],
	["harbor", "Deployment", "harbor-jobservice"],
	["harbor", "Deployment", "harbor-nginx"],
	["harbor", "Deployment", "harbor-portal"],
	["harbor", "Deployment", "harbor-registry"],
	["", "StatefulSet", "garage"],
}

_is_grandfathered(t) if {
	ns := object.get(t.metadata, "namespace", "")
	[ns, t.kind, t.metadata.name] in _grandfathered_workloads
}

# Violation: missing resources.requests.cpu
deny contains msg if {
	some t in _targets
	not _is_grandfathered(t)
	some c in _containers_for_target(t)
	not c.resources.requests.cpu
	msg := sprintf(
		"%s/%s — container '%s' missing resources.requests.cpu. Declare CPU request to prevent scheduling on over-committed nodes.",
		[t.kind, t.metadata.name, c.name],
	)
}

# Violation: missing resources.requests.memory
deny contains msg if {
	some t in _targets
	not _is_grandfathered(t)
	some c in _containers_for_target(t)
	not c.resources.requests.memory
	msg := sprintf(
		"%s/%s — container '%s' missing resources.requests.memory. Declare memory request to prevent OOM eviction.",
		[t.kind, t.metadata.name, c.name],
	)
}

# Violation: missing resources.limits.memory
deny contains msg if {
	some t in _targets
	not _is_grandfathered(t)
	some c in _containers_for_target(t)
	not c.resources.limits.memory
	msg := sprintf(
		"%s/%s — container '%s' missing resources.limits.memory. Declare memory limit to bound unbounded growth.",
		[t.kind, t.metadata.name, c.name],
	)
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

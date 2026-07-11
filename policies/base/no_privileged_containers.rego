# METADATA
# title: No privileged containers
# description: |
#   Containers MUST NOT run with securityContext.privileged: true unless they
#   appear on the permanent allow-list below.
#
#   The allow-list is container-level (namespace, kind, workload-name, container-name),
#   so a new privileged sidecar added to an allow-listed workload still fires.
#
#   Scope: depth-1 Object recursion (Object.spec.forProvider.manifest).
#   ephemeralContainers are out of scope — not Helm-rendered.
#
#   The allow-list is PERMANENT for infrastructure components that legitimately
#   require host-level access (CSI drivers, CNI plugins, eBPF tracers).
#   Adding a new entry requires a linked ADR or reviewer approval documenting
#   the operational necessity.
# scope: package
# custom:
#   severity: critical
#   related_resources:
#     - https://kubernetes.io/docs/concepts/security/pod-security-standards/
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md
package base.no_privileged_containers

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

# Permanent allow-list — container-level (namespace, kind, workload-name, container-name).
# Empirically derived from `task render` probe (issue #236).
# PERMANENT: these workloads legitimately require privileged access for host-level operations.
# To add an entry: open a PR with a linked ADR or reviewer-approved rationale.
_privileged_allowed := {
	# Multus CNI — installs CNI plugins and binaries on the host
	["kube-system", "DaemonSet", "kube-multus-ds", "install-cni-plugins"],
	["kube-system", "DaemonSet", "kube-multus-ds", "install-multus-binary"],
	["kube-system", "DaemonSet", "kube-multus-ds", "kube-multus"],
	# Tetragon — eBPF-based security observability requires host access
	["tetragon", "DaemonSet", "tetragon", "tetragon"],
	# democratic-csi — CSI driver requires host filesystem access
	["democratic-csi", "DaemonSet", "democratic-csi-node", "csi-driver"],
	# synology-csi controller — CSI operations requiring host-level access
	["synology-csi", "StatefulSet", "synology-csi-controller", "csi-attacher"],
	["synology-csi", "StatefulSet", "synology-csi-controller", "csi-plugin"],
	["synology-csi", "StatefulSet", "synology-csi-controller", "csi-provisioner"],
	["synology-csi", "StatefulSet", "synology-csi-controller", "csi-resizer"],
	# synology-csi node — CSI node plugin requires privileged access
	["synology-csi", "DaemonSet", "synology-csi-node", "csi-driver-registrar"],
	["synology-csi", "DaemonSet", "synology-csi-node", "csi-plugin"],
}

_is_allowed(t, c) if {
	[t.metadata.namespace, t.kind, t.metadata.name, c.name] in _privileged_allowed
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

# Violation: privileged container not on the allow-list
deny contains msg if {
	some t in _targets
	some c in _containers_for_target(t)
	c.securityContext.privileged == true
	not _is_allowed(t, c)
	msg := sprintf(
		"%s/%s — container '%s' runs with securityContext.privileged: true. Add to the allow-list with a linked ADR if host-level access is operationally required.",
		[t.kind, t.metadata.name, c.name],
	)
}

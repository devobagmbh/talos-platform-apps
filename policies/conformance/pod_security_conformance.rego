# METADATA
# title: Workload conforms to its Namespace's declared PSA enforce level
# description: |
#   The sibling `base.pod_security_standards` policy only asserts that a declared
#   Namespace carries a *valid* enforce level. It does NOT check whether the
#   workloads shipped in the same artifact actually CONFORM to that level — so a
#   component can declare `enforce: baseline` while shipping a workload that PSA
#   admission would reject, and the defect stays invisible until live admission on
#   a real cluster (exactly the node-feature-discovery hostPath/baseline defect,
#   apps PR #328: "HostPath Volumes" is a *Baseline* PSS control — baseline AND
#   restricted forbid hostPath; only privileged admits it).
#
#   This policy runs over a SINGLE component's rendered artifact with
#   `conftest test --combine` (so `input` is the array of that component's
#   documents) and, when the artifact ships a Namespace declaring enforce
#   `baseline` or `restricted`, denies any workload pod spec in the same artifact
#   that violates the Baseline structural controls. `privileged` is not gated
#   (it admits everything); an artifact with no Namespace is consumer-owned and
#   not gated here.
#
#   INVOCATION REQUIREMENT (load-bearing): this package is INERT without `--combine`.
#   In a non-combine run (e.g. `task scan:conftest`, which loads `policies/` whole)
#   `input` is a single bare document, every `input[i].contents` access is undefined,
#   `_gated` is false, and ALL deny rules silently produce nothing — no error, no
#   signal. Enforcement lives ONLY in `task scan:psa-conformance` (per-component
#   `--combine`). A refactor that drops `--combine`, or folds this package into the
#   non-combine `scan:conftest` run, turns the gate into a no-op while `conftest
#   verify` stays green (the self-tests build the combined array shape directly). Keep
#   the dedicated combine task.
#
#   SCOPE (deliberately bounded — no silent cap): this checks the Baseline
#   *structural forbid* controls — the deterministic, zero-false-positive set that
#   forces a workload to `privileged`: hostPath volumes, host namespaces
#   (hostNetwork/hostPID/hostIPC), privileged containers, host ports, Windows
#   hostProcess, non-Default procMount, Unconfined seccomp, and added capabilities
#   outside the declared level's allow-list (Baseline: a 13-member list; Restricted:
#   NET_BIND_SERVICE only). NOT yet checked (tracked follow-up, lower
#   frequency / judgment-bearing): sysctls safe-list, AppArmor/SELinux value
#   constraints, and ALL Restricted-additional hardening (volume-type allow-list,
#   runAsNonRoot, runAsUser!=0, allowPrivilegeEscalation, required seccomp,
#   capabilities drop ALL). The catalog-evaluator keeps a residual semantic
#   judgment over these deferred controls — the gate's defer-list is NOT a
#   no-look-zone for the evaluator.
#
#   FOUR BOUNDARIES a reader must not over-read:
#   1. Closed workload kind-set: pod specs are extracted from Deployment / DaemonSet
#      / StatefulSet / ReplicaSet / Job / ReplicationController / Rollout / Pod /
#      CronJob only. A pod-bearing CRD outside this set (an operator CR embedding a
#      pod template) is the evaluator's residual judgment, not this gate.
#   2. Correlation is ARTIFACT-scoped, not namespace-scoped: the level declared by
#      the artifact's Namespace gates ALL pod specs in the same artifact. This is
#      exact under the one-Namespace-per-component invariant; a (malformed) artifact
#      shipping two Namespaces at different levels would gate every workload against
#      the strictest — over-strict (fail-safe), surfacing at that component's CI.
#   3. No-Namespace (consumer-owned) artifacts are NOT gated: their enforce level is
#      composed by the consumer, invisible here. A hostPath workload that ships no
#      Namespace and documents "deploy me into namespace X" is the evaluator's
#      residual judgment + the component README, not this gate.
#   4. Type-coercion: fields are matched on their YAML-typed value (a boolean `true`,
#      not the string "true"). A mistyped field is caught upstream by `kubeconform`
#      (`task lint:rendered`, in `task ci`) before conftest runs.
#   Authoritative control reference:
#   https://kubernetes.io/docs/concepts/security/pod-security-standards/
# custom:
#   severity: high
#   related_resources:
#     - https://kubernetes.io/docs/concepts/security/pod-security-standards/
#     - https://github.com/devobagmbh/talos-platform-apps/pull/328
package conformance.pod_security

import rego.v1

_enforce_label := "pod-security.kubernetes.io/enforce"

# Enforce levels declared on Namespaces in this (per-component) combined artifact.
_levels contains lvl if {
	some i
	input[i].contents.kind == "Namespace"
	lvl := input[i].contents.metadata.labels[_enforce_label]
}

# Gate only a baseline|restricted artifact. privileged admits everything; an artifact
# with no Namespace is consumer-owned (the per-label policy already requires a level).
_gated if _levels["baseline"]

_gated if _levels["restricted"]

# The declared level, for the message (strictest present; components ship <=1 Namespace).
_declared_level := "restricted" if _levels["restricted"]

_declared_level := "baseline" if {
	_levels["baseline"]
	not _levels["restricted"]
}

# Pod specs by workload kind, each tagged with an owner label for messages.
# Closed kind-set: pod-template controllers whose pod spec is at `.spec.template.spec`.
# `Rollout` (argoproj.io) is Deployment-shaped and in-ecosystem, so it is included.
# A pod-bearing CRD outside this set (an operator CR embedding a pod template) is
# NOT extracted here — that long tail is the catalog-evaluator's residual semantic
# judgment, NOT this gate (see the SCOPE note in the header).
_podspecs contains ps if {
	some i
	c := input[i].contents
	c.kind in {"Deployment", "DaemonSet", "StatefulSet", "ReplicaSet", "Job", "ReplicationController", "Rollout"}
	ps := {"owner": sprintf("%s/%s", [c.kind, c.metadata.name]), "spec": c.spec.template.spec}
}

_podspecs contains ps if {
	some i
	c := input[i].contents
	c.kind == "Pod"
	ps := {"owner": sprintf("Pod/%s", [c.metadata.name]), "spec": c.spec}
}

_podspecs contains ps if {
	some i
	c := input[i].contents
	c.kind == "CronJob"
	ps := {"owner": sprintf("CronJob/%s", [c.metadata.name]), "spec": c.spec.jobTemplate.spec.template.spec}
}

# All containers of a pod spec (workload + init + ephemeral).
_all_containers(spec) := cs if {
	cs := array.concat(
		array.concat(
			object.get(spec, "containers", []),
			object.get(spec, "initContainers", []),
		),
		object.get(spec, "ephemeralContainers", []),
	)
}

# Capabilities a pod may add, BY DECLARED LEVEL. Baseline permits a fixed 13-member
# list; Restricted tightens it to NET_BIND_SERVICE only. (Restricted additionally
# requires `capabilities.drop: [ALL]` — a Restricted-additional control left to the
# evaluator's residual judgment, not this gate.) `_allowed_caps` is defined only for
# the gated levels; every `capabilities` deny references it under `_gated`.
_baseline_allowed_caps := {
	"AUDIT_WRITE", "CHOWN", "DAC_OVERRIDE", "FOWNER", "FSETID", "KILL", "MKNOD",
	"NET_BIND_SERVICE", "SETFCAP", "SETGID", "SETPCAP", "SETUID", "SYS_CHROOT",
}

_allowed_caps := _baseline_allowed_caps if _declared_level == "baseline"

_allowed_caps := {"NET_BIND_SERVICE"} if _declared_level == "restricted"

# ---------------- Baseline structural controls ----------------

# HostPath volumes — the defect this policy was built for.
deny contains msg if {
	_gated
	some ps in _podspecs
	some v in object.get(ps.spec, "volumes", [])
	v.hostPath
	msg := sprintf(
		"PSA-conformance: %s mounts a hostPath volume but its Namespace declares enforce: %s. 'HostPath Volumes' is a Baseline control — baseline AND restricted forbid hostPath; a hostPath workload requires enforce: privileged.",
		[ps.owner, _declared_level],
	)
}

# Host namespaces.
deny contains msg if {
	_gated
	some ps in _podspecs
	some field in ["hostNetwork", "hostPID", "hostIPC"]
	ps.spec[field] == true
	msg := sprintf(
		"PSA-conformance: %s sets %s:true but Namespace enforce: %s forbids host namespaces (only privileged permits them).",
		[ps.owner, field, _declared_level],
	)
}

# Privileged containers.
deny contains msg if {
	_gated
	some ps in _podspecs
	some ctr in _all_containers(ps.spec)
	object.get(ctr, ["securityContext", "privileged"], false) == true
	msg := sprintf(
		"PSA-conformance: %s container %s sets securityContext.privileged:true but Namespace enforce: %s forbids privileged containers.",
		[ps.owner, object.get(ctr, "name", "?"), _declared_level],
	)
}

# Added capabilities outside the Baseline allow-list.
deny contains msg if {
	_gated
	some ps in _podspecs
	some ctr in _all_containers(ps.spec)
	some cap in object.get(ctr, ["securityContext", "capabilities", "add"], [])
	not _allowed_caps[cap]
	msg := sprintf(
		"PSA-conformance: %s container %s adds capability %s, outside the %s capabilities allow-list, but Namespace enforce: %s forbids it.",
		[ps.owner, object.get(ctr, "name", "?"), cap, _declared_level, _declared_level],
	)
}

# Host ports.
deny contains msg if {
	_gated
	some ps in _podspecs
	some ctr in _all_containers(ps.spec)
	some p in object.get(ctr, "ports", [])
	object.get(p, "hostPort", 0) > 0
	msg := sprintf(
		"PSA-conformance: %s container %s declares hostPort %d but Namespace enforce: %s forbids host ports.",
		[ps.owner, object.get(ctr, "name", "?"), object.get(p, "hostPort", 0), _declared_level],
	)
}

# Windows hostProcess (pod-level or container-level).
deny contains msg if {
	_gated
	some ps in _podspecs
	object.get(ps.spec, ["securityContext", "windowsOptions", "hostProcess"], false) == true
	msg := sprintf("PSA-conformance: %s sets windowsOptions.hostProcess:true but Namespace enforce: %s forbids it.", [ps.owner, _declared_level])
}

deny contains msg if {
	_gated
	some ps in _podspecs
	some ctr in _all_containers(ps.spec)
	object.get(ctr, ["securityContext", "windowsOptions", "hostProcess"], false) == true
	msg := sprintf("PSA-conformance: %s container %s sets windowsOptions.hostProcess:true but Namespace enforce: %s forbids it.", [ps.owner, object.get(ctr, "name", "?"), _declared_level])
}

# /proc mount type — anything other than Default is a Baseline violation.
deny contains msg if {
	_gated
	some ps in _podspecs
	some ctr in _all_containers(ps.spec)
	pm := object.get(ctr, ["securityContext", "procMount"], "Default")
	pm != "Default"
	msg := sprintf("PSA-conformance: %s container %s sets procMount:%s but Namespace enforce: %s allows only Default.", [ps.owner, object.get(ctr, "name", "?"), pm, _declared_level])
}

# Seccomp Unconfined (pod-level or container-level) — Baseline forbids Unconfined.
deny contains msg if {
	_gated
	some ps in _podspecs
	object.get(ps.spec, ["securityContext", "seccompProfile", "type"], "") == "Unconfined"
	msg := sprintf("PSA-conformance: %s sets pod seccompProfile.type:Unconfined but Namespace enforce: %s forbids it.", [ps.owner, _declared_level])
}

deny contains msg if {
	_gated
	some ps in _podspecs
	some ctr in _all_containers(ps.spec)
	object.get(ctr, ["securityContext", "seccompProfile", "type"], "") == "Unconfined"
	msg := sprintf("PSA-conformance: %s container %s sets seccompProfile.type:Unconfined but Namespace enforce: %s forbids it.", [ps.owner, object.get(ctr, "name", "?"), _declared_level])
}

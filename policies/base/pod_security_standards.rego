# METADATA
# title: Namespace declares a Pod Security Admission enforce level
# description: |
#   Every Namespace a component declares MUST carry a
#   `pod-security.kubernetes.io/enforce` label set to a valid PSA level
#   (privileged | baseline | restricted). A namespace without an explicit
#   enforce level inherits the cluster default — an undefined security
#   posture. The component author picks the strictest level the rendered
#   workload satisfies (see the skill's CONVENTIONS.md § Namespace & PSA);
#   this deterministic policy only asserts that *some* valid level is
#   declared on every declared namespace. Whether a component that owns a
#   dedicated namespace actually SHIPS one is a semantic judgment the gate
#   cannot make — the catalog-evaluator's semantic AC covers that gap.
# scope: package
# custom:
#   severity: high
#   related_resources:
#     - https://kubernetes.io/docs/concepts/security/pod-security-admission/
#     - https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md
package base.pod_security_standards

import rego.v1

_enforce_label := "pod-security.kubernetes.io/enforce"

_valid_levels := {"privileged", "baseline", "restricted"}

# Violation: a declared Namespace without the enforce label (no labels at all,
# or labels present but the enforce key absent).
deny contains msg if {
	input.kind == "Namespace"
	not input.metadata.labels[_enforce_label]
	msg := sprintf(
		"Namespace/%s — missing '%s' label. Declare a Pod Security Admission enforce level (privileged|baseline|restricted).",
		[input.metadata.name, _enforce_label],
	)
}

# Violation: enforce label present but not a valid PSA level.
deny contains msg if {
	input.kind == "Namespace"
	level := input.metadata.labels[_enforce_label]
	not _valid_levels[level]
	msg := sprintf(
		"Namespace/%s — '%s: %s' is not a valid PSA level (must be privileged|baseline|restricted).",
		[input.metadata.name, _enforce_label, level],
	)
}

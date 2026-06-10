# Self-tests for pod_security_standards.rego — run via `task scan:conftest-verify`
# (conftest verify --policy policies/).
package base.pod_security_standards

import rego.v1

# --- Violations: declared Namespace without a valid enforce level ---

test_namespace_no_labels_violates if {
	count(deny) > 0 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-bad"},
	}
}

test_namespace_missing_enforce_violates if {
	count(deny) > 0 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-bad", "labels": {"team": "platform"}},
	}
}

test_namespace_invalid_level_violates if {
	count(deny) > 0 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-bad", "labels": {"pod-security.kubernetes.io/enforce": "strict"}},
	}
}

# --- Edge: falsy label values (empty string / null) deny exactly once ---
# In Rego only `false` and `undefined` are falsy, so an empty-string or null
# value is NOT treated as a missing key by rule 1 (`not ""` / `not null` are
# both false); only rule 2 (invalid-level) fires → exactly one deny message.

test_namespace_empty_enforce_denies_once if {
	count(deny) == 1 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-empty", "labels": {"pod-security.kubernetes.io/enforce": ""}},
	}
}

test_namespace_null_enforce_denies_once if {
	count(deny) == 1 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-null", "labels": {"pod-security.kubernetes.io/enforce": null}},
	}
}

# --- Conforming: each of the three valid PSA levels ---

test_namespace_restricted_ok if {
	count(deny) == 0 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-good", "labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
	}
}

test_namespace_baseline_ok if {
	count(deny) == 0 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-good", "labels": {"pod-security.kubernetes.io/enforce": "baseline"}},
	}
}

test_namespace_privileged_ok if {
	count(deny) == 0 with input as {
		"kind": "Namespace",
		"metadata": {"name": "ns-csi", "labels": {"pod-security.kubernetes.io/enforce": "privileged"}},
	}
}

# --- Non-Namespace kinds are ignored (the policy only governs declared namespaces) ---

test_non_namespace_ignored if {
	count(deny) == 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "app"},
		"spec": {},
	}
}

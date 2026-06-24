# Self-tests for no_privileged_containers.rego — run via `task scan:conftest-verify`
# (conftest verify --policy policies/).
#
# Shape: bare-document `with input as {...}` — NOT the --combine array shape.
# Pattern for positive tests: assign deny set first, then assert on it.
package base.no_privileged_containers

import rego.v1

# ---------------------------------------------------------------------------
# Positive test — privileged container not on allow-list → deny fires
# ---------------------------------------------------------------------------

test_privileged_container_violates if {
	msgs := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "bad-app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"securityContext": {"privileged": true},
		}]}}},
	}
	some m in msgs
	contains(m, "privileged: true")
}

# ---------------------------------------------------------------------------
# Negative test — non-privileged container → no deny
# ---------------------------------------------------------------------------

test_non_privileged_container_passes if {
	count(deny) == 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "good-app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"securityContext": {"runAsNonRoot": true, "allowPrivilegeEscalation": false},
		}]}}},
	}
}

# ---------------------------------------------------------------------------
# Exemption-suppresses — allow-listed identity → no deny
# ---------------------------------------------------------------------------

test_allowed_tetragon_suppressed if {
	count(deny) == 0 with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "tetragon", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"securityContext": {"privileged": true},
		}]}}},
	}
}

# ---------------------------------------------------------------------------
# Near-miss-still-denies — one case per key field
# The allow-list is (namespace, kind, workload-name, container-name); each test
# changes exactly one field from a valid allow-list entry to prove container-level
# specificity.
# ---------------------------------------------------------------------------

# Different namespace — same kind/workload/container
test_near_miss_different_namespace_still_denies if {
	result := deny with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "tetragon", "namespace": "other-ns"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"securityContext": {"privileged": true},
		}]}}},
	}
	count(result) > 0
}

# Different kind — same ns/workload/container
test_near_miss_different_kind_still_denies if {
	result := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "tetragon", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"securityContext": {"privileged": true},
		}]}}},
	}
	count(result) > 0
}

# Different workload name — same ns/kind/container
test_near_miss_different_workload_name_still_denies if {
	result := deny with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "tetragon-other", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"securityContext": {"privileged": true},
		}]}}},
	}
	count(result) > 0
}

# Different container name — same ns/kind/workload (proves container-level grant, not workload-level)
test_near_miss_different_container_name_still_denies if {
	result := deny with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "tetragon", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "new-sidecar",
			"image": "app:v1.0.0",
			"securityContext": {"privileged": true},
		}]}}},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# Object-recursion — Object wrapping a privileged inner workload fires
# ---------------------------------------------------------------------------

test_object_wrapped_privileged_fires if {
	msgs := deny with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Deployment",
			"metadata": {"name": "inner-workload", "namespace": "apps"},
			"spec": {"template": {"spec": {"containers": [{
				"name": "app",
				"image": "app:v1.0.0",
				"securityContext": {"privileged": true},
			}]}}},
		}}},
	}
	some m in msgs
	contains(m, "inner-workload")
}

# Object wrapping a compliant inner workload → no deny
test_object_wrapped_compliant_passes if {
	count(deny) == 0 with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Deployment",
			"metadata": {"name": "inner-workload", "namespace": "apps"},
			"spec": {"template": {"spec": {"containers": [{
				"name": "app",
				"image": "app:v1.0.0",
				"securityContext": {"runAsNonRoot": true},
			}]}}},
		}}},
	}
}

# ---------------------------------------------------------------------------
# Workload-kind matrix — initContainers
# ---------------------------------------------------------------------------

test_privileged_init_container_violates if {
	result := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {
			"containers": [{"name": "main", "image": "app:v1.0.0"}],
			"initContainers": [{
				"name": "privileged-init",
				"image": "busybox:1.36",
				"securityContext": {"privileged": true},
			}],
		}}},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# Non-privileged or missing securityContext — no deny
# ---------------------------------------------------------------------------

test_privileged_false_passes if {
	count(deny) == 0 with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"securityContext": {"privileged": false},
		}]}}},
	}
}

test_no_security_context_passes if {
	count(deny) == 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
		}]}}},
	}
}

# ---------------------------------------------------------------------------
# Non-workload kinds are ignored
# ---------------------------------------------------------------------------

test_configmap_ignored if {
	count(deny) == 0 with input as {
		"kind": "ConfigMap",
		"metadata": {"name": "foo", "namespace": "default"},
		"data": {},
	}
}

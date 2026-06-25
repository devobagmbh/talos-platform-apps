# Self-tests for required_resource_limits.rego — run via `task scan:conftest-verify`
# (conftest verify --policy policies/).
#
# Shape: bare-document `with input as {...}` — NOT the --combine array shape
# (scan:conftest uses non-combine mode; only scan:psa-conformance uses --combine).
# Pattern for positive tests: assign deny set first, then assert on it.
package base.required_resource_limits

import rego.v1

# ---------------------------------------------------------------------------
# Positive tests — each violates exactly ONE branch so the token uniquely
# identifies the firing deny rule. Other required fields are valid.
# ---------------------------------------------------------------------------

test_missing_cpu_request_violates if {
	msgs := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"resources": {"requests": {"memory": "128Mi"}, "limits": {"memory": "256Mi"}},
		}]}}},
	}
	some m in msgs
	contains(m, "requests.cpu")
}

test_missing_memory_request_violates if {
	msgs := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"resources": {"requests": {"cpu": "100m"}, "limits": {"memory": "256Mi"}},
		}]}}},
	}
	some m in msgs
	contains(m, "requests.memory")
}

test_missing_memory_limit_violates if {
	msgs := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"resources": {"requests": {"cpu": "100m", "memory": "128Mi"}},
		}]}}},
	}
	some m in msgs
	contains(m, "limits.memory")
}

# ---------------------------------------------------------------------------
# Negative test — compliant workload with all resources declared → no deny
# ---------------------------------------------------------------------------

test_compliant_deployment_passes if {
	count(deny) == 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "main",
			"image": "app:v1.0.0",
			"resources": {
				"requests": {"cpu": "100m", "memory": "128Mi"},
				"limits": {"memory": "256Mi"},
			},
		}]}}},
	}
}

# ---------------------------------------------------------------------------
# Exemption-suppresses — a grandfathered identity → no deny despite violation
# ---------------------------------------------------------------------------

test_grandfathered_workload_suppressed if {
	count(deny) == 0 with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "tetragon", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"resources": {},
		}]}}},
	}
}

# ---------------------------------------------------------------------------
# Near-miss-still-denies — one case per key field (namespace / kind / name)
# ---------------------------------------------------------------------------

test_near_miss_different_namespace_still_denies if {
	result := deny with input as {
		"kind": "DaemonSet",
		# Same kind+name as grandfathered entry but DIFFERENT namespace
		"metadata": {"name": "tetragon", "namespace": "kube-system"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"resources": {},
		}]}}},
	}
	count(result) > 0
}

test_near_miss_different_kind_still_denies if {
	result := deny with input as {
		# Same ns+name as grandfathered entry but DIFFERENT kind
		"kind": "Deployment",
		"metadata": {"name": "tetragon", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"resources": {},
		}]}}},
	}
	count(result) > 0
}

test_near_miss_different_name_still_denies if {
	result := deny with input as {
		"kind": "DaemonSet",
		"metadata": {"name": "tetragon-other", "namespace": "tetragon"},
		"spec": {"template": {"spec": {"containers": [{
			"name": "tetragon",
			"image": "quay.io/cilium/tetragon:v1.0.0",
			"resources": {},
		}]}}},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# Workload-kind matrix — initContainers
# ---------------------------------------------------------------------------

test_init_container_missing_cpu_violates if {
	msgs := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {
			"containers": [{"name": "main", "image": "app:v1.0.0", "resources": {"requests": {"cpu": "100m", "memory": "128Mi"}, "limits": {"memory": "256Mi"}}}],
			"initContainers": [{"name": "init", "image": "busybox:1.36", "resources": {"requests": {"memory": "64Mi"}, "limits": {"memory": "64Mi"}}}],
		}}},
	}
	some m in msgs
	contains(m, "requests.cpu")
}

# ---------------------------------------------------------------------------
# Workload-kind matrix — CronJob jobTemplate
# ---------------------------------------------------------------------------

test_cronjob_missing_memory_limit_violates if {
	msgs := deny with input as {
		"kind": "CronJob",
		"metadata": {"name": "batch", "namespace": "default"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [{
			"name": "task",
			"image": "batch:v1.0.0",
			"resources": {"requests": {"cpu": "100m", "memory": "128Mi"}},
		}]}}}}},
	}
	some m in msgs
	contains(m, "limits.memory")
}

# ---------------------------------------------------------------------------
# Object-recursion — Object wrapping a violating inner workload fires
# ---------------------------------------------------------------------------

test_object_wrapped_workload_fires if {
	msgs := deny with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Deployment",
			"metadata": {"name": "inner-workload", "namespace": "apps"},
			"spec": {"template": {"spec": {"containers": [{
				"name": "app",
				"image": "app:v1.0.0",
				"resources": {},
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
				"resources": {
					"requests": {"cpu": "100m", "memory": "128Mi"},
					"limits": {"memory": "256Mi"},
				},
			}]}}},
		}}},
	}
}

# ---------------------------------------------------------------------------
# Non-workload kinds are ignored (no deny on irrelevant resources)
# ---------------------------------------------------------------------------

test_configmap_ignored if {
	count(deny) == 0 with input as {
		"kind": "ConfigMap",
		"metadata": {"name": "foo", "namespace": "default"},
		"data": {"key": "value"},
	}
}

test_namespace_ignored if {
	count(deny) == 0 with input as {
		"kind": "Namespace",
		"metadata": {
			"name": "my-ns",
			"labels": {"pod-security.kubernetes.io/enforce": "baseline"},
		},
	}
}

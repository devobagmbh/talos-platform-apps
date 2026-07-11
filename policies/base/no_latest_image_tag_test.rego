# Self-tests for no_latest_image_tag.rego — run via `task scan:conftest-verify`
# (conftest verify --policy policies/).
#
# Shape: bare-document `with input as {...}` — NOT the --combine array shape.
# Pattern for positive tests: assign deny set first, then assert on it.
package base.no_latest_image_tag

import rego.v1

# ---------------------------------------------------------------------------
# Violations: Pod with :latest or without tag
# ---------------------------------------------------------------------------

test_pod_latest_violates if {
	msgs := deny with input as {
		"kind": "Pod",
		"metadata": {"name": "bad"},
		"spec": {"containers": [{"name": "main", "image": "nginx:latest"}]},
	}
	some m in msgs
	contains(m, ":latest")
}

test_pod_untagged_violates if {
	msgs := deny with input as {
		"kind": "Pod",
		"metadata": {"name": "bad"},
		"spec": {"containers": [{"name": "main", "image": "nginx"}]},
	}
	some m in msgs
	contains(m, "no explicit tag")
}

test_pod_untagged_with_registry_violates if {
	msgs := deny with input as {
		"kind": "Pod",
		"metadata": {"name": "bad"},
		"spec": {"containers": [{"name": "main", "image": "ghcr.io/devobagmbh/atlantis"}]},
	}
	some m in msgs
	contains(m, "no explicit tag")
}

# ---------------------------------------------------------------------------
# Violations: Deployment + initContainer with :latest
# ---------------------------------------------------------------------------

test_deployment_latest_violates if {
	msgs := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "bad"},
		"spec": {"template": {"spec": {"containers": [{"name": "app", "image": "alpine:latest"}]}}},
	}
	some m in msgs
	contains(m, "bad")
}

test_init_container_latest_violates if {
	result := deny with input as {
		"kind": "Deployment",
		"metadata": {"name": "bad"},
		"spec": {"template": {"spec": {
			"containers": [{"name": "main", "image": "alpine:3.20.1"}],
			"initContainers": [{"name": "init", "image": "busybox:latest"}],
		}}},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# Violation: CronJob (extra jobTemplate wrapper)
# ---------------------------------------------------------------------------

test_cronjob_latest_violates if {
	result := deny with input as {
		"kind": "CronJob",
		"metadata": {"name": "bad"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {
			"containers": [{"name": "task", "image": "alpine:latest"}],
		}}}}},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# Compliant manifests: pinned versions or digests
# ---------------------------------------------------------------------------

test_pod_pinned_ok if {
	count(deny) == 0 with input as {
		"kind": "Pod",
		"metadata": {"name": "good"},
		"spec": {"containers": [{"name": "main", "image": "nginx:1.25.3"}]},
	}
}

test_pod_with_registry_pinned_ok if {
	count(deny) == 0 with input as {
		"kind": "Pod",
		"metadata": {"name": "good"},
		"spec": {"containers": [{"name": "main", "image": "ghcr.io/devobagmbh/atlantis:v0.3.1"}]},
	}
}

test_pod_digest_ok if {
	count(deny) == 0 with input as {
		"kind": "Pod",
		"metadata": {"name": "good"},
		"spec": {"containers": [{"name": "main", "image": "nginx@sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]},
	}
}

test_statefulset_pinned_ok if {
	count(deny) == 0 with input as {
		"kind": "StatefulSet",
		"metadata": {"name": "good"},
		"spec": {"template": {"spec": {"containers": [{"name": "db", "image": "postgres:16.4"}]}}},
	}
}

# ---------------------------------------------------------------------------
# Non-workload kinds are ignored
# ---------------------------------------------------------------------------

test_configmap_ignored if {
	count(deny) == 0 with input as {
		"kind": "ConfigMap",
		"metadata": {"name": "foo"},
		"data": {"image": "anything:latest"},
	}
}

test_crd_ignored if {
	count(deny) == 0 with input as {
		"kind": "CustomResourceDefinition",
		"metadata": {"name": "xclusters.platform.devoba.de"},
	}
}

# ---------------------------------------------------------------------------
# Object-recursion — :latest in inner workload fires with inner name in message
# ---------------------------------------------------------------------------

test_object_wrapped_latest_fires if {
	msgs := deny with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Deployment",
			"metadata": {"name": "inner-workload", "namespace": "apps"},
			"spec": {"template": {"spec": {"containers": [{
				"name": "app",
				"image": "nginx:latest",
			}]}}},
		}}},
	}
	some m in msgs
	contains(m, "inner-workload")
}

# Object wrapping inner workload with no explicit tag also fires
test_object_wrapped_untagged_fires if {
	msgs := deny with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Deployment",
			"metadata": {"name": "inner-workload", "namespace": "apps"},
			"spec": {"template": {"spec": {"containers": [{
				"name": "app",
				"image": "nginx",
			}]}}},
		}}},
	}
	some m in msgs
	contains(m, "inner-workload")
}

# Object wrapping a compliant inner workload → no deny
test_object_wrapped_pinned_passes if {
	count(deny) == 0 with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Deployment",
			"metadata": {"name": "inner-workload", "namespace": "apps"},
			"spec": {"template": {"spec": {"containers": [{
				"name": "app",
				"image": "nginx:1.25.3",
			}]}}},
		}}},
	}
}

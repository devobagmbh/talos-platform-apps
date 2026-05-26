# Selbsttests für no_latest_image_tag.rego — laufen via `task scan:conftest-verify`
# (conftest verify --policy policies/).
package base.no_latest_image_tag

import rego.v1

# --- Verstöße: Pod mit :latest oder ohne Tag ---

test_pod_latest_violates if {
	count(deny) > 0 with input as {
		"kind": "Pod",
		"metadata": {"name": "bad"},
		"spec": {"containers": [{"name": "main", "image": "nginx:latest"}]},
	}
}

test_pod_untagged_violates if {
	count(deny) > 0 with input as {
		"kind": "Pod",
		"metadata": {"name": "bad"},
		"spec": {"containers": [{"name": "main", "image": "nginx"}]},
	}
}

test_pod_untagged_with_registry_violates if {
	count(deny) > 0 with input as {
		"kind": "Pod",
		"metadata": {"name": "bad"},
		"spec": {"containers": [{"name": "main", "image": "ghcr.io/devobagmbh/atlantis"}]},
	}
}

# --- Verstöße: Deployment + initContainer mit :latest ---

test_deployment_latest_violates if {
	count(deny) > 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "bad"},
		"spec": {"template": {"spec": {"containers": [{"name": "app", "image": "alpine:latest"}]}}},
	}
}

test_init_container_latest_violates if {
	count(deny) > 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "bad"},
		"spec": {"template": {"spec": {
			"containers": [{"name": "main", "image": "alpine:3.20.1"}],
			"initContainers": [{"name": "init", "image": "busybox:latest"}],
		}}},
	}
}

# --- Verstoß: CronJob (zusätzlicher jobTemplate-Wrapper) ---

test_cronjob_latest_violates if {
	count(deny) > 0 with input as {
		"kind": "CronJob",
		"metadata": {"name": "bad"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {
			"containers": [{"name": "task", "image": "alpine:latest"}],
		}}}}},
	}
}

# --- Konforme Manifeste: gepinnte Versionen oder Digest ---

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

# --- Nicht-Workload-Kinds werden ignoriert ---

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

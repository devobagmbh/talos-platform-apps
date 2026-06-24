# Self-tests for no_inline_secrets.rego — run via `task scan:conftest-verify`
# (conftest verify --policy policies/).
#
# Shape: bare-document `with input as {...}` — NOT the --combine array shape.
# Pattern for positive tests: assign deny set first, then assert on it.
package apps.no_inline_secrets

import rego.v1

# ---------------------------------------------------------------------------
# Positive tests — each violates exactly ONE branch
# ---------------------------------------------------------------------------

test_secret_with_data_violates if {
	msgs := deny with input as {
		"kind": "Secret",
		"metadata": {"name": "my-secret", "namespace": "default"},
		"data": {"key": "dmFsdWU="},
	}
	some m in msgs
	contains(m, "non-empty data")
}

test_secret_with_stringdata_violates if {
	msgs := deny with input as {
		"kind": "Secret",
		"metadata": {"name": "my-secret", "namespace": "default"},
		"stringData": {"key": "value"},
	}
	some m in msgs
	contains(m, "non-empty stringData")
}

# ---------------------------------------------------------------------------
# Negative test — empty data Secret passes (e.g. placeholder or type-only)
# ---------------------------------------------------------------------------

test_empty_data_secret_passes if {
	count(deny) == 0 with input as {
		"kind": "Secret",
		"metadata": {"name": "empty-secret", "namespace": "default"},
		"data": {},
	}
}

test_secret_without_data_field_passes if {
	count(deny) == 0 with input as {
		"kind": "Secret",
		"metadata": {"name": "type-only-secret", "namespace": "default"},
		"type": "Opaque",
	}
}

# ---------------------------------------------------------------------------
# Exemption-suppresses — grandfathered identity → no deny despite non-empty data
# ---------------------------------------------------------------------------

test_grandfathered_harbor_core_suppressed if {
	count(deny) == 0 with input as {
		"kind": "Secret",
		"metadata": {"name": "harbor-core", "namespace": "harbor"},
		"data": {"key": "dmFsdWU="},
	}
}

test_grandfathered_crossview_suppressed if {
	count(deny) == 0 with input as {
		"kind": "Secret",
		"metadata": {"name": "crossview-secrets", "namespace": "crossview"},
		"stringData": {"token": "abc123"},
	}
}

# ---------------------------------------------------------------------------
# Near-miss-still-denies — one case per key field (namespace / name)
# ---------------------------------------------------------------------------

# Same name as grandfathered, different namespace
test_near_miss_different_namespace_still_denies if {
	result := deny with input as {
		"kind": "Secret",
		"metadata": {"name": "harbor-core", "namespace": "other-ns"},
		"data": {"key": "dmFsdWU="},
	}
	count(result) > 0
}

# Same namespace as grandfathered, different name
test_near_miss_different_name_still_denies if {
	result := deny with input as {
		"kind": "Secret",
		"metadata": {"name": "harbor-other", "namespace": "harbor"},
		"data": {"key": "dmFsdWU="},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# No type-based exclusion — SA token Secret WITH data still fires
# ---------------------------------------------------------------------------

test_sa_token_with_data_still_fires if {
	result := deny with input as {
		"kind": "Secret",
		"metadata": {"name": "sa-token", "namespace": "default"},
		"type": "kubernetes.io/service-account-token",
		"data": {"token": "dG9rZW4="},
	}
	count(result) > 0
}

# ---------------------------------------------------------------------------
# Object-recursion — Object wrapping a Secret with data fires
# ---------------------------------------------------------------------------

test_object_wrapped_secret_fires if {
	msgs := deny with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Secret",
			"metadata": {"name": "inner-secret", "namespace": "apps"},
			"data": {"key": "dmFsdWU="},
		}}},
	}
	some m in msgs
	contains(m, "inner-secret")
}

# Object wrapping a Secret with empty data → no deny
test_object_wrapped_empty_secret_passes if {
	count(deny) == 0 with input as {
		"kind": "Object",
		"metadata": {"name": "outer-object", "namespace": "crossplane-system"},
		"spec": {"forProvider": {"manifest": {
			"kind": "Secret",
			"metadata": {"name": "inner-secret", "namespace": "apps"},
			"data": {},
		}}},
	}
}

# ---------------------------------------------------------------------------
# Non-Secret kinds are ignored
# ---------------------------------------------------------------------------

test_configmap_ignored if {
	count(deny) == 0 with input as {
		"kind": "ConfigMap",
		"metadata": {"name": "foo", "namespace": "default"},
		"data": {"key": "value"},
	}
}

test_deployment_ignored if {
	count(deny) == 0 with input as {
		"kind": "Deployment",
		"metadata": {"name": "app", "namespace": "default"},
		"spec": {"template": {"spec": {"containers": [{"name": "main", "image": "app:v1.0.0"}]}}},
	}
}

# ---------------------------------------------------------------------------
# ExternalSecret is NOT a Secret — ignored
# ---------------------------------------------------------------------------

test_external_secret_ignored if {
	count(deny) == 0 with input as {
		"kind": "ExternalSecret",
		"metadata": {"name": "my-eso-secret", "namespace": "default"},
		"spec": {"secretStoreRef": {"name": "vault-backend", "kind": "SecretStore"}},
	}
}

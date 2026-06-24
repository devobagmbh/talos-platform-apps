# Self-tests for pod_security_conformance.rego — run via `task scan:conftest-verify`
# (conftest verify --policy policies/). These simulate the `--combine` input shape:
# `input` is an array of {path, contents} objects (one per rendered document).
#
# Deny-direction tests pin the SPECIFIC control via a message substring (not just
# `count(deny) > 0`), so a test goes green only when ITS control fires — deleting any
# one deny rule turns its test red (red-green binding per ai-written-tests).
package conformance.pod_security

import rego.v1

_ns(level) := {"contents": {
	"kind": "Namespace",
	"metadata": {"name": "comp", "labels": {"pod-security.kubernetes.io/enforce": level}},
}}

# --- a controller (Deployment) carrying one container with `sc` + volumes `vols` ---
_deploy(sc, vols) := {"contents": {
	"kind": "Deployment",
	"metadata": {"name": "wl"},
	"spec": {"template": {"spec": {
		"containers": [{"name": "c", "image": "x", "securityContext": sc}],
		"volumes": vols,
	}}},
}}

_hostpath_vol := [{"name": "h", "hostPath": {"path": "/sys"}}]

# ===================== covered-control deny tests (one per rule) =====================

test_baseline_hostpath_denies if {
	r := deny with input as [_ns("baseline"), _deploy({}, _hostpath_vol)]
	some m in r
	contains(m, "hostPath")
}

# restricted inherits the baseline hostPath forbid.
test_restricted_hostpath_denies if {
	r := deny with input as [_ns("restricted"), _deploy({}, _hostpath_vol)]
	some m in r
	contains(m, "hostPath")
}

test_baseline_privileged_denies if {
	r := deny with input as [_ns("baseline"), _deploy({"privileged": true}, [])]
	some m in r
	contains(m, "privileged")
}

test_baseline_capabilities_add_denies if {
	r := deny with input as [_ns("baseline"), _deploy({"capabilities": {"add": ["SYS_ADMIN"]}}, [])]
	some m in r
	contains(m, "SYS_ADMIN")
}

# An allow-listed capability (NET_BIND_SERVICE) does NOT deny.
test_baseline_capabilities_allowlisted_passes if {
	count(deny) == 0 with input as [_ns("baseline"), _deploy({"capabilities": {"add": ["NET_BIND_SERVICE"]}}, [])]
}

# Under restricted the cap allow-list tightens to NET_BIND_SERVICE only: a
# Baseline-legal cap (CHOWN) added under restricted DENIES.
test_restricted_baseline_legal_cap_denies if {
	r := deny with input as [_ns("restricted"), _deploy({"capabilities": {"add": ["CHOWN"]}}, [])]
	some m in r
	contains(m, "CHOWN")
}

# Under restricted, NET_BIND_SERVICE is still allowed → PASS.
test_restricted_netbind_cap_passes if {
	count(deny) == 0 with input as [_ns("restricted"), _deploy({"capabilities": {"add": ["NET_BIND_SERVICE"]}}, [])]
}

test_baseline_hostport_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"containers": [{"name": "c", "ports": [{"hostPort": 8080}]}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "hostPort")
}

test_baseline_hostnetwork_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"hostNetwork": true, "containers": [{"name": "c"}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "host namespaces")
}

test_baseline_hostpid_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"hostPID": true, "containers": [{"name": "c"}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "hostPID")
}

test_baseline_hostipc_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"hostIPC": true, "containers": [{"name": "c"}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "hostIPC")
}

test_baseline_hostprocess_pod_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"securityContext": {"windowsOptions": {"hostProcess": true}}, "containers": [{"name": "c"}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "hostProcess")
}

test_baseline_hostprocess_container_denies if {
	r := deny with input as [_ns("baseline"), _deploy({"windowsOptions": {"hostProcess": true}}, [])]
	some m in r
	contains(m, "hostProcess")
}

test_baseline_procmount_denies if {
	r := deny with input as [_ns("baseline"), _deploy({"procMount": "Unmasked"}, [])]
	some m in r
	contains(m, "procMount")
}

test_baseline_seccomp_unconfined_pod_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"securityContext": {"seccompProfile": {"type": "Unconfined"}}, "containers": [{"name": "c"}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "seccompProfile.type:Unconfined")
}

test_baseline_seccomp_unconfined_container_denies if {
	r := deny with input as [_ns("baseline"), _deploy({"seccompProfile": {"type": "Unconfined"}}, [])]
	some m in r
	contains(m, "seccompProfile.type:Unconfined")
}

# ===================== container-list coverage (init / ephemeral) =====================

test_baseline_privileged_initcontainer_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"containers": [{"name": "main"}], "initContainers": [{"name": "init", "securityContext": {"privileged": true}}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "privileged")
}

test_baseline_privileged_ephemeralcontainer_denies if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"containers": [{"name": "main"}], "ephemeralContainers": [{"name": "dbg", "securityContext": {"privileged": true}}]}}}}}
	r := deny with input as [_ns("baseline"), c]
	some m in r
	contains(m, "privileged")
}

# ===================== podspec-extraction shapes (Pod / CronJob / Rollout) =====================

test_pod_baseline_hostpath_denies if {
	p := {"contents": {"kind": "Pod", "metadata": {"name": "wl"}, "spec": {"containers": [{"name": "c"}], "volumes": _hostpath_vol}}}
	r := deny with input as [_ns("baseline"), p]
	some m in r
	contains(m, "hostPath")
}

test_cronjob_baseline_hostpath_denies if {
	cj := {"contents": {"kind": "CronJob", "metadata": {"name": "wl"}, "spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [{"name": "c"}], "volumes": _hostpath_vol}}}}}}}
	r := deny with input as [_ns("baseline"), cj]
	some m in r
	contains(m, "hostPath")
}

test_rollout_baseline_hostpath_denies if {
	ro := {"contents": {"kind": "Rollout", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"containers": [{"name": "c"}], "volumes": _hostpath_vol}}}}}
	r := deny with input as [_ns("baseline"), ro]
	some m in r
	contains(m, "hostPath")
}

# ===================== pass cases =====================

# privileged + hostPath → PASS (privileged is not gated).
test_privileged_hostpath_passes if {
	count(deny) == 0 with input as [_ns("privileged"), _deploy({}, _hostpath_vol)]
}

# baseline + clean workload → PASS.
test_baseline_clean_passes if {
	count(deny) == 0 with input as [_ns("baseline"), _deploy({"privileged": false}, [{"name": "t", "emptyDir": {}}])]
}

# restricted + clean workload → PASS (exercises the restricted gated branch in the pass direction).
test_restricted_clean_passes if {
	count(deny) == 0 with input as [_ns("restricted"), _deploy({"privileged": false}, [{"name": "t", "emptyDir": {}}])]
}

# baseline + a container with NO securityContext and no volumes → PASS (exercises every object.get default).
test_baseline_no_securitycontext_passes if {
	c := {"contents": {"kind": "Deployment", "metadata": {"name": "wl"}, "spec": {"template": {"spec": {"containers": [{"name": "c", "image": "x"}]}}}}}
	count(deny) == 0 with input as [_ns("baseline"), c]
}

# no Namespace (consumer-owned) → PASS even with hostPath (not gated).
test_no_namespace_passes if {
	count(deny) == 0 with input as [_deploy({}, _hostpath_vol)]
}

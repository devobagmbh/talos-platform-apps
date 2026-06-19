#!/usr/bin/env bash
# lint-version-parity.sh — apps#226 A7: declared `version.<sot>` vs rendered reality.
#
# The SOT axis HARD-FAILS (exit 1); secondary declared axes WARN. Per-`sot` rendered mapping
# (pinned — an undifferentiated check false-fails charts that emit only a subset of labels):
#   app        -> app.kubernetes.io/version label   [rendered set must contain version.app]
#   chart      -> declared-only for now (helm.sh/chart parity is a follow-up)   [WARN]
#   crd-schema -> rendered CRD .spec.group + .spec.versions[].name
#                 [must contain each api_surface[] served group/version]
#   none       -> no provenance axis to check   [WARN]
#
# Scans every compatibility.yaml carrying a typed `version` block; un-migrated components
# (still on the legacy apis[]) are skipped, so this is safe to run repo-wide during rollout.
#
# Usage:
#   scripts/lint-version-parity.sh                       # all migrated components
#   scripts/lint-version-parity.sh databases/cnpg ...    # scope to specific components
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail=0
warn=0
checked=0

if [ "$#" -gt 0 ]; then
  compat_files=()
  for c in "$@"; do compat_files+=("sub-layers/${c%/*}/components/${c#*/}/compatibility.yaml"); done
else
  # portable to bash 3.2 (macOS default) — `mapfile` is bash 4+
  compat_files=()
  while IFS= read -r line; do compat_files+=("$line"); done \
    < <(find sub-layers -name compatibility.yaml -not -path '*/.claude/*' | sort)
fi

for compat in "${compat_files[@]}"; do
  [ -f "$compat" ] || { echo "ERROR $compat not found"; fail=1; continue; }
  migrated=$(yq -r '[.provides[] | select(has("version"))] | length' "$compat")
  [ "$migrated" -gt 0 ] || continue

  comp_dir="$(dirname "$compat")"
  sub_layer="$(echo "$comp_dir" | sed -E 's#sub-layers/([^/]+)/components/.*#\1#')"
  cid="${sub_layer}/$(basename "$comp_dir")"
  manifest="${comp_dir}/rendered/manifest.yaml"

  if [ ! -s "$manifest" ]; then
    echo "WARN  [$cid] no rendered manifest — run 'task render:one -- $cid'; render-parity skipped"
    warn=$((warn + 1)); continue
  fi

  n=$(yq -r '.provides | length' "$compat")
  for i in $(seq 0 $((n - 1))); do
    sot=$(yq -r ".provides[$i].version.sot // \"\"" "$compat")
    [ -n "$sot" ] && [ "$sot" != "null" ] || continue
    checked=$((checked + 1))
    case "$sot" in
      app)
        declared=$(yq -r ".provides[$i].version.app" "$compat")
        # extraction may legitimately be empty (label-less raw manifests) — guard against pipefail
        rendered=$(grep -hoE 'app\.kubernetes\.io/version: "?[^"]+' "$manifest" \
                   | sed -E 's/.*version: "?//' | sort -u | tr '\n' ' ' || true)
        img_tags=$(grep -hoE 'image: "?[^"@ ]+' "$manifest" | sed -E 's/.*://' | sort -u | tr '\n' ' ' || true)
        if printf ' %s ' "$rendered" | grep -qF " $declared "; then
          echo "OK    [$cid] sot=app declared=$declared ∈ rendered labels{ $rendered}"
        elif printf ' %s ' "$img_tags" | grep -qF " $declared "; then
          # #226 A7: "app -> app.kubernetes.io/version (+ image tag)" — label-less components (raw manifests) match via image tag
          echo "OK    [$cid] sot=app declared=$declared ∈ rendered image tags (no app-version label)"
        else
          echo "FAIL  [$cid] sot=app declared=$declared NOT in rendered labels{ $rendered} nor image tags"
          fail=1
        fi
        ;;
      crd-schema)
        rendered_gv=$(yq -r 'select(.kind == "CustomResourceDefinition") | .spec.group + "/" + .spec.versions[].name' \
                      "$manifest" 2>/dev/null | sort -u)
        while IFS= read -r s; do
          [ -n "$s" ] && [ "$s" != "null" ] || continue
          gv="${s%%/*}/${s##*@}"   # k8s.cni.cncf.io/NAD@v1 -> k8s.cni.cncf.io/v1
          if printf '%s\n' "$rendered_gv" | grep -qx "$gv"; then
            echo "OK    [$cid] sot=crd-schema surface=$gv ∈ rendered CRDs"
          else
            echo "FAIL  [$cid] sot=crd-schema surface=$gv NOT in rendered CRD group/versions{ $(printf '%s ' $rendered_gv)}"
            fail=1
          fi
        done < <(yq -r ".provides[$i].api_surface[]?" "$compat" 2>/dev/null)
        ;;
      chart | none)
        echo "WARN  [$cid] sot=$sot — provenance render-parity not enforced (declared-only)"
        warn=$((warn + 1))
        ;;
      *)
        echo "FAIL  [$cid] sot=$sot not in {app,chart,crd-schema,none}"
        fail=1
        ;;
    esac

    # artifacts[] cardinality (A3): every declared image:version must appear in the render.
    # Image tags always render, so this is render-parity-enforced (hard-fail), not declared-only.
    arts=$(yq -r ".provides[$i].version.artifacts // [] | length" "$compat")
    if [ "$arts" -gt 0 ]; then
      img_all=$(grep -hoE 'image: "?[^"@ ]+' "$manifest" | sed -E 's/image: "?//' | sort -u || true)
      for j in $(seq 0 $((arts - 1))); do
        aimg=$(yq -r ".provides[$i].version.artifacts[$j].image" "$compat")
        aver=$(yq -r ".provides[$i].version.artifacts[$j].version" "$compat")
        if printf '%s\n' "$img_all" | grep -qF "${aimg}:${aver}"; then
          echo "OK    [$cid] artifact ${aimg}:${aver} ∈ render"
        else
          echo "FAIL  [$cid] artifact ${aimg}:${aver} NOT in render"
          fail=1
        fi
      done
    fi
  done
done

echo "---"
echo "checked=$checked warnings=$warn result=$([ $fail -eq 0 ] && echo PASS || echo FAIL)"
exit $fail

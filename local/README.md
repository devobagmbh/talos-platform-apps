# Lokale Entwicklungs-Umgebung

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36.0-326ce5?style=flat-square&logo=kubernetes)](https://kubernetes.io/)
[![kind](https://img.shields.io/badge/kind-local%20K8s-326CE5?style=flat-square&logo=kubernetes)](https://kind.sigs.k8s.io/)
[![Cilium](https://img.shields.io/badge/Cilium-1.19.3-F8C517?style=flat-square&logo=cilium)](https://cilium.io/)
[![Gateway API](https://img.shields.io/badge/Gateway%20API-v1.2-326CE5?style=flat-square&logo=kubernetes)](https://gateway-api.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-7.7-EF7B4D?style=flat-square&logo=argo)](https://argo-cd.readthedocs.io/)
[![cert-manager](https://img.shields.io/badge/cert--manager-1.17-0A6E32?style=flat-square)](https://cert-manager.io/)
[![mkcert](https://img.shields.io/badge/mkcert-Local%20TLS-1F305F?style=flat-square)](https://github.com/FiloSottile/mkcert)
[![Helm](https://img.shields.io/badge/Helm-v3-0F1689?style=flat-square&logo=helm)](https://helm.sh/)
[![Taskfile](https://img.shields.io/badge/Taskfile-v3-29BEB0?style=flat-square&logo=Task)](https://taskfile.dev/)

Prod-konformer Kind-Cluster für lokales Sub-Layer-Testing: gleiche CNI- und Ingress-Komponenten wie Seeder/DHQ, plus lokale OCI-Registry mit Gateway-Exposure und mkcert-TLS. Damit lässt sich der komplette **Render → Push → Argo-Sync → Apply**-Workflow am Laptop spielen, bevor ein Tag in den produktiven OCI-Pfad gepusht wird.

## Zweck und Designprinzipien

- **Identisch mit Prod, wo es zählt**: Cilium statt kindnet, Gateway-API statt Ingress, kube-proxy abgeschaltet, ArgoCD als Pull-basierter Apply-Mechanismus. Was im Kind funktioniert, funktioniert auch auf Talos.
- **Keine `localhost`-Hostnames**: alles läuft über `*.localhost.direct` (öffentliche DNS-Wildcard auf `127.0.0.1`) mit mkcert-Wildcard-Zertifikat. Damit verhalten sich Argo, Helm-OCI-Client und Browser exakt wie gegen einen echten Cluster.
- **Bootstrap ohne Henne-Ei**: der OCI-Backing-Store ist ein eigener Docker-Container (`kind-registry`), nicht ein Pod im Cluster. Damit existiert die Registry **bevor** das Cluster lebt, und Argo kann beim ersten Sync Artefakte ziehen.
- **Workstation- vs. Cluster-View** auf dieselbe Registry: per Gateway als `registry.localhost.direct` (für `helm push`), intern als Service-DNS `kind-registry.registry.svc.cluster.local:5000` (für Argo).

## Architektur

```
┌──────────────────────────── Workstation ─────────────────────────────┐
│                                                                      │
│  Browser ───────► https://argocd.localhost.direct ─┐                 │
│  Browser ───────► https://registry.localhost.direct │ DNS → 127.0.0.1│
│  helm push  ────► oci://registry.localhost.direct ──┤                │
│                                                     │                │
│                                  Host-Port 443/80   │                │
└──────────────────────────────────────────│──────────┼────────────────┘
                                           ▼          ▼
                       ┌──────────────────────────────────────────┐
                       │  kind-Container (control-plane)          │
                       │  extraPortMappings 30080→80 / 30443→443  │
                       │                                          │
                       │  ┌──── Cilium-Gateway-Service ─────┐    │
                       │  │  NodePort 30080 / 30443         │    │
                       │  │  GatewayClass: cilium           │    │
                       │  └────┬────────────────────────────┘    │
                       │       │                                  │
                       │       │  TLS terminate (mkcert-Wildcard) │
                       │       ▼                                  │
                       │  ┌─────────────────────────────────┐    │
                       │  │  HTTPRoutes                     │    │
                       │  │   • argocd.localhost.direct ──► argocd-server (NS: argocd)
                       │  │   • registry.localhost.direct ► kind-registry  (NS: registry)
                       │  └─────────────────────────────────┘    │
                       │       │                                  │
                       │       │  intra-cluster Pull:             │
                       │       │  kind-registry.registry.svc      │
                       │       │  .cluster.local:5000             │
                       │       │  (Service + EndpointSlice ohne   │
                       │       │   Selector, statische Docker-IP) │
                       │       ▼                                  │
                       └──┬────────────────────────────────────┬──┘
                          │       docker-Netzwerk "kind"       │
                          │                                    │
                          ▼                                    │
                ┌─────────────────────┐                        │
                │  kind-registry      │ ◄──────────────────────┘
                │  (Docker-Container) │
                │  127.0.0.1:5001     │   (Workstation-direkter
                │  registry:2 anonym  │    Fallback ohne Gateway)
                └─────────────────────┘
```

## Komponenten und Manifeste

| Datei | Zweck |
|---|---|
| [`kind-config.yaml`](kind-config.yaml) | Kind-Spec: `disableDefaultCNI: true`, `kubeProxyMode: none`, containerd-Patch für `localhost:5001`, `extraPortMappings 30080→80` / `30443→443` |
| [`cilium-values.yaml`](cilium-values.yaml) | Helm-Werte: `kubeProxyReplacement: true`, `gatewayAPI.enabled: true`, Hubble + Relay, `l2announcements.enabled` für künftiges LB-IPAM |
| [`mkcert-cluster-issuer.yaml`](mkcert-cluster-issuer.yaml) | `ClusterIssuer mkcert-ca` für cert-manager (CA-Material aus `~/.local/share/mkcert/`) |
| [`gateway.yaml`](gateway.yaml) | Gateway `localhost-direct` mit HTTP- und HTTPS-Listener für `*.localhost.direct` + Wildcard-`Certificate` |
| [`argocd-values.yaml`](argocd-values.yaml) | Headless ArgoCD: Service `ClusterIP`, kein Ingress, `--insecure` (Gateway terminiert), Dex/Notifications/ApplicationSet aus |
| [`argocd-route.yaml`](argocd-route.yaml) | `HTTPRoute argocd` → `argocd-server:443` auf `argocd.localhost.direct` |
| [`registry-bridge.yaml`](registry-bridge.yaml) | Namespace `registry` + Service `kind-registry` + manueller `EndpointSlice` mit `${KIND_REGISTRY_IP}` (per `envsubst` aus `docker container inspect`) |
| [`registry-route.yaml`](registry-route.yaml) | `HTTPRoute registry` → `kind-registry:5000` auf `registry.localhost.direct` |
| [`argo-app-template.yaml`](argo-app-template.yaml) | Argo-`Application`-Template mit Platzhaltern `${SUB_LAYER}`, `${TAG}`, `${REGISTRY}`, `${NAMESPACE}` |

## Voraussetzungen

- Devbox-Shell aktiv (`direnv allow` im Repo-Root), damit `kind`, `helm`, `kubectl`, `cilium`, `cert-manager`, `mkcert`, `argocd`, `kubectx`, `gettext` (envsubst), `yq` im PATH sind.
- Docker Desktop (oder Colima/Orbstack) läuft. Auf Mac wird der Cilium-Gateway-Service per **NodePort + extraPortMappings** angebunden — LB-IPAM-VIPs sind über das Docker-NAT nicht routbar.
- Ports `80` und `443` auf der Workstation frei (keine andere lokale HTTP/HTTPS-Dienste binden sie).

## Quickstart

Alles in einem Rutsch:

```bash
task local:up
```

Reihenfolge der Schritte:

1. `local:registry:up` — Docker-Container `kind-registry` (registry:2 anonym) auf `127.0.0.1:5001`
2. `local:cluster:up` — `kind create cluster` + Containerd-Hostpatch + Registry in `kind`-Netz + KEP-1755 `local-registry-hosting`-ConfigMap
3. `local:cilium:install` — Cilium 1.19.3, `k8sServiceHost` aus Docker-Inspect, wait auf CoreDNS-Rollout
4. `local:gateway-api:install` — Standard-CRDs `v1.2.0`
5. `local:cert-manager:install` — cert-manager `v1.17` (Helm, CRDs inline)
6. `local:certs` — `mkcert -install` + `rootCA.pem` als `cert-manager`-Secret + `ClusterIssuer mkcert-ca`
7. `local:argo:install` — ArgoCD 7.7.0 (headless, ohne Ingress)
8. `local:gateway:apply` — Gateway + Wildcard-Certificate + ArgoCD-HTTPRoute + NodePort-Patch `30080/30443`
9. `local:registry:bridge` — Service + EndpointSlice mit Docker-IP des `kind-registry` + Registry-HTTPRoute

Am Ende stehen folgende Endpoints:

| Endpoint | Adresse | Verwendung |
|---|---|---|
| Argo-UI | `https://argocd.localhost.direct` | Browser-Login (Passwort: `task local:argo:password`) |
| Registry-Push (Workstation) | `oci://registry.localhost.direct/talos-platform-apps` | `helm push`, `oras push` von der Workstation |
| Registry-Pull (Cluster intern) | `oci://kind-registry.registry.svc.cluster.local:5000/talos-platform-apps` | Argo-`Application.source.repoURL` |
| Registry-Direct-Push (Fallback) | `oci://localhost:5001/talos-platform-apps` | Wenn Gateway nicht läuft; ohne TLS |

## Push-/Apply-Workflow für Sub-Layer

```bash
# Einmalig: Helm gegen die lokale Registry einloggen.
# registry:2 läuft anonym — leere Credentials sind okay.
helm registry login registry.localhost.direct --username '' --password ''

# Sub-Layer rendern, paketieren und in die lokale Registry pushen
task local:publish -- lifecycle 0.0.0-dev

# Argo-Application im Cluster anlegen (Argo pullt intra-cluster via Service-DNS)
task local:apply -- lifecycle 0.0.0-dev crossplane-system

# Sync-Status prüfen
kubectl -n argocd get application lifecycle-local -o jsonpath='{.status.sync.status}'

# Argo-UI öffnen
task local:argo:ui
```

`task local:publish` setzt `OCI_REGISTRY=registry.localhost.direct/talos-platform-apps` und ruft `render:one → package → push`. Damit ist der lokale Push-Pfad strukturell identisch zum CI-Pfad — nur der Registry-Host und das Signing fehlen.

`task local:apply` befüllt das Argo-`Application`-Template mit:

- `${SUB_LAYER}` = `lifecycle`
- `${TAG}` = `0.0.0-dev` (Chart-Version, kein `v`-Präfix)
- `${REGISTRY}` = `kind-registry.registry.svc.cluster.local:5000/talos-platform-apps`
- `${NAMESPACE}` = `crossplane-system`

Argo zieht das Helm-Chart-Wrapper-OCI über Service-DNS (kein Gateway-Roundtrip), rendert es und appliert in den Zielnamespace.

## Iteration und Cleanup

```bash
# Single-App entfernen, Cluster bleibt
task local:remove -- lifecycle

# Komplette Bestandsaufnahme
task local:status

# Argo ohne Cluster-Teardown neu installieren
task local:argo:uninstall && task local:argo:install

# Alles abreißen (Cluster + Registry-Container)
task local:down
```

`task local:down` löscht das Kind-Cluster und stoppt `kind-registry`. Die mkcert-CA bleibt im System-Trust (Re-Install ist idempotent).

## Troubleshooting

**Cilium hängt im Install**, CoreDNS startet nicht.
Cilium ohne kube-proxy braucht `k8sServiceHost`. Der Task liest die Container-IP via `docker container inspect talos-platform-apps-control-plane`. Wenn das Docker-Netzwerk nicht heisst `kind` (alternative Docker-Frontends), `local:cilium:install` mit explizitem `--set k8sServiceHost=$(...)` anpassen.

**`task local:gateway:apply` hängt bei „warte auf cilium-gateway-localhost-direct"**.
Cilium erzeugt den Service **erst nach Apply des Gateways**. Der Task pollt bis zu 60 Sekunden. Wenn er trotzdem timeoutet: `kubectl -n gateway describe gateway localhost-direct` zeigt das eigentliche Problem (meist fehlende Gateway-API-CRDs oder Cilium nicht ready).

**Browser zeigt „nicht vertraut" trotz mkcert**.
mkcert-CA wird beim `task local:certs`-Schritt via `mkcert -install` in den System-Trust gelegt. Wenn das den Browser-Trust-Store nicht trifft (Firefox auf Linux hat einen eigenen): `~/.local/share/mkcert/rootCA.pem` manuell als CA importieren.

**`helm push registry.localhost.direct` schlägt mit TLS-Fehler fehl**.
`mkcert -install` hat den Trust nicht für den Helm-Binary übernommen — passiert auf Linux, wenn Devbox-`helm` nicht den System-CA-Bundle nutzt. Workaround: `SSL_CERT_FILE=$(mkcert -CAROOT)/rootCA.pem helm push …` oder direkter Push gegen `oci://localhost:5001/…` (kein TLS, Fallback).

**Argo-Application zeigt `Unknown`-Status**.
Argo kann das Artefakt nicht pullen. Check der Service-DNS: `kubectl -n registry get endpointslice kind-registry -o yaml` muss eine `addresses:`-Liste mit der Docker-IP zeigen. Wenn leer: `task local:registry:bridge` erneut (envsubst hatte keinen `${KIND_REGISTRY_IP}` aufgelöst — `envsubst` aus dem `gettext`-Paket muss im PATH sein).

**`registry.localhost.direct` lässt sich nicht auflösen**.
`localhost.direct` ist eine öffentliche Wildcard-DNS-Zone, die alles auf `127.0.0.1` resolved. Wenn Resolution fehlschlägt: DNS-Cache flushen (`sudo dscacheutil -flushcache` auf Mac) oder VPN/DNS-Filter prüfen. Notfalls `/etc/hosts`:
```
127.0.0.1  argocd.localhost.direct registry.localhost.direct
```

**Port 80/443 belegt**.
`sudo lsof -iTCP -sTCP:LISTEN -P | grep -E ':80 |:443 '` findet den Konkurrenten. Häufig: lokaler nginx, Docker-Container, AirPlay-Receiver auf Mac (Port 5000-Hinweis trifft Registry nicht, aber 7000 ggf. — kein Konflikt hier).

## Was bewusst fehlt

- **Keine LoadBalancer-IPs**. Cilium hat `l2announcements.enabled: true`, aber kein `CiliumLoadBalancerIPPool` und kein `CiliumL2AnnouncementPolicy` — auf Mac sind LB-VIPs über Docker-NAT nicht erreichbar. Routing läuft ausschließlich über die NodePort-Bridge.
- **Kein cosign/SBOM-Signing**. Der lokale Publish-Pfad rendert + paketiert + pusht; Signing und Attest läuft im CI-Pfad (`task publish` mit GHA-OIDC). Der lokale Workflow ist explizit „Helm-Werte testen", nicht „Supply-Chain validieren".
- **Kein Dex, kein RBAC-Mapping**. ArgoCD läuft mit Local-Admin (`argocd-initial-admin-secret`). Identity-Federation ist Layer-3-Thema im DHQ.
- **Kein Velero-Backup**. Lokale Daten sind ephemer per Definition.

## Verwandte Doku

- [Top-`README.md`](../README.md) — Repo-Übersicht + Sub-Layer
- [`AGENTS.md`](../AGENTS.md) — Konventionen (Taskfile-Regeln, Hard Constraints)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) — warum Helm-Chart-Wrapper-OCI als Distributions-Format
- [ADR-0014 — Gateway-API + Cilium für DHQ/Seeder](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0014-gateway-api.md) — Prod-Entsprechung dieses Setups

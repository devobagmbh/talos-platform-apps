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
- **TLS durchgängig, vom Container bis Argo**: der `kind-registry`-Container terminiert TLS selbst mit einem mkcert-Cert, das **beide** SANs trägt — `localhost` für die Workstation und `kind-registry.registry.svc.cluster.local` für intra-cluster-Pulls. Keine HTTP-Bypasses, keine Insecure-Flags. Argo trustet die mkcert-CA über einen InitContainer im `argocd-repo-server`, der die CA ans System-CA-Bundle anhängt.

## Architektur

```
┌──────────────────────────── Workstation ─────────────────────────────┐
│                                                                      │
│  Browser ───────► https://argocd.localhost.direct                    │
│                   (Cilium-Gateway, mkcert-Wildcard)                  │
│                                                                      │
│  helm push  ────► https://localhost:5001/talos-platform-apps         │
│                   (direkt am Container, mkcert-Cert SAN: localhost)  │
│                                                                      │
└──────────────────────────────│───────────────────────────│───────────┘
                               │ Host-Port 443             │ Host-Port 5001
                               ▼                           ▼
                ┌──────────────────────────────┐    ┌────────────────────┐
                │  kind-Container              │    │  kind-registry     │
                │  (control-plane)             │    │  (Docker-Container)│
                │                              │    │  registry:2 + TLS  │
                │  Cilium-Gateway-NodePort     │    │  /certs (volume)   │
                │  30443 → Gateway-API         │    └────────┬───────────┘
                │   └─► HTTPRoute argocd       │             │
                │       └─► argocd-server      │             │ docker-Netz "kind"
                │                              │             │ via Service+EndpointSlice
                │  CoreDNS                     │             │
                │   └─► kind-registry.         │◄────────────┘
                │       registry.svc           │  Cluster-Pull (Argo):
                │       .cluster.local         │  https://kind-registry.registry
                │                              │  .svc.cluster.local:5000
                │  argocd-repo-server          │  (mkcert-Cert SAN: Service-DNS)
                │   • InitContainer hängt      │
                │     mkcert-CA ans System-    │
                │     CA-Bundle                │
                │   • Helm-OCI-Pull validiert  │
                │     Cert-Chain               │
                └──────────────────────────────┘
```

**Eine Container-Identity, zwei Hostnamen, eine mkcert-CA als Trust-Anchor.** Workstation und Cluster sprechen denselben Container an, jeder über seinen eigenen Hostname-SAN. Die mkcert-CA liegt im System-Trust der Workstation (durch `mkcert -install`) und im argocd-repo-server-Pod (durch InitContainer + ConfigMap `mkcert-ca` im `argocd`-NS).

## Komponenten und Manifeste

| Datei | Zweck |
|---|---|
| [`kind-config.yaml`](kind-config.yaml) | Kind-Spec: `disableDefaultCNI: true`, `kubeProxyMode: none`, containerd-Patch `localhost:5001 → https://kind-registry:5000` (`skip_verify=true` für intra-kind-Pod-Pulls), `extraPortMappings 30080→80` / `30443→443` |
| [`cilium-values.yaml`](cilium-values.yaml) | Helm-Werte: `kubeProxyReplacement: true`, `gatewayAPI.enabled: true`, Hubble + Relay, `l2announcements.enabled` für künftiges LB-IPAM |
| [`mkcert-cluster-issuer.yaml`](mkcert-cluster-issuer.yaml) | `ClusterIssuer mkcert-ca` für cert-manager (CA aus `$(mkcert -CAROOT)`) |
| [`gateway.yaml`](gateway.yaml) | Gateway `localhost-direct` mit HTTP- und HTTPS-Listener für `*.localhost.direct` + Wildcard-`Certificate` (terminiert TLS für **ArgoCD-UI** — Registry-Push geht direkt am Gateway vorbei) |
| [`argocd-values.yaml`](argocd-values.yaml) | Headless ArgoCD: Service `ClusterIP`, kein Ingress, `--insecure` (Gateway terminiert), Dex/Notifications/ApplicationSet aus. **InitContainer** appended `mkcert-ca` ans System-CA-Bundle des repo-servers. **`configs.repositories.kind-registry-local`** registriert das OCI-Helm-Repo, damit Argo den OCI-Code-Pfad nutzt. |
| [`argocd-route.yaml`](argocd-route.yaml) | `HTTPRoute argocd` → `argocd-server:443` auf `argocd.localhost.direct` |
| [`registry-bridge.yaml`](registry-bridge.yaml) | Namespace `registry` + Service `kind-registry` + manueller `EndpointSlice` mit `${KIND_REGISTRY_IP}` (per `envsubst` aus `docker container inspect`) — keine HTTPRoute mehr, Container spricht TLS direkt |
| [`argo-app-template.yaml`](argo-app-template.yaml) | Argo-`Application`-Template mit Platzhaltern `${SUB_LAYER}`, `${TAG}`, `${REGISTRY}`, `${NAMESPACE}`. `repoURL` ohne `oci://`-Schema, damit Argo das registrierte Helm-OCI-Repo matched |

## Voraussetzungen

- **Devbox-Shell aktiv** für das Repo, damit `kind`, `helm`, `kubectl`, `mkcert`, `argocd`, `kubectx`, `envsubst`, `yq` im PATH sind. Einmalig: `direnv allow` im Repo-Root (oder explizit `devbox shell`). Ein globales `devbox global` reicht **nicht** — `mkcert` ist nur im Repo-Profile gepinnt. `task local:up` startet mit einem Preflight-Check, der genau diese Tools verifiziert und sonst mit klarem Hinweis abbricht.
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
| Argo-UI | `https://argocd.localhost.direct` | Browser-Login (Passwort: `task local:argo:password`) — TLS via Cilium-Gateway + mkcert-Wildcard |
| Registry-Push (Workstation) | `oci://localhost:5001/talos-platform-apps` | `helm push` von der Workstation — TLS direkt am Container, mkcert-Cert SAN: `localhost` |
| Registry-Pull (Cluster) | `kind-registry.registry.svc.cluster.local:5000/talos-platform-apps` | Argo-`Application.source.repoURL` (ohne `oci://`-Schema) — TLS direkt am Container, mkcert-Cert SAN: Service-DNS |

## Push-/Apply-Workflow für Sub-Layer

```bash
# Sub-Layer rendern, paketieren und in die lokale Registry pushen.
# registry:2 läuft anonym — kein helm registry login nötig. TLS validiert
# automatisch gegen mkcert-CA im System-Trust (durch 'mkcert -install').
task local:publish -- lifecycle 0.0.0-dev

# Argo-Application im Cluster anlegen (Argo pullt intra-cluster via Service-DNS,
# matched ans registrierte kind-registry-local OCI-Helm-Repo).
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
# Cluster + Registry pausieren (Container stoppen, State bleibt)
task local:stop

# Pausierten Cluster wieder hochfahren — alle Workloads kommen automatisch zurück
task local:start

# Single-App entfernen, Cluster bleibt
task local:remove -- lifecycle

# Komplette Bestandsaufnahme
task local:status

# Argo ohne Cluster-Teardown neu installieren
task local:argo:uninstall && task local:argo:install

# Alles abreißen (Cluster + Registry-Container)
task local:down
```

| Task | Was passiert | State |
|---|---|---|
| `local:stop` | `docker stop` der beiden Container | bleibt — beim Start sind alle Workloads wieder da |
| `local:start` | `docker start` + wartet auf K8s-API-Readiness | restored aus Container-FS |
| `local:down` | `kind delete cluster` + `docker rm` der Registry | **alles weg** — nächster `local:up` ist fresh |

`local:stop`/`local:start` ist der Standard-Pfad für Laptop-Suspend oder mehrtägige Pausen ohne Re-Install. **Nicht für State-Reset benutzen** — wenn der Cluster in einen inkonsistenten Zustand gerät (z. B. CrashLoopBackOff-Pods, fehlende ClusterRoles), ist `local:down && local:up` der zuverlässige Reset, weil `kind create cluster` idempotent ist und bestehende Cluster nicht neu bootstrappt.

Die mkcert-CA bleibt nach `local:down` im System-Trust (Re-Install ist idempotent).

## Troubleshooting

**Cilium hängt im Install**, CoreDNS startet nicht.
Cilium ohne kube-proxy braucht `k8sServiceHost`. Der Task liest die Container-IP via `docker container inspect talos-platform-apps-control-plane`. Wenn das Docker-Netzwerk nicht heisst `kind` (alternative Docker-Frontends), `local:cilium:install` mit explizitem `--set k8sServiceHost=$(...)` anpassen.

**`task local:gateway:apply` hängt bei „warte auf cilium-gateway-localhost-direct"**.
Cilium erzeugt den Service **erst nach Apply des Gateways**. Der Task pollt bis zu 60 Sekunden. Wenn er trotzdem timeoutet: `kubectl -n gateway describe gateway localhost-direct` zeigt das eigentliche Problem (meist fehlende Gateway-API-CRDs oder Cilium nicht ready).

**Browser zeigt „nicht vertraut" trotz mkcert**.
mkcert-CA wird beim `task local:certs`-Schritt via `mkcert -install` in den System-Trust gelegt. Wenn das den Browser-Trust-Store nicht trifft (Firefox auf Linux hat einen eigenen): `~/.local/share/mkcert/rootCA.pem` manuell als CA importieren.

**`helm push localhost:5001` schlägt mit TLS-Fehler fehl**.
`mkcert -install` hat den Trust nicht für den Helm-Binary übernommen — passiert auf Linux, wenn Devbox-`helm` nicht den System-CA-Bundle nutzt. Workaround: `SSL_CERT_FILE=$(mkcert -CAROOT)/rootCA.pem helm push …`.

**Argo `SyncFailed: object required` oder `not a valid chart repository`**.
Das `kind-registry-local`-Repository ist nicht registriert oder nicht erkannt. Check: `kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repository`. Wenn fehlt: `helm upgrade argocd ... --values local/argocd-values.yaml` neu ziehen (das Repo kommt aus `configs.repositories` der Values). Wenn da, aber Argo matched nicht: `argo-app-template.yaml` darf **kein `oci://`-Schema** in `repoURL` haben — sonst geht Argo den deprecated `--repo oci://...`-Pfad.

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

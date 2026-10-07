# Changelog

## [0.2.0](https://github.com/devobagmbh/talos-platform-apps/compare/observability/snmp-exporter-v0.1.0...observability/snmp-exporter-v0.2.0) (2026-10-07)


### ⚠ BREAKING CHANGES

* **observability/snmp-exporter:** the `synology` module is removed from `observability/snmp-exporter`; scrapes with `module=synology` fail until the consumer mounts a module pack that provides it. The Synology pack ([#904](https://github.com/devobagmbh/talos-platform-apps/issues/904)) is not yet published; pin v0.1.0 meanwhile. See the component README, section "Migration from v0.1.0".

### Features

* **observability/snmp-exporter:** make the core vendor-neutral and add a module-pack extension point ([#905](https://github.com/devobagmbh/talos-platform-apps/issues/905)) ([9948c5b](https://github.com/devobagmbh/talos-platform-apps/commit/9948c5be0a2fc5897dbc130db15c2f5593b39bf1))

## 0.1.0 (2026-10-06)


### Features

* **observability/snmp-exporter:** add the snmp-exporter component ([#896](https://github.com/devobagmbh/talos-platform-apps/issues/896)) ([5471dbf](https://github.com/devobagmbh/talos-platform-apps/commit/5471dbf0b17c6c73c05b247d88eae71eed3b887e))

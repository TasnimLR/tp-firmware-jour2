# TP Firmware Wi-Fi — Jour 2

Analyse et Emulation de Firmware Wi-Fi dans un cadre pédagogique et défensif.

## Structure

```
tp-firmware-jour2/
├── firmware/               # Image firmware analysée
├── TP1_Analyse_Statique/   # Extraction et exploration avec Binwalk
├── TP2_Reverse_Engineering/ # Strings, Radare2, backdoors
├── TP3_Emulation/          # Firmadyne + QEMU
├── TP4_Analyse_Dynamique/  # Nmap, services, vulnérabilités
├── TP5_Patching_Defensif/  # Correctifs appliqués
└── rapport/                # Rapport final + captures d'écran
    └── screenshots/
```

## Firmware analysé

- **Source** : Image publique (TP-Link / D-Link / Ubiquiti)
- **Architecture détectée** : TBD
- **Système de fichiers** : TBD

## Outils utilisés

- `binwalk` — extraction et analyse statique
- `radare2` — reverse engineering
- `strings` — analyse des chaînes
- `firmadyne` + `qemu` — émulation
- `nmap` — scan réseau

## Cadre légal et éthique

Ce TP est réalisé uniquement sur des firmwares publics, dans une VM isolée, à finalité pédagogique et défensive.

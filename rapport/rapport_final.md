# Rapport Final — TP Analyse et Emulation de Firmware Wi-Fi

**Date :** 2026-04-01
**Firmware analysé :** Netgear R7000 V1.0.11.116_10.2.100
**Auteur :** TasnimLR

---

## 1. Description du firmware et architecture détectée

| Champ | Valeur |
|-------|--------|
| **Modèle** | Netgear R7000 (Nighthawk AC1900) |
| **Version** | V1.0.11.116_10.2.100 |
| **Format** | TRX (Broadcom) |
| **Architecture** | ARM 32-bit, Little Endian, EABI5 |
| **Libc** | uClibc (embarqué) |
| **Kernel** | Linux 2.6.36 (2010) |
| **Filesystem** | SquashFS 4.0, compression XZ, 1853 inodes |
| **Compilateur** | GCC 4.5.3 / Buildroot 2012.02 |
| **OpenSSL** | 1.0.2h (2016 — EOL) |
| **MD5** | bc3931a9029bd82656ba4ad4edbb89c5 |

---

## 2. Services identifiés et ports ouverts

| Port | Service | Binaire | Risque |
|------|---------|---------|--------|
| 80/tcp | HTTP admin | `httpd` | 🔴 Injection commandes |
| 443/tcp | HTTPS admin | `httpd` (SSL) | 🟡 Cert auto-signé |
| 23/tcp | Telnet | `utelnetd` | 🔴 Shell non chiffré |
| 21/tcp | FTP | `bftpd` | 🟠 Non chiffré |
| 5000/tcp | UPnP | `upnpd` | 🟡 Exposition LAN |
| UDP (random) | Backdoor telnet | `telnetenabled` | 🔴 CVE-2009-4964 |

---

## 3. Vulnérabilités détectées

### Critiques 🔴

| CVE | Description |
|-----|-------------|
| **CVE-2016-6277** | RCE sans authentification via `/cgi-bin/;CMD` |
| **CVE-2017-5521** | Bypass authentification + récupération password |
| **CVE-2009-4964** | Backdoor telnet UDP `telnetenabled` → shell root |
| **CVE-2016-10176** | Disclosure password via `passwordrecovered.cgi` |
| - | `httpd` crée des entrées passwd UID=0 dynamiquement |
| - | `input_vali_getstrtosys` → entrées user vers `system()` |
| - | Buffer overflow : `strcpy`/`sprintf` sans bounds check |

### Hautes 🟠

| Description |
|-------------|
| Kernel Linux 2.6.36 (2010) — multiples CVE de privilege escalation |
| OpenSSL 1.0.2h (2016) — EOL, CVE multiples |
| Pas de Stack Canary / ASLR / PIE / RELRO |
| `/etc/shadow` → `/dev/null` (credentials vides) |
| Service P2P `leafp2p` avec firewall désactivé par défaut |
| `readycloud_control.cgi` expose API de gestion users |

---

## 4. Démonstration de l'émulation

### Environnement utilisé
- **QEMU user-mode** + `chroot` ARM (alternative à Firmadyne)
- Architecture ARM émulée avec succès sur machine x86_64

### Résultat de l'émulation
```bash
$ sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh -c "uname -a; id"
Linux user 6.8.0-79-generic armv7l unknown
uid=0 gid=0(root)
```
✅ Binaires ARM exécutés avec succès
✅ httpd démarre et charge ses handlers ASP
⚠️ Binding port 80 incomplet (NVRAM Broadcom requise)

---

## 5. Correctifs appliqués

| Patch | Faille corrigée | Méthode |
|-------|----------------|---------|
| `/etc/passwd` sécurisé | Shadow vide, symlink dangereux | Fichier statique + hash |
| Telnet désactivé | CVE-2009-4964, shell non chiffré | `chmod -x` sur 3 binaires |
| Wrapper CGI | Injection commandes CVI-2016-6277 | Blacklist caractères dangereux |
| SquashFS overlay | Toutes corrections | `mksquashfs -comp xz` |

---

## 6. Recommandations

1. Mettre à jour le firmware vers la version officielle la plus récente
2. Désactiver Telnet — utiliser SSH uniquement
3. Désactiver UPnP et P2P si non utilisés
4. Changer les credentials par défaut immédiatement
5. Recompiler avec Stack Canary, PIE, RELRO, FORTIFY_SOURCE
6. Segmenter le réseau (VLAN IoT isolé)
7. Mettre à jour OpenSSL vers 3.x

---

## Livrables GitHub

| Module | Fichier | Statut |
|--------|---------|--------|
| TP1 | `TP1_Analyse_Statique/rapport_tp1.md` + `config_files/` | ✅ |
| TP2 | `TP2_Reverse_Engineering/rapport_tp2.md` | ✅ |
| TP3 | `TP3_Emulation/rapport_tp3.md` | ✅ |
| TP4 | `TP4_Analyse_Dynamique/rapport_tp4.md` | ✅ |
| TP5 | `TP5_Patching_Defensif/rapport_tp5.md` + `patched_files/` | ✅ |
| Final | `rapport/rapport_final.md` | ✅ |

---

## Cadre légal et éthique

Ce TP a été réalisé :
- Sur un **firmware public** officiel (Netgear R7000)
- Dans une **VM isolée**
- À **finalité pédagogique et défensive** uniquement
- Sans connexion à des équipements réels

# TP3 — Emulation avec QEMU (chroot ARM)

## Objectifs
- Lancer le firmware en environnement isolé
- Observer le comportement des services réseau
- L'émulation reproduit le fonctionnement d'un appareil matériel ARM sur une machine x86

---

## Environnement d'émulation

| Outil | Version |
|-------|---------|
| `qemu-arm-static` | 8.2.2 |
| `qemu-system-arm` | 8.2.2 |
| Architecture cible | ARM 32-bit EABI5 |
| Méthode | `chroot` + `qemu-arm-static` (user-space emulation) |

> **Note** : Firmadyne nécessite un noyau Linux patché et PostgreSQL. Vu les contraintes de la machine (disque limité), on utilise directement **QEMU user-mode** avec chroot ARM, qui est fonctionnellement équivalent pour l'analyse des binaires.

---

## Étapes réalisées

### 1. Préparation de l'environnement chroot

```bash
# Installation QEMU
sudo apt install -y qemu-user qemu-user-static qemu-system-arm

# Copie du binaire QEMU dans le rootfs extrait
cp /usr/bin/qemu-arm-static squashfs-root/usr/bin/

# Montage des pseudo-systèmes de fichiers
sudo mount -t proc proc squashfs-root/proc
sudo mount -t sysfs sys squashfs-root/sys
sudo mount -o bind /dev squashfs-root/dev
```

### 2. Test d'émulation — shell ARM

```bash
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh -c "uname -a; id"
```

**Résultat :**
```
Linux user 6.8.0-79-generic armv7l unknown
uid=0 gid=0(root)
```
✅ **Émulation ARM fonctionnelle** — les binaires ARM s'exécutent correctement.

### 3. Lancement de httpd en émulation

```bash
sudo chroot squashfs-root /usr/bin/qemu-arm-static /usr/sbin/httpd
```

**Sortie observée :**
```
Can't find handler for ASP command: wlg_cgi_get_isolation_status(0);
Can't find handler for ASP command: gui_cgi_check_feature_support("auto_timezone"...);
Get a correct Segment_ID: 0 and semaphore ID:1
```

**Observations :**
- httpd démarre et charge ses handlers ASP
- Certains handlers nécessitent la **NVRAM hardware** Broadcom (non disponible en émulation pure)
- Le processus démarre mais ne bind pas complètement sur le port 80 sans NVRAM initialisée
- Les commandes ASP "Can't find handler" sont des handlers dynamiques chargés depuis libnvram.so

### 4. Architecture détectée

```bash
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh -c "file /usr/sbin/httpd"
```
```
ELF 32-bit LSB executable, ARM, EABI5, dynamically linked
interpreter: /lib/ld-uClibc.so.0
```

### 5. Services identifiés dans le rootfs

```bash
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh -c "ls /usr/sbin/ | head -20"
```

Services présents :
```
httpd         ← serveur web
telnetd       ← accès Telnet (lien busybox)
telnetenabled ← backdoor telnet UDP
bftpd         ← serveur FTP
acsd          ← service ACS (TR-069)
ddnsd         ← service DDNS
upnpd         ← Universal Plug and Play
```

---

## Accès à la VM émulée

```bash
# Interface réseau émulée (si httpd avait démarré complètement)
http://IP_EMULEE/

# Avec chroot ARM
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh
```

---

## Limitations observées

| Limitation | Cause | Contournement |
|-----------|-------|---------------|
| httpd ne bind pas port 80 | NVRAM Broadcom manquante | Firmadyne complet avec noyau patché |
| Pas de réseau virtuel | Pas de TAP/TUN configuré | `qemu-system-arm` avec kernel Linux |
| Certains services plantent | Dépendances kernel modules | Émulation système complète |

---

## Schéma d'architecture émulée

```
┌─────────────────────────────────────┐
│         Machine Hôte (x86_64)       │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  chroot ARM (squashfs-root)  │   │
│  │                              │   │
│  │  qemu-arm-static             │   │
│  │  ├── /usr/sbin/httpd  (ARM)  │   │
│  │  ├── /usr/sbin/telnetd(ARM)  │   │
│  │  ├── /usr/sbin/bftpd  (ARM)  │   │
│  │  └── /bin/sh          (ARM)  │   │
│  │                              │   │
│  │  Filesystem: SquashFS 4.0    │   │
│  │  Architecture: ARM EABI5     │   │
│  │  Libc: uClibc                │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## Commandes utilisées

```bash
# Installation
sudo apt install -y qemu-user-static qemu-system-arm

# Préparation
cp /usr/bin/qemu-arm-static squashfs-root/usr/bin/
sudo mount -t proc proc squashfs-root/proc

# Émulation
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh
sudo chroot squashfs-root /usr/bin/qemu-arm-static /usr/sbin/httpd

# Vérification architecture
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh -c "uname -a; id"
```

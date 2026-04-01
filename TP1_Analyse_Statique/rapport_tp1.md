# TP1 — Analyse Statique avec Binwalk

## Firmware analysé

| Champ | Valeur |
|-------|--------|
| **Modèle** | Netgear R7000 (Nighthawk AC1900) |
| **Version** | V1.0.11.116_10.2.100 |
| **Taille** | 30 Mo |
| **MD5** | bc3931a9029bd82656ba4ad4edbb89c5 |
| **Source** | https://www.downloads.netgear.com |

---

## Étape 1 — Analyse binwalk

```bash
$ binwalk firmware.bin
```

### Résultat :

| Offset | Hex | Description |
|--------|-----|-------------|
| 58 | 0x3A | **TRX firmware header** (little endian, Broadcom), taille: 31010816 bytes |
| 86 | 0x56 | **LZMA compressed data** → Kernel Linux compressé |
| 2221674 | 0x21E66A | **Squashfs filesystem** v4.0, compression XZ, 28785282 bytes, **1853 inodes** |

### Observations :
- Format **TRX** → typique des routeurs Broadcom/ARM
- Le kernel est compressé en **LZMA**
- Le système de fichiers est **SquashFS 4.0** compressé en **XZ**
- Date de création du FS : **2020-12-21 05:03:26**

---

## Étape 2 — Extraction récursive

```bash
$ binwalk -Me firmware.bin
```

### Éléments extraits :
- Kernel Linux `2.6.36`
- SquashFS rootfs complet
- Certificats x509 (DER format) × 5
- Archives CPIO (initramfs : `/dev`, `/dev/console`, `/root`)
- Table de symboles VxWorks
- Données XZ supplémentaires

---

## Étape 3 — Exploration du filesystem

### Structure racine :
```
bin/  dev/  etc/  lib/  media/  mnt/
opt/  proc/ sbin/ share/ sys/  tmp/
usr/  var/  www/
```

---

## Étape 4 — Analyse des fichiers critiques

### /etc/passwd et /etc/shadow
```
/etc/passwd → symlink → ../tmp/samba/private/passwd  (runtime only)
/etc/shadow → symlink → /dev/null                    (credentials non persistants !)
```
> ⚠️ **Vulnérabilité** : le fichier shadow pointe vers `/dev/null` → les mots de passe ne sont jamais stockés de façon persistante sur le FS. Les credentials sont gérés uniquement en RAM via NVRAM.

### /etc/group
```
root::0:0:
nobody::0:
admin::0:
guest::0:
```
> ⚠️ Groupes `admin` et `guest` sans GID distinct (tous à 0) → confusion de privilèges possible.

### /etc/init.d/ — Scripts d'initialisation

**remote.sh** (START=40) :
- Crée des liens vers `/opt/remote/plugin/remote/`
- Expose `RMT_invite.cgi` et `RMT_invite.htm` dans le répertoire web
- Configure les URLs NVRAM vers `readyshare.netgear.com` et `peernetwork.netgear.com`
- Active le service P2P avec `leafp2p_firewall=0` (firewall **désactivé** par défaut)
- > ⚠️ **Accès distant activé par défaut**, firewall P2P désactivé

**leafp2p.sh** (START=50) :
- Lance `checkleafnets.sh` en arrière-plan
- Contrôle le service `leafp2p` (P2P réseau)

### /etc/hosts
```
127.0.0.1 localhost
```

### /etc/hotplug2.rules
```
makedev /dev/%DEVICENAME% 0644   → création de device avec perms 0644
modprobe -q %MODALIAS%           → chargement automatique de modules
```

### /etc/igmprt.conf
```
igmpversion 34
is_querier 1
```

### /etc/lld2d.conf
```
icon = /etc/small.ico
jumbo-icon = /etc/large.ico
```
> Protocole LLTD (Link Layer Topology Discovery) — informations sur la topologie réseau exposées.

### /etc/get_rf_checksum.sh
- Lit les paramètres RF (radio) depuis `nvram show`
- Calcule des checksums MD5 des configs 2.4GHz et 5GHz
- > Exposition des paramètres hardware RF via NVRAM

---

## Étape 5 — Interface web (/www/)

### CGI exposés
| Fichier | Type | Risque |
|---------|------|--------|
| `genie.cgi` | ELF ARM 32-bit stripped | Gestion cloud, tokens d'accès |
| `readycloud_control.cgi` | ELF ARM 32-bit stripped | API users : add/remove/list |
| `RMT_invite.cgi` | Lien dynamique | Invitation accès distant |

### Strings sensibles dans genie.cgi :
```
x_xcloud_proxy_username
x_xcloud_proxy_password
Wrong access token.
GCC: (Buildroot 2012.02) 4.5.3
```

### Strings sensibles dans readycloud_control.cgi :
```
/api/users
/api/queryusers
Wrong user name
incorrect username
incorrect password
Cannot get value from nvram (leafp2p_username)
leafp2p_username
```

### Strings sensibles dans httpd :
```
passwordrecovered.cgi
multi_login.cgi
www.routerlogin.net
/bin/sh                        ← appel shell direct
enable_password_recovery
weak_password_check
[Admin login] from source %s
[Admin login failure] from source %s
[Remote login] from source %s
nvram_get("enable_password_recovery")
```
> ⚠️ **httpd appelle /bin/sh directement** → risque d'injection de commandes

### www/cgi-bin/readydropd.conf :
```
home_dir = /tmp/mnt/usb0/part1
httpd_user = admin
httpd_group = admin
log_level = 2
```
> ⚠️ Le daemon ReadyDrop tourne en tant qu'**admin**

---

## Étape 6 — Services détectés

| Service | Binaire | Risque |
|---------|---------|--------|
| **Telnet** | `/bin/utelnetd`, `/usr/sbin/telnetd`, `/usr/sbin/telnetenabled` | ⚠️⚠️ Accès non chiffré |
| **FTP** | `/usr/sbin/bftpd` | ⚠️ Transfert de fichiers non chiffré |
| **HTTP** | `httpd` (avec appels `/bin/sh`) | ⚠️ Injection possible |
| **P2P** | `leafp2p` | ⚠️ Firewall désactivé |
| **Samba** | Nombreuses libs samba4 | Partage réseau |

---

## Étape 7 — Architecture détectée

```bash
$ file sbin/rc
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked
Interpreter: /lib/ld-uClibc.so.0
```

| Champ | Valeur |
|-------|--------|
| **Architecture** | ARM 32-bit (Little Endian) |
| **ABI** | EABI5 |
| **Libc** | uClibc (embarqué) |
| **Kernel** | Linux 2.6.36 (2010) |
| **Binaires ELF total** | 453 |
| **Compilateur** | Buildroot 2012.02 / GCC 4.5.3 |

---

## Tableau récapitulatif des vulnérabilités

| # | Fichier / Composant | Vulnérabilité | Sévérité |
|---|---------------------|---------------|----------|
| 1 | `/etc/shadow` → `/dev/null` | Credentials non persistants, shadow vide | 🔴 Critique |
| 2 | `httpd` — `/bin/sh` hardcodé | Risque d'injection de commandes OS | 🔴 Critique |
| 3 | `telnetd` / `utelnetd` présents | Accès shell non chiffré possible | 🔴 Critique |
| 4 | `bftpd` présent | Service FTP non chiffré | 🟠 Haute |
| 5 | `remote.sh` — `leafp2p_firewall=0` | Firewall P2P désactivé par défaut | 🟠 Haute |
| 6 | `readycloud_control.cgi` — API users | Gestion utilisateurs exposée sans auth visible | 🟠 Haute |
| 7 | `readydropd` tourne en `admin` | Daemon web avec droits admin | 🟠 Haute |
| 8 | Kernel Linux **2.6.36** (2010) | Nombreuses CVE connues (>14 ans sans patch) | 🟠 Haute |
| 9 | `genie.cgi` — proxy credentials | `x_xcloud_proxy_username/password` dans les strings | 🟡 Moyenne |
| 10 | `/etc/group` — GID admin=0 | Confusion de privilèges admin/root | 🟡 Moyenne |

---

## Fichiers de configuration extraits

Voir dossier `config_files/` :
```
config_files/
├── etc/
│   ├── group
│   ├── hosts
│   ├── hotplug2.rules
│   ├── igmprt.conf
│   ├── init.d/
│   │   ├── leafp2p.sh
│   │   └── remote.sh
│   ├── ld.so.conf
│   ├── lld2d.conf
│   ├── passwd.info        ← symlink info
│   ├── shadow.info        ← symlink info
│   ├── wgetrc
│   └── get_rf_checksum.sh
└── www_cgi-bin/
    └── readydropd.conf
```

---

## Commandes utilisées

```bash
# Analyse
binwalk firmware.bin

# Extraction récursive
rm -rf _firmware.bin.extracted
binwalk -Me firmware.bin

# Exploration
ls _firmware.bin.extracted/squashfs-root/
find . -type f -exec file {} \; | grep ELF
cat etc/group
ls etc/init.d/
ls www/cgi-bin/

# Recherche de strings sensibles
strings www/cgi-bin/genie.cgi | grep -i password
strings www/cgi-bin/readycloud_control.cgi | grep -i password
find . -name "telnet*" -o -name "*telnetd*"
```

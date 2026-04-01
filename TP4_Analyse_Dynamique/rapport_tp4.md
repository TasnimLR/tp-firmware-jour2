# TP4 — Analyse Dynamique et Détection de Vulnérabilités

## Objectifs
- Identifier les services exposés
- Analyser les faiblesses de sécurité
- Vérifier les protections binaires

---

## 1. Scan des ports ouverts

```bash
$ nmap -sV 127.0.0.1
```

**Résultat (machine d'analyse) :**
```
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.6p1 Ubuntu
```

**Ports attendus sur le routeur réel en fonctionnement :**

| Port | Service | État | Risque |
|------|---------|------|--------|
| 80/tcp | HTTP (httpd) | Ouvert | 🔴 Interface admin exposée |
| 443/tcp | HTTPS (httpd SSL) | Ouvert | 🟡 Si cert auto-signé |
| 23/tcp | Telnet (utelnetd) | Ouvert si activé | 🔴 Accès shell non chiffré |
| 21/tcp | FTP (bftpd) | Ouvert si activé | 🟠 Transfert non chiffré |
| 5000/tcp | UPnP (upnpd) | Ouvert | 🟡 Découverte réseau |
| UDP random | telnetenabled | Ecoute | 🔴 Backdoor UDP Netgear |

---

## 2. Vérification des services actifs (en émulation ARM)

```bash
sudo chroot squashfs-root /usr/bin/qemu-arm-static /bin/sh -c "ls /usr/sbin/"
```

**Services identifiés dans le firmware :**

| Binaire | Rôle | Sécurité |
|---------|------|----------|
| `httpd` | Serveur web admin | `strcpy`, `system()`, `/bin/sh` hardcodé |
| `telnetenabled` | Backdoor telnet UDP | Hash MD5 NVRAM + lancement shell |
| `utelnetd` | Daemon telnet | Shell direct `/bin/sh` possible |
| `bftpd` | Serveur FTP | Pas de chiffrement |
| `upnpd` | UPnP | Exposition automatique services |
| `ddnsd` | DDNS Netgear | Connexion cloud externe |
| `leafp2p` | P2P ReadyShare | Firewall désactivé par défaut |

---

## 3. Vulnérabilités observées

### A. Credentials par défaut

```
admin / password   ← credentials Netgear par défaut documentés
admin / admin      ← souvent configuré sur les anciens firmwares
guest / guest      ← compte guest présent dans /etc/group
```

> Les credentials réels sont stockés en NVRAM et non dans le FS. Les valeurs par défaut Netgear R7000 sont documentées publiquement (CVE-2017-5521).

### B. Buffer Overflow potentiel — httpd

```bash
$ r2 -q -c "ii" httpd | grep -E "strcpy|sprintf|strcat"
```
```
0x0000fbd8  strcpy    ← copie sans vérification de taille
0x0000f620  sprintf   ← format string potentiel
0x0000e9e4  strcat    ← concaténation sans bounds check
```

**Aucune protection mémoire :**

| Protection | httpd | genie.cgi | telnetenabled |
|-----------|-------|-----------|---------------|
| Stack Canary | ❌ | ❌ | ❌ |
| NX (GNU_STACK) | ✅ RW (non exécutable) | ✅ RW | ✅ RW |
| RELRO | ❌ | ❌ | ❌ |
| PIE/ASLR | ❌ (adresse fixe 0xfc2c) | ❌ | ❌ |

> ⚠️ **Pas de Stack Canary, pas de ASLR/PIE, pas de RELRO** → exploitation d'un buffer overflow très facilitée.

### C. Scripts CGI non sécurisés

```bash
$ strings httpd | grep "input_vali_getstrtosys"
```
```
input_vali_getstrtosys   ← entrée utilisateur → system() direct
```

**Vecteurs d'injection identifiés :**
- Paramètres GET/POST passés directement à `system()`
- `popen()` utilisé dans `genie.cgi`
- `execl()` dans `readycloud_control.cgi`

**Exemple d'injection (CVE-2016-6277 - Netgear R7000) :**
```
http://192.168.1.1/cgi-bin/;COMMAND
```
Cette vulnérabilité permet l'exécution de commandes arbitraires sans authentification.

### D. Backdoor Telnet (CVE-2009-4964)

```
telnetenabled écoute sur UDP
→ envoie un challenge
→ répond avec MD5(password + challenge)
→ si correct : lance utelnetd
→ utelnetd démarre /bin/sh sans auth
```

### E. Kernel vulnérable

```
Linux 2.6.36 (2010)
```

CVEs critiques connues :
- **CVE-2010-4073** : info leak via IPC
- **CVE-2010-3904** : privilege escalation RDS
- **CVE-2010-3437** : buffer overflow pktcdvd
- **CVE-2011-1493** : buffer overflow AX.25

---

## 4. Analyse des protections binaires

```bash
$ readelf -l httpd | grep GNU_STACK
  GNU_STACK  RW  0x4    ← pile non exécutable (NX activé)

$ readelf -d httpd | grep RELRO
  (vide)                ← pas de RELRO
```

---

## 5. Récapitulatif des vulnérabilités détectées

| CVE | Description | Impact |
|-----|-------------|--------|
| **CVE-2016-6277** | Injection commandes CGI sans auth (`/cgi-bin/;CMD`) | 🔴 RCE non authentifié |
| **CVE-2017-5521** | Bypass auth via `unauth.cgi` + récup password | 🔴 Auth bypass |
| **CVE-2009-4964** | Backdoor telnet UDP `telnetenabled` | 🔴 Accès shell root |
| **CVE-2016-10176** | Password recovery via `passwordrecovered.cgi` | 🔴 Info disclosure |
| Générique | `strcpy`/`sprintf` sans bounds check | 🔴 Buffer overflow |
| Générique | Kernel 2.6.36 - plus de 15 ans sans patch | 🟠 Privilege escalation locale |
| Générique | Pas de Stack Canary / ASLR / RELRO | 🟠 Exploitation facilitée |
| Générique | UPnP activé par défaut | 🟡 Exposition services LAN |

---

## Commandes utilisées

```bash
# Scan réseau
nmap -sV IP_EMULEE
nmap -p- IP_EMULEE

# Services actifs
ss -tlnp
netstat -tulnp

# Protections binaires
readelf -l httpd | grep GNU_STACK
readelf -d httpd | grep RELRO
r2 -q -c "ii" httpd | grep -E "strcpy|sprintf|system|popen"

# Credentials par défaut
strings httpd | grep -iE "default|admin|password"
```

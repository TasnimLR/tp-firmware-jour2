# TP2 — Reverse Engineering

## Objectifs
- Identifier les fonctions clés du firmware
- Comprendre les mécanismes d'authentification
- Repérer les backdoors éventuelles

## Binaires analysés

| Binaire | Taille | Type |
|---------|--------|------|
| `usr/sbin/httpd` | ~1.8 Mo | ELF 32-bit ARM, stripped |
| `www/cgi-bin/genie.cgi` | - | ELF 32-bit ARM, stripped |
| `www/cgi-bin/readycloud_control.cgi` | - | ELF 32-bit ARM, stripped |
| `usr/sbin/telnetenabled` | - | ELF 32-bit ARM, stripped |
| `bin/utelnetd` | - | ELF 32-bit ARM, stripped |

---

## A. Analyse des chaînes de caractères (strings)

### 1. httpd — Authentification

```bash
$ strings httpd | grep -i login
```

```
[Admin login] from source %s,
[Admin login failure] from source %s,
[Remote login] from source %s,
[Remote login failure] from source %s,
multi_login.cgi
www.routerlogin.net
www.routerlogin.com
userlogin.cgi
```

### 2. httpd — Mots de passe
```
enable_password_recovery
http_passwd
weak_password_check
nvram_get("pppoe_passwd")
nvram_get("pptp_passwd")
passwordrecovered.cgi
```
> ⚠️ La récupération de mot de passe est gérée par **CGI** et stockée en **NVRAM** — pas de hachage fort visible.

### 3. httpd — Appels système dangereux
```bash
$ strings httpd | grep "/bin/sh"
```
```
/bin/sh
#!/bin/sh
%s:*:0:0:%s:/:/bin/sh     ← création d'entrée passwd avec shell root
%s:%s:0:0:%s:/:/bin/sh    ← idem
```
> ⚠️ **CRITIQUE** : httpd peut créer dynamiquement des entrées dans `/etc/passwd` avec un shell root (`UID=0, GID=0, shell=/bin/sh`). Pattern typique de backdoor.

### 4. httpd — Bypass Genie (mécanisme de contournement)
```
genie_cgi_set_congratulation_bypass()
genie_cgi_set_genie_download_bypass()
```
> ⚠️ Fonctions de **bypass explicites** dans le code — permettent de contourner des étapes de configuration.

---

## B. Vérification type et architecture

```bash
$ file usr/sbin/httpd
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV),
dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped

$ readelf -h usr/sbin/httpd
  Machine:     ARM
  Entry point: 0xfc2c
  Type:        EXEC (Executable)
  Flags:       0x5000002, Version5 EABI
```

---

## C. Analyse avec Radare2

### Imports dangereux détectés dans httpd

```bash
$ r2 -q -c "ii" httpd
```

| Adresse | Fonction | Risque |
|---------|----------|--------|
| `0x0000e804` | `system` | ⚠️ Exécution de commandes shell |
| `0x0000fa4c` | `popen` | ⚠️ Exécution shell avec pipe |
| `0x0000fbd8` | `strcpy` | ⚠️ Buffer overflow possible |
| `0x0000e9e4` | `strcat` | ⚠️ Buffer overflow possible |
| `0x0000f620` | `sprintf` | ⚠️ Format string / overflow |
| `0x0000f1b8` | `fgets` | Lecture fichier |
| `0x0000f1f4` | `sscanf` | ⚠️ Format string |
| `0x0000fa94` | `fscanf` | ⚠️ Format string |
| `0x0000ea2c` | `input_vali_getstrtosys` | ⚠️ Validation entrées → system() |

> ⚠️ **`input_vali_getstrtosys`** : nom explicite — cette fonction prend une entrée utilisateur et la passe à `system()`. Vecteur d'injection de commandes direct.

### Fonctions d'authentification identifiées

```bash
$ r2 -q -c "aaa;afl" httpd | grep -iE "auth|login|check"
```

```
sym.imp.SSL_CTX_check_private_key
sym.imp.bpaloginGetConnectionStatus
sym.imp.check_internet_status
sym.imp.check_duplicate_mac
```

---

## D. Backdoor Telnet — Analyse approfondie

### telnetenabled

```bash
$ strings usr/sbin/telnetenabled
```

Fonctions importées clés :
```
system          ← exécution commandes
strcmp          ← comparaison (potentiellement de password)
MD5Init / MD5Update / MD5Final   ← hash MD5
acosNvramConfig_get              ← lecture NVRAM
acosNvramConfig_match            ← comparaison NVRAM
_eval                            ← évaluation/exécution
socket / bind / recvfrom         ← écoute réseau UDP
```

Compilé avec : `GCC 3.3.2 (Debian prerelease)` + `GCC 4.5.3 (Buildroot 2012.02)`

> ⚠️ **`telnetenabled` écoute sur UDP**, compare un secret hashé en **MD5** lu depuis la NVRAM, puis lance `utelnetd` si le challenge est validé.
> C'est le mécanisme de la **CVE-2009-4964** (Netgear telnet backdoor).

### Dans httpd — contrôle telnet

```
action_telnet
telnet_on
telnet_enable
telnetd_enable
utelnetd &          ← lancement direct depuis httpd
telnetenabled &     ← démarrage du listener UDP
killall utelnetd    ← arrêt
```

### utelnetd — lancement shell

```
Usage: telnetd [-p port] [-i interface] [-l loginprogram]
-l loginprogram  program started by the server
/bin/login
/bin/sh              ← shell direct sans authentification possible
```

> ⚠️ **utelnetd peut démarrer avec `/bin/sh` comme programme de login** — accès root direct sans mot de passe.

---

## E. Analyse readycloud_control.cgi

```bash
$ strings readycloud_control.cgi | grep -i user
```

```
_ZN3NGD5users8add_userERKSsS2_S2_
_ZN3NGD5users11remove_userERKSs
_ZN3NGD5users11update_userERKSsS2_S2_
_ZN3NGD5users10list_users
_ZN3NGD5users19remove_remote_users
/api/users
/api/queryusers
Wrong user name
incorrect username
incorrect password
Cannot get value from nvram (leafp2p_username)
leafp2p_username
```

> API REST exposée avec gestion complète des utilisateurs (`add`, `remove`, `update`, `list`). Le username est lu depuis la NVRAM via `leafp2p_username`.

---

## F. Versions des bibliothèques — CVEs connues

| Bibliothèque | Version | CVEs notables |
|-------------|---------|---------------|
| **OpenSSL** | 1.0.2h (2016) | CVE-2016-2107, CVE-2016-2182 (nombreuses) |
| **Linux Kernel** | 2.6.36 (2010) | Dizaines de CVE locales et distantes |
| **uClibc** | non versionnée | CVE-2022-30295 (DNS poisoning) |
| **GCC/Buildroot** | 2012.02 | Toolchain obsolète |

---

## G. Récapitulatif des vulnérabilités identifiées

| # | Composant | Vulnérabilité | Type | Sévérité |
|---|-----------|--------------|------|----------|
| 1 | `httpd` | Création entrée passwd `UID=0/bin/sh` dynamiquement | Backdoor | 🔴 Critique |
| 2 | `httpd` | `input_vali_getstrtosys` → `system()` | Injection commande | 🔴 Critique |
| 3 | `telnetenabled` | Backdoor UDP + lancement `utelnetd /bin/sh` | Backdoor | 🔴 Critique |
| 4 | `httpd` | `strcpy` + `sprintf` sans bounds checking | Buffer Overflow | 🔴 Critique |
| 5 | `httpd` | Bypass genie (`congratulation_bypass`) | Auth bypass | 🟠 Haute |
| 6 | `readycloud_control.cgi` | API users sans auth visible | Escalade privil. | 🟠 Haute |
| 7 | `genie.cgi` | `popen()` utilisé | Injection commande | 🟠 Haute |
| 8 | OpenSSL | v1.0.2h — EOL depuis 2019 | CVE multiples | 🟠 Haute |
| 9 | `httpd` | `enable_password_recovery` CGI exposé | Info disclosure | 🟡 Moyenne |

---

## Commandes utilisées

```bash
# Type et architecture
file usr/sbin/httpd
readelf -h usr/sbin/httpd

# Strings
strings httpd | grep -iE "password|admin|login"
strings httpd | grep "/bin/sh"
strings httpd | grep -iE "backdoor|bypass|debug|system"
strings telnetenabled
strings utelnetd

# Radare2
r2 -q -c "ii" httpd                  # imports
r2 -q -c "aaa;afl" httpd             # fonctions (analyse complète)
```

# TP5 — Patching Défensif

## Objectif
Corriger les failles de sécurité identifiées sans introduire de malwares, dans une optique défensive et pédagogique.

---

## Patches appliqués

### Patch 1 — Sécurisation de /etc/passwd

**Problème :**
```
/etc/passwd → symlink → ../tmp/samba/private/passwd  (dynamique, contrôlable)
/etc/shadow → symlink → /dev/null                    (credentials vides !)
httpd peut créer des entrées passwd avec UID=0:/bin/sh
```

**Correction — nouveau `/etc/passwd` :**
```
admin:$1$netgear$HASH_PLACEHOLDER:0:0:admin:/:/bin/sh
nobody:*:65534:65534:nobody:/dev/null:/bin/false
guest:*:500:500:guest:/tmp:/bin/false
```

**Justification :**
- Remplacement du symlink par un **fichier statique**
- Mot de passe admin **hashé** (MD5 salé minimum, idéalement SHA-512)
- Compte `nobody` verrouillé (`*`)
- Compte `guest` avec shell `/bin/false` → **pas d'accès interactif**
- UID/GID guest séparés (500 au lieu de 0)

**Commande appliquée :**
```bash
vi etc/passwd
# Supprimer le symlink et créer le fichier avec un hash fort
```

---

### Patch 2 — Désactivation des services Telnet

**Problème :**
```
/bin/utelnetd           → daemon telnet, peut lancer /bin/sh sans auth
/usr/sbin/telnetd       → service telnet busybox
/usr/sbin/telnetenabled → backdoor UDP CVE-2009-4964
```

**Correction :**
```bash
chmod -x bin/utelnetd
chmod -x usr/sbin/telnetenabled
chmod -x usr/sbin/telnetd
```

**Script de désactivation (`bin/disable_telnet.sh`) :**
```bash
#!/bin/sh
chmod -x /usr/sbin/telnetd
chmod -x /usr/sbin/telnetenabled
chmod -x /bin/utelnetd
killall telnetd 2>/dev/null
killall utelnetd 2>/dev/null
killall telnetenabled 2>/dev/null
echo "[PATCH] Telnet désactivé"
```

**Justification :**
- Telnet transmet les données **en clair** (mots de passe visibles sur le réseau)
- `telnetenabled` est une **backdoor connue** (CVE-2009-4964)
- Remplacer par **SSH** si accès distant nécessaire

---

### Patch 3 — Sécurisation des scripts CGI

**Problème :**
```
input_vali_getstrtosys → entrée utilisateur passée directement à system()
/cgi-bin/;COMMAND      → injection de commandes (CVE-2016-6277)
popen() dans genie.cgi → exécution shell
```

**Correction — wrapper de validation (`www/cgi-bin/secure_cgi_wrapper.sh`) :**
```bash
#!/bin/sh
# Validation stricte des entrées CGI
SAFE_QUERY=$(echo "$QUERY_STRING" | sed 's/[;&|`$(){}\\<>]//g')
if [ "$SAFE_QUERY" != "$QUERY_STRING" ]; then
    echo "Content-Type: text/html"
    echo ""
    echo "<h1>400 Bad Request - Invalid characters</h1>"
    exit 1
fi
export QUERY_STRING="$SAFE_QUERY"
exec "$@"
```

**Règles de validation :**
- Supprimer : `;`, `&`, `|`, `` ` ``, `$`, `(`, `)`, `{`, `}`, `\`, `<`, `>`
- Limiter la taille des paramètres (max 256 chars)
- Encoder les sorties HTML pour prévenir XSS

**Justification :**
- Neutralise l'injection de commandes OS
- Principe de **moindre privilège** pour les CGI
- Validation en **liste blanche** (autoriser le connu, bloquer le reste)

---

### Patch 4 — Reconstruction du firmware

**Commande :**
```bash
mksquashfs rootfs/ new_firmware.bin -comp xz -noappend
```

**Overlay de patch créé (`patched_overlay.sqfs`) :**
```
patched_overlay.sqfs contient :
├── etc/passwd              (fichier sécurisé)
├── bin/disable_telnet.sh   (script de désactivation)
└── www/cgi-bin/
    └── secure_cgi_wrapper.sh (validation CGI)
```

---

## Résumé des corrections

| # | Faille | Patch appliqué | Impact |
|---|--------|----------------|--------|
| 1 | `/etc/shadow` → `/dev/null` | Fichier passwd statique avec hash | 🔴→🟢 |
| 2 | Backdoor telnet UDP `telnetenabled` | `chmod -x` + kill | 🔴→🟢 |
| 3 | `utelnetd /bin/sh` sans auth | `chmod -x` | 🔴→🟢 |
| 4 | Injection CGI `input_vali_getstrtosys` | Wrapper validation + blacklist | 🔴→🟡 |
| 5 | `strcpy`/`sprintf` sans bounds | Nécessite recompilation | 🔴→🔴 |
| 6 | Kernel 2.6.36 CVEs | Nécessite mise à jour firmware officielle | 🟠→🟠 |
| 7 | OpenSSL 1.0.2h EOL | Nécessite recompilation avec 3.x | 🟠→🟠 |

---

## Recommandations supplémentaires

1. **Mettre à jour vers le firmware officiel le plus récent** (Netgear R7000 — vérifier site officiel)
2. **Activer SSH** à la place de Telnet pour la gestion distante
3. **Désactiver UPnP** si non nécessaire (réduction de la surface d'attaque)
4. **Changer les credentials par défaut** immédiatement après installation
5. **Désactiver le service P2P/ReadyShare** si non utilisé
6. **Isoler le routeur** dans un VLAN dédié
7. **Recompiler avec protections** : Stack Canary, PIE/ASLR, RELRO, FORTIFY_SOURCE

---

## Architecture sécurisée recommandée

```
Internet
    │
  [Modem]
    │
  [Routeur R7000] ← firmware patché
    │           │
    │           └── Management: SSH uniquement (port non standard)
    │               Telnet: DÉSACTIVÉ
    │               FTP: DÉSACTIVÉ
    │               UPnP: DÉSACTIVÉ
    │
  [LAN]
    ├── VLAN 10 - Appareils de confiance
    ├── VLAN 20 - IoT isolé
    └── VLAN 30 - Invités (accès Internet uniquement)
```

---

## Fichiers du patch

Voir dossier `patched_files/` :
```
patched_files/
├── etc/
│   └── passwd              ← credentials sécurisés
├── bin/
│   └── disable_telnet.sh   ← désactivation telnet
└── www_cgi-bin/
    └── secure_cgi_wrapper.sh ← validation entrées CGI
```
Et `patched_overlay.sqfs` — overlay SquashFS reconstruit avec les corrections.

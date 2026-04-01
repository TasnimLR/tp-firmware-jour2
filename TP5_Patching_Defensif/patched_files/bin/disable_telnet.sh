#!/bin/sh
# TP5 - Désactivation des services Telnet non sécurisés
# CVE-2009-4964 : telnetenabled backdoor UDP

chmod -x /usr/sbin/telnetd       2>/dev/null && echo "[PATCH] telnetd désactivé"
chmod -x /usr/sbin/telnetenabled 2>/dev/null && echo "[PATCH] telnetenabled désactivé"
chmod -x /bin/utelnetd           2>/dev/null && echo "[PATCH] utelnetd désactivé"

killall -9 telnetd      2>/dev/null
killall -9 utelnetd     2>/dev/null
killall -9 telnetenabled 2>/dev/null

echo "[DONE] Tous les services Telnet ont été désactivés"
echo "[INFO] Utiliser SSH pour l'accès distant sécurisé"

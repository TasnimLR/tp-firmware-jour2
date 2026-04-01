#!/bin/sh
# TP5 - Validation stricte des entrées CGI
# Contre CVE-2016-6277 : injection commandes via /cgi-bin/;CMD

# Longueur max des paramètres
MAX_LEN=256

# Vérification taille
if [ ${#QUERY_STRING} -gt $MAX_LEN ]; then
    echo "Content-Type: text/html"
    echo "Status: 400 Bad Request"
    echo ""
    echo "<h1>400 - Request Too Long</h1>"
    exit 1
fi

# Blacklist caractères dangereux
SAFE_QUERY=$(echo "$QUERY_STRING" | sed 's/[;&|`$(){}\\<>'"'"']//g')

if [ "$SAFE_QUERY" != "$QUERY_STRING" ]; then
    echo "Content-Type: text/html"
    echo "Status: 400 Bad Request"
    echo ""
    echo "<h1>400 - Invalid characters in request</h1>"
    logger -t "cgi_security" "BLOCKED injection attempt: $QUERY_STRING"
    exit 1
fi

# Encodage HTML de la sortie
export QUERY_STRING="$SAFE_QUERY"
exec "$@"

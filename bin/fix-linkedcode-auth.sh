#!/bin/bash
#
# Fixes rápidos para problemas que check-linkedcode-auth.sh detecta pero no
# corrige solo (a propósito: son intervenciones, no lecturas). Cada uno se
# corre por nombre, nunca "todos a la vez", porque no siempre aplican todos.
#
#   ./bin/fix-linkedcode-auth.sh <fix>
#
# Fixes disponibles:
#   key-perms      chown de config/{private,public}.key a www-data:www-data
#                  dentro del contenedor. Corregí esto cuando el error log dice
#                  "Permission denied" leyendo esas claves: 600 en el host no
#                  alcanza si el dueño no es www-data (uid 33) puertas adentro.
#   config-cache   borra var/cache/config.php. Corregí esto cuando cambiaste
#                  config.php o common.php y no ves el efecto: Loader cachea el
#                  merge sin comparar fechas, así que un config.php nuevo no
#                  aplica hasta que el caché se borre o expire.
#
set -euo pipefail

CONTAINER="linkedcode-auth"

usage() {
    echo "Uso: $0 <key-perms|config-cache>"
    exit 1
}

require_running() {
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
        echo "$CONTAINER no está corriendo."
        exit 1
    fi
}

fix_key_perms() {
    require_running
    echo "==> chown www-data:www-data en config/{private,public}.key"
    docker exec -u root "$CONTAINER" chown www-data:www-data \
        /var/www/html/config/private.key /var/www/html/config/public.key

    echo "==> verificando"
    for key in private.key public.key; do
        docker exec -u www-data "$CONTAINER" test -r "/var/www/html/config/$key" \
            && echo "    $key: legible por www-data" \
            || echo "    $key: SIGUE sin ser legible por www-data"
    done
}

fix_config_cache() {
    require_running
    echo "==> borrando var/cache/config.php"
    docker exec "$CONTAINER" rm -f /var/www/html/var/cache/config.php
    echo "    listo: el próximo request reconstruye la config desde common.php + config.php"
}

[ $# -eq 1 ] || usage

case "$1" in
    key-perms)    fix_key_perms ;;
    config-cache) fix_config_cache ;;
    *)            usage ;;
esac

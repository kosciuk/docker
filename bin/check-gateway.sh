#!/bin/bash
#
# Detecta un shared-gateway cuyo proceso quedó desalineado del binario en disco.
#
#   ./bin/check-gateway.sh            # sólo diagnostica
#   ./bin/check-gateway.sh --fix      # reinicia si detecta el desfasaje
#
# El síntoma: el gateway sirve 404 en todos los vhosts aunque la config esté
# bien (vhosts cargados, certificados válidos, backends resolviendo). Se
# reconoce porque la versión de Apache que devuelve por HTTP no coincide con
# la que reporta su propio binario -- el proceso que atiende no es el que
# `docker exec` ejecuta.
#
# Visto el 2026-09-02: liberamerkato daba 404 en api/app mientras auth.linkedcode
# andaba. El header decía 2.4.68 y `httpd -v` 2.4.67. Un restart lo resolvió.
# La causa de fondo (por qué se desalinean) quedó sin explicar.
#
# SÓLO LEE, salvo que se pase --fix.
#
set -uo pipefail

GATEWAY="${GATEWAY:-shared-gateway}"
FIX=0

case "${1:-}" in
    --fix) FIX=1 ;;
    "")    ;;
    *)     echo "uso: $0 [--fix]"; exit 2 ;;
esac

ok()   { echo "  [ ok ]   $1"; }
bad()  { echo "  [FALLA]  $1"; }
info() { echo "           $1"; }

echo "==> Gateway"

if [ "$(docker inspect -f '{{.State.Running}}' "$GATEWAY" 2>/dev/null)" != "true" ]; then
    bad "$GATEWAY no está corriendo"
    info "docker compose -f /var/www/docker/gateway/compose.yml up -d"
    exit 1
fi
ok "$GATEWAY corriendo"

# Versión según el binario dentro del contenedor.
bin_ver=$(docker exec "$GATEWAY" httpd -v 2>/dev/null \
          | sed -n 's|.*Apache/\([0-9.]*\).*|\1|p' | head -1)

# Versión según el proceso que realmente atiende requests. Se pide por loopback
# para no depender de DNS ni de salir a internet; basta cualquier ruta, porque
# el header Server viene hasta en un 404.
srv_ver=$(curl -sI --max-time 5 http://127.0.0.1/ 2>/dev/null \
          | sed -n 's|^[Ss]erver: Apache/\([0-9.]*\).*|\1|p' | head -1)

if [ -z "$bin_ver" ] || [ -z "$srv_ver" ]; then
    bad "no se pudieron leer las dos versiones (binario='${bin_ver:-?}' servida='${srv_ver:-?}')"
    exit 1
fi

if [ "$bin_ver" = "$srv_ver" ]; then
    ok "versiones alineadas ($bin_ver)"
    exit 0
fi

bad "el proceso no coincide con el binario"
info "binario en disco: $bin_ver"
info "sirviendo:        $srv_ver"
info "el gateway devuelve 404 en todos los vhosts hasta que se reinicie"

if [ "$FIX" -eq 0 ]; then
    echo
    info "para arreglarlo:  $0 --fix"
    exit 1
fi

echo
echo "==> Reiniciando"

# Nunca reiniciar con la config rota: el gateway no volvería a levantar y se
# caerían todos los sitios, no sólo el que ya estaba fallando.
if ! docker exec "$GATEWAY" httpd -t >/dev/null 2>&1; then
    bad "la config tiene errores: NO reinicio"
    docker exec "$GATEWAY" httpd -t 2>&1 | sed 's/^/           /'
    exit 1
fi
ok "config válida"

if ! docker restart "$GATEWAY" >/dev/null 2>&1; then
    bad "falló el restart"
    exit 1
fi

# El contenedor vuelve antes de que Apache acepte conexiones.
for _ in $(seq 1 15); do
    sleep 1
    srv_ver=$(curl -sI --max-time 5 http://127.0.0.1/ 2>/dev/null \
              | sed -n 's|^[Ss]erver: Apache/\([0-9.]*\).*|\1|p' | head -1)
    [ -n "$srv_ver" ] && break
done

if [ "$srv_ver" = "$bin_ver" ]; then
    ok "reiniciado — sirviendo $srv_ver"
    exit 0
fi

bad "sigue desalineado tras el restart (sirviendo '${srv_ver:-sin respuesta}')"
info "docker logs --tail 40 $GATEWAY"
exit 1

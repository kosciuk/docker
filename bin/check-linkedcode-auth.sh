#!/bin/bash
#
# Verifica en el VPS lo que auth.linkedcode.com necesita para funcionar bien.
# Sólo lee: no modifica nada. Correr después de un deploy o un rebuild.
#
#   ./bin/check-linkedcode-auth.sh
#
set -uo pipefail

CONTAINER="linkedcode-auth"
GATEWAY="shared-gateway"
APP_CONFIG="/var/www/linkedcode/auth.linkedcode.com/config/config.php"

fails=0
warns=0

ok()   { echo "  [ ok ]   $1"; }
fail() { echo "  [FALLA]  $1"; fails=$((fails + 1)); }
warn() { echo "  [ ojo ]  $1"; warns=$((warns + 1)); }

section() { echo; echo "==> $1"; }

# ---------------------------------------------------------------- contenedores

section "Contenedores"

for name in "$GATEWAY" "$CONTAINER"; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = "true" ]; then
        ok "$name corriendo"
    else
        fail "$name NO está corriendo"
    fi
done

# Sin el contenedor de la app no tiene sentido seguir con el resto.
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
    echo
    echo "Sin $CONTAINER no se puede verificar el resto. Levantalo y volvé a correr."
    exit 1
fi

# ------------------------------------------------------------------- mod_remoteip

section "IP real del cliente (mod_remoteip)"

if docker exec "$CONTAINER" apache2ctl -M 2>/dev/null | grep -qi remoteip; then
    ok "remoteip_module cargado"
else
    fail "remoteip_module NO cargado -> REMOTE_ADDR va a ser la IP del gateway"
    echo "           rebuild: docker compose ... up -d --build auth"
fi

if docker exec "$CONTAINER" grep -q "RemoteIPTrustedProxy" \
    /etc/apache2/sites-available/000-default.conf 2>/dev/null; then
    ok "RemoteIPTrustedProxy configurado"
else
    fail "falta RemoteIPTrustedProxy -> el header X-Forwarded-For sería falseable"
fi

# Prueba de verdad: pedir desde el gateway con un XFF conocido y ver qué IP
# termina viendo PHP. Es lo único que confirma que la cadena entera funciona.
section "Prueba de extremo a extremo"

probe_dir="/var/www/html/public"
probe="_ip_probe_$$.php"

if docker exec "$CONTAINER" sh -c \
    "printf '<?php echo \$_SERVER[\"REMOTE_ADDR\"];' > $probe_dir/$probe" 2>/dev/null; then

    seen=$(docker exec "$GATEWAY" sh -c \
        "curl -s -H 'X-Forwarded-For: 203.0.113.55' http://$CONTAINER/$probe" 2>/dev/null)

    docker exec "$CONTAINER" rm -f "$probe_dir/$probe" 2>/dev/null

    case "$seen" in
        203.0.113.55)
            ok "REMOTE_ADDR = IP real del visitante"
            ;;
        "")
            warn "no hubo respuesta (¿el gateway resuelve '$CONTAINER'?) - verificar a mano"
            ;;
        *)
            fail "REMOTE_ADDR = $seen (debería ser 203.0.113.55)"
            echo "           el rate limit está usando un contador único compartido"
            ;;
    esac
else
    warn "no se pudo escribir el archivo de prueba en $probe_dir - salteado"
fi

# ------------------------------------------------------------------ config app

section "Config de la app"

if [ -f "$APP_CONFIG" ]; then
    if grep -q "CHANGE_ME" "$APP_CONFIG"; then
        fail "config.php todavía tiene secretos CHANGE_ME_*"
        grep -n "CHANGE_ME" "$APP_CONFIG" | sed 's/^/           /'
    else
        ok "sin placeholders CHANGE_ME"
    fi

    # verify_ssl en false es lo correcto en local (certificados self-signed),
    # pero en el VPS deja las llamadas a ember sin validar el certificado.
    if grep -q "'verify_ssl' => false" "$APP_CONFIG"; then
        fail "mail_api.verify_ssl está en false"
    else
        ok "mail_api.verify_ssl activo"
    fi

    if grep -q "linkedcode.local" "$APP_CONFIG"; then
        fail "config.php apunta a hosts .local (entorno de desarrollo)"
        grep -n "linkedcode.local" "$APP_CONFIG" | sed 's/^/           /'
    else
        ok "sin hosts .local"
    fi
else
    fail "no se encontró $APP_CONFIG"
fi

# Las claves OAuth no deben ser legibles por otros usuarios del sistema.
for key in private.key public.key; do
    path="/var/www/linkedcode/auth.linkedcode.com/config/$key"
    if [ -f "$path" ]; then
        perms=$(stat -c '%a' "$path")
        if [ "$key" = "private.key" ] && [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
            fail "$key con permisos $perms (se espera 600)"
        else
            ok "$key presente ($perms)"
        fi
    else
        fail "falta $path"
    fi
done

# -------------------------------------------------------------------- resumen

section "Resumen"

if [ "$fails" -gt 0 ]; then
    echo "  $fails falla(s), $warns advertencia(s)"
    exit 1
fi

if [ "$warns" -gt 0 ]; then
    echo "  Todo OK, con $warns advertencia(s) para mirar."
    exit 0
fi

echo "  Todo OK."

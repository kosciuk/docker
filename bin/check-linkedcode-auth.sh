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

# Prueba de verdad: mandar un XFF conocido y ver qué IP termina viendo PHP.
# Corre curl DESDE linkedcode-auth contra sí mismo, pero por su IP en la red
# Docker (no 127.0.0.1): RemoteIPTrustedProxy sólo confía en los rangos
# privados 172.16/12, 192.168/16 y 10/8, y loopback no cae en ninguno, así que
# pegarle a 127.0.0.1 haría fallar la prueba aunque la config esté bien -es
# la propia prueba la que quedaría fuera de lo que la config declara confiable,
# no un problema real. Usar la IP de la red sí reproduce cómo llega la conexión
# desde shared-gateway en producción (shared-gateway tampoco trae curl, ver
# commit anterior).
section "Prueba de extremo a extremo"

probe_dir="/var/www/html/public"
probe="_ip_probe_$$.php"

# linkedcode-auth está en dos redes (shared_services para MySQL, projects_public
# para el gateway): iterar todas las redes con {{range}} las concatena sin
# separador y arma una IP inválida. Se pide la de projects_public en concreto,
# que es por donde en verdad llega el tráfico del gateway.
self_ip=$(docker inspect "$CONTAINER" \
    --format '{{(index .NetworkSettings.Networks "projects_public").IPAddress}}' 2>/dev/null)

if [ -z "$self_ip" ]; then
    warn "no se pudo obtener la IP de $CONTAINER en la red Docker - salteado"
elif docker exec "$CONTAINER" sh -c \
    "printf '<?php echo \$_SERVER[\"REMOTE_ADDR\"];' > $probe_dir/$probe" 2>/dev/null; then

    seen=$(docker exec "$CONTAINER" sh -c \
        "curl -s -H 'X-Forwarded-For: 203.0.113.55' http://$self_ip/$probe" 2>/dev/null)

    docker exec "$CONTAINER" rm -f "$probe_dir/$probe" 2>/dev/null

    case "$seen" in
        203.0.113.55)
            ok "REMOTE_ADDR = IP real del visitante"
            ;;
        "")
            warn "curl no disponible en $CONTAINER o sin respuesta - verificar a mano"
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

# La config efectiva es el merge de common.php con config.php, así que grepear
# los archivos no alcanza: se le pregunta a la app por el valor que realmente usa.
section "Cookie de sesión"

cookie=$(docker exec "$CONTAINER" php -r '
require "/var/www/html/vendor/autoload.php";
$c = Linkedcode\NotEnv\Loader::reload("/var/www/html");
foreach (["secure", "httponly", "samesite"] as $k) {
    printf("%s=%s\n", $k, var_export($c->get("cookie.$k", null), true));
}' 2>/dev/null)

if [ -z "$cookie" ]; then
    warn "no se pudo leer la config de cookie - verificar a mano"
else
    for flag in secure httponly; do
        value=$(printf '%s\n' "$cookie" | sed -n "s/^${flag}=//p")
        case "$value" in
            true)  ok "cookie $flag activo" ;;
            false) fail "cookie $flag en false (en producción debe ser true)" ;;
            *)     fail "cookie $flag sin definir -> la cookie sale sin ese flag" ;;
        esac
    done

    samesite=$(printf '%s\n' "$cookie" | sed -n "s/^samesite=//p")
    case "$samesite" in
        "'Lax'"|"'Strict'") ok "cookie samesite $samesite" ;;
        *)                  warn "cookie samesite $samesite" ;;
    esac
fi

# Loader cachea el merge y no compara fechas: si el caché es más viejo que los
# archivos, la app sigue sirviendo la config anterior aunque el deploy ya pasó.
section "Caché de config"

stale=$(docker exec "$CONTAINER" sh -c '
cache=/var/www/html/var/cache/config.php
[ -f "$cache" ] || { echo "sin-cache"; exit 0; }
for f in /var/www/html/config/common.php /var/www/html/config/config.php; do
    [ "$f" -nt "$cache" ] && { echo "rancio"; exit 0; }
done
echo "fresco"' 2>/dev/null)

case "$stale" in
    fresco)    ok "el caché está al día" ;;
    sin-cache) ok "sin caché: se reconstruye en el próximo request" ;;
    rancio)    fail "var/cache/config.php es más viejo que la config -> borralo"
               echo "           docker exec $CONTAINER rm -f /var/www/html/var/cache/config.php" ;;
    *)         warn "no se pudo revisar el caché de config" ;;
esac

# Las claves OAuth no deben ser legibles por otros usuarios del sistema, pero
# eso no alcanza: hay que probar que el proceso del contenedor (www-data) las
# puede leer. 600 con el dueño equivocado (típico si el archivo se creó desde
# el host) es ilegible para www-data y la stat del host no lo detecta -pasó
# exactamente eso: 600 correcto, dueño incorrecto, la app rota con Permission
# denied.
for key in private.key public.key; do
    path="/var/www/linkedcode/auth.linkedcode.com/config/$key"
    if [ ! -f "$path" ]; then
        fail "falta $path"
        continue
    fi

    perms=$(stat -c '%a' "$path")
    owner=$(stat -c '%U:%G' "$path" 2>/dev/null || echo '?')

    if [ "$key" = "private.key" ] && [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        fail "$key con permisos $perms (se espera 600), dueño $owner"
    elif ! docker exec -u www-data "$CONTAINER" test -r "/var/www/html/config/$key" 2>/dev/null; then
        fail "$key ($perms, dueño $owner en el host) no es legible por www-data en el contenedor"
        echo "           fix: docker exec -u root $CONTAINER chown www-data:www-data /var/www/html/config/$key"
    else
        ok "$key presente ($perms) y legible por www-data"
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

#!/bin/bash
#
# Motor común de los bin/setup-*.sh.
#
# No se ejecuta directo: cada proyecto tiene un wrapper en bin/setup-<x>.sh que
# hace `source` de su config en bin/projects/<x>.conf y después de este archivo.
#
# El flujo es siempre el mismo, y está partido en dos fases:
#
#   FASE 1 (sólo lectura)  chequea env, Docker, servicios compartidos, base de
#                          datos, código y lo que el proyecto declare. Si algo
#                          falla, corta SIN haber modificado nada: o el script
#                          hace todo, o no dejó el sistema a medias.
#   FASE 2 (modifica)      crea directorios y redes, levanta los contenedores.
#
# Converge, pero no es idempotente en sentido estricto:
#   - si cambió el compose los contenedores afectados se recrean -> corte breve
#   - --build NO reproduce la imagen anterior: los Dockerfile usan tags móviles
#     (php:8.4-fpm) y apt/pecl/composer sin versión fija. Por eso es opt-in.
#
# ---------------------------------------------------------------------------
# Variables que puede declarar la config del proyecto
# ---------------------------------------------------------------------------
# Obligatorias:
#   PROJECT       nombre del proyecto (= directorio en projects/ y prefijo de
#                 los contenedores, salvo que se declare CONTAINERS)
#
# Opcionales (con su default entre paréntesis):
#   ROOT          raíz de datos en el VPS            (/var/www/$PROJECT)
#   COMPOSE       ruta del compose                   (projects/$PROJECT/compose/web.yml)
#   ENV_FILE      ruta del env                       (projects/$PROJECT/env/web.env)
#   ENV_REQUIRED  1 si el proyecto necesita env      (1)
#   ENV_HINT      qué completar, para el mensaje     (DB_USER / DB_PASS / COMPOSER_AUTH)
#   PLACEHOLDERS  regex de valores sin completar     (patrón genérico)
#   NEEDS_MYSQL   1 si depende de shared-mysql       (1)
#   NEEDS_GATEWAY 1 si depende de shared-gateway     (1)
#   NETWORKS      redes a crear                      (shared_services projects_public)
#   DATA_DIRS     directorios a crear bajo ROOT      (vacío)
#   WRITABLE_DIRS directorios que www-data debe poder escribir (vacío)
#   REPOS         "ruta|url" por repo que debe estar clonado   (vacío)
#   DIST_DIRS     rutas que deben existir con contenido compilado (vacío)
#   REQUIRED_FILES "ruta|explicación" de archivos que deben existir (vacío)
#   DB_SOURCE     de dónde salen las credenciales: env | config | none  (env)
#   DB_NAME       nombre de la base                  ($PROJECT)
#   APP_CONFIG    config.php a leer si DB_SOURCE=config
#   KEYPAIR_DIR   directorio con private.key/public.key a verificar
#   SERVICES      servicios del compose a levantar y verificar (todos)
#   CONTAINERS    contenedores a verificar           ($PROJECT-$svc por servicio)
#   SYSTEMD_UNITS units que deberían estar activas   (vacío)
#   SUPPORTS_BUILD 1 si acepta --build               (1)
#   POST_MSG      texto extra para el final          (vacío)
#
# Hooks opcionales: si la config define estas funciones, se llaman en su fase.
#   check_extra   chequeos propios del proyecto (fase 1, sólo lectura)
#   setup_extra   pasos propios del proyecto (fase 2)
#
set -uo pipefail

# --------------------------------------------------------------- defaults

DOCKER="${DOCKER:-/var/www/docker}"
: "${PROJECT:?la config del proyecto debe declarar PROJECT}"

ROOT="${ROOT:-/var/www/${PROJECT}}"
COMPOSE="${COMPOSE:-${DOCKER}/projects/${PROJECT}/compose/web.yml}"
ENV_FILE="${ENV_FILE:-${DOCKER}/projects/${PROJECT}/env/web.env}"
ENV_REQUIRED="${ENV_REQUIRED:-1}"
ENV_HINT="${ENV_HINT:-DB_USER / DB_PASS / COMPOSER_AUTH}"
PLACEHOLDERS="${PLACEHOLDERS:-^(DB_PASS|COMPOSER_AUTH)=[[:space:]]*\$|CAMBIAR|CHANGE_ME}"
NEEDS_MYSQL="${NEEDS_MYSQL:-1}"
NEEDS_GATEWAY="${NEEDS_GATEWAY:-1}"
DB_SOURCE="${DB_SOURCE:-env}"
DB_NAME="${DB_NAME:-$PROJECT}"
APP_CONFIG="${APP_CONFIG:-}"
KEYPAIR_DIR="${KEYPAIR_DIR:-}"
SUPPORTS_BUILD="${SUPPORTS_BUILD:-1}"
POST_MSG="${POST_MSG:-}"

# Arrays: se declaran vacíos si la config no los definió.
declare -p NETWORKS      >/dev/null 2>&1 || NETWORKS=(shared_services projects_public)
declare -p DATA_DIRS     >/dev/null 2>&1 || DATA_DIRS=()
declare -p WRITABLE_DIRS >/dev/null 2>&1 || WRITABLE_DIRS=()
declare -p REPOS         >/dev/null 2>&1 || REPOS=()
declare -p DIST_DIRS     >/dev/null 2>&1 || DIST_DIRS=()
declare -p REQUIRED_FILES >/dev/null 2>&1 || REQUIRED_FILES=()
declare -p SERVICES      >/dev/null 2>&1 || SERVICES=()
declare -p CONTAINERS    >/dev/null 2>&1 || CONTAINERS=()
declare -p SYSTEMD_UNITS >/dev/null 2>&1 || SYSTEMD_UNITS=()

# Si no se declararon contenedores, se derivan de los servicios.
if [ "${#CONTAINERS[@]}" -eq 0 ] && [ "${#SERVICES[@]}" -gt 0 ]; then
    for _svc in "${SERVICES[@]}"; do CONTAINERS+=("${PROJECT}-${_svc}"); done
fi

# ------------------------------------------------------------------ argumentos

BUILD=0
case "${1:-}" in
    --build)
        if [ "$SUPPORTS_BUILD" -eq 1 ]; then
            BUILD=1
        else
            echo "uso: $0            ($PROJECT no acepta --build: usa una imagen ya publicada)"
            exit 2
        fi ;;
    "") ;;
    *)
        if [ "$SUPPORTS_BUILD" -eq 1 ]; then
            echo "uso: $0 [--build]"
        else
            echo "uso: $0"
        fi
        exit 2 ;;
esac

# -------------------------------------------------------------------- helpers

fails=0
warns=0

ok()   { echo "  [ ok ]   $1"; }
fail() { echo "  [FALLA]  $1"; fails=$((fails + 1)); }
warn() { echo "  [ ojo ]  $1"; warns=$((warns + 1)); }

section() { echo; echo "==> $1"; }

# Un solo docker inspect por consulta, detrás de un nombre legible.
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

# =============================================================================
# FASE 1 - sólo lectura
#
# Nada de acá modifica el sistema. Los chequeos caros (MySQL, base de datos)
# van antes de crear nada, para que un problema de configuración no deje el
# sistema a medio armar.
# =============================================================================

section "Requisitos"

if [ ! -f "$COMPOSE" ]; then
    echo "  No se encontró $COMPOSE."
    echo "  Este script se corre en el VPS, con el repo en /var/www/docker."
    exit 1
fi
ok "compose encontrado"

env_ok=0
if [ ! -f "$ENV_FILE" ]; then
    if [ "$ENV_REQUIRED" -eq 1 ]; then
        fail "falta $ENV_FILE"
        echo "           cp ${ENV_FILE}.example ${ENV_FILE}"
        echo "           y completar ${ENV_HINT}"
    else
        warn "no hay $ENV_FILE (este proyecto no lo necesita)"
    fi
else
    env_ok=1
    # Un env copiado del example y no editado levanta contenedores que fallan
    # recién en el primer request, no al arrancar.
    if grep -qE "$PLACEHOLDERS" "$ENV_FILE"; then
        fail "$ENV_FILE tiene valores sin completar"
        grep -nE "$PLACEHOLDERS" "$ENV_FILE" | sed 's/^/           /'
    else
        ok "env completo"
    fi
fi

section "Docker"

if ! docker info >/dev/null 2>&1; then
    fail "no se puede hablar con el demonio de Docker"
    echo "           ¿está corriendo? ¿el usuario está en el grupo docker?"
else
    ok "demonio de Docker accesible"
fi

if [ "$NEEDS_MYSQL" -eq 1 ] || [ "$NEEDS_GATEWAY" -eq 1 ]; then
    section "Servicios compartidos"

    # Se recuerda el estado de mysql: la sección "Base de datos" lo reusa en vez
    # de volver a preguntarle a Docker.
    mysql_up=0

    if [ "$NEEDS_MYSQL" -eq 1 ]; then
        if running shared-mysql; then
            mysql_up=1
            ok "shared-mysql corriendo"
        else
            fail "shared-mysql NO está corriendo"
            echo "           docker compose --env-file ${DOCKER}/services/mysql/.env \\"
            echo "             -f ${DOCKER}/services/mysql/compose.yml up -d"
        fi
    fi

    if [ "$NEEDS_GATEWAY" -eq 1 ]; then
        if running shared-gateway; then
            ok "shared-gateway corriendo"
        else
            fail "shared-gateway NO está corriendo"
            echo "           docker compose -f ${DOCKER}/gateway/compose.yml up -d"
        fi
    fi
else
    mysql_up=0
fi

# ------------------------------------------------------------------- código

if [ "${#REPOS[@]}" -gt 0 ] || [ "${#DIST_DIRS[@]}" -gt 0 ]; then
    section "Código"

    # Los contenedores montan estos directorios. Si no están clonados, Docker
    # los crearía vacíos y los contenedores levantarían sin aplicación adentro.
    for entry in "${REPOS[@]}"; do
        path="${entry%%|*}"
        url="${entry##*|}"
        if [ -d "${path}/.git" ]; then
            ok "${path} clonado"
        else
            fail "falta clonar ${path}"
            echo "           git clone ${url} ${path}"
        fi
    done

    for path in "${DIST_DIRS[@]}"; do
        if [ -d "$path" ]; then
            ok "${path} presente"
        else
            fail "falta ${path}"
            echo "           el contenedor lo monta: compilar la SPA y subirla"
        fi
    done
fi

# ------------------------------------------------------- archivos requeridos

if [ "${#REQUIRED_FILES[@]}" -gt 0 ]; then
    section "Archivos de configuración"

    for entry in "${REQUIRED_FILES[@]}"; do
        path="${entry%%|*}"
        hint="${entry##*|}"
        if [ -f "$path" ]; then
            ok "$(basename "$path") presente"
        else
            fail "falta ${path}"
            echo "           ${hint}"
        fi
    done
fi

# -------------------------------------------------------------- keypair OAuth

if [ -n "$KEYPAIR_DIR" ]; then
    section "Keypair OAuth"

    # league/oauth2-server necesita el par de claves para firmar tokens. Si
    # falta, el contenedor levanta igual y falla al emitir el primer token.
    for key in private.key public.key; do
        path="${KEYPAIR_DIR}/${key}"
        if [ -f "$path" ]; then
            ok "$key presente ($(stat -c '%a' "$path" 2>/dev/null))"
        else
            fail "falta $path"
            echo "           openssl genrsa -out ${KEYPAIR_DIR}/private.key 2048"
            echo "           (ver README para el public.key y los permisos)"
        fi
    done
fi

# ------------------------------------------------------------- base de datos

if [ "$DB_SOURCE" != "none" ]; then
    section "Base de datos"

    # La base se crea a mano con la contraseña de root, que estos scripts no
    # tienen: sólo se verifica. Es 'fail' y no 'warn' porque levantar la API
    # contra una base inexistente da un stack que parece sano (contenedores
    # arriba) pero devuelve error 500 en el primer request.
    db_user=""
    db_pass=""
    db_skip=""

    case "$DB_SOURCE" in
        env)
            if [ "$env_ok" -eq 0 ]; then
                db_skip="sin env no se puede verificar la base"
            else
                db_name=$(sed -n 's/^DB_NAME=//p' "$ENV_FILE" | tr -d '"'"'"'')
                db_name=${db_name:-$DB_NAME}
                db_user=$(sed -n 's/^DB_USER=//p' "$ENV_FILE" | tr -d '"'"'"'')
                db_pass=$(sed -n 's/^DB_PASS=//p' "$ENV_FILE" | tr -d '"'"'"'')
                db_origin="del env"
            fi ;;
        config)
            # Estos proyectos NO arman la conexión con las variables DB_* del
            # compose: config/common.php fija localhost y eso se pisa desde
            # config/config.php, que no se versiona.
            if [ ! -f "$APP_CONFIG" ]; then
                db_skip="sin config.php no se puede verificar la base"
            elif ! command -v php >/dev/null 2>&1; then
                # El VPS puede no tener PHP en el host: todo corre en contenedores.
                db_skip="no hay php en el host para leer config.php"
            else
                # Se le pregunta a PHP por el valor efectivo en vez de grepear.
                creds=$(php -r '
                    $c = require $argv[1];
                    $db = $c["db"] ?? [];
                    printf("%s\n%s\n%s\n", $db["dbname"] ?? "", $db["user"] ?? "", $db["password"] ?? "");
                ' "$APP_CONFIG" 2>/dev/null)
                db_name=$(printf '%s\n' "$creds" | sed -n 1p)
                db_user=$(printf '%s\n' "$creds" | sed -n 2p)
                db_pass=$(printf '%s\n' "$creds" | sed -n 3p)
                db_name=${db_name:-$DB_NAME}
                db_origin="de config.php"
            fi ;;
    esac

    if [ -n "$db_skip" ]; then
        warn "${db_skip} - salteado"
    elif [ "$mysql_up" -eq 0 ]; then
        warn "shared-mysql no está corriendo - salteado"
    elif [ -z "$db_user" ] || [ -z "$db_pass" ]; then
        fail "no hay usuario/contraseña de base ${db_origin}"
    elif docker exec shared-mysql mysql -u "$db_user" -p"$db_pass" \
             -e "USE \`${db_name}\`" >/dev/null 2>&1; then
        ok "base '${db_name}' accesible con las credenciales ${db_origin}"
    else
        fail "no se pudo entrar a '${db_name}' con las credenciales ${db_origin}"
        echo "           si es la primera vez, crear base y usuario (ver README)"
    fi
fi

# Chequeos propios del proyecto, si los declaró.
if declare -F check_extra >/dev/null; then
    check_extra
fi

# ------------------------------------------------- corte antes de tocar nada

if [ "$fails" -gt 0 ]; then
    echo
    echo "==> Corto acá"
    echo "  $fails falla(s) en los chequeos. No modifiqué nada todavía."
    echo "  Resolvelas y volvé a correr."
    exit 1
fi

# =============================================================================
# FASE 2 - a partir de acá sí se modifica el sistema
# =============================================================================

if [ "${#DATA_DIRS[@]}" -gt 0 ]; then
    section "Directorios en $ROOT"

    for dir in "${DATA_DIRS[@]}"; do
        path="${ROOT}/${dir}"
        if [ -d "$path" ]; then
            ok "$path ya existe"
        elif sudo mkdir -p "$path" && sudo chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$path"; then
            ok "$path creado"
        else
            fail "no se pudo crear $path"
        fi
    done

    # La API escribe los uploads que sirve el contenedor img, y corre como
    # www-data adentro del contenedor. Si el directorio quedó como root (típico
    # de un mkdir a mano), los uploads fallan con Permission denied recién al
    # subir la primera imagen, no al levantar.
    for dir in "${WRITABLE_DIRS[@]}"; do
        path="${ROOT}/${dir}"
        if [ -d "$path" ] && ! sudo -u www-data test -w "$path" 2>/dev/null; then
            warn "$path no es escribible por www-data"
            echo "           sudo chown -R www-data:www-data $path"
        fi
    done
fi

if [ "${#NETWORKS[@]}" -gt 0 ]; then
    section "Redes Docker"

    for net in "${NETWORKS[@]}"; do
        if docker network inspect "$net" >/dev/null 2>&1; then
            ok "$net existe"
        elif docker network create "$net" >/dev/null 2>&1; then
            ok "$net creada"
        else
            fail "no se pudo crear la red $net"
        fi
    done
fi

# Pasos propios del proyecto, si los declaró.
if declare -F setup_extra >/dev/null; then
    setup_extra
fi

section "Stack de ${PROJECT}"

if [ "$fails" -gt 0 ]; then
    echo "  Hay $fails falla(s) arriba: no levanto el stack."
    exit 1
fi

up_args=(up -d)
[ "$BUILD" -eq 1 ] && up_args+=(--build)

# SERVICES vacío = todo el compose. Con servicios nombrados, los demás quedan
# intactos (así setup-linkedcode-auth no toca linkedcode-www).
compose_args=()
[ -f "$ENV_FILE" ] && compose_args+=(--env-file "$ENV_FILE")
compose_args+=(-f "$COMPOSE")

if [ "$BUILD" -eq 1 ]; then
    echo "  docker compose up -d --build ${SERVICES[*]:-} ..."
else
    echo "  docker compose up -d ${SERVICES[*]:-} ...  (sin rebuild; usar --build si hace falta)"
fi

if docker compose "${compose_args[@]}" "${up_args[@]}" ${SERVICES[@]+"${SERVICES[@]}"}; then
    ok "stack levantado"
else
    fail "falló el docker compose up"
    exit 1
fi

if [ "${#CONTAINERS[@]}" -gt 0 ]; then
    section "Contenedores"

    for name in "${CONTAINERS[@]}"; do
        if running "$name"; then
            ok "$name corriendo"
        else
            fail "$name NO está corriendo -> docker logs $name"
        fi
    done
fi

if [ "${#SYSTEMD_UNITS[@]}" -gt 0 ]; then
    section "Units de systemd"

    for unit in "${SYSTEMD_UNITS[@]}"; do
        if ! systemctl list-unit-files "$unit" >/dev/null 2>&1 \
           || ! systemctl list-unit-files 2>/dev/null | grep -q "^${unit}"; then
            warn "$unit no está instalada"
            echo "           sudo cp ${DOCKER}/systemd/${unit} /etc/systemd/system/"
            echo "           sudo systemctl daemon-reload"
            echo "           sudo systemctl enable --now ${unit}"
        elif systemctl is-active --quiet "$unit"; then
            ok "$unit activa"
        else
            warn "$unit instalada pero NO activa"
            echo "           sudo systemctl enable --now ${unit}"
        fi
    done
fi

# -------------------------------------------------------------------- resumen

section "Resumen"

if [ "$fails" -gt 0 ]; then
    echo "  $fails falla(s), $warns advertencia(s)"
    exit 1
fi

if [ "$warns" -gt 0 ]; then
    echo "  ${PROJECT} arriba, con $warns advertencia(s) para mirar."
else
    echo "  ${PROJECT} arriba."
fi

[ -n "$POST_MSG" ] && printf '%s\n' "$POST_MSG"

exit 0

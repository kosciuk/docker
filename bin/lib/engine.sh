#!/bin/bash
#
# Motor común de los bin/<proyecto>.sh.
#
# No se ejecuta directo: cada proyecto tiene un wrapper en bin/<proyecto>.sh
# que hace `source` de su config en bin/projects/<proyecto>.conf y después de
# este archivo.
#
# Fusiona lo que antes eran dos comandos (setup-*.sh y deploy-*.sh) en uno
# solo, idempotente: si el proyecto nunca se levantó, clona lo que falte, crea
# directorios/redes y levanta los contenedores; si ya existe, actualiza el
# código (git pull) y reinicia sólo si hubo cambios. Correrlo dos veces
# seguidas sin cambios no debería reiniciar nada.
#
#   FASE 1 (sólo lectura)  env, Docker, servicios compartidos, DB, REPOS (si
#                          falta clonar, NO falla -- se anota para fase 2),
#                          DIST_DIRS, REQUIRED_FILES, keypair, y -- si el repo
#                          ya existe -- working tree limpio, rama correcta,
#                          acceso al remoto. Si el contenedor principal ya
#                          está corriendo, además valida COMPOSER_AUTH contra
#                          GitHub. Si algo falla, corta sin haber modificado
#                          nada.
#   FASE 2 (modifica)      clona REPOS que faltaban, git pull --ff-only en los
#                          que ya estaban, crea DATA_DIRS/NETWORKS, docker
#                          compose up -d [--build], y recién con el contenedor
#                          arriba: composer install + migraciones si
#                          USES_COMPOSER=1, reinicio sólo si hubo cambios de
#                          código o se hizo build.
#
# No es atómico: si migrate falla a mitad de camino, el código ya actualizado
# queda corriendo contra un schema viejo hasta que se resuelva a mano. No hay
# rollback automático.
#
# ---------------------------------------------------------------------------
# Variables que puede declarar la config del proyecto
# ---------------------------------------------------------------------------
# Obligatoria:
#   PROJECT       nombre del proyecto (= directorio en projects/, y prefijo
#                 por default de sus contenedores)
#
# Stack (con su default entre paréntesis):
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
#   DIST_DIRS     rutas que deben existir con contenido compilado (vacío)
#   REQUIRED_FILES "ruta|explicación" de archivos que deben existir (vacío)
#   DB_SOURCE     de dónde salen las credenciales: env | config | none  (env)
#   DB_NAME       nombre de la base                  ($PROJECT)
#   APP_CONFIG    config.<env>.php a leer si DB_SOURCE=config
#   KEYPAIR_DIR   directorio con private.key/public.key a verificar
#   SERVICES      servicios del compose a levantar y verificar (todos)
#   CONTAINERS    contenedores a verificar           ($PROJECT-$svc por servicio)
#   SYSTEMD_UNITS units que deberían estar activas   (vacío)
#   SUPPORTS_BUILD 1 si acepta --build               (1)
#   POST_MSG      texto extra para el final          (vacío)
#
# Código y deploy:
#   REPOS         "ruta|url" por repo que debe estar clonado   (vacío)
#   DEPLOY_BRANCH rama a la que hacer pull                     (main)
#   USES_COMPOSER 1 si corre composer install/migrate adentro  (0)
#   MIGRATE_CONTAINER contenedor donde correr composer/migrate (primer container
#                                                                de CONTAINERS)
#   MIGRATE       1 si además de composer corre vendor/bin/migrate (1, ignorado
#                                                                    si USES_COMPOSER=0)
#   RESTART_CONTAINERS contenedores a reiniciar si hubo cambios de código
#                                                                (CONTAINERS)
#
# Hooks opcionales: si la config define estas funciones, se llaman en su fase.
#   check_extra     chequeos propios del proyecto (fase 1, sólo lectura)
#   converge_extra  pasos propios del proyecto (fase 2, después de migrate)
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

DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
USES_COMPOSER="${USES_COMPOSER:-0}"
MIGRATE="${MIGRATE:-1}"

# Arrays: se declaran vacíos si la config no los definió.
declare -p NETWORKS       >/dev/null 2>&1 || NETWORKS=(shared_services projects_public)
declare -p DATA_DIRS      >/dev/null 2>&1 || DATA_DIRS=()
declare -p WRITABLE_DIRS  >/dev/null 2>&1 || WRITABLE_DIRS=()
declare -p REPOS          >/dev/null 2>&1 || REPOS=()
declare -p DIST_DIRS      >/dev/null 2>&1 || DIST_DIRS=()
declare -p REQUIRED_FILES >/dev/null 2>&1 || REQUIRED_FILES=()
declare -p SERVICES       >/dev/null 2>&1 || SERVICES=()
declare -p CONTAINERS     >/dev/null 2>&1 || CONTAINERS=()
declare -p SYSTEMD_UNITS  >/dev/null 2>&1 || SYSTEMD_UNITS=()

# Si no se declararon contenedores, se derivan de los servicios.
if [ "${#CONTAINERS[@]}" -eq 0 ] && [ "${#SERVICES[@]}" -gt 0 ]; then
    for _svc in "${SERVICES[@]}"; do CONTAINERS+=("${PROJECT}-${_svc}"); done
fi

# El contenedor de composer/migrate es explícito si se declaró; si no, el
# primero de CONTAINERS. Proyectos con auth+www o api+app+img+www comparten
# PROJECT o tienen contenedores que no siguen $PROJECT-api (ember-app,
# linkedcode-auth): por eso no hay un default "ciego" tipo $PROJECT-api.
if [ -z "${MIGRATE_CONTAINER:-}" ]; then
    MIGRATE_CONTAINER="${CONTAINERS[0]:-}"
fi

declare -p RESTART_CONTAINERS >/dev/null 2>&1 || RESTART_CONTAINERS=("${CONTAINERS[@]}")

# DEPLOY_ROOT: repo sobre el que corren git pull/composer/migrate.
if [ -z "${DEPLOY_ROOT:-}" ]; then
    if [ "${#REPOS[@]}" -gt 0 ]; then
        DEPLOY_ROOT="${REPOS[0]%%|*}"
    else
        DEPLOY_ROOT="$ROOT"
    fi
fi

# ------------------------------------------------------------------ argumentos

BUILD=0
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --build)
            if [ "$SUPPORTS_BUILD" -eq 1 ]; then
                BUILD=1
            else
                echo "uso: $0 [--dry-run]  ($PROJECT no acepta --build: usa una imagen ya publicada)"
                exit 2
            fi ;;
        --dry-run) DRY_RUN=1 ;;
        *)
            if [ "$SUPPORTS_BUILD" -eq 1 ]; then
                echo "uso: $0 [--build] [--dry-run]"
            else
                echo "uso: $0 [--dry-run]"
            fi
            exit 2 ;;
    esac
done

# -------------------------------------------------------------------- helpers

fails=0
warns=0

ok()   { echo "  [ ok ]   $1"; }
fail() { echo "  [FALLA]  $1"; fails=$((fails + 1)); }
warn() { echo "  [ ojo ]  $1"; warns=$((warns + 1)); }

section() { echo; echo "==> $1"; }

# Un solo docker inspect por consulta, detrás de un nombre legible.
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

dc() { docker exec -w /var/www/html "$MIGRATE_CONTAINER" "$@"; }

# =============================================================================
# FASE 1 - sólo lectura
#
# Nada de acá modifica el sistema. Los chequeos caros (MySQL, base de datos)
# van antes de cualquier otra cosa, para que un problema de configuración no
# deje el sistema a medio armar.
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

# REPOS que faltan NO son un fail acá: fase 2 los clona. Se anotan en
# repos_missing para no repetir el `[ -d .git ]` en fase 2.
declare -a repos_missing=()

if [ "${#REPOS[@]}" -gt 0 ] || [ "${#DIST_DIRS[@]}" -gt 0 ]; then
    section "Código"

    for entry in "${REPOS[@]}"; do
        path="${entry%%|*}"
        url="${entry##*|}"
        if [ -d "${path}/.git" ]; then
            ok "${path} clonado"
        elif [ -d "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ]; then
            # git clone no clona sobre un directorio con contenido. Suele
            # pasar cuando Docker creó el bind mount (como root) antes del
            # clone, o cuando se copió a mano un config/ antes de clonar.
            fail "${path} existe con contenido pero no es un repo git"
            echo "           contiene: $(ls -A "$path" | head -10 | tr '\n' ' ')"
            echo "           moverlo aparte y volver a correr (se clona limpio):"
            echo "             sudo mv ${path} ${path}.old"
        else
            warn "falta clonar ${path} (se clona en esta misma corrida)"
            repos_missing+=("$entry")
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

# El repo de deploy (DEPLOY_ROOT) sólo se valida si ya está clonado: si es la
# primera vez (setup desde cero) fase 2 lo clona y no hay nada que chequear.
deploy_root_exists=0
if [ -d "$DEPLOY_ROOT/.git" ]; then
    deploy_root_exists=1
    section "Repo de deploy ($DEPLOY_ROOT)"

    # Un pull sobre un working tree sucio puede fallar a mitad de camino o,
    # peor, mezclar el cambio local con lo que viene de git. Se corta antes.
    dirty=$(git -C "$DEPLOY_ROOT" status --porcelain)
    if [ -n "$dirty" ]; then
        fail "$DEPLOY_ROOT tiene cambios sin commitear"
        echo "$dirty" | sed 's/^/           /'
        echo "           commitear, descartar (git checkout --) o guardarlos (git stash)"
    else
        ok "working tree limpio"
    fi

    branch=$(git -C "$DEPLOY_ROOT" branch --show-current)
    if [ "$branch" != "$DEPLOY_BRANCH" ]; then
        fail "el repo está en '$branch', se esperaba '$DEPLOY_BRANCH'"
    else
        ok "en la rama $DEPLOY_BRANCH"
    fi

    # git pull usa el remote configurado (SSH con su propia clave, en general).
    # Probarlo con ls-remote autentica sin traer nada -- así una clave vencida
    # corta acá, no a mitad del pull.
    remote=$(git -C "$DEPLOY_ROOT" remote get-url origin 2>/dev/null)
    if [ -z "$remote" ]; then
        fail "no se pudo leer el remote 'origin' de $DEPLOY_ROOT"
    elif git -C "$DEPLOY_ROOT" ls-remote --exit-code origin "$DEPLOY_BRANCH" >/dev/null 2>&1; then
        ok "acceso a git remoto ($remote)"
    else
        fail "no hay acceso a $remote"
        echo "           revisar la clave SSH del host (~/.ssh/config) o el token, según el tipo de remote"
    fi
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
            # Con notenv la conexión sale de config/config.<env>.php (no
            # versionado), no del env del compose: se le pregunta a PHP por el
            # valor efectivo en vez de grepear. El VPS no tiene PHP en el host,
            # así que se usa el del contenedor de la API si ya corre; el archivo
            # entra por stdin, sin depender de cómo esté montado.
            read_db_php='
                $code = stream_get_contents(STDIN);
                $code = preg_replace("/^<\?php\s*/", "", $code);
                $code = preg_replace("/declare\s*\(\s*strict_types\s*=\s*1\s*\)\s*;/", "", $code, 1);
                $c  = eval($code);
                $db = is_array($c) ? ($c["db"] ?? []) : [];
                printf("%s\n%s\n%s\n", $db["dbname"] ?? "", $db["user"] ?? "", $db["password"] ?? "");
            '
            creds=""
            if [ ! -f "$APP_CONFIG" ]; then
                db_skip="sin $(basename "$APP_CONFIG") no se puede verificar la base"
            elif command -v php >/dev/null 2>&1; then
                creds=$(php -r "$read_db_php" <"$APP_CONFIG" 2>/dev/null)
            elif [ -n "$MIGRATE_CONTAINER" ] && running "$MIGRATE_CONTAINER"; then
                creds=$(docker exec -i "$MIGRATE_CONTAINER" php -r "$read_db_php" <"$APP_CONFIG" 2>/dev/null)
            else
                db_skip="sin php en el host y ${MIGRATE_CONTAINER:-la API} sin correr: no se lee $(basename "$APP_CONFIG")"
            fi
            if [ -z "$db_skip" ]; then
                db_name=$(printf '%s\n' "$creds" | sed -n 1p)
                db_user=$(printf '%s\n' "$creds" | sed -n 2p)
                db_pass=$(printf '%s\n' "$creds" | sed -n 3p)
                db_name=${db_name:-$DB_NAME}
                db_origin="de $(basename "$APP_CONFIG")"
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

# --------------------------------------------------------------- COMPOSER_AUTH

# Se prueba el token de ENV_FILE, no el del contenedor corriendo: fase 2
# recrea el contenedor con ese env, así que es el que composer va a usar. Se
# prueba contra la API sin instalar nada: un 401 anticipa que composer
# install fallaría. El token nunca se imprime, sólo el código HTTP.
if [ "$USES_COMPOSER" -eq 1 ] && [ -f "$ENV_FILE" ]; then
    token=$(sed -n 's/^COMPOSER_AUTH=//p' "$ENV_FILE" \
        | sed -n 's/.*"github.com"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$token" ]; then
        warn "COMPOSER_AUTH no definido o con formato inesperado -- no se pudo probar"
    else
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
            -H "Authorization: token $token" https://api.github.com/rate_limit)
        case "$code" in
            200) ok "COMPOSER_AUTH válido contra GitHub" ;;
            401) fail "COMPOSER_AUTH inválido o vencido (GitHub respondió 401)" ;;
            000) warn "no se pudo contactar a GitHub -- COMPOSER_AUTH sin probar" ;;
            *)   fail "COMPOSER_AUTH: GitHub respondió HTTP $code" ;;
        esac
    fi
    unset token code
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

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "==> --dry-run: no se modifica nada"

    if [ "${#repos_missing[@]}" -gt 0 ]; then
        echo "  Se clonarían:"
        for entry in "${repos_missing[@]}"; do
            echo "    ${entry%%|*}  <-  ${entry##*|}"
        done
    fi

    if [ "$deploy_root_exists" -eq 1 ]; then
        if git -C "$DEPLOY_ROOT" fetch origin "$DEPLOY_BRANCH" 2>&1 | sed 's/^/  /'; then
            ahead=$(git -C "$DEPLOY_ROOT" log HEAD..origin/"$DEPLOY_BRANCH" --oneline)
            if [ -n "$ahead" ]; then
                echo "  Commits nuevos en origin/$DEPLOY_BRANCH:"
                echo "$ahead" | sed 's/^/    /'
            else
                echo "  $DEPLOY_ROOT ya está al día con origin/$DEPLOY_BRANCH."
            fi
        else
            echo "  no se pudo hacer fetch en $DEPLOY_ROOT"
        fi
    fi

    if [ "$BUILD" -eq 1 ]; then
        echo "  Se correría: docker compose up -d --build ${SERVICES[*]:-}"
    else
        echo "  Se correría: docker compose up -d ${SERVICES[*]:-}"
    fi

    exit 0
fi

# =============================================================================
# FASE 2 - a partir de acá sí se modifica el sistema
# =============================================================================

code_changed=0

if [ "${#repos_missing[@]}" -gt 0 ] || [ "$deploy_root_exists" -eq 1 ]; then
    section "Código"

    for entry in "${repos_missing[@]}"; do
        path="${entry%%|*}"
        url="${entry##*|}"
        # git clone crea sólo el último nivel: el padre tiene que existir y
        # ser del usuario. Si lo creó Docker o un `sudo mkdir -p`, es de root.
        parent=$(dirname "$path")
        if [ ! -w "$parent" ]; then
            if sudo mkdir -p "$parent" && sudo chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$parent"; then
                ok "$parent ahora es de ${SUDO_USER:-$USER}"
            else
                fail "no se pudo dejar $parent escribible"
                continue
            fi
        fi
        if git clone "$url" "$path"; then
            ok "${path} clonado"
            code_changed=1
        else
            fail "no se pudo clonar ${path}"
        fi
    done

    if [ "$deploy_root_exists" -eq 1 ]; then
        before=$(git -C "$DEPLOY_ROOT" rev-parse HEAD)
        if ! git -C "$DEPLOY_ROOT" pull --ff-only origin "$DEPLOY_BRANCH"; then
            fail "git pull falló en $DEPLOY_ROOT"
            echo "           --ff-only rechaza un merge: si divergió, resolver a mano"
        else
            after=$(git -C "$DEPLOY_ROOT" rev-parse HEAD)
            if [ "$before" = "$after" ]; then
                ok "$DEPLOY_ROOT sin cambios (ya estaba al día)"
            else
                ok "$DEPLOY_ROOT actualizado $before -> $after"
                git -C "$DEPLOY_ROOT" log --oneline "${before}..${after}" | sed 's/^/           /'
                code_changed=1
            fi
        fi
    fi
fi

if [ "$fails" -gt 0 ]; then
    echo
    echo "==> Corto acá"
    echo "  $fails falla(s) clonando/actualizando código. Reviso antes de seguir."
    exit 1
fi

if [ "${#DATA_DIRS[@]}" -gt 0 ]; then
    section "Directorios en $ROOT"

    # `sudo mkdir -p` deja como root los niveles intermedios: ROOT tiene que
    # ser del usuario para que los REPOS se puedan clonar adentro.
    if [ ! -d "$ROOT" ] || [ ! -w "$ROOT" ]; then
        if sudo mkdir -p "$ROOT" && sudo chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$ROOT"; then
            ok "$ROOT listo (de ${SUDO_USER:-$USER})"
        else
            fail "no se pudo dejar $ROOT escribible"
        fi
    fi

    for dir in "${DATA_DIRS[@]}"; do
        path="${ROOT}/${dir}"
        if [ -d "$path" ] && [ -w "$path" ]; then
            ok "$path ya existe"
        elif [ -d "$path" ] && [[ " ${WRITABLE_DIRS[*]} " == *" $dir "* ]]; then
            # Los WRITABLE_DIRS son de www-data a propósito; se chequean abajo.
            ok "$path ya existe"
        elif [ -d "$path" ]; then
            # Suele ser Docker, que crea el bind mount como root si no existía:
            # después el rsync del deploy de la SPA falla con Permission denied.
            if sudo chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$path"; then
                ok "$path era de root, ahora es de ${SUDO_USER:-$USER}"
            else
                fail "$path no es escribible y no se pudo cambiar el dueño"
            fi
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
            if sudo chown -R www-data:www-data "$path"; then
                ok "$path ahora es de www-data"
            else
                warn "$path no es escribible por www-data"
                echo "           sudo chown -R www-data:www-data $path"
            fi
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

if [ "$fails" -gt 0 ]; then
    echo
    echo "==> Corto acá"
    echo "  $fails falla(s) preparando directorios/redes: no levanto el stack."
    exit 1
fi

section "Stack de ${PROJECT}"

up_args=(up -d)
[ "$BUILD" -eq 1 ] && up_args+=(--build)

# SERVICES vacío = todo el compose. Con servicios nombrados, los demás quedan
# intactos (así bin/linkedcode-auth.sh no toca linkedcode-www).
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

if [ "$fails" -gt 0 ]; then
    echo
    echo "==> Corto acá"
    echo "  $fails falla(s) levantando contenedores. No corro composer/migrate."
    exit 1
fi

# ------------------------------------------------------------ composer/migrate

if [ "$USES_COMPOSER" -eq 1 ] && [ -n "$MIGRATE_CONTAINER" ]; then
    section "composer install"

    # --no-dev: mismo criterio que el resto del stack, que corre en production.
    if ! dc composer install --no-dev -o --no-interaction; then
        fail "composer install falló en $MIGRATE_CONTAINER"
        exit 1
    fi
    ok "dependencias instaladas"

    if [ "$MIGRATE" -eq 1 ]; then
        section "Migraciones"

        if ! dc test -x vendor/bin/migrate; then
            warn "no hay vendor/bin/migrate en $MIGRATE_CONTAINER -- ¿el paquete linkedcode/infra está instalado?"
        else
            migrate_out=$(dc vendor/bin/migrate --dry-run 2>&1)
            migrate_status=$?

            if [ "$migrate_status" -ne 0 ]; then
                fail "vendor/bin/migrate --dry-run falló"
                echo "$migrate_out" | sed 's/^/           /'
                exit 1
            fi

            if echo "$migrate_out" | grep -q '^No hay migraciones pendientes'; then
                ok "sin migraciones pendientes"
            else
                echo "$migrate_out" | sed 's/^/           /'
                if ! dc vendor/bin/migrate; then
                    fail "vendor/bin/migrate falló -- revisar qué quedó aplicado antes de reintentar"
                    exit 1
                fi
                ok "migraciones aplicadas"
                code_changed=1
            fi
        fi
    fi
fi

# Pasos propios del proyecto, si los declaró.
if declare -F converge_extra >/dev/null; then
    section "Pasos propios de ${PROJECT}"
    converge_extra
fi

section "Reinicio"

# Idempotencia: si no hubo pull con commits nuevos, ni clone nuevo, ni migrate
# aplicado, ni --build, no hay nada que el `up -d` no haya resuelto ya solo
# (recrea el contenedor si cambió el compose). Reiniciar de más acá sólo corta
# el servicio sin necesidad.
if [ "$code_changed" -eq 1 ] || [ "$BUILD" -eq 1 ]; then
    if [ "$USES_COMPOSER" -eq 1 ] && [ -n "$MIGRATE_CONTAINER" ]; then
        # El cache de DI compilado queda con el código viejo embebido -- si no
        # se borra, el contenedor arranca sirviendo la versión anterior aunque
        # git y composer ya estén actualizados.
        dc rm -f var/cache/CompiledContainer.php 2>/dev/null || true
    fi

    for c in "${RESTART_CONTAINERS[@]}"; do
        if docker restart "$c" >/dev/null 2>&1; then
            ok "$c reiniciado"
        else
            fail "no se pudo reiniciar $c"
        fi
    done
else
    ok "sin cambios de código -- no hace falta reiniciar"
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

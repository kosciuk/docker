#!/bin/bash
#
# Motor común de los bin/deploy-<x>.sh.
#
# No se ejecuta directo: cada proyecto tiene un wrapper en bin/deploy-<x>.sh que
# hace `source` de su config en bin/projects/<x>.conf y después de este archivo.
# Es la misma config que usa setup-engine.sh -- un solo .conf por proyecto.
#
# A diferencia del setup, que converge el stack (crea lo que falta, levanta
# contenedores), esto asume que el stack YA está arriba y actualiza el código
# que corre adentro:
#
#   FASE 1 (sólo lectura)  verifica que el contenedor esté corriendo y que el
#                          repo no tenga cambios locales sin commitear. Si algo
#                          falla, corta sin haber tocado nada.
#   FASE 2 (modifica)      git pull, composer install, migraciones, reinicio.
#
# No es atómico: si migrate falla a mitad de camino, el código ya actualizado
# queda corriendo contra un schema viejo hasta que se resuelva a mano (el
# propio migrate avisa qué quedó aplicado). No hay rollback automático.
#
# ---------------------------------------------------------------------------
# Variables que puede declarar la config del proyecto (además de las de setup)
# ---------------------------------------------------------------------------
# Obligatoria:
#   PROJECT        (ya la declara la config para el setup)
#
# Opcionales (con su default entre paréntesis):
#   DEPLOY_ROOT     ruta del repo a actualizar         (primer path de REPOS,
#                                                        o ROOT si REPOS está vacío)
#   DEPLOY_CONTAINER contenedor donde correr composer/migrate ($PROJECT-api)
#   DEPLOY_BRANCH   rama a la que hacer pull            (main)
#   MIGRATE         1 si el proyecto corre vendor/bin/migrate (1)
#   RESTART_CONTAINERS contenedores a reiniciar al final ($DEPLOY_CONTAINER)
#
# Hooks opcionales: si la config define estas funciones, se llaman en su fase.
#   deploy_check_extra   chequeos propios del proyecto (fase 1, sólo lectura)
#   deploy_extra         pasos propios del proyecto, después de migrate (fase 2)
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"
: "${PROJECT:?la config del proyecto debe declarar PROJECT}"

# Reusa lo que ya declaró (o asumió por default) el .conf para el setup.
ROOT="${ROOT:-/var/www/${PROJECT}}"
declare -p REPOS >/dev/null 2>&1 || REPOS=()

if [ -n "${DEPLOY_ROOT:-}" ]; then
    :
elif [ "${#REPOS[@]}" -gt 0 ]; then
    DEPLOY_ROOT="${REPOS[0]%%|*}"
else
    DEPLOY_ROOT="$ROOT"
fi

DEPLOY_CONTAINER="${DEPLOY_CONTAINER:-${PROJECT}-api}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
MIGRATE="${MIGRATE:-1}"

declare -p RESTART_CONTAINERS >/dev/null 2>&1 || RESTART_CONTAINERS=("$DEPLOY_CONTAINER")

# ------------------------------------------------------------------ argumentos

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    "")        ;;
    *)         echo "uso: $0 [--dry-run]"; exit 2 ;;
esac

# -------------------------------------------------------------------- helpers

fails=0

ok()   { echo "  [ ok ]   $1"; }
fail() { echo "  [FALLA]  $1"; fails=$((fails + 1)); }
warn() { echo "  [ ojo ]  $1"; }
section() { echo; echo "==> $1"; }

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

dc() { docker exec -w /var/www/html "$DEPLOY_CONTAINER" "$@"; }

# =============================================================================
# FASE 1 - sólo lectura
# =============================================================================

section "Requisitos"

if ! running "$DEPLOY_CONTAINER"; then
    fail "$DEPLOY_CONTAINER no está corriendo"
    echo "           el deploy actualiza código en un contenedor ya levantado -- correr antes ./bin/setup-${PROJECT}.sh"
else
    ok "$DEPLOY_CONTAINER corriendo"
fi

if [ ! -d "$DEPLOY_ROOT/.git" ]; then
    fail "$DEPLOY_ROOT no es un repo git"
else
    ok "repo encontrado en $DEPLOY_ROOT"

    # Un pull sobre un working tree sucio puede fallar a mitad de camino o,
    # peor, mezclar el cambio local con lo que viene de git. Se corta antes.
    dirty=$(git -C "$DEPLOY_ROOT" status --porcelain)
    if [ -n "$dirty" ]; then
        fail "$DEPLOY_ROOT tiene cambios sin commitear"
        echo "$dirty" | sed 's/^/           /'
        echo "           commitear, descartar (git checkout --) o guardarlos (git stash) antes de deployar"
    else
        ok "working tree limpio"
    fi

    branch=$(git -C "$DEPLOY_ROOT" branch --show-current)
    if [ "$branch" != "$DEPLOY_BRANCH" ]; then
        fail "el repo está en '$branch', se esperaba '$DEPLOY_BRANCH'"
    else
        ok "en la rama $DEPLOY_BRANCH"
    fi
fi

if [ -d "$DEPLOY_ROOT/.git" ]; then
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

if running "$DEPLOY_CONTAINER"; then
    # COMPOSER_AUTH es el token que composer install usa adentro del
    # contenedor para bajar paquetes VCS de GitHub. Se prueba contra la API
    # sin instalar nada: un 401 ahí anticipa que composer install fallaría.
    auth_check=$(docker exec "$DEPLOY_CONTAINER" sh -c '
        [ -z "$COMPOSER_AUTH" ] && exit 2
        token=$(printf %s "$COMPOSER_AUTH" | sed -n "s/.*\"github-oauth\"[^{]*{[^}]*\"github.com\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")
        [ -z "$token" ] && exit 2
        code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $token" https://api.github.com/rate_limit)
        [ "$code" = "200" ] && exit 0 || exit 1
    ' 2>/dev/null; echo $?)

    case "$auth_check" in
        0) ok "COMPOSER_AUTH válido contra GitHub" ;;
        2) warn "COMPOSER_AUTH no definido o con formato inesperado -- no se pudo probar" ;;
        *) fail "COMPOSER_AUTH inválido o vencido (GitHub rechazó el token)" ;;
    esac
fi

if declare -F deploy_check_extra >/dev/null; then
    deploy_check_extra
fi

if [ "$fails" -gt 0 ]; then
    echo
    echo "==> Corto acá"
    echo "  $fails falla(s) en los chequeos. No modifiqué nada todavía."
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "==> --dry-run: no se modifica nada"

    if ! git -C "$DEPLOY_ROOT" fetch origin "$DEPLOY_BRANCH" 2>&1 | sed 's/^/  /'; then
        echo "  no se pudo hacer fetch"
        exit 1
    fi

    ahead=$(git -C "$DEPLOY_ROOT" log HEAD..origin/"$DEPLOY_BRANCH" --oneline)
    if [ -n "$ahead" ]; then
        echo "  Commits nuevos en origin/$DEPLOY_BRANCH:"
        echo "$ahead" | sed 's/^/    /'
    else
        echo "  Ya está al día con origin/$DEPLOY_BRANCH."
    fi
    exit 0
fi

# =============================================================================
# FASE 2 - a partir de acá sí se modifica el sistema
# =============================================================================

section "git pull"

before=$(git -C "$DEPLOY_ROOT" rev-parse HEAD)
if ! git -C "$DEPLOY_ROOT" pull --ff-only origin "$DEPLOY_BRANCH"; then
    fail "git pull falló"
    echo "           --ff-only rechaza un merge: si divergió, resolver a mano"
    exit 1
fi
after=$(git -C "$DEPLOY_ROOT" rev-parse HEAD)

if [ "$before" = "$after" ]; then
    ok "sin cambios (ya estaba al día)"
else
    ok "actualizado $before -> $after"
    git -C "$DEPLOY_ROOT" log --oneline "${before}..${after}" | sed 's/^/           /'
fi

section "composer install"

# --no-dev: mismo criterio que el resto del stack, que corre en production.
if ! dc composer install --no-dev -o --no-interaction; then
    fail "composer install falló"
    exit 1
fi
ok "dependencias instaladas"

if [ "$MIGRATE" -eq 1 ]; then
    section "Migraciones"

    if ! dc test -x vendor/bin/migrate; then
        warn "no hay vendor/bin/migrate en el contenedor -- ¿el paquete linkedcode/infra está instalado?"
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
        fi
    fi
fi

if declare -F deploy_extra >/dev/null; then
    section "Pasos propios de ${PROJECT}"
    deploy_extra
fi

section "Reinicio"

# El cache de DI compilado queda con el código viejo embebido -- si no se
# borra, el contenedor arranca sirviendo la versión anterior aunque git y
# composer ya estén actualizados.
dc rm -f var/cache/CompiledContainer.php 2>/dev/null || true

for c in "${RESTART_CONTAINERS[@]}"; do
    if docker restart "$c" >/dev/null 2>&1; then
        ok "$c reiniciado"
    else
        fail "no se pudo reiniciar $c"
    fi
done

section "Resumen"

if [ "$fails" -gt 0 ]; then
    echo "  $fails falla(s)"
    exit 1
fi

echo "  ${PROJECT} deployado."
exit 0

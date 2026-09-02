#!/bin/bash
#
# Errores recientes de cada sitio, agrupados y en una línea por error.
#
#   ./bin/errors.sh                    # todos los proyectos, últimas 24h
#   ./bin/errors.sh enforos            # sólo uno
#   ./bin/errors.sh enforos 2h         # otra ventana
#   ./bin/errors.sh --all              # sin agrupar: cada ocurrencia
#
# A diferencia de diagnose.sh, que sólo dice "hay N líneas con error", esto
# muestra CUÁLES. El objetivo es que entre en pantalla: de cada error se
# imprime la primera línea (mensaje + archivo), nunca el stack trace, y las
# repeticiones se cuentan en vez de repetirse.
#
# SÓLO LEE: docker logs y nada más. Se puede correr en producción.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

ONLY=""
SINCE="24h"
GROUP=1

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help|help) SHOW_HELP=1; shift ;;
        -a|--all)       GROUP=0; shift ;;
        # Una ventana es un número seguido de unidad; cualquier otra cosa es el
        # nombre del proyecto. Así el orden de los argumentos no importa.
        [0-9]*[smhd])   SINCE="$1"; shift ;;
        -*)             echo "Opción desconocida: $1"; exit 2 ;;
        *)              ONLY="$1"; shift ;;
    esac
done

list_projects() {
    local c
    for c in "$DOCKER"/bin/projects/*.conf; do
        [ -e "$c" ] || continue
        basename "$c" .conf
    done
}

usage() {
    cat <<EOF
Errores recientes de los contenedores de cada proyecto, agrupados.

  $(basename "$0")                  todos los proyectos, últimas 24h
  $(basename "$0") <proyecto>       sólo uno
  $(basename "$0") <proyecto> 2h    otra ventana (30m, 2h, 7d...)
  $(basename "$0") --all            sin agrupar: cada ocurrencia con su hora
  $(basename "$0") --help           esta ayuda

Proyectos disponibles:
EOF
    local n
    for n in $(list_projects); do
        printf '  %-24s %s\n' "$n" "$(sed -n '1s/^# *//p' "$DOCKER/bin/projects/$n.conf")"
    done
    cat <<EOF

Se imprime una línea por error (mensaje y archivo), sin stack trace. Para ver
el traceback completo de uno puntual:

  docker logs --since 1h <contenedor> | grep -A 20 '<fragmento del mensaje>'
EOF
}

if [ -n "${SHOW_HELP:-}" ]; then usage; exit 0; fi

if [ -n "$ONLY" ] && [ ! -f "$DOCKER/bin/projects/$ONLY.conf" ]; then
    echo "No existe el proyecto '$ONLY'."
    echo
    echo "Disponibles:"
    list_projects | sed 's/^/  /'
    echo
    echo "Ver '$(basename "$0") --help' para más detalle."
    exit 2
fi

if ! docker info >/dev/null 2>&1; then
    echo "No se puede hablar con el demonio de Docker."
    echo "¿está corriendo? ¿el usuario está en el grupo docker?"
    exit 1
fi

# Qué cuenta como error. Deliberadamente no incluye "warning" ni "notice": esto
# es para encontrar lo roto, no para auditar el código.
PATTERN='PHP (Fatal|Parse) error|Uncaught [A-Za-z\\]*(Exception|Error)|\[error\]|\[crit\]|\[alert\]|\[emerg\]|Segmentation fault|Allowed memory size'

# Las líneas de continuación de un stack trace de PHP y las de mod_php que
# repiten el mismo evento. Sacarlas es lo que hace legible la salida.
NOISE='^[[:space:]]*#[0-9]+|^[[:space:]]*thrown in|Stack trace:|^[[:space:]]*\{main\}'

# Deja el mensaje en una sola línea corta y sin las partes que cambian entre
# ocurrencias, para que dos veces el mismo error agrupen juntos.
normalize() {
    sed -E \
        -e 's/^\[[^]]*\] //' \
        -e 's/\[(pid|client) [^]]*\] //g' \
        -e 's/^[A-Z][a-z]{2} [A-Z][a-z]{2} [0-9 ]+[0-9:.]+ [0-9]{4} //' \
        -e 's/, referer:.*$//' \
        -e 's/0x[0-9a-f]+/0xADDR/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+/FECHA/g' \
        -e 's/[[:space:]]+/ /g' \
        -e 's/^ //; s/ $//'
}

report_container() {
    local c="$1" raw n
    raw=$(docker logs --since "$SINCE" "$c" 2>&1 \
          | grep -E "$PATTERN" \
          | grep -Ev "$NOISE") || true

    if [ -z "$raw" ]; then
        echo "  [ ok ]   $c — sin errores en $SINCE"
        return
    fi

    n=$(printf '%s\n' "$raw" | wc -l)
    echo "  [FALLA]  $c — $n línea(s) con error en $SINCE"

    if [ "$GROUP" -eq 0 ]; then
        printf '%s\n' "$raw" | cut -c1-160 | sed 's/^/             /'
        return
    fi

    # Agrupado: cuántas veces y el mensaje una sola vez. sort -rn deja arriba
    # el que más se repite, que casi siempre es el que hay que arreglar.
    printf '%s\n' "$raw" \
        | normalize \
        | sort | uniq -c | sort -rn \
        | head -12 \
        | while read -r count msg; do
              printf '             %4sx  %s\n' "$count" "$(printf '%s' "$msg" | cut -c1-140)"
          done

    local distintos
    distintos=$(printf '%s\n' "$raw" | normalize | sort -u | wc -l)
    [ "$distintos" -gt 12 ] && echo "             ... y $((distintos - 12)) mensaje(s) distinto(s) más"
}

echo "############ ERRORES — últimas $SINCE"

for conf in "$DOCKER"/bin/projects/*.conf; do
    name=$(basename "$conf" .conf)
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue

    (
        set +u
        # shellcheck source=/dev/null
        source "$conf"

        echo
        echo "==> $name"

        if [ -n "${CONTAINERS:-}" ]; then
            list=("${CONTAINERS[@]}")
        elif [ -n "${SERVICES:-}" ]; then
            list=(); for s in "${SERVICES[@]}"; do list+=("${PROJECT}-${s}"); done
        else
            echo "           (la config no declara SERVICES ni CONTAINERS)"
            exit 0
        fi

        for c in "${list[@]}"; do
            if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
                # Un contenedor caído no tiene errores "recientes" que valgan:
                # lo último que dijo antes de morir es lo que importa.
                echo "  [ ojo ]  $c NO está corriendo — últimas líneas:"
                docker logs --tail 5 "$c" 2>&1 | cut -c1-140 | sed 's/^/             /'
                continue
            fi
            report_container "$c"
        done
    )
done

echo
echo "############ FIN"
echo
echo "  Traceback completo de un error puntual:"
echo "    docker logs --since $SINCE <contenedor> | grep -A 20 '<fragmento>'"

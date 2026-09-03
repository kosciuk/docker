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
# Mira las tres capas que define la convención de logging (ver logging.xml),
# porque cada una ve lo que las otras no pueden ver:
#
#   app.log     Monolog. Excepciones de dominio con contexto. Es la capa útil:
#               un 500 mapeado por ProblemDetailsMiddleware llega acá y NUNCA
#               a Apache, porque la respuesta sale limpia.
#   error.log   Apache/PHP-FPM. Lo que pasa ANTES de llegar a la app: fatales,
#               parse errors, fcgi caído. Un fatal mata el proceso, así que
#               nunca llega a Monolog.
#   docker logs stdout del contenedor. Sólo como respaldo: lo que muere tan
#               temprano que no alcanza a escribir a ningún archivo.
#
# La salida pasa por redact(): IPs, mails, tokens, credenciales y user-agents
# se tachan antes de imprimir, así se puede pegar en un chat o un ticket. El
# archivo en disco queda intacto.
#
# SÓLO LEE. Se puede correr en producción con el sitio andando.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/redact.sh"

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
Errores recientes de cada proyecto, agrupados y sin stack trace.

  $(basename "$0")                  todos los proyectos, últimas 24h
  $(basename "$0") <proyecto>       sólo uno
  $(basename "$0") <proyecto> 2h    otra ventana (30m, 2h, 7d...)
  $(basename "$0") --all            sin agrupar: cada ocurrencia
  $(basename "$0") --help           esta ayuda

Se leen las tres capas de log de cada proyecto:
  app.log      excepciones de la app (Monolog) — la capa con más contexto
  error.log    Apache / PHP-FPM — fatales y errores previos a la app
  docker logs  respaldo, para lo que muere antes de escribir a archivo

Proyectos disponibles:
EOF
    local n
    for n in $(list_projects); do
        printf '  %-24s %s\n' "$n" "$(sed -n '1s/^# *//p' "$DOCKER/bin/projects/$n.conf")"
    done
    cat <<EOF

La salida va tachada (IPs, mails, tokens, credenciales): se puede compartir.

Para el traceback completo de un error puntual — SIN tachar, sale tal cual
está en disco, así que no pegarlo afuera sin leerlo antes:
  grep -A 20 '<fragmento del mensaje>' /var/www/<proyecto>/logs/app.log
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

ok()   { echo "  [ ok ]   $1"; }
bad()  { echo "  [FALLA]  $1"; }
hmm()  { echo "  [ ojo ]  $1"; }
info() { echo "           $1"; }

# Convierte la ventana (30m, 2h, 7d) a minutos, para `find -mmin`.
since_minutes() {
    local n="${SINCE%[smhd]}" u="${SINCE: -1}"
    case "$u" in
        s) echo $(( n / 60 + 1 )) ;;
        m) echo "$n" ;;
        h) echo $(( n * 60 )) ;;
        d) echo $(( n * 1440 )) ;;
        *) echo 1440 ;;
    esac
}

# Qué cuenta como error en cada capa. Separados a propósito: el formato de
# Monolog (app.ERROR:) y el de Apache ([error]) no se parecen en nada, y un
# patrón único obligaría a aflojarlo hasta que empiece a traer ruido.
PATTERN_APP='\.(ERROR|CRITICAL|ALERT|EMERGENCY):'
PATTERN_SYS='PHP (Fatal|Parse) error|Uncaught [A-Za-z\\]*(Exception|Error)|\[(error|crit|alert|emerg)\]|Segmentation fault|Allowed memory size'

# Líneas de continuación de un stack trace, y el ruido de dev que no es un
# problema del sitio (Xdebug intentando conectarse a un cliente que no está).
NOISE='^[[:space:]]*#[0-9]+|^[[:space:]]*thrown in|Stack trace:|^[[:space:]]*\{main\}|Xdebug: \[Step Debug\]'

# Deja el mensaje en una línea corta y sin las partes que cambian entre
# ocurrencias, para que dos veces el mismo error agrupen juntos.
normalize() {
    sed -E \
        -e 's/^\[[^]]*\] //' \
        -e 's/\[(pid|client) [^]]*\] //g' \
        -e 's/^[A-Z][a-z]{2} [A-Z][a-z]{2} [0-9 ]+[0-9:.]+ [0-9]{4} //' \
        -e 's/, referer:.*$//' \
        -e 's/"(exception|trace)":".*$//' \
        -e 's/0x[0-9a-f]+/0xADDR/g' \
        -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/UUID/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.+]+/FECHA/g' \
        -e 's/[[:space:]]+/ /g' \
        -e 's/^ //; s/ $//'
}

# Imprime las líneas ya filtradas: agrupadas con su contador, o todas.
render() {
    local raw="$1"

    if [ "$GROUP" -eq 0 ]; then
        printf '%s\n' "$raw" | redact | cut -c1-160 | sed 's/^/             /'
        return
    fi

    printf '%s\n' "$raw" \
        | redact \
        | normalize \
        | sort | uniq -c | sort -rn \
        | head -10 \
        | while read -r count msg; do
              printf '             %4sx  %s\n' "$count" "$(printf '%s' "$msg" | cut -c1-140)"
          done

    local distintos
    distintos=$(printf '%s\n' "$raw" | redact | normalize | sort -u | wc -l)
    [ "$distintos" -gt 10 ] && echo "             ... y $((distintos - 10)) mensaje(s) distinto(s) más"
}

# Una capa basada en archivo (app.log / error.log).
#
# Se filtra por antigüedad del archivo, no por la fecha de cada línea: los dos
# formatos fechan distinto y parsearlos sería frágil. La consecuencia hay que
# tenerla presente: si el archivo se tocó dentro de la ventana, se reportan
# TODAS sus líneas con error, también las más viejas. Para eso está el mtime en
# el encabezado de cada capa.
report_file_layer() {
    local label="$1" file="$2" pattern="$3" mins="$4"

    if [ ! -f "$file" ]; then
        info "$label: no existe ($file)"
        return
    fi

    if [ ! -r "$file" ]; then
        hmm "$label: sin permiso de lectura — probá con sudo"
        return
    fi

    local mtime
    mtime=$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null)

    if [ -z "$(find "$file" -mmin "-${mins}" 2>/dev/null)" ]; then
        info "$label: sin escrituras en $SINCE (última: ${mtime:-?})"
        return
    fi

    local raw n
    raw=$(grep -E "$pattern" "$file" 2>/dev/null | grep -Ev "$NOISE") || true

    if [ -z "$raw" ]; then
        ok "$label: sin errores (última escritura: ${mtime:-?})"
        return
    fi

    n=$(printf '%s\n' "$raw" | wc -l)
    bad "$label: $n línea(s) con error — última escritura: ${mtime:-?}"
    render "$raw"
}

# La capa de respaldo. Sólo interesa lo que no llegó a ningún archivo, así que
# un contenedor sin errores en stdout no se reporta: sería ruido.
report_docker_layer() {
    local c="$1" logs raw n

    local state
    state=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)

    # Un contenedor que no existe no es lo mismo que uno caído: suele ser un
    # nombre viejo en la conf, o un proyecto que todavía no se levantó acá.
    # Reportarlo como [FALLA] manda a buscar un incidente que no pasó.
    if [ -z "$state" ]; then
        info "docker/$c: no existe en este host"
        return
    fi

    if [ "$state" != "true" ]; then
        bad "docker/$c: NO está corriendo — últimas líneas antes de morir:"
        docker logs --tail 5 "$c" 2>&1 | redact | cut -c1-140 | sed 's/^/             /'
        return
    fi

    if ! logs=$(docker logs --since "$SINCE" "$c" 2>&1); then
        hmm "docker/$c: no se pudieron leer los logs"
        return
    fi

    raw=$(printf '%s\n' "$logs" | grep -E "$PATTERN_SYS" | grep -Ev "$NOISE") || true
    [ -z "$raw" ] && return

    n=$(printf '%s\n' "$raw" | wc -l)
    bad "docker/$c: $n línea(s) en stdout"
    render "$raw"
}

MINS=$(since_minutes)
have_docker=0
docker info >/dev/null 2>&1 && have_docker=1

echo "############ ERRORES — últimas $SINCE"

for conf in "$DOCKER"/bin/projects/*.conf; do
    name=$(basename "$conf" .conf)
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue

    (
        set +u
        # shellcheck source=/dev/null
        source "$conf"

        ROOT="${ROOT:-/var/www/${PROJECT}}"
        LOGS="${LOGS_DIR:-${ROOT}/logs}"

        echo
        echo "==> $name"

        # ---- capa de aplicación: la que más contexto tiene
        report_file_layer "app.log  " "${LOGS}/app.log"   "$PATTERN_APP" "$MINS"

        # ---- capa de infraestructura: fatales y lo previo a la app
        report_file_layer "error.log" "${LOGS}/error.log" "$PATTERN_SYS" "$MINS"

        # ---- respaldo: lo que murió antes de escribir a archivo
        if [ "$have_docker" -eq 1 ]; then
            if [ -n "${CONTAINERS:-}" ]; then
                list=("${CONTAINERS[@]}")
            elif [ -n "${SERVICES:-}" ]; then
                list=(); for s in "${SERVICES[@]}"; do list+=("${PROJECT}-${s}"); done
            else
                list=()
            fi
            for c in "${list[@]}"; do
                report_docker_layer "$c"
            done
        fi
    )
done

echo
echo "############ FIN"
echo
echo "  Lo de arriba va tachado (IPs, mails, tokens): se puede compartir."
echo
echo "  Traceback completo de un error puntual — SIN tachar:"
echo "    grep -A 20 '<fragmento>' /var/www/<proyecto>/logs/app.log"

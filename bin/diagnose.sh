#!/bin/bash
#
# Radiografía del VPS: junta en una sola corrida el estado de todo lo que
# suele hacer falta para diagnosticar un problema.
#
#   ./bin/diagnose.sh              # todos los proyectos
#   ./bin/diagnose.sh enforos      # sólo uno
#
# SÓLO LEE. No crea, no modifica, no levanta ni reinicia nada: se puede correr
# en producción con el sitio andando.
#
# Los secretos no se imprimen nunca. De cada uno se reporta si está definido y
# cuántos caracteres tiene, para poder detectar el que falta o el que quedó con
# un placeholder sin exponer el valor. La salida está pensada para pegar en un
# chat o un issue.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"
ONLY="${1:-}"

ok()   { echo "  [ ok ]   $1"; }
bad()  { echo "  [FALLA]  $1"; }
hmm()  { echo "  [ ojo ]  $1"; }
info() { echo "           $1"; }

section() { echo; echo "==> $1"; }
title()   { echo; echo "############ $1"; }

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

have_docker=0
docker info >/dev/null 2>&1 && have_docker=1

# Reporta un secreto sin mostrarlo: sólo si está y cuánto mide.
# Marca los placeholders conocidos, que son el error más común.
describe_secret() {
    local label="$1" value="$2"
    if [ -z "$value" ]; then
        bad "$label: vacío o sin definir"
    elif printf '%s' "$value" | grep -qE 'change[-_]?me|CAMBIAR|CHANGE_ME|ghp_xxx|GITHUB_PAT_AQUI|"TOKEN"|_AQUI|xxxx'; then
        bad "$label: quedó un placeholder (${#value} chars)"
    elif [ "${#value}" -lt 32 ]; then
        hmm "$label: definido pero corto (${#value} chars)"
    else
        ok "$label: definido (${#value} chars)"
    fi
}

# ---------------------------------------------------------------- host

title "HOST"

section "Sistema"
info "$(uname -sr)"
info "uptime: $(uptime -p 2>/dev/null || uptime)"

section "Disco"
df -h / /var 2>/dev/null | awk 'NR==1 || /\/(var)?$/ {printf "           %s\n", $0}'

# El disco lleno es causa frecuente de contenedores que no arrancan.
usage=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -n "$usage" ]; then
    if   [ "$usage" -ge 90 ]; then bad "raíz al ${usage}%"
    elif [ "$usage" -ge 75 ]; then hmm "raíz al ${usage}%"
    else                           ok  "raíz al ${usage}%"
    fi
fi

section "Memoria"
free -h 2>/dev/null | awk 'NR<=2 {printf "           %s\n", $0}'

# ------------------------------------------------------------- docker

title "DOCKER"

if [ "$have_docker" -eq 0 ]; then
    bad "no se puede hablar con el demonio de Docker"
    info "¿está corriendo? ¿el usuario está en el grupo docker?"
else
    ok "demonio accesible"

    section "Servicios compartidos"
    for svc in shared-mysql shared-gateway; do
        if running "$svc"; then
            ok "$svc — up $(docker inspect -f '{{.State.StartedAt}}' "$svc" 2>/dev/null | cut -dT -f1)"
        else
            bad "$svc NO está corriendo"
        fi
    done

    section "Todos los contenedores"
    docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Status}}' 2>/dev/null \
        | sort | awk -F'\t' '{printf "           %-32s %-10s %s\n", $1, $2, $3}'

    # Un contenedor que reinicia en loop suele ser config rota, no falta de
    # recursos: el conteo alto es la pista.
    section "Reinicios"
    docker ps -a --format '{{.Names}}' 2>/dev/null | while read -r c; do
        n=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null || echo 0)
        [ "${n:-0}" -gt 3 ] && echo "  [ ojo ]  $c reinició $n veces"
    done
    echo "           (sólo se listan los que superan 3)"

    section "Redes"
    for net in shared_services projects_public; do
        if docker network inspect "$net" >/dev/null 2>&1; then
            n=$(docker network inspect -f '{{len .Containers}}' "$net" 2>/dev/null)
            ok "$net — $n contenedor(es)"
        else
            bad "$net no existe"
        fi
    done
fi

# ----------------------------------------------------------- proyectos

for conf in "$DOCKER"/bin/projects/*.conf; do
    name=$(basename "$conf" .conf)
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue

    # Cada config se lee en un subshell para que sus variables no se pisen
    # entre proyectos (un PROJECT o un DB_NAME viejo daría un diagnóstico
    # equivocado en el siguiente).
    (
        set +u
        # shellcheck source=/dev/null
        source "$conf"

        title "PROYECTO: $name"

        ROOT="${ROOT:-/var/www/${PROJECT}}"
        COMPOSE="${COMPOSE:-${DOCKER}/projects/${PROJECT}/compose/web.yml}"
        ENV_FILE="${ENV_FILE:-${DOCKER}/projects/${PROJECT}/env/web.env}"

        section "Archivos"
        [ -f "$COMPOSE" ]  && ok "compose presente" || bad "falta $COMPOSE"
        if [ -f "$ENV_FILE" ]; then
            ok "web.env presente"
        else
            bad "falta $ENV_FILE"
        fi

        # ---- variables del env, sin exponer valores
        if [ -f "$ENV_FILE" ]; then
            section "Variables del env"
            for var in APP_ENV DB_HOST DB_NAME DB_USER; do
                v=$(sed -n "s/^${var}=//p" "$ENV_FILE" | tr -d '"'"'"'')
                [ -n "$v" ] && ok "$var = $v" || hmm "$var sin definir"
            done
            for var in DB_PASS JWT_SECRET SMTP_PASS_KEY COMPOSER_AUTH; do
                if grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
                    v=$(sed -n "s/^${var}=//p" "$ENV_FILE" | tr -d '"'"'"'')
                    describe_secret "$var" "$v"
                fi
            done
        fi

        # ---- código desplegado
        if [ -n "${REPOS:-}" ]; then
            section "Código"
            for entry in "${REPOS[@]}"; do
                path="${entry%%|*}"
                if [ -d "${path}/.git" ]; then
                    rev=$(git -C "$path" log -1 --format='%h %cd %s' --date=short 2>/dev/null | cut -c1-60)
                    ok "$(basename "$path"): $rev"
                    # Cambios sin commitear en el VPS suelen ser parches a mano
                    # que el próximo git pull o rsync se lleva puestos.
                    n=$(git -C "$path" status --short 2>/dev/null | wc -l)
                    [ "$n" -gt 0 ] && hmm "  con $n archivo(s) modificado(s) sin commitear"
                else
                    bad "$path no está clonado"
                fi
            done
        fi

        # ---- config.php: ya es opcional, pero si existe puede estar pisando el env
        app_config="${ROOT}/api/config/config.php"
        if [ -f "$app_config" ]; then
            section "config.php (opcional: pisa al env)"
            hmm "existe: $app_config"
            if grep -qE "'host'[[:space:]]*=>[[:space:]]*'(localhost|127\.0\.0\.1)'" "$app_config" 2>/dev/null; then
                bad "  apunta a localhost -> dentro del contenedor no hay MySQL ahí"
            fi
            grep -qE "'secret'" "$app_config" 2>/dev/null && info "  define un 'secret' propio"
        fi

        # ---- directorios de datos
        if [ -n "${DATA_DIRS:-}" ]; then
            section "Directorios"
            for d in "${DATA_DIRS[@]}"; do
                p="${ROOT}/${d}"
                if [ ! -d "$p" ]; then
                    bad "$p no existe"
                else
                    n=$(find "$p" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
                    sz=$(du -sh "$p" 2>/dev/null | cut -f1)
                    ok "$p — $n entrada(s), $sz"
                fi
            done
            for d in ${WRITABLE_DIRS:-}; do
                p="${ROOT}/${d}"
                [ -d "$p" ] || continue
                # La API corre como www-data: si no puede escribir, los uploads
                # fallan recién al subir la primera imagen.
                sudo -n -u www-data test -w "$p" 2>/dev/null \
                    && ok "$p escribible por www-data" \
                    || hmm "$p: no se pudo confirmar escritura de www-data"
            done
        fi

        # ---- contenedores del proyecto
        if [ "$have_docker" -eq 1 ] && [ -n "${SERVICES:-}" ]; then
            section "Contenedores"
            if [ -n "${CONTAINERS:-}" ]; then
                list=("${CONTAINERS[@]}")
            else
                list=(); for s in "${SERVICES[@]}"; do list+=("${PROJECT}-${s}"); done
            fi
            for c in "${list[@]}"; do
                if running "$c"; then
                    ok "$c corriendo"
                    # Los errores recientes suelen explicar el problema mejor
                    # que cualquier otro chequeo.
                    errs=$(docker logs --since 24h "$c" 2>&1 | grep -icE "fatal|exception|error" || true)
                    [ "${errs:-0}" -gt 0 ] && hmm "  $errs línea(s) con error/exception en 24h"
                else
                    bad "$c NO está corriendo"
                    docker logs --tail 3 "$c" 2>&1 | sed 's/^/             /' | cut -c1-100
                fi
            done
        fi

        # ---- base de datos
        if [ "$have_docker" -eq 1 ] && running shared-mysql && [ -f "$ENV_FILE" ]; then
            section "Base de datos"
            db=$(sed -n 's/^DB_NAME=//p' "$ENV_FILE" | tr -d '"'"'"'')
            db=${db:-${DB_NAME:-$PROJECT}}
            u=$(sed -n 's/^DB_USER=//p' "$ENV_FILE" | tr -d '"'"'"'')
            p=$(sed -n 's/^DB_PASS=//p' "$ENV_FILE" | tr -d '"'"'"'')
            if [ -z "$u" ] || [ -z "$p" ]; then
                hmm "sin credenciales en el env - no se verifica"
            elif docker exec shared-mysql mysql -u "$u" -p"$p" -e "USE \`$db\`" >/dev/null 2>&1; then
                n=$(docker exec shared-mysql mysql -u "$u" -p"$p" -N -B -e \
                    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db'" 2>/dev/null)
                ok "'$db' accesible — ${n:-?} tabla(s)"
            else
                bad "no se pudo entrar a '$db' con las credenciales del env"
            fi
        fi

        # ---- dns y certificado
        if [ -n "${DOMAIN:-}" ] && command -v dig >/dev/null 2>&1; then
            section "DNS"
            myip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)
            for sub in "" www. api. app. img.; do
                host="${sub}${DOMAIN}"
                ip=$(dig +short "$host" A 2>/dev/null | tail -1)
                if [ -z "$ip" ]; then
                    hmm "$host no resuelve"
                elif [ -n "$myip" ] && [ "$ip" = "$myip" ]; then
                    ok "$host → $ip"
                else
                    hmm "$host → $ip (este VPS: ${myip:-?})"
                fi
            done
        fi
    )
done

# ------------------------------------------------------------- systemd

title "SYSTEMD"

section "Units de docker"
# Casi todas son Type=oneshot: levantan el compose y terminan. Con
# RemainAfterExit=yes quedan "active exited" (normal, el stack está arriba); las
# que dispara un timer quedan "inactive dead" entre corridas (también normal).
# Lo que sí es problema es "failed".
systemctl list-units --type=service --all --no-legend 'docker-*' 2>/dev/null \
    | awk '{printf "           %-40s %s %s\n", $1, $3, $4}' || echo "           (sin acceso a systemctl)"
info ""
info "oneshot: 'active exited' = levantada; 'inactive dead' = espera su timer."
info "Preocupa 'failed'."

section "Timers"
# Un servicio disparado por timer se ve igual estando el timer activo o no: hay
# que mirar el timer, no el .service.
# La salida de list-timers es ancha y el nombre del timer queda al final, así
# que se reordena en vez de truncar la línea a lo bruto.
timers=$(systemctl list-timers --all --no-legend 'docker-*' 2>/dev/null)
if [ -n "$timers" ]; then
    printf '%s\n' "$timers" | awk '
        {
          # Reiniciar por línea: si no, un timer que nunca corrió hereda el
          # "hace X" del anterior y parece que sí corrió.
          t = ""; passed = "nunca"
          for (i = 1; i <= NF; i++) if ($i ~ /\.timer$/) { t = $i; break }
          left = $5                                    # LEFT, antes de la fecha de LAST
          for (i = 1; i <= NF; i++) if ($i == "ago") passed = $(i-1)
          printf "           %-34s próxima en %-8s última hace %s\n", t, left, passed
        }'
else
    hmm "no hay timers docker-* instalados"
fi

for unit in docker-ember-cron.timer; do
    if ! systemctl list-unit-files "$unit" >/dev/null 2>&1 \
       || ! systemctl list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
        bad "$unit NO está instalado"
        info "sin él la cola de emails no se procesa sola"
        info "sudo cp ${DOCKER}/systemd/${unit%.timer}.{service,timer} /etc/systemd/system/"
        info "sudo systemctl daemon-reload && sudo systemctl enable --now $unit"
    elif systemctl is-active --quiet "$unit"; then
        ok "$unit activo"
    else
        bad "$unit instalado pero NO activo"
        info "sudo systemctl enable --now $unit"
    fi
done

echo
echo "############ FIN"
echo
echo "  Sólo lectura: no se modificó nada."
echo "  Los secretos se reportan por largo, nunca por valor."

#!/bin/bash
#
# Limpieza de disco del VPS: libera lo que Docker y systemd acumulan solos.
#
#   ./bin/cleanup.sh              # muestra qué se liberaría, sin tocar nada
#   ./bin/cleanup.sh --apply      # ejecuta la limpieza
#
# Por defecto corre en seco (dry-run): imprime el tamaño de cada cosa y qué
# comando la borraría, pero no borra. Hay que pasar --apply explícitamente.
#
# Lo que limpia, en orden de cuánto suele recuperar:
#
#   1. Build cache de Docker  — capas intermedias de builds viejos. Es el que
#      más crece (llegó a 8.7 GB) y el más inofensivo: se regenera solo en el
#      próximo build, a costa de que ese build tarde más.
#   2. Journal de systemd     — se lo deja en 200 MB.
#   3. Imágenes sin contenedor— builds viejos que ya nadie corre.
#   4. Volúmenes sin links    — restos de stacks renombrados o dados de baja.
#
# Lo que NO toca, a propósito:
#
#   - Volúmenes en uso. En particular mysql_mysql_data y los del mailserver:
#     ahí viven las bases y los mails. Por eso este script nunca usa
#     `docker system prune --volumes`, que sí se los llevaría puestos.
#   - /var/www (el código) ni los logs de Apache de cada proyecto.
#   - Contenedores corriendo. No reinicia ni baja nada: se puede correr en
#     producción con los sitios andando.
#
set -uo pipefail

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

ok()   { echo "  [ ok ]   $1"; }
bad()  { echo "  [FALLA]  $1"; }
hmm()  { echo "  [ ojo ]  $1"; }
info() { echo "           $1"; }

section() { echo; echo "==> $1"; }

# En seco imprime el comando; con --apply lo ejecuta.
run() {
    if [ "$APPLY" = "1" ]; then
        info "\$ $*"
        "$@" 2>&1 | sed 's/^/           /'
    else
        info "\$ $*"
    fi
}

echo "############ Limpieza de disco"
if [ "$APPLY" = "1" ]; then
    echo
    hmm "Modo --apply: esto SÍ borra."
else
    echo
    info "Modo simulación. Nada se borra. Usar --apply para ejecutar."
fi

have_docker=0
docker info >/dev/null 2>&1 && have_docker=1
[ "$have_docker" = "1" ] || bad "docker no responde (¿falta sudo?). Se saltean sus secciones."

section "Espacio antes"
df -h / | sed 's/^/           /'

# --- 1. Build cache ----------------------------------------------------------
if [ "$have_docker" = "1" ]; then
    section "Build cache de Docker"
    cache=$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null \
            | awk -F'\t' '$1 == "Build Cache" {print $2}')
    info "En uso: ${cache:-desconocido}"
    run docker builder prune -a -f
fi

# --- 2. Journal --------------------------------------------------------------
section "Journal de systemd"
journalctl --disk-usage 2>/dev/null | sed 's/^/           /'
run journalctl --vacuum-size=200M

if [ -f /etc/systemd/journald.conf ] && ! grep -qE '^\s*SystemMaxUse=' /etc/systemd/journald.conf; then
    hmm "journald.conf no tiene SystemMaxUse: el journal va a volver a crecer."
    info "Agregar 'SystemMaxUse=200M' y reiniciar systemd-journald."
fi

# --- 3. Imágenes sin contenedor ----------------------------------------------
if [ "$have_docker" = "1" ]; then
    section "Imágenes sin contenedor"
    # Sólo las que ningún contenedor (ni corriendo ni parado) referencia.
    huerfanas=$(docker image ls --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' \
                --filter 'dangling=false' 2>/dev/null \
                | grep -v '^<none>' || true)
    if [ -z "$huerfanas" ]; then
        ok "No hay imágenes taggeadas."
    else
        en_uso=$(docker ps -a --format '{{.Image}}' 2>/dev/null | sort -u)
        encontradas=0
        while IFS=$'\t' read -r img size; do
            [ -n "$img" ] || continue
            # El tag :latest se omite en `docker ps`, hay que probar las dos formas.
            corto="${img%:latest}"
            if ! grep -qxF -e "$img" -e "$corto" <<< "$en_uso"; then
                hmm "$img ($size) — ningún contenedor la usa"
                encontradas=1
            fi
        done <<< "$huerfanas"
        [ "$encontradas" = "0" ] && ok "Todas las imágenes están en uso."
    fi
    info "Borrar las de arriba a mano: docker image rm <imagen>"
    info "(no se borran solas: una imagen sin contenedor puede ser una base"
    info " que se quiere conservar para no rebuildear desde cero)"

    # Las <none> sí son basura pura de builds interrumpidos.
    section "Capas dangling"
    run docker image prune -f
fi

# --- 4. Volúmenes sin links --------------------------------------------------
if [ "$have_docker" = "1" ]; then
    section "Volúmenes sin links"
    sueltos=$(docker volume ls -q --filter dangling=true 2>/dev/null)
    if [ -z "$sueltos" ]; then
        ok "No hay volúmenes sueltos."
    else
        while read -r vol; do
            [ -n "$vol" ] || continue
            hmm "$vol"
        done <<< "$sueltos"
        hmm "Revisar la lista antes de seguir: un volumen queda 'suelto' también"
        info "cuando su stack está momentáneamente bajado."
        run docker volume prune -f
    fi
fi

# --- 5. Rotación de logs de contenedores -------------------------------------
section "Rotación de logs de Docker"
if [ -f /etc/docker/daemon.json ] && grep -q 'max-size' /etc/docker/daemon.json; then
    ok "daemon.json tiene rotación configurada."
else
    hmm "Sin rotación: los logs de contenedor crecen sin límite."
    info "Crear /etc/docker/daemon.json con:"
    info '  { "log-driver": "json-file",'
    info '    "log-opts": { "max-size": "10m", "max-file": "3" } }'
    info "y reiniciar docker (reinicia todos los contenedores)."
fi

section "Espacio después"
df -h / | sed 's/^/           /'

echo
if [ "$APPLY" = "1" ]; then
    ok "Listo."
else
    info "Simulación terminada. Para ejecutar: ./bin/cleanup.sh --apply"
fi

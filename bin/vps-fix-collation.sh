#!/bin/bash
#
# Lleva las bases de los proyectos a utf8mb4 / utf8mb4_0900_ai_ci: el default
# de la base y todas las tablas (con sus columnas) que tengan otra collation.
#
#   ./bin/vps-fix-collation.sh                    # muestra qué cambiaría
#   ./bin/vps-fix-collation.sh enforos            # sólo un proyecto
#   ./bin/vps-fix-collation.sh --apply            # ejecuta
#   ./bin/vps-fix-collation.sh --apply enforos    # combinables
#
# Por defecto corre en seco: lista base por base qué tablas convertiría, sin
# tocar nada. Hay que pasar --apply explícitamente.
#
# Con --apply, antes de tocar cada base se hace un mysqldump comprimido en
# ~/backups/. Si el dump falla, esa base no se toca.
#
# ALTER TABLE ... CONVERT reescribe la tabla entera y la bloquea mientras
# tanto: en tablas chicas es un instante, en una grande puede tardar. Correrlo
# con poco tráfico.
#
# Las FOREIGN KEY se desactivan durante la conversión (en la misma sesión): si
# no, convertir una tabla referenciada antes que la que la referencia falla con
# "incompatible columns". Al terminar, todas quedan en la misma collation.
#
# Se conecta como root dentro del contenedor, con la clave que ya tiene en su
# entorno: no se lee ningún .env y la clave no sale del contenedor.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"
WANT_CS=utf8mb4
WANT_CO=utf8mb4_0900_ai_ci
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"

APPLY=0
ONLY=""
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)       ONLY="$arg" ;;
    esac
done

ok()   { echo "  [ ok ]   $1"; }
bad()  { echo "  [FALLA]  $1"; }
hmm()  { echo "  [ ojo ]  $1"; }
info() { echo "           $1"; }
section() { echo; echo "==> $1"; }

if [ -n "$ONLY" ] && [ ! -f "$DOCKER/bin/projects/$ONLY.conf" ]; then
    echo "No existe el proyecto '$ONLY'. Disponibles:"
    for c in "$DOCKER"/bin/projects/*.conf; do echo "  $(basename "$c" .conf)"; done
    exit 2
fi

if [ "$(docker inspect -f '{{.State.Running}}' shared-mysql 2>/dev/null)" != "true" ]; then
    bad "shared-mysql no está corriendo"
    exit 1
fi

q() {
    docker exec -i shared-mysql sh -c \
        'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B 2>/dev/null' <<<"$1"
}

# Igual que q, pero con los errores: para el ALTER, donde hace falta ver por
# qué falló. El aviso de "password on the command line" se filtra al mostrar.
q_err() {
    docker exec -i shared-mysql sh -c \
        'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B 2>&1' <<<"$1"
}

# Una base por proyecto: DB_NAME del .conf, o el nombre del proyecto. Varios
# .conf pueden compartir base; se procesa una sola vez.
declare -A seen=()
dbs=()
for conf in "$DOCKER"/bin/projects/*.conf; do
    name=$(basename "$conf" .conf)
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
    db=$( set +u; source "$conf"; echo "${DB_NAME:-$PROJECT}" )
    [ -n "$db" ] && [ -z "${seen[$db]:-}" ] || continue
    seen[$db]=1
    dbs+=("$db")
done

[ "$APPLY" -eq 1 ] && mkdir -p "$BACKUP_DIR"

fails=0
changed=0

for db in "${dbs[@]}"; do
    section "$db"

    read -r cs co < <(q "SELECT default_character_set_name, default_collation_name
                           FROM information_schema.schemata WHERE schema_name='$db'")
    if [ -z "${cs:-}" ]; then
        info "no existe en shared-mysql (el proyecto no usa base, o todavía no se creó)"
        continue
    fi

    tables=$(q "SELECT table_name, table_collation FROM information_schema.tables
                 WHERE table_schema='$db' AND table_type='BASE TABLE'
                   AND table_collation <> '$WANT_CO'
                 ORDER BY table_name")
    # Columnas desalineadas en tablas cuyo default ya está bien: el CONVERT
    # también las arregla.
    tables_cols=$(q "SELECT DISTINCT c.table_name FROM information_schema.columns c
                      JOIN information_schema.tables t
                        ON t.table_schema = c.table_schema AND t.table_name = c.table_name
                     WHERE c.table_schema='$db' AND t.table_type='BASE TABLE'
                       AND c.collation_name IS NOT NULL AND c.collation_name <> '$WANT_CO'
                       AND t.table_collation = '$WANT_CO'
                     ORDER BY c.table_name")

    db_ok=0
    [ "$cs" = "$WANT_CS" ] && [ "$co" = "$WANT_CO" ] && db_ok=1

    if [ "$db_ok" -eq 1 ] && [ -z "$tables" ] && [ -z "$tables_cols" ]; then
        ok "todo en $WANT_CS / $WANT_CO"
        continue
    fi

    [ "$db_ok" -eq 1 ] && ok "base en $co" || hmm "base en $cs / $co"
    to_convert=()
    if [ -n "$tables" ]; then
        while IFS=$'\t' read -r t tco; do
            hmm "tabla $t en $tco"
            to_convert+=("$t")
        done <<<"$tables"
    fi
    if [ -n "$tables_cols" ]; then
        while read -r t; do
            hmm "tabla $t tiene columnas con otra collation"
            to_convert+=("$t")
        done <<<"$tables_cols"
    fi

    sql="SET FOREIGN_KEY_CHECKS=0;
ALTER DATABASE \`$db\` CHARACTER SET $WANT_CS COLLATE $WANT_CO;"
    for t in "${to_convert[@]}"; do
        sql+="
ALTER TABLE \`$db\`.\`$t\` CONVERT TO CHARACTER SET $WANT_CS COLLATE $WANT_CO;"
    done
    sql+="
SET FOREIGN_KEY_CHECKS=1;"

    if [ "$APPLY" -eq 0 ]; then
        info "se convertiría: base + ${#to_convert[@]} tabla(s)"
        continue
    fi

    backup="$BACKUP_DIR/${db}-antes-collation-$(date +%Y%m%d-%H%M%S).sql.gz"
    if docker exec shared-mysql sh -c \
           'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers "$1" 2>/dev/null' \
           _ "$db" | gzip >"$backup" \
       && [ "$(gzip -dc "$backup" | head -c 1000 | wc -c)" -gt 0 ]; then
        ok "backup en $backup ($(du -h "$backup" | cut -f1))"
    else
        bad "no se pudo hacer el backup -- no se toca $db"
        rm -f "$backup"
        fails=$((fails + 1))
        continue
    fi

    out=$(q_err "$sql")
    if [ -z "$out" ] || ! grep -q "ERROR" <<<"$out"; then
        ok "convertida: base + ${#to_convert[@]} tabla(s)"
        changed=$((changed + 1))
    else
        bad "falló la conversión de $db"
        grep -v "Using a password" <<<"$out" | sed 's/^/           /'
        info "lo convertido hasta el error quedó; el backup está en $backup"
        fails=$((fails + 1))
    fi
done

echo
if [ "$APPLY" -eq 0 ]; then
    echo "  Simulación: no se modificó nada. Para ejecutar: $(basename "$0") --apply ${ONLY}"
else
    echo "  $changed base(s) convertida(s), $fails falla(s)."
fi
[ "$fails" -eq 0 ]

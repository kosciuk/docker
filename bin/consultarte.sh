#!/bin/bash
#
# Converge consultarte en el VPS: crea lo que falte (dirs, redes,
# clona el repo si no existe) y actualiza el código a lo último (git pull,
# composer install, migraciones), en una sola corrida idempotente.
#
#   ./bin/consultarte.sh              # converge y actualiza (sin rebuild)
#   ./bin/consultarte.sh --build      # además reconstruye las imágenes
#   ./bin/consultarte.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/engine.sh; lo propio de este proyecto, en
# bin/projects/consultarte.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/consultarte.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/engine.sh"

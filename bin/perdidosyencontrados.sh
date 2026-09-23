#!/bin/bash
#
# Converge perdidosyencontrados en el VPS: crea lo que falte (dirs, redes,
# clona el repo si no existe) y actualiza el código a lo último (git pull,
# composer install, migraciones), en una sola corrida idempotente.
#
#   ./bin/perdidosyencontrados.sh              # converge y actualiza (sin rebuild)
#   ./bin/perdidosyencontrados.sh --build      # además reconstruye las imágenes
#   ./bin/perdidosyencontrados.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/engine.sh; lo propio de este proyecto, en
# bin/projects/perdidosyencontrados.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/perdidosyencontrados.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/engine.sh"

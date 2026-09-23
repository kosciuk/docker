#!/bin/bash
#
# Converge granhermano.com.ar en el VPS: clona/actualiza www (git pull) y
# levanta el contenedor, en una sola corrida idempotente. Reemplaza a los
# viejos reload-granhermano.sh, restart-granhermano.sh y status-granhermano.sh.
#
#   ./bin/granhermano.sh              # converge y actualiza (sin rebuild)
#   ./bin/granhermano.sh --build      # además reconstruye la imagen
#   ./bin/granhermano.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/engine.sh; lo propio de este proyecto, en
# bin/projects/granhermano.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/granhermano.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/engine.sh"

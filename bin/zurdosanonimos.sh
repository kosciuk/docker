#!/bin/bash
#
# Converge zurdosanonimos.com.ar en el VPS: clona/actualiza www (git pull) y
# levanta el contenedor, en una sola corrida idempotente. Reemplaza a los
# viejos reload-zurdosanonimos.sh, restart-zurdosanonimos.sh y
# status-zurdosanonimos.sh.
#
#   ./bin/zurdosanonimos.sh              # converge y actualiza (sin rebuild)
#   ./bin/zurdosanonimos.sh --build      # además reconstruye la imagen
#   ./bin/zurdosanonimos.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/engine.sh; lo propio de este proyecto, en
# bin/projects/zurdosanonimos.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/zurdosanonimos.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/engine.sh"

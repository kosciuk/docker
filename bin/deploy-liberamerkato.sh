#!/bin/bash
#
# Deploy de liberamerkato en el VPS: actualiza el código que ya está arriba
# (git pull + composer install + migraciones + reinicio). No crea nada -- para
# eso está ./bin/setup-liberamerkato.sh.
#
#   ./bin/deploy-liberamerkato.sh              # aplica
#   ./bin/deploy-liberamerkato.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/deploy-engine.sh; lo propio de este proyecto, en
# bin/projects/liberamerkato.conf (el mismo .conf que usa el setup).
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/liberamerkato.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/deploy-engine.sh"

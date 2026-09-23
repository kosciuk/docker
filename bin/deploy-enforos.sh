#!/bin/bash
#
# Deploy de enforos en el VPS: actualiza el código que ya está arriba (git
# pull + composer install + migraciones + reinicio). No crea nada -- para eso
# está ./bin/setup-enforos.sh.
#
#   ./bin/deploy-enforos.sh              # aplica
#   ./bin/deploy-enforos.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/deploy-engine.sh; lo propio de este proyecto, en
# bin/projects/enforos.conf (el mismo .conf que usa el setup).
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/enforos.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/deploy-engine.sh"

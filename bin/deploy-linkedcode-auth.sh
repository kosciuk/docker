#!/bin/bash
#
# Deploy de auth.linkedcode.com en el VPS: actualiza el código que ya está
# arriba (git pull + composer install + migraciones + reinicio). No crea nada
# -- para eso está ./bin/setup-linkedcode-auth.sh.
#
#   ./bin/deploy-linkedcode-auth.sh              # aplica
#   ./bin/deploy-linkedcode-auth.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/deploy-engine.sh; lo propio de este proyecto, en
# bin/projects/linkedcode-auth.conf (el mismo .conf que usa el setup).
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/linkedcode-auth.conf"

# linkedcode-auth y linkedcode-www comparten PROJECT="linkedcode" (mismo
# compose), así que el default del engine (contenedor $PROJECT-api) no sirve:
# se nombra explícito para no tocar linkedcode-www.
DEPLOY_ROOT="/var/www/linkedcode/auth.linkedcode.com"
DEPLOY_CONTAINER="linkedcode-auth"

# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/deploy-engine.sh"

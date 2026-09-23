#!/bin/bash
#
# Deploy de ember en el VPS: actualiza el código que ya está arriba (git pull
# + composer install + migraciones + reinicio). No crea nada -- para eso está
# ./bin/setup-ember.sh.
#
#   ./bin/deploy-ember.sh              # aplica
#   ./bin/deploy-ember.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/deploy-engine.sh; lo propio de este proyecto, en
# bin/projects/ember.conf (el mismo .conf que usa el setup).
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/ember.conf"

# El contenedor se llama ember-app (SERVICES=(app) en el .conf), no
# ember-api: el default del engine no sirve acá.
DEPLOY_CONTAINER="ember-app"

# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/deploy-engine.sh"

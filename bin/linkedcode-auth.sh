#!/bin/bash
#
# Converge linkedcode-auth (auth.linkedcode.com) en el VPS: crea lo que falte
# (dirs, redes, clona el repo si no existe) y actualiza el código a lo último
# (git pull, composer install, migraciones), en una sola corrida idempotente.
#
#   ./bin/linkedcode-auth.sh              # converge y actualiza (sin rebuild)
#   ./bin/linkedcode-auth.sh --build      # además reconstruye las imágenes
#   ./bin/linkedcode-auth.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/engine.sh; lo propio de este proyecto, en
# bin/projects/linkedcode-auth.conf.
#
# Chequeo profundo aparte (mod_remoteip, cookies, permisos de claves):
#   ./bin/check-linkedcode-auth.sh
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/linkedcode-auth.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/engine.sh"

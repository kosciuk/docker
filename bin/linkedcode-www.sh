#!/bin/bash
#
# Converge linkedcode-www (www.linkedcode.com) en el VPS: crea lo que falte
# (dirs, redes) y levanta el contenedor. No usa composer: es sólo el build
# estático de Vue, así que esta corrida no clona ni actualiza código -- el
# build se sube a mano (ver REQUIRED_FILES en el .conf).
#
#   ./bin/linkedcode-www.sh              # converge (sin rebuild)
#   ./bin/linkedcode-www.sh --build      # además reconstruye las imágenes
#   ./bin/linkedcode-www.sh --dry-run    # sólo muestra qué cambiaría
#
# La lógica está en bin/lib/engine.sh; lo propio de este proyecto, en
# bin/projects/linkedcode-www.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/linkedcode-www.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/engine.sh"

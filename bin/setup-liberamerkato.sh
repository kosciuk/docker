#!/bin/bash
#
# Setup de liberamerkato en el VPS.
#
#   ./bin/setup-liberamerkato.sh            # converge el stack (sin rebuild)
#   ./bin/setup-liberamerkato.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/liberamerkato.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/liberamerkato.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

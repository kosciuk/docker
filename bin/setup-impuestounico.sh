#!/bin/bash
#
# Setup de impuestounico en el VPS.
#
#   ./bin/setup-impuestounico.sh            # converge el stack (sin rebuild)
#   ./bin/setup-impuestounico.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/impuestounico.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/impuestounico.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

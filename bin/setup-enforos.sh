#!/bin/bash
#
# Setup de enforos en el VPS.
#
#   ./bin/setup-enforos.sh            # converge el stack (sin rebuild)
#   ./bin/setup-enforos.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/enforos.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/enforos.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

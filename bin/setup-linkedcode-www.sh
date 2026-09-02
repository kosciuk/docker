#!/bin/bash
#
# Setup de linkedcode-www en el VPS.
#
#   ./bin/setup-linkedcode-www.sh            # converge el stack (sin rebuild)
#   ./bin/setup-linkedcode-www.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/linkedcode-www.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/linkedcode-www.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

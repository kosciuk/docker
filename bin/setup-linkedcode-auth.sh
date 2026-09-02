#!/bin/bash
#
# Setup de linkedcode-auth en el VPS.
#
#   ./bin/setup-linkedcode-auth.sh            # converge el stack (sin rebuild)
#   ./bin/setup-linkedcode-auth.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/linkedcode-auth.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/linkedcode-auth.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

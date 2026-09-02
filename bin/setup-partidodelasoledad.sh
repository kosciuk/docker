#!/bin/bash
#
# Setup de partidodelasoledad en el VPS.
#
#   ./bin/setup-partidodelasoledad.sh            # converge el stack (sin rebuild)
#   ./bin/setup-partidodelasoledad.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/partidodelasoledad.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/partidodelasoledad.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

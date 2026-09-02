#!/bin/bash
#
# Setup de cooperativismoabierto en el VPS.
#
#   ./bin/setup-cooperativismoabierto.sh            # converge el stack (sin rebuild)
#   ./bin/setup-cooperativismoabierto.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/cooperativismoabierto.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/cooperativismoabierto.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

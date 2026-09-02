#!/bin/bash
#
# Setup de perdidosyencontrados en el VPS.
#
#   ./bin/setup-perdidosyencontrados.sh            # converge el stack (sin rebuild)
#   ./bin/setup-perdidosyencontrados.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/perdidosyencontrados.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/perdidosyencontrados.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

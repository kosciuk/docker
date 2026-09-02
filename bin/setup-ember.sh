#!/bin/bash
#
# Setup de ember en el VPS.
#
#   ./bin/setup-ember.sh            # converge el stack (sin rebuild)
#   ./bin/setup-ember.sh --build    # además reconstruye las imágenes
#
# La lógica está en bin/lib/setup-engine.sh; lo propio de este proyecto, en
# bin/projects/ember.conf.
#
set -uo pipefail

DOCKER="${DOCKER:-/var/www/docker}"

# shellcheck source=/dev/null
source "${DOCKER}/bin/projects/ember.conf"
# shellcheck source=/dev/null
source "${DOCKER}/bin/lib/setup-engine.sh"

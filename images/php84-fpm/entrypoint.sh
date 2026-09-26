#!/bin/sh
set -e

mkdir -p /run/php
chown www-data:www-data /run/php

git config --global --add safe.directory /var/www/html

if [ -d /var/www/html/var/cache ]; then
    chown -R www-data:www-data /var/www/html/var/cache
fi

if [ -f /var/www/html/composer.json ] && [ ! -f /var/www/html/vendor/autoload.php ]; then
    # Sólo pasa en el primer arranque (volumen vendor vacío). Si falla no se
    # corta: con set -e el contenedor moría y quedaba en loop de reinicios,
    # sin poder hacerle docker exec. bin/<proyecto>.sh corre composer install
    # después de levantarlo y ahí reporta el error. Se vacía la caché porque
    # sobrevive a los reinicios: un zip corrupto se reintentaba siempre igual.
    echo "Running composer install..."
    if ! composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --working-dir=/var/www/html; then
        echo "composer install falló; el contenedor sigue arriba sin vendor completo." >&2
        composer clear-cache >/dev/null 2>&1 || true
    fi
fi

php-fpm -D

exec "$@"

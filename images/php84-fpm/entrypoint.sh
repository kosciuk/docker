#!/bin/sh
set -e

mkdir -p /run/php
chown www-data:www-data /run/php

if [ -d /var/www/html/var/cache ]; then
    chown -R www-data:www-data /var/www/html/var/cache
fi

if [ -f /var/www/html/composer.json ] && [ ! -f /var/www/html/vendor/autoload.php ]; then
    echo "Running composer install..."
    composer install --no-interaction --prefer-dist --optimize-autoloader --working-dir=/var/www/html
fi

php-fpm -D

exec "$@"

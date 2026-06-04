#!/bin/sh
set -e

if [ -f /var/www/html/composer.json ] && [ ! -f /var/www/html/vendor/autoload.php ]; then
    echo "Running composer install..."
    composer install --no-interaction --prefer-dist --optimize-autoloader --working-dir=/var/www/html
fi

exec docker-php-entrypoint "$@"

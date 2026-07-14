FROM php:8.4-fpm

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 \
        curl \
        git \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        unzip \
        zip; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" \
        gd \
        intl \
        opcache \
        pdo_mysql \
        zip; \
    pecl install apcu; \
    docker-php-ext-enable apcu; \
    a2enmod rewrite headers expires proxy proxy_fcgi; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark apache2 curl git unzip zip; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*; \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY images/php84-fpm/vhost.conf /etc/apache2/sites-available/000-default.conf
COPY images/php84-fpm/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY images/php84-fpm/zz-app.ini /usr/local/etc/php/conf.d/zz-app.ini
COPY images/php84-fpm/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

ENTRYPOINT ["entrypoint.sh"]
CMD ["apache2ctl", "-D", "FOREGROUND"]

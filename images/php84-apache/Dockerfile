FROM php:8.4-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        unzip \
        zip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        gd \
        intl \
        opcache \
        pdo_mysql \
        zip \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && a2enmod rewrite headers expires \
    && rm -rf /var/lib/apt/lists/*

COPY images/php84-apache/vhost.conf /etc/apache2/sites-available/000-default.conf

WORKDIR /var/www/html

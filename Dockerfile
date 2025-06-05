# Multi-stage build for Yii2 application
FROM composer:2.5 AS composer

WORKDIR /app
COPY yii2-app/composer.json yii2-app/composer.lock* ./
RUN composer install --no-dev --optimize-autoloader --no-scripts

FROM php:8.2-fpm-alpine

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev \
    icu-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        pdo_mysql \
        mysqli \
        zip \
        intl \
        opcache

# Install Yii2 framework
RUN composer global require "fxp/composer-asset-plugin:^1.2.0" --no-plugins

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY yii2-app/ .
COPY --from=composer /app/vendor ./vendor

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && chmod -R 777 runtime web/assets

# PHP configuration
COPY config/php.ini /usr/local/etc/php/conf.d/custom.ini

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

# Expose port
EXPOSE 9000

# Start PHP-FPM
CMD ["php-fpm"]
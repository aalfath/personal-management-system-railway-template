# Personal Management System (Volmarg) for Railway: Symfony API + prebuilt Vue frontend in one service.
# Upstream publishes no container image, so this builds the official PHP-FPM image (pinned by version
# and digest) with the upstream v2.1.0 release commits (pinned by commit and sha256) on top.
# To update: bump PMS_*_COMMIT and their sha256 (and the PHP pin if needed), add a CHANGELOG.md entry.
FROM php:8.4.28-fpm@sha256:495ab94788034640ddd6fb313476e75570261622c42704e5ae02047b8d934ea0

ARG PMS_VERSION=2.1.0
# github.com/Volmarg/personal-management-system tag v2.1.0
ARG PMS_BACKEND_COMMIT=6bbeb0217468a3a36ed1d58149eb1d81d485f4f7
ARG PMS_BACKEND_SHA256=92f707ae89ca4b937bd1d889650f8cba93f0950d98ef6b5dedcbb0b314d5d4e7
# github.com/Volmarg/personal-management-system-front tag v2.1.0 (ships the built dist/)
ARG PMS_FRONTEND_COMMIT=f16eb6dbdb81b0d5d47b99929e5336980629366d
ARG PMS_FRONTEND_SHA256=d27ab0d8fff54b48cc4f73c9c71eba7030b1d8c8cd19437814e49a2894aa2b6e
ARG APCU_VERSION=5.1.28

COPY --from=composer:2.9.8@sha256:b09bccd91a78fe8a9ab4b33d707b862e8fe54fec17782e32683ad2a69c46867d /usr/bin/composer /usr/local/bin/composer

# PHP extensions the app needs (gd, intl, pdo_mysql, zip, apcu); build dependencies are removed again.
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends $PHPIZE_DEPS libicu-dev libzip-dev libpng-dev \
        libjpeg62-turbo-dev libwebp-dev libfreetype-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl pdo_mysql zip; \
    pecl install "apcu-${APCU_VERSION}"; \
    docker-php-ext-enable apcu; \
    rm -rf /tmp/pear; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
    find /usr/local -type f -executable -exec ldd '{}' ';' 2>/dev/null \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u | xargs -r dpkg-query --search | cut -d: -f1 | sort -u | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get install -y --no-install-recommends nginx unzip git; \
    rm -rf /var/lib/apt/lists/*; \
    php -m | grep -qi apcu; php -m | grep -qi gd; php -m | grep -qi intl; php -m | grep -qi pdo_mysql; php -m | grep -qi zip

# Upstream code, checked against its sha256.
RUN set -eux; \
    curl -fsSL "https://codeload.github.com/Volmarg/personal-management-system/tar.gz/${PMS_BACKEND_COMMIT}" -o /tmp/backend.tgz; \
    echo "${PMS_BACKEND_SHA256}  /tmp/backend.tgz" | sha256sum -c -; \
    curl -fsSL "https://codeload.github.com/Volmarg/personal-management-system-front/tar.gz/${PMS_FRONTEND_COMMIT}" -o /tmp/frontend.tgz; \
    echo "${PMS_FRONTEND_SHA256}  /tmp/frontend.tgz" | sha256sum -c -; \
    mkdir -p /app /srv/front /tmp/front; \
    tar -xzf /tmp/backend.tgz -C /app --strip-components=1; \
    tar -xzf /tmp/frontend.tgz -C /tmp/front --strip-components=1; \
    cp -a /tmp/front/dist/. /srv/front/; \
    rm -rf /tmp/backend.tgz /tmp/frontend.tgz /tmp/front

WORKDIR /app

# Dependencies exactly as locked upstream (upstream installs them the same way, dev packages included).
RUN set -eux; \
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-interaction --no-progress --ignore-platform-reqs --optimize-autoloader; \
    rm -rf /root/.composer /root/.cache /app/composer.phar /app/docker /app/private /app/.opencode /app/github

# Per-instance secrets instead of the keys upstream ships to everyone:
# - the frontend calls the API on the same origin under /api (upstream: port 8002 on the same host);
# - the JWT key pair and the encryption key live on the volume and are generated on the first boot;
# - uploads live on the volume; only the system contact icons are kept as seed data (no demo files).
RUN set -eux; \
    js="$(grep -l 'VITE_BACKEND_BASE_URL:"8002"' /srv/front/assets/index.*.js)"; \
    sed -i 's#VITE_BACKEND_BASE_URL:"8002"#VITE_BACKEND_BASE_URL:"/api"#g' "$js"; \
    grep -q 'VITE_BACKEND_BASE_URL:"/api"' "$js"; \
    cp "$js" /srv/front-index.js.orig; echo "$js" > /srv/front-index.path; \
    find /srv/front -name '*.gz' -delete; \
    cp /app/config/jwt/prod/public.pem /srv/default-jwt-public.pem; \
    rm -rf /app/config/jwt/prod; ln -s /data/jwt /app/config/jwt/prod; \
    rm /app/config/packages/config/encryption.yaml; \
    ln -s /data/config/encryption.yaml /app/config/packages/config/encryption.yaml; \
    mkdir -p /srv/seed/upload/images; \
    cp -a /app/public/upload/images/system /srv/seed/upload/images/; \
    rm -rf /app/public/upload; ln -s /data/upload /app/public/upload; \
    rm -f /app/.env; mkdir -p /app/var; chown -R www-data:www-data /app/var

COPY php.ini /usr/local/etc/php/conf.d/zz-pms.ini
COPY fpm-pool.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY nginx.conf /etc/nginx/pms.conf.template
COPY fastcgi_pms /etc/nginx/fastcgi_pms
COPY start.sh /usr/local/bin/pms-start

ENV PMS_VERSION=${PMS_VERSION}
EXPOSE 8080
VOLUME ["/data"]
CMD ["bash", "/usr/local/bin/pms-start"]

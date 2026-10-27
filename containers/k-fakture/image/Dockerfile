FROM php:8.5-fpm

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/install-php-extensions
RUN chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions \
        pdo_pgsql \
        mbstring \
        bcmath \
        gd \
        zip \
        intl \
        opcache \
        exif \
        pcntl \
        redis

RUN apt-get update \
    && apt-get install -y --no-install-recommends libxml2-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

COPY --from=node:22-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:22-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

WORKDIR /var/www/html

COPY . .

RUN composer install --no-interaction --optimize-autoloader

ARG HOST_UID=1000
ARG HOST_GID=1000
RUN groupmod -g ${HOST_GID} www-data \
    && usermod -u ${HOST_UID} -g ${HOST_GID} www-data

RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# /var/www je home www-data korisnika (composer i npm kes).
RUN chown www-data:www-data /var/www

RUN echo 'umask 000' >> /etc/bash.bashrc \
    && echo 'umask 000' > /etc/profile.d/00-umask.sh

RUN { \
      echo '#!/bin/sh'; \
      echo 'umask 000'; \
      echo 'exec php /var/www/html/artisan "$@"'; \
    } > /usr/local/bin/artisan \
    && chmod +x /usr/local/bin/artisan

# Entrypoint je ugradjen u Dockerfile: build kontekst je direktorijum projekta
# (zbog COPY . .), pa COPY ne moze da dohvati fajl iz k-docker-a.
COPY <<'ENTRYPOINT' /usr/local/bin/docker-entrypoint.sh
#!/bin/sh
# Shared entrypoint for the php / vite / queue / scheduler services. Dispatches
# on the first CMD word:
#
#   php-fpm            -> web container: install node deps + build assets
#                         (fallback for when the vite dev server is down),
#                         then start PHP-FPM
#   vite               -> dev server: install node deps, drop a stale
#                         public/hot, then run `npm run dev` (HMR)
#   anything else      -> hand straight to docker-php-entrypoint (queue
#                         worker, scheduler, one-off artisan/composer
#                         commands, ...)
#
# umask 000: everything the containers create (storage, caches, builds,
# artisan make:*) ends up 0666/0777, so it is fully writable both from the
# host and from inside the containers (see also the umask setup in Dockerfile).
set -e
umask 000
cd /var/www/html

# node_modules is shared with the host and between the php/vite services via
# the bind mount, and both services can boot at the same time — serialize the
# install behind flock so two npm runs can't corrupt it. The lock file lives
# in bootstrap/cache (always present, gitignored, on the shared mount) because
# npm ci wipes node_modules and would delete a lock file kept in there.
ensure_node_deps() {
    [ -f package.json ] || return 0
    flock bootstrap/cache/.npm-install.lock sh -c '
        if ! ls -d node_modules/@esbuild/linux-* >/dev/null 2>&1; then
            if [ -f package-lock.json ]; then
                echo "[entrypoint] installing node dependencies (npm ci)..."
                npm ci
            else
                echo "[entrypoint] no lockfile found, installing with npm install..."
                npm install
            fi
        fi
    '
}

case "$1" in
    vite)
        ensure_node_deps
        # a stale hot file (left after a crash/kill) would point Laravel at a
        # dead dev server; vite recreates it on boot
        rm -f public/hot
        echo "[entrypoint] starting vite dev server (npm run dev)..."
        exec npm run dev
        ;;
    php-fpm)
        if [ -f package.json ]; then
            ensure_node_deps
            echo "[entrypoint] building frontend assets (npm run build)..."
            npm run build
        else
            echo "[entrypoint] no package.json found, skipping frontend build"
        fi
        exec docker-php-entrypoint "$@"
        ;;
    *)
        exec docker-php-entrypoint "$@"
        ;;
esac
ENTRYPOINT
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER www-data

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm"]

EXPOSE 9000 5173

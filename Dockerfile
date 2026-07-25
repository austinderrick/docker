ARG FRANKENPHP_VERSION="1.12.1"
ARG PHP_VERSION="8.4.18"
ARG WINTER_VERSION="v1.2.11"

FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-trixie
LABEL org.opencontainers.image.title="Winter CMS"
LABEL org.opencontainers.image.description="Builds and deploys a Winter CMS project using Docker."
LABEL org.opencontainers.image.source=https://github.com/wintercms/docker

ARG USER="winter"

RUN \
    # Install Microsoft packages key for SQL Server support
    curl -sSL -o /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && mkdir -p /opt/microsoft/msodbcsql18/ \
    && touch /opt/microsoft/msodbcsql18/ACCEPT_EULA \
    && apt-get update \
    # Install PHP extensions
    && install-php-extensions \
    gd \
    intl \
    memcached \
    # Required by `octane:start`, which registers signal handlers for SIGINT, SIGTERM and SIGHUP so
    # the worker can be stopped and reloaded. Those constants come from pcntl, so the command fails
    # with "Undefined constant SIGINT" without it even though Octane calls no pcntl_* function.
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    pdo_sqlsrv \
    pdo_odbc \
    redis \
    zip \
    # Install additional software for Composer
    && apt-get update \
    && apt-get install -y \
    git \
    unzip \
    tar \
    wget \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Setup Winter user and download Winter
RUN \
    groupadd -g 10000 -r ${USER} \
    && useradd -m -d /home/winter -u 10000 -g 10000 -s /bin/bash ${USER} \
    # Add additional capability to bind to port 80 and 443
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    # Give write access to /config/caddy and /data/caddy
    && chown -R ${USER}:${USER} /config/caddy /data/caddy \
    && mkdir /winter \
    && chown -R ${USER}:${USER} /winter

COPY entrypoint.sh /entrypoint.sh
COPY install-winter.sh /usr/local/bin/install-winter
RUN chmod +x /usr/local/bin/install-winter

# Worker-mode assets. Kept outside the project so `winter:mirror` cannot remove them; the entrypoint
# copies the worker entry point into the mirrored public directory on each start.
COPY Caddyfile.octane /etc/frankenphp/Caddyfile.octane
COPY frankenphp-worker.php /usr/local/share/winter/frankenphp-worker.php
COPY config/php.ini /usr/local/etc/php/conf.d/winter.ini

# Switch to user
USER ${USER}

# Redeclared inside the stage: an ARG declared before FROM is only in scope for the FROM line, so
# without this the create-project below expanded to an empty string and silently installed the
# latest stable release regardless of --build-arg WINTER_VERSION.
ARG WINTER_VERSION="v1.2.11"

# Optional VCS repository to build from instead of Packagist, so CI can build an unreleased branch
# without publishing it. Example:
#   --build-arg WINTER_REPOSITORY=https://github.com/wintercms/winter
ARG WINTER_REPOSITORY=""

# Optional matching Storm branch. Winter and Storm are developed in lockstep, so building an
# unreleased Winter branch usually means testing an unreleased Storm alongside it.
ARG STORM_REPOSITORY=""
ARG STORM_VERSION="dev-wip/1.3"

RUN STORM_VERSION="${STORM_VERSION}" \
    /usr/local/bin/install-winter "${WINTER_VERSION}" "${WINTER_REPOSITORY}" "${STORM_REPOSITORY}"

# Install Node for Mix/Vite support
ARG NODE_VERSION="v24.14.0"
ENV BASH_ENV=/home/${USER}/.bash_env
ENV XDG_CONFIG_HOME=/home/${USER}/.config
ENV NVM_DIR=/home/${USER}/.config/nvm
ENV NODE_BIN_PATH=${NVM_DIR}/versions/node/${NODE_VERSION}/bin

RUN touch "${BASH_ENV}" \
    && echo '. "${BASH_ENV}"' >> ~/.bashrc \
    && mkdir -p /home/${USER}/.config/nvm \
    && wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE="${BASH_ENV}" bash \
    && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
    && nvm install "${NODE_VERSION}"

ENV PATH="${NODE_BIN_PATH}:$PATH"

# Set up environment
WORKDIR /winter

ENV SERVER_NAME=":8000"
ENV SERVER_ROOT="/winter/public"
ENV APP_DEBUG="false"
ENV APP_URL="http://localhost:8000"
ENV DB_CONNECTION="sqlite"
ENV DB_DATABASE="/winter/storage/database.sqlite"
ENV ACTIVE_THEME="demo"
ENV BACKEND_URI="backend"
ENV ROUTES_CACHE="true"
ENV ASSET_CACHE="true"

# Runtime selection. "classic" serves one request per bootstrap, exactly as this image always has,
# and remains the default. "octane" keeps the application in memory between requests, which
# requires a Winter release containing worker-mode support.
ENV WINTER_RUNTIME="classic"
ENV OCTANE_PORT="8000"
ENV OCTANE_WORKERS="auto"
ENV OCTANE_MAX_REQUESTS="500"

# The entrypoint maps this sentinel to the runtime selected above. It is not a real executable, so
# an explicit command still overrides it and bypasses the mapping entirely.
CMD ["winter-server"]
ENTRYPOINT ["/entrypoint.sh"]

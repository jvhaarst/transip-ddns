FROM php:8.5-cli-alpine@sha256:d386a12bad6b5dbee1f7dbd0291a4526dbfcbe5cfc0e8833de8d8309be8f3e50

LABEL maintainer="TransIP DDNS" \
      description="Dynamic DNS updater for TransIP using tipctl"

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    composer \
    jq \
    yq

# CVE-2026-111497, the out-of-bounds write in the Brotli C decoder: the
# digest-pinned base still carries brotli-libs 1.2.0-r1, and the fix is
# 1.2.1-r0, which Alpine 3.24 already ships. The `apk add` above does not
# touch it -- brotli-libs arrives as a curl dependency that is already
# installed and satisfied, so only an explicit upgrade moves it. The exposure
# here is narrow (libcurl asking for `br` from the TransIP API, nothing
# inbound), but it is one package. Drop this line once the base image rebuilds
# past the fix and the Renovate digest bump carries it in.
RUN apk upgrade --no-cache brotli-libs

# Install tipctl globally via composer (with cache adapter dependency)
# renovate: datasource=packagist depName=transip/tipctl
ARG TIPCTL_VERSION=6.34.10
RUN composer global require transip/tipctl:${TIPCTL_VERSION} symfony/cache --no-interaction --no-progress \
    && ln -s /root/.composer/vendor/bin/tipctl /usr/local/bin/tipctl

# Create directories
RUN mkdir -p /app /config /keys

# Copy script
COPY transip-ddns.sh /app/transip-ddns.sh
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/transip-ddns.sh /app/docker-entrypoint.sh

WORKDIR /app

ENTRYPOINT ["/app/docker-entrypoint.sh"]

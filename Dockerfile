FROM php:8.3-cli-alpine

LABEL maintainer="TransIP DDNS" \
      description="Dynamic DNS updater for TransIP using tipctl"

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    composer \
    yq

# Install tipctl globally via composer
RUN composer global require transip/tipctl --no-interaction --no-progress \
    && ln -s /root/.composer/vendor/bin/tipctl /usr/local/bin/tipctl

# Create directories
RUN mkdir -p /app /config /keys

# Copy script
COPY transip-ddns.sh /app/transip-ddns.sh
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/transip-ddns.sh /app/docker-entrypoint.sh

WORKDIR /app

ENTRYPOINT ["/app/docker-entrypoint.sh"]

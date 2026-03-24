FROM debian:13-slim

ARG S6_OVERLAY_VERSION=3.2.2.0
ARG RESTIC_VERSION=0.18.1
ARG RCLONE_VERSION=1.73.3
ARG YQ_VERSION=4.52.4

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        cron \
        curl \
        gettext-base \
        jq \
        sqlite3 \
        tzdata \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# s6-overlay
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) S6_ARCH=x86_64;; arm64) S6_ARCH=aarch64;; *) S6_ARCH=$ARCH;; esac && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        | tar -C / -Jxp && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
        | tar -C / -Jxp

# restic
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) RESTIC_ARCH=linux_amd64;; arm64) RESTIC_ARCH=linux_arm64;; esac && \
    curl -fsSL "https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_${RESTIC_ARCH}.bz2" \
        | bunzip2 > /usr/local/bin/restic && \
    chmod +x /usr/local/bin/restic

# rclone
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/rclone/rclone/releases/download/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ARCH}.zip" \
        -o /tmp/rclone.zip && \
    apt-get update && apt-get install -y --no-install-recommends unzip && \
    unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/rclone && \
    apt-get purge -y unzip && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* /tmp/rclone.zip

# yq
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

RUN mkdir -p /var/log/docker-backup

COPY config.example.yml /etc/docker-backup/config.example.yml
COPY scripts/ /usr/local/bin/
COPY etc/ /etc/

RUN chmod +x /usr/local/bin/*.sh \
    && chmod +x /etc/s6-overlay/s6-rc.d/init-backup/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/cron/run

HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/init"]

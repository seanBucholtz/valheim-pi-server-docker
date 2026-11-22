# Valheim dedicated server for 64-bit ARM (tested on a Raspberry Pi 4).
#
#   DepotDownloader (native arm64) -> installs/updates the server from Steam
#   box64 (arm64)                  -> runs valheim_server.x86_64 under emulation
#
# Build this ON the ARM machine (docker compose build). It is arm64-only.
FROM debian:bookworm-slim

# Which box64 build to install; each is tuned for a CPU (Pi-Apps-Coders packages):
#   rpi4 (default) | rpi3 | rk3399 | tegrax1 | generic (any other ARM64: Pi 5, RK3588...)
ARG EMULATOR_BUILD=rpi4
# Box64 has had Valheim regressions between versions. Leave empty to get the
# latest build, or pin an exact apt version (see `make box-versions`).
# Neither name starts with BOX64_: box64 treats every BOX64_* variable as one of
# its own options, and BOX64_VERSION makes it print its version and exit.
ARG PIN_BOX64_VERSION=
# Native arm64 Steam downloader (https://github.com/SteamRE/DepotDownloader).
# SteamCMD can't be used: it is 32-bit x86 and its steamclient.so needs glibc
# symbols box86 doesn't provide (pthread_mutex_clocklock).
ARG DEPOTDOWNLOADER_VERSION=3.4.0
ARG DEPOTDOWNLOADER_SHA256=d9fb612ccebc1db8eeea3b4045d2221ec70431381393ce908fb72f01d4f9c812

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    case "${EMULATOR_BUILD}" in \
        rpi4) pkg=box64-rpi4arm64 ;; rpi3) pkg=box64-rpi3arm64 ;; \
        rk3399) pkg=box64-rk3399 ;; tegrax1) pkg=box64-tegrax1 ;; \
        generic) pkg=box64-generic-arm ;; \
        *) echo "EMULATOR_BUILD='${EMULATOR_BUILD}' is not valid: use rpi4, rpi3, rk3399, tegrax1 or generic" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg unzip tini procps \
        # DepotDownloader (.NET): ICU for globalization, OpenSSL for TLS
        libicu72 libssl3 \
        # native arm64 libs that box64 maps the server's x86_64 imports onto
        libstdc++6 libgcc-s1 zlib1g libatomic1; \
    install -d /usr/share/keyrings; \
    curl -fsSL https://pi-apps-coders.github.io/box64-debs/KEY.gpg \
      | gpg --dearmor -o /usr/share/keyrings/box64-archive-keyring.gpg; \
    printf 'Types: deb\nURIs: https://Pi-Apps-Coders.github.io/box64-debs/debian\nSuites: ./\nSigned-By: /usr/share/keyrings/box64-archive-keyring.gpg\n' \
      > /etc/apt/sources.list.d/box64.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends "${pkg}${PIN_BOX64_VERSION:+=${PIN_BOX64_VERSION}}"; \
    echo "${pkg}" > /etc/box64-package; \
    box64 --version; \
    curl -fsSL -o /tmp/dd.zip \
      "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOTDOWNLOADER_VERSION}/DepotDownloader-linux-arm64.zip"; \
    echo "${DEPOTDOWNLOADER_SHA256}  /tmp/dd.zip" | sha256sum -c -; \
    unzip -q /tmp/dd.zip DepotDownloader -d /usr/local/bin; \
    chmod 0755 /usr/local/bin/DepotDownloader; \
    rm -f /tmp/dd.zip; \
    DepotDownloader -V; \
    rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Everything mutable (server files, worlds, HOME) lives under /data.
VOLUME ["/data"]
EXPOSE 2456/udp 2457/udp

# Healthy = joinable: the entrypoint creates /tmp/valheim-ready when the server
# logs "Game server connected", and the server process must still be running.
# Until then the status is "starting". The 30m start period covers a first-start
# world generation plus the server download.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30m --retries=3 \
    CMD test -f /tmp/valheim-ready && pgrep -f '[v]alheim_server[.]x86_64' >/dev/null || exit 1
# (the [v] keeps pgrep from matching this healthcheck's own shell command line)

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

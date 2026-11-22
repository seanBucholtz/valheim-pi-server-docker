#!/usr/bin/env bash
# FALLBACK: download the Valheim server on an x86_64 PC (natively, no emulation).
# Not normally needed: the container downloads the server itself (DepotDownloader).
# Only use this if that download keeps failing on the Pi.
#
#   ./scripts/fetch-server-x86.sh ./valheim-server-files
#
# Then transfer the output directory's contents into DATA_DIR/server/ on the Pi,
# set UPDATE_ON_START=0 in the Pi's .env, and `make restart` there.
set -euo pipefail

out="${1:?usage: $0 <output-dir>}"
[[ "$(uname -m)" == "x86_64" ]] || { echo "run this on an x86_64 machine"; exit 1; }
command -v docker >/dev/null || { echo "needs docker on this machine"; exit 1; }

mkdir -p "$out"
out="$(realpath "$out")"

docker run --rm -v "$out:/out" steamcmd/steamcmd:latest \
    +force_install_dir /out +login anonymous +app_update 896660 validate +quit

[[ -f "$out/valheim_server.x86_64" ]] || { echo "download failed"; exit 1; }
echo "Server files are in $out - copy them into DATA_DIR/server/ on the Pi."

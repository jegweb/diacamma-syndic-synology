#!/usr/bin/env bash
# Construit l'image sur un ordinateur pour l'architecture du NAS et l'exporte
# en archive .tar, à importer dans Container Manager (Image > Ajouter > À partir
# d'un fichier). Pour un NAS sans accès à ghcr.io ou pour une image modifiée.
# L'image porte le nom et la version écrits dans docker-compose.yml : le projet
# l'utilise sans autre changement que « pull_policy: never » (voir README).
# Usage : scripts/build-image.sh [amd64|arm64]   (défaut : amd64)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:-amd64}"
case "$ARCH" in
  amd64|arm64) ;;
  *) echo "Architecture inconnue : $ARCH (amd64 ou arm64)." >&2; exit 64 ;;
esac

IMAGE="$(sed -nE 's/^ *image: *(ghcr\.io\/[^ ]*diacamma-syndic:[^ ]+).*/\1/p' docker-compose.yml | head -n 1)"
[[ -n "$IMAGE" ]] || { echo "Nom d'image introuvable dans docker-compose.yml." >&2; exit 1; }
VERSION="${IMAGE##*:}"

mkdir -p dist
# Sans attestations : l'archive reste lisible par le Docker de Container Manager.
docker build --pull --platform "linux/$ARCH" --provenance=false --sbom=false \
  --build-arg VERSION="$VERSION" -t "$IMAGE" .
docker save "$IMAGE" -o "dist/diacamma-syndic-$VERSION-$ARCH.tar"
echo "Archive prête : dist/diacamma-syndic-$VERSION-$ARCH.tar ($IMAGE)"

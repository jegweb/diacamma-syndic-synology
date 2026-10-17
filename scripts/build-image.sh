#!/usr/bin/env bash
# Construit l'image sur un ordinateur pour l'architecture du NAS et l'exporte
# en archive .tar, à importer dans Container Manager (Image > Ajouter > À partir
# d'un fichier). Solution de repli si la construction échoue sur le NAS.
# Usage : scripts/build-image.sh [amd64|arm64]   (défaut : amd64)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:-amd64}"
case "$ARCH" in
  amd64|arm64) ;;
  *) echo "Architecture inconnue : $ARCH (amd64 ou arm64)." >&2; exit 64 ;;
esac

# Même nom que dans docker-compose.yml, pour que le projet utilise l'image importée.
IMAGE=diacamma-syndic:local
mkdir -p dist
# Sans attestations : l'archive reste lisible par le Docker de Container Manager.
docker build --pull --platform "linux/$ARCH" --provenance=false --sbom=false -t "$IMAGE" .
docker save "$IMAGE" -o "dist/diacamma-syndic-$ARCH.tar"
echo "Archive prête : dist/diacamma-syndic-$ARCH.tar"

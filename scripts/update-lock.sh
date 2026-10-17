#!/usr/bin/env bash
# Régénère requirements.lock à partir de requirements.in : résout les dernières
# versions compatibles dans l'image Python de base, puis fige le résultat.
# PyQt6 (dépendance de l'interface graphique de bureau, inutile sur un serveur)
# est retiré : le Dockerfile installe le verrou avec --no-deps.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON_IMAGE="${PYTHON_IMAGE:-python:3.13-slim-trixie}"

docker run --rm -v "$PWD/requirements.in:/requirements.in:ro" "$PYTHON_IMAGE" sh -euc '
  python -m venv /tmp/venv
  /tmp/venv/bin/pip install --quiet --disable-pip-version-check -r /requirements.in
  /tmp/venv/bin/pip freeze
' > requirements.lock.tmp

{
  echo "# Généré par scripts/update-lock.sh le $(date +%Y-%m-%d) avec ${PYTHON_IMAGE}."
  echo "# Ne pas modifier à la main. PyQt6 (interface de bureau) est volontairement exclu."
  grep -viE '^pyqt6([-_]qt6|[-_]sip)?==' requirements.lock.tmp
} > requirements.lock
rm -f requirements.lock.tmp

grep -iE '^(lucterios|diacamma)' requirements.lock

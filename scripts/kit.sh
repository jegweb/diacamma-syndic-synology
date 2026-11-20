#!/usr/bin/env bash
# Prépare les fichiers du kit d'installation d'une application : les deux
# compose et .env.example. Les fichiers du dépôt sont ceux de Diacamma Syndic ;
# ceux de Diacamma Asso en sont dérivés ici, pour qu'ils ne puissent pas diverger.
#
# Usage : scripts/kit.sh <syndic|asso> <dossier> [image:tag]
#   image:tag : image à écrire dans les compose (défaut : celle du dépôt).
#
# Différences d'Asso : nom du projet et des conteneurs (diacamma-asso…),
# DIACAMMA_APPLI, dossier de l'instance (data/asso), domaine d'exemple et port
# publié 8101 au lieu de 8100, pour pouvoir installer les deux sur un même NAS.
set -euo pipefail

fail() { printf '[kit] ERREUR : %s\n' "$*" >&2; exit 1; }

APPLI="${1:-}"
DEST="${2:-}"
IMAGE="${3:-}"
[[ "$APPLI" == syndic || "$APPLI" == asso ]] || fail "usage : scripts/kit.sh <syndic|asso> <dossier> [image:tag]"
[[ -n "$DEST" ]] || fail "dossier de destination manquant."
[[ -z "$IMAGE" || "$IMAGE" =~ ^[A-Za-z0-9._/:-]+$ ]] || fail "nom d'image invalide : $IMAGE"
# Chemin absolu avant de se placer à la racine du dépôt.
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
cd "$(dirname "$0")/.."

COMPOSES=(docker-compose.yml docker-compose.sqlite.yml)
for f in "${COMPOSES[@]}" .env.example; do
  args=(-e '')
  if [[ -n "$IMAGE" ]]; then
    args+=(-e "s|^( *image: *)ghcr\.io/[^ ]*/diacamma:[^ ]+|\1$IMAGE|")
  fi
  if [[ "$APPLI" == asso ]]; then
    args+=(
      -e 's/Diacamma Syndic/Diacamma Asso/g'
      -e 's/diacamma-syndic/diacamma-asso/g'
      -e 's/(DIACAMMA_APPLI: *)syndic$/\1asso/'
      -e 's|data/syndic/|data/asso/|g'
      -e 's/syndic\.mondomaine\.fr/asso.mondomaine.fr/g'
      -e 's/8100/8101/g'
    )
  fi
  sed -E "${args[@]}" "$f" > "$DEST/$f"
done

# Contrôles : une modification future des fichiers sources ne doit pas
# produire un kit faux sans que personne ne s'en aperçoive.
for f in "${COMPOSES[@]}"; do
  grep -qE "^ *DIACAMMA_APPLI: *$APPLI\$" "$DEST/$f" || fail "$f : DIACAMMA_APPLI n'est pas « $APPLI »."
  grep -qE "^ *container_name: *diacamma-$APPLI\$" "$DEST/$f" || fail "$f : conteneur diacamma-$APPLI absent."
  if [[ -n "$IMAGE" ]]; then
    grep -qxE " *image: *${IMAGE//./\\.}" "$DEST/$f" || fail "$f : l'image n'a pas été remplacée par $IMAGE."
  fi
done
if [[ "$APPLI" == asso ]]; then
  # « syndic » en minuscules, « Diacamma Syndic » ou le port de Syndic : une
  # substitution manque (le titre « Syndic ou Asso ? » du README est permis).
  if grep -nE 'syndic|Diacamma Syndic|8100' "$DEST"/docker-compose*.yml "$DEST/.env.example" >&2; then
    fail "le kit Asso contient encore des références à Syndic (lignes ci-dessus) : compléter les substitutions de scripts/kit.sh."
  fi
fi
echo "[kit] Fichiers du kit $APPLI prêts dans $DEST."

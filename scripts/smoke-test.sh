#!/usr/bin/env bash
# Test de fumée : lance le projet Compose dans un dossier jetable, puis vérifie
# la connexion, les protections (admin/admin, /static/, hôte inconnu) et les
# commandes de sauvegarde et de restauration. Code de retour non nul en cas d'échec.
#
# Usage : scripts/smoke-test.sh [--postgresql] [image]
#   image : image à tester, déjà présente localement (défaut : celle du compose).
#   Exemple : docker build -t diacamma-syndic:local . && scripts/smoke-test.sh diacamma-syndic:local
# Variable : SMOKE_TIMEOUT, délai maximal d'attente de l'état « healthy » (600 s).
set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSE_SRC=docker-compose.yml
if [[ "${1:-}" == --postgresql ]]; then
  COMPOSE_SRC=docker-compose.postgresql.yml
  shift
fi
IMAGE="${1:-}"
TIMEOUT="${SMOKE_TIMEOUT:-600}"
HOST=syndic.example.test
PASSWORD=MotDePasseDeTest-2026
URL=http://127.0.0.1:8100
APP=diacamma-syndic

log() { printf '[test] %s\n' "$*"; }
fail() { printf '[test] ÉCHEC : %s\n' "$*" >&2; exit 1; }

for name in "$APP" "$APP-sauvegarde" "$APP-db"; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    fail "un conteneur « $name » existe déjà sur cette machine : supprimez-le avant le test."
  fi
done

T="$(mktemp -d "${TMPDIR:-/tmp}/diacamma-test.XXXXXX")"
compose() { docker compose --project-directory "$T" -f "$T/docker-compose.yml" -p diacamma-test "$@"; }
cleanup() {
  local status=$?
  if (( status != 0 )); then
    log "Journal des conteneurs :"
    compose logs --no-color --tail 150 >&2 || true
  fi
  compose down --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$T"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$T/data" "$T/backups"
cp "$COMPOSE_SRC" "$T/docker-compose.yml"
if [[ -n "$IMAGE" ]]; then
  sed -i.orig -E "s|^( *image: *)ghcr\.io/[^ ]*diacamma-syndic:[^ ]+|\1$IMAGE|" "$T/docker-compose.yml"
  rm -f "$T/docker-compose.yml.orig"
fi
{
  echo "DIACAMMA_ALLOWED_HOSTS=$HOST"
  echo "DIACAMMA_ADMIN_PASSWORD=$PASSWORD"
  # Sous Linux, les dossiers appartiennent à l'utilisateur courant (UID 1026
  # absent) ; sous macOS, le partage de fichiers de Docker gère les droits.
  if [[ "$(uname -s)" == Linux ]]; then
    echo "PUID=$(id -u)"
    echo "PGID=$(id -g)"
  fi
} > "$T/.env"
if [[ "$COMPOSE_SRC" == docker-compose.postgresql.yml ]]; then
  mkdir -p "$T/postgresql" "$T/secrets"
  openssl rand -hex 16 > "$T/secrets/db_password.txt"
fi

wait_healthy() {
  local waited=0 status
  while (( waited < TIMEOUT )); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}} {{.RestartCount}}' "$APP")"
    case "$status" in
      "healthy "*) log "« $APP » est healthy après ${waited} s."; return 0 ;;
      unhealthy*) fail "« $APP » est unhealthy." ;;
      *" 0") ;;
      *) fail "« $APP » a redémarré (erreur au démarrage)." ;;
    esac
    sleep 5
    waited=$(( waited + 5 ))
  done
  fail "« $APP » n'est pas healthy après ${TIMEOUT} s."
}

http_code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: ${2:-$HOST}" "$URL$1"; }
login() {
  curl -s -H "Host: $HOST" -X POST --data "login=$1&password=$2" "$URL/CORE/authentification"
}
# Réessaie pendant 2 minutes : juste après un redémarrage, l'état « healthy »
# peut encore être celui d'avant et gunicorn pas encore prêt.
check_login() {
  local tries=0
  until login admin "$PASSWORD" | grep -qE '"data" *: *"OK"'; do
    (( ++tries < 40 )) || fail "connexion admin avec le mot de passe fourni refusée."
    sleep 3
  done
  log "OK : connexion admin."
}

log "Dossier de test : $T ($COMPOSE_SRC, image ${IMAGE:-du compose})"
compose up -d --quiet-pull
wait_healthy
[[ "$(docker inspect -f '{{.State.Running}}' "$APP-sauvegarde")" == true ]] || fail "le service de sauvegarde ne tourne pas."
log "OK : service de sauvegarde lancé."

check_login
login admin admin | grep -q BADAUTH || fail "admin/admin n'est pas refusé."
log "OK : admin/admin refusé."
for path in /static/settings.py /static/db.sqlite3; do
  code="$(http_code "$path")"
  [[ "$code" == 404 ]] || fail "$path répond $code au lieu de 404."
  log "OK : $path → 404."
done
code="$(http_code / inconnu.example.test)"
[[ "$code" == 400 ]] || fail "un hôte inconnu reçoit $code au lieu de 400."
log "OK : hôte inconnu → 400."

docker exec "$APP" diacamma version
docker exec "$APP" diacamma backup
archive="$(find "$T/backups" -maxdepth 1 -name 'manuel_syndic_*.lbk' -exec basename {} \; | head -n 1)"
[[ -n "$archive" ]] || fail "aucune archive manuelle créée dans backups/."
log "OK : archive $archive créée."
docker exec "$APP" diacamma restore "$archive"
docker restart "$APP" >/dev/null
check_login
log "OK : restauration puis redémarrage."

log "Tous les contrôles sont passés."

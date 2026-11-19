#!/usr/bin/env bash
# Test de fumée : lance le projet Compose dans un dossier jetable, puis vérifie
# la connexion, les protections (admin/admin, /static/, hôte inconnu) et les
# commandes de sauvegarde et de restauration. Code de retour non nul en cas d'échec.
#
# Usage : scripts/smoke-test.sh [--sqlite] [--depuis <ancienne image>] [image]
#   image : image à tester (défaut : celle du compose).
#   --sqlite : variante SQLite (docker-compose.sqlite.yml) au lieu de PostgreSQL.
#     Vérifie aussi qu'un compose PostgreSQL est refusé sur une instance SQLite.
#   --depuis : installe d'abord l'ancienne image, puis passe à la nouvelle, comme
#     un utilisateur qui met à jour. Vérifie la détection de la mise à jour, les
#     migrations et l'instantané SQLite (si les versions des paquets diffèrent).
#   Exemples :
#     docker build -t diacamma-syndic:local . && scripts/smoke-test.sh diacamma-syndic:local
#     scripts/smoke-test.sh --depuis ghcr.io/jegweb/diacamma-syndic:latest diacamma-syndic:local
# Variable : SMOKE_TIMEOUT, délai maximal d'attente de l'état « healthy » (600 s).
set -euo pipefail
cd "$(dirname "$0")/.."

log() { printf '[test] %s\n' "$*"; }
fail() { printf '[test] ÉCHEC : %s\n' "$*" >&2; exit 1; }

ENGINE=postgresql
COMPOSE_SRC=docker-compose.yml
FROM_IMAGE=""
while (( $# > 0 )); do
  case "$1" in
    --sqlite) ENGINE=sqlite; COMPOSE_SRC=docker-compose.sqlite.yml; shift ;;
    --depuis) FROM_IMAGE="${2:-}"; [[ -n "$FROM_IMAGE" ]] || fail "--depuis demande une image."; shift 2 ;;
    -*) fail "option inconnue : $1" ;;
    *) break ;;
  esac
done
IMAGE="${1:-$(sed -nE 's/^ *image: *([^ ]*diacamma-syndic[^ ]*).*/\1/p' "$COMPOSE_SRC" | head -n 1)}"
TIMEOUT="${SMOKE_TIMEOUT:-600}"
HOST=syndic.example.test
PASSWORD=MotDePasseDeTest-2026
URL=http://127.0.0.1:8100
APP=diacamma-syndic

for name in "$APP" "$APP-sauvegarde" "$APP-db"; do
  if docker ps -a --format '{{.Names}}' | grep -x "$name" >/dev/null; then
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
# Remplace l'image des services Diacamma (pas celle de PostgreSQL).
set_image() {
  sed -i.orig -E "s|^( *image: *)[^ ]*diacamma-syndic[^ ]*|\1$1|" "$T/docker-compose.yml"
  rm -f "$T/docker-compose.yml.orig"
}
build_id() {
  docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null
  docker run --rm --entrypoint cat "$1" /opt/diacamma/diacamma-build-id
}
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
# Dossiers vides, comme créés avec File Station : le mot de passe de la base
# est généré au premier démarrage.
if [[ "$ENGINE" == postgresql ]]; then
  mkdir -p "$T/postgresql" "$T/secrets"
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

# Les images publiées jusqu'à 2.7.10-2 n'attendent pas PostgreSQL : pour
# elles, on démarre la base d'abord (comme l'ancien compose, en « healthy »).
start_db_first() {
  local waited=0
  compose up -d --quiet-pull db
  until [[ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-db")" == healthy ]]; do
    (( waited < 180 )) || fail "« $APP-db » n'est pas healthy après 180 s."
    sleep 3
    waited=$(( waited + 3 ))
  done
}

http_code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: ${2:-$HOST}" "$URL$1"; }
login() {
  curl -s -H "Host: $HOST" -X POST --data "login=$1&password=$2" "$URL/CORE/authentification"
}
# Les grep lisent toute leur entrée (pas de -q) : avec pipefail, un grep -q
# qui s'arrête tôt ferait échouer la commande en amont (SIGPIPE).
# Réessaie pendant 2 minutes : juste après un redémarrage, l'état « healthy »
# peut encore être celui d'avant et gunicorn pas encore prêt.
check_login() {
  local tries=0
  until login admin "$PASSWORD" | grep -E '"data" *: *"OK"' >/dev/null; do
    (( ++tries < 40 )) || fail "connexion admin avec le mot de passe fourni refusée."
    sleep 3
  done
  log "OK : connexion admin."
}

log "Dossier de test : $T ($COMPOSE_SRC, image $IMAGE${FROM_IMAGE:+, depuis $FROM_IMAGE})"
if [[ -n "$FROM_IMAGE" ]]; then
  set_image "$FROM_IMAGE"
  [[ "$ENGINE" == sqlite ]] || start_db_first
  compose up -d --quiet-pull
  wait_healthy
  check_login
  log "OK : installation de l'ancienne version ; passage à $IMAGE."
  old_id="$(build_id "$FROM_IMAGE")"
  new_id="$(build_id "$IMAGE")"
  set_image "$IMAGE"
  compose up -d --quiet-pull
  wait_healthy
  if [[ "$old_id" != "$new_id" ]]; then
    docker logs "$APP" 2>&1 | grep -F "Mise à jour détectée : $old_id -> $new_id" >/dev/null \
      || fail "la mise à jour $old_id -> $new_id n'a pas été détectée."
    if [[ "$ENGINE" == sqlite ]]; then
      find "$T/backups/avant-mise-a-jour" -name 'syndic_*.tar.gz' 2>/dev/null | grep . >/dev/null \
        || fail "aucun instantané dans backups/avant-mise-a-jour/."
      log "OK : instantané SQLite pris avant la mise à jour."
    else
      docker logs "$APP" 2>&1 | grep -F "pas d'instantané automatique" >/dev/null \
        || fail "l'absence d'instantané PostgreSQL n'est pas signalée."
    fi
    log "OK : mise à jour détectée et migrations appliquées ($old_id -> $new_id)."
  else
    ! docker logs "$APP" 2>&1 | grep -F "Mise à jour détectée" >/dev/null || fail "mise à jour détectée alors que les paquets sont identiques."
    log "OK : paquets identiques, aucune migration (révision de l'image)."
  fi
else
  set_image "$IMAGE"
  compose up -d --quiet-pull
  wait_healthy
fi
[[ "$(docker inspect -f '{{.State.Running}}' "$APP-sauvegarde")" == true ]] || fail "le service de sauvegarde ne tourne pas."
log "OK : service de sauvegarde lancé."
if [[ "$ENGINE" == postgresql ]]; then
  [[ "$(wc -c < "$T/secrets/db_password.txt" | tr -d ' ')" == 32 ]] \
    || fail "secrets/db_password.txt n'a pas été généré (32 caractères attendus)."
  log "OK : mot de passe de la base généré dans secrets/."
fi

check_login
login admin admin | grep BADAUTH >/dev/null || fail "admin/admin n'est pas refusé."
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

# Utilisateur SQLite qui prend par erreur le compose PostgreSQL du kit (sans
# créer postgresql/ ni secrets/) : refus explicite, base intacte.
if [[ "$ENGINE" == sqlite ]]; then
  compose down >/dev/null 2>&1
  before="$(cksum < "$T/data/syndic/db.sqlite3")"
  cp docker-compose.yml "$T/docker-compose.yml"
  set_image "$IMAGE"
  compose up -d --quiet-pull
  tries=0
  until docker logs "$APP" 2>&1 | grep -F "prenez docker-compose.sqlite.yml" >/dev/null; do
    (( ++tries < 30 )) || fail "le compose PostgreSQL n'est pas refusé sur une instance SQLite."
    sleep 3
  done
  compose stop >/dev/null 2>&1
  [[ "$(cksum < "$T/data/syndic/db.sqlite3")" == "$before" ]] || fail "la base SQLite a été modifiée par le compose PostgreSQL."
  log "OK : compose PostgreSQL refusé sur une instance SQLite, base intacte."
fi

log "Tous les contrôles sont passés."

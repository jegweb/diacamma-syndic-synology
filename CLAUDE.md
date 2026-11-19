# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Objectif du projet

Image Docker et projet Compose pour déployer **Diacamma Syndic** (gestion de copropriété, framework Python/Django **Lucterios**) dans **Synology Container Manager** (DSM 7.2+, NAS amd64 ou arm64). Priorités : déploiement simple, sécurisé, sans perte de fonctionnalités de l'application. `README.md` est le guide utilisateur (en français) : le tenir à jour à chaque changement de comportement.

L'utilisateur travaille en français : réponses, commentaires, messages du conteneur et documentation en français.

## Commandes

```sh
docker build -t diacamma-syndic:local .                     # construire l'image (arch locale)
docker build --platform linux/amd64 -t diacamma-syndic:amd64-test .   # vérifier l'autre architecture
scripts/smoke-test.sh diacamma-syndic:local                 # test de fumée (ajouter --postgresql pour l'autre variante)
scripts/smoke-test.sh --depuis ghcr.io/jegweb/diacamma-syndic:latest diacamma-syndic:local   # test de mise à jour
scripts/update-lock.sh                                      # régénérer requirements.lock depuis requirements.in
scripts/build-image.sh amd64                                # image exportée en dist/*.tar pour import dans Container Manager
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable docker/bin/diacamma scripts/*.sh   # lint shell
```

Il n'y a pas de suite de tests unitaires. `scripts/smoke-test.sh [--postgresql] <image>` lance le projet dans un dossier jetable, en dehors du dépôt pour ne pas y créer `data/` et `backups/`. Il remplace la ligne `image:` du compose par l'image locale indiquée, puis vérifie :

- la connexion avec le mot de passe fourni, et le refus de `admin`/`admin` ;
- `/static/settings.py` et `/static/db.sqlite3` en 404, un hôte inconnu en 400 ;
- `backup`, puis `restore` suivi d'un redémarrage.

La CI (`.github/workflows/ci.yml`) le lance sur chaque push et chaque pull request, et chaque mois sans cache. Pour un essai manuel, la connexion se teste ainsi :

```sh
curl -s -H 'Host: syndic.example.test' -X POST --data 'login=admin&password=MotDePasseDeTest-2026' \
  http://127.0.0.1:8100/CORE/authentification    # "data": "OK" si la connexion réussit, "BADAUTH" sinon
```

Container Manager embarque un Docker plus ancien que celui du Mac (Docker 24, Compose 2.19 ou 2.20). Pour tester un changement du compose ou du Dockerfile dans ces conditions, utiliser un moteur isolé, avec dans `$T` un compose et un `.env` :

```sh
docker run -d --privileged --name dind24 -e DOCKER_TLS_CERTDIR= -v "$T:/project" docker:24.0.2-dind
docker exec -w /project dind24 docker compose pull     # ne doit pas échouer : l'image doit exister sur ghcr.io
docker exec -w /project dind24 docker compose up -d
```

### Publication

L'image est publiée sur `ghcr.io/jegweb/diacamma-syndic`. Versions `X.Y.Z-N` : version de Diacamma, puis révision de l'empaquetage. La procédure complète est dans `CONTRIBUTING.md`.

- Le tag d'image est écrit en dur dans **les deux** compose.
- **Plafonds prudents** (`requirements.in`) : une dépendance indirecte que l'amont ne limite pas, et dont une version majeure est sortie après la version amont de Diacamma, est plafonnée sous cette majeure. Les règles complètes sont dans CONTRIBUTING, étape 1. Le Dockerfile lance `pip check` : seule l'absence de PyQt6 est tolérée.
- Test de mise à jour : `smoke-test.sh --depuis <image publiée>`. La CI (variante `mise-a-jour`) et la publication le lancent depuis `:latest`.
- Une étiquette Git `vX.Y.Z-N` (ou `-rcM`) lance `.github/workflows/release.yml`. Il vérifie la cohérence (étiquette, compose, `requirements.lock`, entrée `## [X.Y.Z-N]` du CHANGELOG), puis construit et teste sur des runners natifs amd64 et arm64.
- Il pousse l'image testée sous `X.Y.Z-N-<arch>`, assemble le manifeste multi-architecture (`X.Y.Z-N`, puis `X.Y.Z` et `latest` hors pré-version) et crée la Release avec le kit `.zip` (deux compose et `.env.example`).
- Images sans attestation (`provenance`/`sbom` désactivés), pour le Docker 24 de Container Manager.
- Une version définitive est annoncée par une discussion dans la catégorie `ANNONCES` (« Annonces »), seulement si cette catégorie existe. Le formulaire `.github/DISCUSSION_TEMPLATE/questions-et-aide.yml` doit porter le nom (slug) de la catégorie « Questions et aide ».
- `ARG VERSION` donne `DIACAMMA_IMAGE_VERSION`, affiché par `diacamma version`. Elle n'entre pas dans `diacamma-build-id` : une révision sans changement de paquets ne déclenche pas de migration.

## Architecture

- `Dockerfile` : construction en deux étapes sur `python:3.13-slim-trixie`. Trixie est obligatoire : les roues aarch64 exigent glibc ≥ 2.39. Le verrou est installé avec `pip install --no-deps -r requirements.lock`. **PyQt6 est volontairement exclu** du verrou : c'est une dépendance déclarée de `lucterios`, mais elle ne sert qu'à l'interface de bureau. Exécution sous l'UID:GID 1026:100, avec `tini` comme PID 1.
- `docker/bin/diacamma` : point d'entrée et outil d'administration (`serve`, `backup`, `backup-daemon`, `restore`, `reset-admin-password`, `version`, `manage`, `admin`). Il pilote `python -m lucterios.install.lucterios_admin … -i /data`.
- `docker/lib/diacamma_docker.py` : fonctions Python appelées par le script (`extra-settings`, `secure-admin`, `clean-static`, `snapshot-sqlite`). `diacamma_wsgi.py` enveloppe l'application Lucterios avec WhiteNoise. `healthcheck.py` est la sonde de santé.
- `docker-compose.yml` (SQLite) et `docker-compose.postgresql.yml` : deux services avec la même image, téléchargée depuis ghcr.io. `diacamma` sert l'application ; `sauvegarde` lance `backup-daemon`. Durcissement : `read_only`, `cap_drop: ALL`, `no-new-privileges`, port publié sur `127.0.0.1`. Toute la configuration passe par `.env` (voir `.env.example`).

### Contraintes propres à Synology (constatées sur un NAS Synology, noyau 4.4)

- **Pas de section `logging`** dans le compose. Container Manager n'affiche que les journaux écrits par le pilote par défaut de Synology (un `log.db` par conteneur). Avec `json-file`, l'onglet Journal reste vide.
- **Port publié en valeur fixe** (`"127.0.0.1:8100:8000"`), sans variable. L'assistant « portail Web via Web Station » de Container Manager lit le compose lui-même et ne propose aucun service si la ligne `ports` contient `${…}`. Web Station accepte en revanche un port publié sur `127.0.0.1`.
- **Pas de `pids_limit`** : le noyau ne gère pas cette limite (avertissement « PIDs limit discarded »).
- **Vocabulaire de l'interface française** : l'action « Build » d'un projet s'appelle **« Créer »**. Pour qu'un changement du compose ou de `.env` soit pris en compte, la documentation demande **Arrêter → Nettoyer → Créer**. « Démarrer » relance les conteneurs existants sans relire le compose. « Nettoyer » supprime les conteneurs, mais ni les images ni les dossiers de données.
- **Container Manager lance `docker compose pull` avant `up`.** L'image du compose doit donc exister sur ghcr.io, dans un paquet public. Pour une image importée ou construite sur le NAS, l'utilisateur décommente `pull_policy: never` dans l'ancre `x-diacamma` ; sinon le pull échoue ou remplace l'image. Ne pas remettre de section `build:` : le kit ne contient pas le Dockerfile.
- **`sauvegarde` dépend de `diacamma` en `service_started`, pas `service_healthy`.** Container Manager affiche tout échec de `compose up` comme « Build project failed », sans garder de conteneur dont on puisse lire le journal. Les erreurs de démarrage doivent laisser le conteneur visible, en redémarrage, avec un message `[diacamma] ERREUR` explicite.

### Séquence `serve`

1. Valider la configuration.
2. Créer l'instance (`lucterios_admin add`) ou la mettre à jour (`lucterios_admin modif`, qui réécrit `settings.py` puis applique les migrations).
3. Remplacer le mot de passe `admin`/`admin` s'il est encore actif.
4. Lancer `collectstatic`, seulement si la version a changé.
5. Nettoyer `static/`.
6. Écrire le marqueur `/data/.diacamma-build-id`.
7. Lancer gunicorn.

Une mise à jour est détectée quand ce marqueur **existe** et diffère de `/opt/diacamma/diacamma-build-id`, généré à la construction à partir des versions des paquets. Le conteneur prend alors un instantané SQLite dans `backups/avant-mise-a-jour/`. Sans marqueur (démarrages précédents ratés, données importées), il n'y a pas d'instantané. L'instantané ouvre la base en lecture-écriture : un démarrage interrompu en pleine migration laisse un journal SQLite « chaud », qu'une ouverture `mode=ro` ne peut pas annuler (« attempt to write a readonly database »). Le service de sauvegarde attend que le marqueur corresponde à l'image avant d'archiver.

### Particularités de Lucterios qui guident la conception

- **Réglages** : `lucterios_admin -e '<json>'` écrit chaque clé dans `settings.py` sous la forme `CLE = valeur`. Les chaînes de premier niveau sont écrites entre guillemets **sans échappement**, d'où la validation dans `extra_settings()`. `modif` conserve `SECRET_KEY` et la base, et fusionne les nouvelles clés avec les anciennes.
- **`DEBUG` vaut `True` par défaut** dans Lucterios. On le force à `False`. Django ne sert alors plus `/static/` (WhiteNoise prend le relais), tandis que `/web/` reste servi par une vue Lucterios.
- **Fuite de fichiers par `collectstatic`** : `STATICFILES_DIRS` contient le répertoire de l'instance. `collectstatic` y copierait `settings.py`, `db.sqlite3` et `usr/` (les documents). Pour l'éviter, on passe des options `-i` et on lance `clean-static` à chaque démarrage. Ne pas retirer ces protections.
- **Planificateur dans le processus web** : APScheduler s'exécute dans le processus gunicorn et gère l'envoi des courriels par lots, les archives lancées depuis l'interface et les rapports de clôture. Il faut donc **un seul worker** (`--workers 1`, les threads sont permis), sans `--preload` ni `--max-requests`. Les archives de l'interface relancent `sys.executable -m lucterios.install.lucterios_admin` et lisent `DJANGO_SETTINGS_MODULE` dans l'environnement.
- **Adresse du site** : les liens des courriels (documents partagés, paiement, statistiques d'ouverture) partent de `LUCTERIOS_ROOT_URL`. Vide, Lucterios la déduit du `Referer` de la première requête qui en a besoin et la garde en mémoire jusqu'au redémarrage. Les envois par lots repris au démarrage partent alors avec des liens incomplets. `extra_settings()` la fixe donc à `https://<premier nom non IP de DIACAMMA_ALLOWED_HOSTS>`, et la laisse vide en HTTP, où le port compte. La clé est toujours écrite, même vide, car `modif` conserve les anciennes clés.
- **Langue** : `set_locale_lang('fr')` repasse silencieusement en anglais si la locale `fr_FR.UTF-8` n'est pas générée dans l'image.
- **Compte par défaut** : la migration CORE 0001 crée `admin`/`admin`. `secure-admin` le remplace à chaque démarrage et après chaque restauration.
- **Données** : toutes les données de l'instance sont dans `/data/<instance>/` (`settings.py`, `db.sqlite3`, `usr/` pour les documents, `static/`, `tmp/`, `django_cache/`). `BACKUP_DIRECTORY=/backups` active la gestion des archives `.lbk` dans l'interface.
- **Modules requis** : `lucterios-standard` doit être installé, car `lucterios_admin` l'importe dans `setup_from_none`. Liste des modules de l'instance : `lucterios.contacts,lucterios.documents,lucterios.mailing,diacamma.accounting,diacamma.payoff,diacamma.condominium`.

### Référence amont

Le paquet YunoHost (`https://git.yunohost.org/YunoHost-Apps/diacamma_ynh`), maintenu par l'auteur de Diacamma, sert de référence pour les conventions de déploiement. Il utilise gunicorn avec 1 worker, `--timeout 600`, un `collectstatic` suivi d'un nettoyage, et `lucterios_admin check/update/refreshall` pour les mises à jour. Les sources des paquets sont publiées sur PyPI sous forme de roues.

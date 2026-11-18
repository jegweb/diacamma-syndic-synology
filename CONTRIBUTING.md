# Contribuer

Merci de votre intérêt ! Le projet est en français : tickets, commentaires du code, messages du conteneur et documentation.

- **Une question, un retour d'installation** : les [Discussions](https://github.com/jegweb/diacamma-syndic-synology/discussions).
- **Un problème du conteneur ou de la documentation** : un ticket. Joignez le journal et masquez votre domaine et vos mots de passe.
- **Un problème de l'application Diacamma** (comptabilité, appels de fonds, impressions…) : l'[équipe Diacamma](https://www.diacamma.org).
- **Une faille de sécurité** : voir [SECURITY.md](SECURITY.md), jamais en ticket public.

## Avant de modifier

Lisez la partie « Architecture » de [CLAUDE.md](CLAUDE.md). Elle explique les choix qui ne se devinent pas, en particulier :

- les **contraintes de Container Manager** : pas de section `logging`, port publié en valeur fixe, pas de `pids_limit`, `service_started` ;
- les **protections contre les particularités de Lucterios** : `collectstatic` avec ses exclusions et `clean-static`, un seul worker gunicorn, remplacement de `admin`/`admin`.

Ne retirez pas une protection sans comprendre pourquoi elle existe. Si un comportement de l'utilisateur change, mettez à jour le README dans la même modification.

## Tester

Il faut Docker sur un ordinateur (amd64 ou Mac Apple Silicon).

```sh
docker build -t diacamma-syndic:local .
scripts/smoke-test.sh diacamma-syndic:local                # base SQLite
scripts/smoke-test.sh --postgresql diacamma-syndic:local   # base PostgreSQL
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable docker/bin/diacamma scripts/*.sh
```

`smoke-test.sh` lance le projet dans un dossier temporaire et vérifie plusieurs points :

- la connexion, et le refus de `admin`/`admin` ;
- `/static/settings.py` et `/static/db.sqlite3` en 404, un hôte inconnu en 400 ;
- la sauvegarde puis la restauration.

L'intégration continue lance les mêmes contrôles sur chaque pull request.

**Docker de Container Manager.** Le NAS embarque un Docker plus ancien (24, avec Compose 2.19 ou 2.20). Pour une modification du compose ou du Dockerfile, testez aussi avec un moteur isolé, depuis un dossier qui contient le compose et un `.env` :

```sh
docker run -d --privileged --name dind24 -e DOCKER_TLS_CERTDIR= -v "$PWD:/project" docker:24.0.2-dind
docker exec -w /project dind24 docker compose pull
docker exec -w /project dind24 docker compose up -d
```

Si vous le pouvez, testez enfin sur un vrai NAS : Container Manager a ses propres comportements (voir CLAUDE.md).

## Publier une version (mainteneurs)

Les versions s'écrivent `X.Y.Z-N` (voir [CHANGELOG.md](CHANGELOG.md)).

1. **Nouvelle version de Diacamma** : lancez `scripts/update-lock.sh`, vérifiez les versions affichées et mettez à jour la ligne « Versions incluses » du README. La révision repart à `-1`.
   **Révision** (correctif du conteneur, ou correctifs de sécurité Debian et Python) : gardez `requirements.lock` et incrémentez `N`.
2. Remplacez le tag de l'image dans `docker-compose.yml` **et** `docker-compose.postgresql.yml`.
3. Ajoutez l'entrée `## [X.Y.Z-N]` au CHANGELOG.
4. Testez (voir plus haut), commitez, puis poussez une pré-version : `git tag vX.Y.Z-N-rc1 && git push origin vX.Y.Z-N-rc1`.
5. Le workflow « Publication » vérifie la cohérence de l'étiquette, des compose, du verrou et du CHANGELOG. Il construit et teste l'image sur amd64 et arm64, la publie sur ghcr.io et crée une Release marquée comme pré-version. Testez le kit sur un NAS.
6. Publiez la version définitive : `git tag vX.Y.Z-N && git push origin vX.Y.Z-N`. Les tags d'image `X.Y.Z-N`, `X.Y.Z` et `latest` sont publiés.

**Correctifs de sécurité.** L'intégration continue reconstruit l'image sans cache le 1er de chaque mois. Publiez une révision environ une fois par mois, ou plus vite après une faille annoncée dans Debian ou Python. GitHub suspend les tâches planifiées d'un dépôt public sans activité depuis 60 jours : relancez-les depuis l'onglet Actions si besoin.

Les runners arm64 (`ubuntu-24.04-arm`) ne sont gratuits que pour les dépôts publics.

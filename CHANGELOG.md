# Journal des modifications

Les versions s'écrivent `X.Y.Z-N` : `X.Y.Z` est la version de Diacamma Syndic incluse, `N` la révision de l'empaquetage. Une révision peut corriger le conteneur ou simplement reconstruire l'image avec les correctifs de sécurité de Debian et de Python.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [2.7.10-2] - 2026-11-19

Révision de sécurité. Les versions de Diacamma et Lucterios sont les mêmes que dans 2.7.10-1 : la mise à jour ne lance aucune migration.

### Sécurité

- Les correctifs de sécurité Debian sont appliqués pendant la construction (`apt-get upgrade`), dont celui de zlib (CVE-2026-85091).
- pip est retiré de l'image. Il ne servait pas à l'exécution et embarquait des versions vulnérables de urllib3 (CVE-2026-97687, CVE-2026-97689), msgpack (CVE-2026-114613, GHSA-6v7p-g79w-8964) et setuptools (CVE-2025-47273). Conséquence : `diacamma admin check` et `diacamma admin update` ne fonctionnent plus, car les mises à jour passent par une nouvelle image.

### Ajouté

- Analyse hebdomadaire des failles de l'image publiée, avec Trivy.
- Modèle de pull request.

## [2.7.10-1] - 2026-11-19

**Faites une sauvegarde avant la mise à jour.** Au premier démarrage, le conteneur détecte la nouvelle version. Il prend alors un instantané de la base SQLite dans `backups/avant-mise-a-jour/`. Cette version ne modifie pas la structure de la base : elle n'apporte aucune nouvelle migration. Suivez l'opération dans le journal.

### Modifié

- Diacamma Syndic 2.7.10 et Lucterios 2.7.10, versions publiées par l'équipe Diacamma le 30 octobre 2026. Les nouveautés fonctionnelles sont présentées sur [diacamma.org](https://www.diacamma.org).
- Dépendances mises à jour. Les nouvelles versions de Lucterios et Diacamma exigent notamment Pillow 13, ReportLab 5, pandas 3 et factur-x 7. Django passe en 5.2.19.

### Ajouté

- Plafonds prudents sur les dépendances indirectes dont une version majeure est sortie après Diacamma 2.7.10, et que l'amont n'a donc pas pu tester : python-dateutil < 4, pypdf < 7, stripe < 17 (paiement en ligne) et gunicorn < 27.
- Contrôle de cohérence des dépendances (`pip check`) pendant la construction de l'image.
- Test de mise à jour depuis la dernière version publiée, lancé par l'intégration continue et à chaque publication : détection de la mise à jour, instantané et migrations.

## [2.7.9-1] - 2026-11-19

Première version publique.

### Ajouté

- Image publiée sur `ghcr.io/jegweb/diacamma-syndic` pour Intel/AMD (amd64) et ARM 64 bits (arm64). Il n'y a plus d'image à construire sur le NAS.
- Kit d'installation joint à chaque Release : `docker-compose.yml`, `docker-compose.postgresql.yml` et `.env.example`.
- Diacamma Syndic 2.7.9 et Lucterios 2.7.9, sur Python 3.13 (Debian 13 « trixie »).
- Projet Compose pour Container Manager, avec une base SQLite (recommandée) ou PostgreSQL.
- Sauvegarde automatique quotidienne en archives `.lbk` et instantané SQLite avant chaque mise à jour.
- Commandes d'administration : `diacamma backup`, `restore`, `reset-admin-password` et `version`.
- Sécurité : le compte `admin`/`admin` est remplacé au démarrage, le mode débogage est désactivé, les noms d'hôte sont contrôlés et les conteneurs tournent sans root, en lecture seule.
- `diacamma version` et le journal de démarrage affichent la version de l'image.

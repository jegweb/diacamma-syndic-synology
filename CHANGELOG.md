# Journal des modifications

Les versions s'écrivent `X.Y.Z-N` : `X.Y.Z` est la version de Diacamma Syndic incluse, `N` la révision de l'empaquetage. Une révision peut corriger le conteneur ou simplement reconstruire l'image avec les correctifs de sécurité de Debian et de Python.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

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

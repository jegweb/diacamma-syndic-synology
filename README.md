# Diacamma Syndic sur NAS Synology (Container Manager)

Ce projet fournit de quoi déployer [Diacamma Syndic](https://www.diacamma.org) (gestion de copropriété, logiciel libre GPL) dans **Container Manager** sur un NAS Synology : une image Docker, un projet Compose et des sauvegardes automatiques. Toutes les fonctions de l'application sont conservées : comptabilité, appels de fonds, documents, courriels, impressions PDF, archives et restauration depuis l'interface.

Versions incluses : Diacamma Syndic 2.7.9 et Lucterios 2.7.9, sur Python 3.13 (Debian 13 « trixie »). Les dépendances sont figées dans `requirements.lock`.

## Sommaire

1. [Fonctionnement](#fonctionnement)
2. [Prérequis](#prérequis)
3. [Installation](#installation)
4. [Accès en HTTPS](#accès-en-https)
5. [Sauvegardes et restauration](#sauvegardes-et-restauration)
6. [Mise à jour](#mise-à-jour)
7. [Commandes d'administration](#commandes-dadministration)
8. [Variante PostgreSQL](#variante-postgresql)
9. [Permissions (PUID/PGID)](#permissions-puidpgid)
10. [Dépannage](#dépannage)
11. [Sécurité : récapitulatif](#sécurité--récapitulatif)

## Fonctionnement

Le projet lance deux conteneurs, construits à partir de la même image :

| Conteneur | Rôle |
| --- | --- |
| `diacamma-syndic` | L'application web (gunicorn). Au démarrage, il crée l'instance ou la met à jour (migrations, fichiers statiques). |
| `diacamma-syndic-sauvegarde` | Crée chaque nuit une archive Diacamma (`.lbk`) et supprime les plus anciennes. |

Les données se trouvent dans deux dossiers du projet sur le NAS :

| Dossier | Contenu |
| --- | --- |
| `data/` | L'instance Diacamma : réglages, base SQLite, documents, fichiers statiques |
| `backups/` | Les archives `.lbk` (visibles et restaurables depuis l'interface de Diacamma) et les instantanés pris avant chaque mise à jour |

Fichiers du projet :

| Fichier | Rôle |
| --- | --- |
| `docker-compose.yml` | Projet Container Manager (base SQLite, recommandé) |
| `docker-compose.postgresql.yml` | Variante avec une base PostgreSQL |
| `.env.example` | Modèle des réglages, à copier en `.env` |
| `Dockerfile`, `requirements.lock`, `docker/` | Construction de l'image |
| `scripts/` | Outils pour l'ordinateur de maintenance (mise à jour des versions, export d'image) |

## Prérequis

- DSM 7.2 ou plus récent, avec le paquet **Container Manager**.
- Un NAS 64 bits : Intel/AMD (`x86_64`) ou ARM 64 bits (`aarch64`).
- Environ 2 Go d'espace disque pour l'image et 300 Mo de mémoire vive. En test, l'application occupe environ 120 Mo au repos.
- Pour un accès hors du réseau local : un nom de domaine pointant vers votre box (par exemple `syndic.mondomaine.fr`).
- Un accès SSH au NAS est utile pour l'administration, mais pas obligatoire.

## Installation

### 1. Copier les fichiers sur le NAS

1. Dans **File Station**, créez le dossier `docker/diacamma-syndic` (le dossier partagé `docker` est créé par Container Manager).
2. Déposez-y le contenu de ce projet : `Dockerfile`, `docker-compose.yml`, `requirements.lock`, `.env.example` et le dossier `docker/`.
3. Créez-y deux dossiers vides : `data` et `backups`.

> Créez `data` et `backups` vous-même avec File Station. S'ils sont créés automatiquement par Docker, ils appartiennent à `root` et l'application ne peut pas y écrire (voir [Permissions](#permissions-puidpgid)).

### 2. Renseigner les réglages

Copiez `.env.example` en `.env`, puis ouvrez `.env` avec le paquet **Éditeur de texte**. Au minimum :

```ini
DIACAMMA_ALLOWED_HOSTS=syndic.mondomaine.fr
PUID=1026
PGID=100
```

- `DIACAMMA_ALLOWED_HOSTS` : le ou les noms de domaine utilisés pour accéder à Diacamma. S'il manque, le site répond « 400 Bad Request ». Le premier nom qui n'est pas une adresse IP sert aussi d'adresse du site dans les liens des courriels (`https://<nom>`).
- `PUID` et `PGID` : l'utilisateur et le groupe DSM propriétaires des dossiers `data` et `backups` (voir [Permissions](#permissions-puidpgid)).

Les autres réglages (heure et durée de conservation des sauvegardes, mot de passe initial…) sont décrits dans `.env.example`.

### 3. Créer le projet dans Container Manager

1. **Container Manager** → **Projet** → **Créer**.
2. Nom du projet : `diacamma-syndic`. Chemin : `/docker/diacamma-syndic`.
3. Source : **utiliser le fichier `docker-compose.yml` existant**.
4. Cochez **Configurer le portail Web via Web Station**. Les valeurs à saisir sont détaillées dans [Accès en HTTPS](#accès-en-https).
5. Validez. Container Manager construit l'image, ce qui prend 5 à 20 minutes selon le NAS, puis démarre les deux conteneurs.

La première initialisation (création de la base) prend encore une à quelques minutes. Le conteneur `diacamma-syndic` passe ensuite à l'état « sain » (*healthy*).

> **Si la construction échoue dans Container Manager**, construisez l'image sur un ordinateur équipé de Docker, avec `scripts/build-image.sh amd64` (ou `arm64` pour un NAS ARM). Importez ensuite `dist/diacamma-syndic-amd64.tar` dans **Container Manager** → **Image** → **Ajouter** → **Ajouter à partir d'un fichier**, puis créez le projet comme ci-dessus. L'image importée porte déjà le nom attendu par `docker-compose.yml`.

### 4. Récupérer le mot de passe administrateur

Au premier démarrage, un mot de passe aléatoire est créé pour le compte `admin`. Vous le trouverez à deux endroits :

- dans **Container Manager** → **Conteneur** → `diacamma-syndic` → **Journal** ;
- dans le fichier `data/MOT_DE_PASSE_ADMIN_INITIAL.txt`.

Connectez-vous, **changez ce mot de passe** dans Diacamma, puis supprimez le fichier.

Si vous avez renseigné `DIACAMMA_ADMIN_PASSWORD` dans `.env`, c'est ce mot de passe qui est utilisé. Retirez-le ensuite de `.env`.

Le compte par défaut de Diacamma (`admin` / `admin`) n'est jamais laissé actif : s'il réapparaît, par exemple après la restauration d'une archive venant d'une installation de bureau, il est remplacé au démarrage suivant.

### 5. Premiers réglages dans Diacamma

- Renseignez la fiche de la copropriété.
- Configurez le serveur d'envoi de courriels (SMTP) dans les paramètres de Diacamma, pour les appels de fonds et les convocations. Les envois partent par lots, depuis le conteneur.
- Si vous utilisez une clé DKIM, placez-la dans `data/` (par exemple `data/dkim/cle.pem`) et indiquez le chemin vu par le conteneur : `/data/dkim/cle.pem`.

## Accès en HTTPS

Le conteneur ne parle que **HTTP**, sur le port **8100** du NAS, et seulement pour le NAS lui-même (`127.0.0.1:8100:8000` dans `docker-compose.yml`). Le HTTPS est assuré par DSM, qui reçoit les visiteurs sur le port 443 et leur transmet les pages du conteneur :

```text
navigateur ──HTTPS, port 443──▶ DSM (Web Station, certificat) ──HTTP, port 8100──▶ conteneur
             └── côté portail : HTTPS, 443 ──┘                  └── côté service : HTTP, 8100 ──┘
```

Règle à retenir : **HTTPS et 443 se règlent côté portail** (ce que voit le navigateur), **HTTP et 8100 côté service** (le conteneur). Le port 8000, interne au conteneur, ne se saisit jamais.

L'option B fait passer l'accès par le proxy inversé de la box, au prix d'une sécurité moindre sur le réseau local.

### Option A : portail Web Station (recommandé)

À la création du projet, l'assistant de Container Manager propose de « Configurer le portail Web via Web Station ». On peut aussi le faire après coup dans **Web Station** → **Portail Web** → **Créer** → portail de services.

| Où | Réglage | Valeur |
| --- | --- | --- |
| Service (Container Manager) | Conteneur et port | `diacamma-syndic`, port **8100**, protocole **HTTP** |
| Portail (Web Station) | Type de portail | **Basé sur le nom** |
| Portail (Web Station) | Nom d'hôte | `syndic.mondomaine.fr` |
| Portail (Web Station) | Port | **HTTPS 443**. Le port HTTP 80 est facultatif. |
| Panneau de configuration → Sécurité → Certificat → **Paramètres** | Certificat du portail | le certificat de `syndic.mondomaine.fr` (Let's Encrypt) |
| Box | Redirection de ports | 443 vers le NAS, et 80 si DSM doit obtenir ou renouveler un certificat Let's Encrypt |
| `.env` | Réglages Diacamma | `DIACAMMA_ALLOWED_HOSTS=syndic.mondomaine.fr` et `DIACAMMA_HTTPS=true` |

Les libellés exacts peuvent varier selon la version de DSM. Si des personnes doivent se connecter depuis Internet, la redirection de ports de la box est nécessaire. Sinon, gardez l'accès limité au réseau local ou à un VPN.

### Variante de l'option A : proxy inversé du Panneau de configuration

Même principe, sans Web Station. Utilisez l'un **ou** l'autre pour un même nom de domaine, pas les deux.

1. **Panneau de configuration** → **Portail de connexion** → **Avancé** → **Proxy inversé** → **Créer** :
   - Source : protocole `HTTPS`, nom d'hôte `syndic.mondomaine.fr`, port `443`. Vous pouvez cocher HSTS.
   - Destination : protocole `HTTP`, nom d'hôte `localhost`, port `8100`.
   - Onglet **En-tête personnalisé** : ajoutez `X-Forwarded-Proto` avec la valeur `$scheme`.
   - Paramètres avancés : passez le délai de lecture du proxy à 300 secondes, pour les gros états PDF.
2. **Panneau de configuration** → **Sécurité** → **Certificat** : obtenez un certificat Let's Encrypt pour `syndic.mondomaine.fr`, puis associez-le à cette entrée du proxy inversé (bouton **Paramètres**).
3. Si des personnes doivent se connecter depuis Internet (copropriétaires, conseil syndical), redirigez le port 443 de votre box vers le NAS. Si l'usage reste interne, gardez l'accès limité au réseau local ou à un VPN.

Votre box a un proxy inversé et vous voulez l'utiliser, par exemple parce que son port 443 sert déjà ? Faites-le pointer vers le proxy inversé de DSM (`https://<IP-du-NAS>:443`) en conservant l'en-tête `Host` d'origine. Le conteneur ne change pas.

### Option B : proxy inversé de la box vers le conteneur

Ici, la box transmet directement au conteneur, sans passer par DSM.

1. Dans `docker-compose.yml`, ligne `ports`, remplacez `"127.0.0.1:8100:8000"` par `"8100:8000"`.
2. Dans `.env` (voir le bloc « Option B » de `.env.example`) :
   - gardez `DIACAMMA_HTTPS=true` ;
   - si la box réécrit l'en-tête `Host`, ajoutez l'IP du NAS à `DIACAMMA_ALLOWED_HOSTS`, par exemple `syndic.mondomaine.fr,192.168.1.10`.
3. Recréez le projet : relancez sa construction dans Container Manager. Un simple redémarrage ne relit ni `.env` ni le compose.
4. Dans la box, créez une règle de proxy inversé :
   - source `https://syndic.mondomaine.fr`, avec un certificat valide (Let's Encrypt par exemple) ;
   - destination `http://<IP-du-NAS>:8100`.
5. Si la box le permet :
   - envoyez l'en-tête `X-Forwarded-Proto: https`. Sans lui, seuls certains liens dans les courriels sont touchés ;
   - passez le délai d'attente à 300 secondes ;
   - autorisez des envois assez gros pour l'import d'archives `.lbk`.

> **Le HTTPS doit être assuré par la box.** En HTTP simple, les mots de passe circuleraient en clair sur Internet.
>
> **Le port 8100 devient joignable en HTTP clair depuis tout le réseau local**, en contournant le HTTPS de la box. Le pare-feu DSM ne filtre pas de façon fiable les ports publiés par Docker. Réservez cette option à un réseau local de confiance.

### Essai sur le réseau local

Pour un simple essai sur le réseau local, sans HTTPS :

1. Dans `docker-compose.yml`, remplacez `"127.0.0.1:8100:8000"` par `"8100:8000"`.
2. Dans `.env`, mettez `DIACAMMA_HTTPS=false` et ajoutez l'adresse IP du NAS à `DIACAMMA_ALLOWED_HOSTS`.
3. Recréez le projet, puis ouvrez `http://<ip-du-nas>:8100`.

Ne laissez pas cette configuration en production.

### Changer de nom de domaine

Les données n'ont pas à être modifiées : le nom de domaine n'est pas enregistré dans la base. Les liens envoyés par courriel (documents partagés, paiement en ligne) utilisent `https://` suivi du premier nom de `DIACAMMA_ALLOWED_HOSTS` qui n'est pas une adresse IP. Le journal du conteneur l'affiche au démarrage : `Adresse du site dans les courriels : …`.

1. Chez votre registraire, faites pointer le nouveau nom vers votre box, comme l'ancien.
2. Dans DSM, obtenez un certificat Let's Encrypt pour le nouveau nom (**Panneau de configuration** → **Sécurité** → **Certificat** → **Ajouter**).
3. Dans Web Station, changez le nom d'hôte du portail. Pour garder l'ancien nom pendant la transition, créez plutôt un second portail. Associez ensuite le nouveau certificat au portail (**Certificat** → **Paramètres**).
4. Dans `.env`, mettez le nouveau nom **en premier**, en gardant l'ancien pendant la transition : `DIACAMMA_ALLOWED_HOSTS=nouveau.mondomaine.fr,syndic.mondomaine.fr`. Recréez le projet : arrêtez-le, puis relancez sa construction.
5. Prévenez les utilisateurs : leurs favoris et les liens des courriels déjà envoyés pointent vers l'ancien nom.
6. Quand l'ancien nom ne sert plus, retirez-le de `DIACAMMA_ALLOWED_HOSTS`, recréez le projet, puis supprimez l'ancien portail et l'ancien certificat.

Si l'adresse d'expédition des courriels change aussi de domaine, mettez à jour l'expéditeur dans les paramètres de Diacamma, ainsi que les enregistrements SPF et DKIM du nouveau domaine.

Pour une adresse de site différente, par exemple avec un port non standard, fixez-la dans `.env` : `DIACAMMA_EXTRA_SETTINGS='{"LUCTERIOS_ROOT_URL": "https://syndic.mondomaine.fr:8443"}'`.

## Sauvegardes et restauration

### Ce qui est sauvegardé

- **Chaque nuit** (à 02:30 par défaut, réglable avec `BACKUP_TIME`), le service de sauvegarde crée `backups/auto_syndic_AAAAMMJJ-HHMMSS.lbk`. Cette archive Diacamma complète contient la base et les documents. Les archives automatiques de plus de `BACKUP_KEEP_DAYS` jours (30 par défaut) sont supprimées.
- **Depuis l'interface** de Diacamma (menu d'administration, archives), un administrateur peut créer, télécharger, importer et restaurer des archives. Elles sont rangées dans le même dossier `backups/`.
- **Avant chaque mise à jour** (base SQLite), un instantané de sécurité est créé automatiquement dans `backups/avant-mise-a-jour/`.

### Copie hors du NAS

Ces sauvegardes restent sur le NAS. Ajoutez le dossier `docker/diacamma-syndic` à une tâche **Hyper Backup** vers un autre support (disque USB, autre NAS, cloud). Le dossier `backups/` est le plus important : les archives `.lbk` sont cohérentes, alors qu'une copie de `data/` prise pendant une écriture peut ne pas l'être.

### Restaurer

- **Depuis l'interface** : menu des archives → choisir l'archive → restaurer.
- **En SSH** :

  ```sh
  sudo docker exec diacamma-syndic diacamma restore auto_syndic_20260101-023000.lbk
  sudo docker restart diacamma-syndic
  ```

- **Instantané d'avant mise à jour** (`.tar.gz`, base SQLite uniquement) : arrêtez le projet, renommez `data/syndic` en `data/syndic.casse`, extrayez l'archive dans `data/`, remettez les fichiers du projet dans la version précédente, puis reconstruisez et redémarrez.

## Mise à jour

1. Faites une sauvegarde : depuis l'interface, ou `sudo docker exec diacamma-syndic diacamma backup`.
2. Remplacez les fichiers du projet sur le NAS par ceux de la nouvelle version, au minimum `requirements.lock`. **Ne touchez pas à `data/`, `backups/` ni `.env`.**
3. Reconstruisez l'image et redémarrez le projet : dans Container Manager, arrêtez le projet puis relancez sa construction. En SSH, depuis `/volume1/docker/diacamma-syndic` :

   ```sh
   sudo docker compose build --pull && sudo docker compose up -d
   ```

4. Au démarrage, le conteneur détecte la nouvelle version. Il prend un instantané (SQLite), applique les migrations de la base, puis régénère les fichiers statiques. Suivez l'opération dans le journal.

Pensez aussi à reconstruire l'image de temps en temps (par exemple tous les mois), même sans nouvelle version de Diacamma : `--pull` récupère les correctifs de sécurité de l'image de base Debian/Python.

Pour préparer une nouvelle version sur l'ordinateur de maintenance, lancez `scripts/update-lock.sh`. Il résout les dernières versions 2.7.x et régénère `requirements.lock`. Testez localement avant de déployer.

## Commandes d'administration

En SSH, préfixez chaque commande par `sudo docker exec -it diacamma-syndic`, par exemple `sudo docker exec -it diacamma-syndic diacamma version`.

| Commande | Effet |
| --- | --- |
| `diacamma backup` | Crée une archive manuelle `backups/manuel_syndic_….lbk` |
| `diacamma restore <fichier.lbk>` | Restaure une archive de `backups/` (remplace les données) |
| `diacamma reset-admin-password` | Génère un nouveau mot de passe pour `admin` et réactive le compte |
| `diacamma version` | Affiche les versions de Diacamma, Lucterios et Django |
| `diacamma manage <args>` | Lance une commande Django `manage.py` sur l'instance |
| `diacamma admin <args>` | Lance une commande `lucterios_admin` (usage avancé) |

## Variante PostgreSQL

SQLite est la base par défaut des installations de bureau de Diacamma et convient à l'usage d'une copropriété. PostgreSQL est l'option retenue par le paquet YunoHost de Diacamma. Si vous la préférez :

1. Avant la première installation, remplacez `docker-compose.yml` par `docker-compose.postgresql.yml` (renommez-le en `docker-compose.yml`).
2. Créez les dossiers `postgresql` et `secrets` à côté de `data`.
3. Créez `secrets/db_password.txt` avec un mot de passe d'au moins 12 caractères (lettres, chiffres et `. _ ~ + -`), sur une seule ligne.
4. Créez le projet comme décrit plus haut.

La base n'est joignable que par Diacamma, sur un réseau Docker interne sans accès extérieur, et le mot de passe n'apparaît pas dans le fichier Compose. Il n'y a pas d'instantané automatique avant mise à jour avec PostgreSQL : faites toujours une sauvegarde au préalable.

### Changer de base de données

Le moteur de base d'une instance existante ne peut pas être changé en modifiant la configuration : le conteneur refuse de démarrer. Pour passer de SQLite à PostgreSQL ou l'inverse :

1. Créez une archive `.lbk`.
2. Installez un nouveau projet avec l'autre variante, dans un dossier `data` vide.
3. Restaurez l'archive dans le nouveau projet.

Procédez de la même façon pour changer de version majeure de PostgreSQL.

## Permissions (PUID/PGID)

Les conteneurs tournent sans privilèges, sous l'utilisateur `PUID:PGID` (par défaut `1026:100`, le premier compte créé sur DSM et le groupe `users`). Cet utilisateur doit pouvoir écrire dans `data` et `backups`.

- Pour connaître l'identifiant d'un compte, en SSH : `id nom_du_compte`. Reportez `uid` dans `PUID` et `gid` dans `PGID`.
- Si les droits ne conviennent pas, le conteneur s'arrête avec un message explicite dans son journal : `le dossier /data (propriétaire …) n'est pas accessible en écriture…`. Il indique le propriétaire actuel du dossier et la commande de correction. Le cas le plus courant est un dossier créé automatiquement par Docker, qui appartient alors à `root` (`0:0`). Pour corriger, en SSH, depuis le dossier du projet :

  ```sh
  sudo chown -R 1026:100 data backups
  ```

  Remplacez `1026:100` par vos `PUID:PGID`. Redémarrez ensuite le projet.
- Les fichiers créés par l'application ne sont lisibles que par leur propriétaire : `settings.py` contient la clé secrète de l'instance.

## Dépannage

| Symptôme | Cause probable et solution |
| --- | --- |
| « 400 Bad Request » | Le nom de domaine utilisé n'est pas dans `DIACAMMA_ALLOWED_HOSTS`. Avec l'option B, la box a peut-être réécrit l'en-tête `Host` : ajoutez l'IP du NAS. Corrigez `.env`, puis recréez le projet (arrêtez-le, puis relancez sa construction) : un simple redémarrage ne relit pas `.env`. |
| La connexion échoue sans message en HTTP | Avec `DIACAMMA_HTTPS=true`, le cookie de session n'est envoyé qu'en HTTPS. Passez par le proxy inverse ou, pour un essai, mettez `DIACAMMA_HTTPS=false`. |
| « Build project … failed » avec « container diacamma-syndic is unhealthy » | Le conteneur `diacamma-syndic` s'arrête au démarrage. Ce message venait d'une ancienne version de `docker-compose.yml` : avec la version actuelle, le projet est créé et le conteneur apparaît « en redémarrage ». La cause est dans **son** journal (Container Manager → Conteneur → `diacamma-syndic` → Journal), sur les lignes `[diacamma] ERREUR`. Si le conteneur n'apparaît pas, lancez-le au premier plan en SSH, depuis le dossier du projet : `sudo docker compose up diacamma` (Ctrl+C pour arrêter). Le plus souvent, ce sont les droits sur `data/` ou `backups/` (voir [Permissions](#permissions-puidpgid)). |
| Le conteneur redémarre en boucle | Lisez son journal. Le message commence par `[diacamma] ERREUR`. |
| « relation "CORE_parameter" does not exist » dans le journal PostgreSQL au premier démarrage | Sans conséquence : Lucterios interroge ses paramètres avant de créer les tables. |
| « pull access denied for diacamma-syndic » | Container Manager cherche l'image sur Docker Hub. Vérifiez que `docker-compose.yml` contient bien `pull_policy: build` (service `diacamma`) et `pull_policy: never` (service `sauvegarde`). |
| La construction de l'image échoue sur le NAS | Construisez sur un ordinateur avec `scripts/build-image.sh` et importez l'image (voir l'étape 3 de l'installation). |

## Sécurité : récapitulatif

Ce que fait le projet :

- Le compte `admin`/`admin` est remplacé dès le premier démarrage par un mot de passe aléatoire ou par celui fourni.
- Le mode débogage de Django est désactivé, alors que c'est le réglage par défaut de Lucterios.
- Les noms d'hôte autorisés sont contrôlés, et le cookie de session est marqué `Secure`, `HttpOnly` et `SameSite=Lax`.
- L'application n'est exposée que sur `127.0.0.1`, derrière le proxy inverse HTTPS de DSM (option A, réglage par défaut).
- Conteneurs sans root : système de fichiers en lecture seule, toutes les capacités Linux retirées, `no-new-privileges`, limite de mémoire.
- Les réglages, la base et les documents ne peuvent pas être servis par `/static/`. Lucterios les y copierait sinon (ils sont exclus puis vérifiés à chaque démarrage).
- La configuration est validée au démarrage : valeurs invalides ou dangereuses refusées, changement de moteur de base bloqué.
- Les versions de toutes les dépendances sont figées. PyQt6, qui ne sert qu'à l'interface de bureau, n'est pas installé.

Ce qui reste à votre charge :

- Changer le mot de passe initial et choisir des mots de passe solides pour tous les comptes.
- Tenir DSM et Container Manager à jour, et reconstruire l'image régulièrement.
- Copier les sauvegardes hors du NAS (Hyper Backup) et tester une restauration de temps en temps.
- N'ouvrir l'accès depuis Internet que si c'est nécessaire, et activer le blocage automatique des adresses IP dans DSM.

# Diacamma Syndic et Diacamma Asso sur NAS Synology (Container Manager)

> **Projet communautaire non officiel**, sans lien avec l'équipe de Diacamma. Signalez ici les problèmes du conteneur et de l'installation, et ceux de l'application elle-même sur le [forum Diacamma](https://forum.diacamma.org).

Ce projet fournit de quoi déployer [Diacamma](https://www.diacamma.org) (logiciel libre GPL) dans **Container Manager** sur un NAS Synology, pour ses deux applications : **Diacamma Syndic** (gestion de copropriété) et **Diacamma Asso** (gestion d'association). Il comprend une image Docker prête à l'emploi (Intel/AMD et ARM 64 bits), un projet Compose par application et des sauvegardes automatiques. Toutes les fonctions sont conservées : comptabilité, appels de fonds ou adhésions et cotisations, documents, courriels, impressions PDF, archives et restauration depuis l'interface.

> **Sans NAS Synology** (serveur Linux, VPS, NAS d'une autre marque) : l'image et les kits fonctionnent sur tout hôte Docker. Voir [HORS-SYNOLOGY.md](HORS-SYNOLOGY.md).

Versions incluses : Diacamma Syndic 2.7.10, Diacamma Asso 2.7.10 et Lucterios 2.7.10, sur Python 3.13 (Debian 13 « trixie »). Les dépendances sont figées dans `requirements.lock`. L'image, commune aux deux applications, est publiée sur `ghcr.io/jegweb/diacamma` ; les nouveautés sont dans le [journal des modifications](CHANGELOG.md).

## Démarrage rapide

1. Téléchargez le kit de votre application dans la [dernière version](https://github.com/jegweb/diacamma-synology/releases/latest) : `diacamma-syndic-<version>.zip` ou `diacamma-asso-<version>.zip`. N'utilisez pas les fichiers affichés sur la page du dépôt : ils peuvent viser une version en préparation, pas encore publiée.
2. Décompressez-le sur le NAS, dans `docker/diacamma-syndic` ou `docker/diacamma-asso`. Créez-y les dossiers `data`, `backups`, `postgresql` et `secrets`.
3. Copiez `.env.example` en `.env` et renseignez au moins `DIACAMMA_ALLOWED_HOSTS`.
4. Dans Container Manager, créez un projet à partir de ce dossier.
5. Récupérez le mot de passe `admin` dans le journal du conteneur.

Le détail de chaque étape est dans [Installation](#installation), et l'accès depuis Internet dans [Accès en HTTPS](#accès-en-https). Les exemples de ce guide sont ceux de Diacamma Syndic : pour Diacamma Asso, voir [Syndic ou Asso ?](#syndic-ou-asso-).

## Sommaire

1. [Syndic ou Asso ?](#syndic-ou-asso-)
2. [Fonctionnement](#fonctionnement)
3. [Prérequis](#prérequis)
4. [Installation](#installation)
5. [Accès en HTTPS](#accès-en-https)
6. [Sauvegardes et restauration](#sauvegardes-et-restauration)
7. [Mise à jour](#mise-à-jour)
8. [Commandes d'administration](#commandes-dadministration)
9. [Choix de la base de données](#choix-de-la-base-de-données)
10. [Permissions (PUID/PGID)](#permissions-puidpgid)
11. [Construire l'image soi-même](#construire-limage-soi-même)
12. [Dépannage](#dépannage)
13. [Sécurité : récapitulatif](#sécurité--récapitulatif)
14. [Contribuer, licence](#contribuer-licence)

## Syndic ou Asso ?

Les deux applications utilisent la même image. Chacune a son kit, qui fixe l'application, les noms et le port :

| | Diacamma Syndic (copropriété) | Diacamma Asso (association) |
| --- | --- | --- |
| Kit | `diacamma-syndic-<version>.zip` | `diacamma-asso-<version>.zip` |
| Dossier et nom du projet | `docker/diacamma-syndic`, `diacamma-syndic` | `docker/diacamma-asso`, `diacamma-asso` |
| Conteneurs | `diacamma-syndic`, `diacamma-syndic-sauvegarde`, `diacamma-syndic-db` | `diacamma-asso`, `diacamma-asso-sauvegarde`, `diacamma-asso-db` |
| Port publié sur le NAS | 8100 | 8101 |
| Instance et archives | `data/syndic/`, `auto_syndic_….lbk` | `data/asso/`, `auto_asso_….lbk` |

**Les exemples de ce guide sont ceux de Diacamma Syndic.** Pour Diacamma Asso, remplacez `syndic` par `asso` dans les noms (dossier, conteneurs, commandes), et `8100` par `8101`. Par exemple, `sudo docker exec diacamma-syndic diacamma backup` devient `sudo docker exec diacamma-asso diacamma backup`.

- Une installation correspond à une application. Pour utiliser les deux sur le même NAS, créez deux projets, chacun dans son dossier et avec son kit. Leurs ports différents leur permettent de fonctionner côte à côte, chacun avec son nom de domaine.
- Un kit posé sur les données de l'autre application est refusé au démarrage, sans toucher aux données.
- Une archive `.lbk` se restaure dans la même application : une archive de Diacamma Syndic ne passe pas dans Diacamma Asso.

### Plusieurs copropriétés ou associations

Chaque copropriété ou association a sa propre installation : un projet, un dossier, ses données et sa base. Les projets ne partagent rien. La base de chacun n'a aucun réseau, et aucun projet ne crée de réseau Docker (voir [Fonctionnement](#fonctionnement)) : leur nombre est limité seulement par la mémoire du NAS. Au repos, une installation en PostgreSQL occupe environ 200 Mo : 130 Mo pour l'application, 30 Mo pour la base, presque rien pour le service de sauvegarde. Comptez davantage pendant les impressions, les envois de courriels et les sauvegardes.

Pour une deuxième copropriété :

1. Créez le dossier `docker/diacamma-syndic-2`, avec ses sous-dossiers `data`, `backups`, `postgresql` et `secrets`. Copiez-y les fichiers du kit et un `.env` propre à cette copropriété (nom de domaine, mot de passe administrateur).
2. Ouvrez `docker-compose.yml` dans un éditeur de texte :
   - remplacez **partout** `diacamma-syndic` par `diacamma-syndic-2` (« Remplacer tout »). Cela change le nom du projet (ligne `name:`) et ceux des trois conteneurs. N'oubliez pas la ligne `name:` : avec le même nom de projet, Docker prendrait les conteneurs de la première copropriété pour ceux de la nouvelle et les remplacerait ;
   - remplacez `8100` par un port libre, par exemple `8102`.
3. Créez le projet `diacamma-syndic-2` dans Container Manager, puis son portail Web Station, avec son propre nom de domaine, vers ce port.
4. Dans `.env`, décalez l'heure de sauvegarde (`BACKUP_TIME`, par exemple `03:00`), pour que les sauvegardes ne tournent pas en même temps.

L'instance garde le nom `syndic`, dans le dossier `data/` de son propre projet. Si un nom de conteneur ou le port est resté identique, la création du projet échoue (« already in use », « port is already allocated ») sans toucher à l'autre installation. À chaque mise à jour, refaites ces remplacements dans le `docker-compose.yml` du nouveau kit, ou changez seulement le numéro de version de la ligne `image:`. Même principe pour une deuxième association : `diacamma-asso-2`, et un autre port libre.

## Fonctionnement

Le projet lance trois conteneurs : deux à partir de l'image Diacamma, et la base de données.

| Conteneur | Rôle |
| --- | --- |
| `diacamma-syndic` | L'application web (gunicorn). Au démarrage, il crée l'instance ou la met à jour (migrations, fichiers statiques). |
| `diacamma-syndic-sauvegarde` | Crée chaque nuit une archive Diacamma (`.lbk`) et supprime les plus anciennes. |
| `diacamma-syndic-db` | La base PostgreSQL (image officielle `postgres:17`), sans aucun réseau : les deux autres conteneurs la joignent par son socket, un fichier de connexion partagé en mémoire. |

Seul `diacamma-syndic` a un réseau, le réseau « bridge » par défaut de Docker (`172.17.0.0/16`), pour le portail web et l'envoi des courriels. Le projet ne crée pas de réseau Docker. Ainsi, plusieurs installations n'épuisent pas les plages d'adresses du NAS, et le pare-feu de DSM ne peut pas couper Diacamma de sa base.

Les données se trouvent dans quatre dossiers du projet sur le NAS :

| Dossier | Contenu |
| --- | --- |
| `data/` | L'instance Diacamma : réglages, documents, fichiers statiques |
| `backups/` | Les archives `.lbk` (visibles et restaurables depuis l'interface de Diacamma) |
| `postgresql/` | La base de données |
| `secrets/` | Le mot de passe interne de la base (`db_password.txt`), créé au premier démarrage. Laissez-le en place. |

Fichiers du kit d'installation, seuls nécessaires sur le NAS :

| Fichier | Rôle |
| --- | --- |
| `docker-compose.yml` | Projet Container Manager (base PostgreSQL, recommandé) |
| `docker-compose.sqlite.yml` | Variante avec une base SQLite, pour une seule personne qui saisit (voir [Choix de la base de données](#choix-de-la-base-de-données)) |
| `.env.example` | Modèle des réglages, à copier en `.env` |

Le dépôt contient aussi de quoi construire l'image (`Dockerfile`, `requirements.lock`, `docker/`) et des outils de maintenance (`scripts/`). Ils ne servent pas sur le NAS.

## Prérequis

- DSM 7.2 ou plus récent, avec le paquet **Container Manager** (sans Synology : voir [HORS-SYNOLOGY.md](HORS-SYNOLOGY.md)).
- Un NAS 64 bits : Intel/AMD (`x86_64`) ou ARM 64 bits (`aarch64`).
- Environ 3 Go d'espace disque pour les images (Diacamma et PostgreSQL) et 300 Mo de mémoire vive. En test, au repos, l'application occupe environ 120 Mo et la base environ 30 Mo.
- Un accès Internet depuis le NAS vers `ghcr.io`, pour télécharger l'image. Sans lui, voir [Construire l'image soi-même](#construire-limage-soi-même).
- Pour un accès hors du réseau local : un nom de domaine pointant vers votre box (par exemple `syndic.mondomaine.fr`).
- Un accès SSH au NAS est utile pour l'administration, mais pas obligatoire.

## Installation

### 1. Copier les fichiers sur le NAS

1. Téléchargez le kit de votre application depuis la page de la [dernière version](https://github.com/jegweb/diacamma-synology/releases/latest), rubrique **Assets** : `diacamma-syndic-<version>.zip` ou `diacamma-asso-<version>.zip`.
2. Dans **File Station**, créez le dossier `docker/diacamma-syndic`, ou `docker/diacamma-asso` (le dossier partagé `docker` est créé par Container Manager).
3. Déposez-y le fichier `.zip`, puis faites un clic droit dessus → **Extraire** → **Extraire ici**. Vous obtenez `docker-compose.yml`, `docker-compose.sqlite.yml` et `.env.example`. Le `.zip` peut ensuite être supprimé.
4. Créez-y quatre dossiers vides : `data`, `backups`, `postgresql` et `secrets`. Pour la variante SQLite, voir [Variante SQLite](#variante-sqlite).

> Créez ces dossiers vous-même avec File Station. S'ils sont créés automatiquement par Docker, ils appartiennent à `root` et les conteneurs ne peuvent pas y écrire (voir [Permissions](#permissions-puidpgid)).

### 2. Renseigner les réglages

Copiez `.env.example` en `.env`, puis ouvrez `.env` avec le paquet **Éditeur de texte**. Au minimum :

```ini
DIACAMMA_ALLOWED_HOSTS=syndic.mondomaine.fr
PUID=1026
PGID=100
```

- `DIACAMMA_ALLOWED_HOSTS` : le ou les noms de domaine utilisés pour accéder à Diacamma. S'il manque, le site répond « 400 Bad Request ». Le premier nom qui n'est pas une adresse IP sert aussi d'adresse du site dans les liens des courriels (`https://<nom>`).
- `PUID` et `PGID` : l'utilisateur et le groupe DSM propriétaires des dossiers du projet (voir [Permissions](#permissions-puidpgid)).

Les autres réglages (heure et durée de conservation des sauvegardes, mot de passe initial…) sont décrits dans `.env.example`.

### 3. Créer le projet dans Container Manager

1. **Container Manager** → **Projet** → **Créer**.
2. Nom du projet : `diacamma-syndic`. Chemin : `/docker/diacamma-syndic`.
3. Source : **utiliser le fichier `docker-compose.yml` existant**.
4. Cochez **Configurer le portail Web via Web Station**. Les valeurs à saisir sont détaillées dans [Accès en HTTPS](#accès-en-https).
5. Validez. Container Manager télécharge les images (quelques centaines de Mo chacune ; la bonne architecture est choisie automatiquement), puis démarre les trois conteneurs.

La première initialisation (création de la base) prend une à quelques minutes. Le conteneur `diacamma-syndic` passe ensuite à l'état « sain » (*healthy*).

> **Si le téléchargement de l'image échoue** (NAS sans accès à Internet, par exemple), voir [Construire l'image soi-même](#construire-limage-soi-même).

### 4. Récupérer le mot de passe administrateur

Au premier démarrage, un mot de passe aléatoire est créé pour le compte `admin`. Vous le trouverez à deux endroits :

- dans le journal du conteneur : **Container Manager** → **Conteneur** → double-clic sur `diacamma-syndic` (ou bouton **Détails**) → onglet **Journal** ;
- dans le fichier `data/MOT_DE_PASSE_ADMIN_INITIAL.txt`.

Connectez-vous, **changez ce mot de passe** dans Diacamma, puis supprimez le fichier.

Si vous avez renseigné `DIACAMMA_ADMIN_PASSWORD` dans `.env`, c'est ce mot de passe qui est utilisé. Retirez-le ensuite de `.env`.

Le compte par défaut de Diacamma (`admin` / `admin`) n'est jamais laissé actif : s'il réapparaît, par exemple après la restauration d'une archive venant d'une installation de bureau, il est remplacé au démarrage suivant.

### 5. Premiers réglages dans Diacamma

- Renseignez la fiche de la copropriété ou de l'association.
- Configurez le serveur d'envoi de courriels (SMTP) dans les paramètres de Diacamma, pour les appels de fonds, les convocations ou les relances de cotisation. Les envois partent par lots, depuis le conteneur.
- Si vous utilisez une clé DKIM, placez-la dans `data/` (par exemple `data/dkim/cle.pem`) et indiquez le chemin vu par le conteneur : `/data/dkim/cle.pem`.

## Accès en HTTPS

Le conteneur ne parle que **HTTP**, sur le port **8100** du NAS (**8101** pour Diacamma Asso), et seulement pour le NAS lui-même (`127.0.0.1:8100:8000` dans `docker-compose.yml`). Le HTTPS est assuré par DSM, qui reçoit les visiteurs sur le port 443 et leur transmet les pages du conteneur :

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
3. Si des personnes doivent se connecter depuis Internet (copropriétaires, conseil syndical, adhérents), redirigez le port 443 de votre box vers le NAS. Si l'usage reste interne, gardez l'accès limité au réseau local ou à un VPN.

Votre box a un proxy inversé et vous voulez l'utiliser, par exemple parce que son port 443 sert déjà ? Faites-le pointer vers le proxy inversé de DSM (`https://<IP-du-NAS>:443`) en conservant l'en-tête `Host` d'origine. Le conteneur ne change pas.

### Option B : proxy inversé de la box vers le conteneur

Ici, la box transmet directement au conteneur, sans passer par DSM.

1. Dans `docker-compose.yml`, ligne `ports`, remplacez `"127.0.0.1:8100:8000"` par `"8100:8000"`.
2. Dans `.env` (voir le bloc « Option B » de `.env.example`) :
   - gardez `DIACAMMA_HTTPS=true` ;
   - si la box réécrit l'en-tête `Host`, ajoutez l'IP du NAS à `DIACAMMA_ALLOWED_HOSTS`, par exemple `syndic.mondomaine.fr,192.168.1.10`.
3. Recréez le projet dans Container Manager : **Arrêter**, **Nettoyer**, puis **Créer**. Un simple redémarrage ne relit ni `.env` ni le compose.
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
4. Dans `.env`, mettez le nouveau nom **en premier**, en gardant l'ancien pendant la transition : `DIACAMMA_ALLOWED_HOSTS=nouveau.mondomaine.fr,syndic.mondomaine.fr`. Recréez le projet : **Arrêter**, **Nettoyer**, puis **Créer**.
5. Prévenez les utilisateurs : leurs favoris et les liens des courriels déjà envoyés pointent vers l'ancien nom.
6. Quand l'ancien nom ne sert plus, retirez-le de `DIACAMMA_ALLOWED_HOSTS`, recréez le projet, puis supprimez l'ancien portail et l'ancien certificat.

Si l'adresse d'expédition des courriels change aussi de domaine, mettez à jour l'expéditeur dans les paramètres de Diacamma, ainsi que les enregistrements SPF et DKIM du nouveau domaine.

Pour une adresse de site différente, par exemple avec un port non standard, fixez-la dans `.env` : `DIACAMMA_EXTRA_SETTINGS='{"LUCTERIOS_ROOT_URL": "https://syndic.mondomaine.fr:8443"}'`.

## Sauvegardes et restauration

### Ce qui est sauvegardé

- **Chaque nuit** (à 02:30 par défaut, réglable avec `BACKUP_TIME`), le service de sauvegarde crée `backups/auto_syndic_AAAAMMJJ-HHMMSS.lbk`. Cette archive Diacamma complète contient la base et les documents. Les archives automatiques de plus de `BACKUP_KEEP_DAYS` jours (30 par défaut) sont supprimées.
- **Depuis l'interface** de Diacamma (menu d'administration, archives), un administrateur peut créer, télécharger, importer et restaurer des archives. Elles sont rangées dans le même dossier `backups/`.
- **Avant chaque mise à jour**, avec la variante SQLite seulement, un instantané de sécurité est créé automatiquement dans `backups/avant-mise-a-jour/`.

### Copie hors du NAS

Ces sauvegardes restent sur le NAS. Ajoutez le dossier `docker/diacamma-syndic` à une tâche **Hyper Backup** vers un autre support (disque USB, autre NAS, cloud). Le dossier `backups/` est le plus important : les archives `.lbk` sont cohérentes, alors qu'une copie de `data/` ou de `postgresql/` prise pendant une écriture peut ne pas l'être. Une archive `.lbk` contient toutes les données et les documents, mais pas le mot de passe de la base : elle se restaure dans n'importe quelle installation neuve, PostgreSQL ou SQLite, sans lui.

### Restaurer

- **Depuis l'interface** : menu des archives → choisir l'archive → restaurer. La restauration démarre une dizaine de secondes après la confirmation, puis se poursuit en arrière-plan, parfois plusieurs minutes. Vous êtes déconnecté et la connexion échoue tant qu'elle n'est pas finie. **Ne redémarrez pas le conteneur pendant ce temps** : la restauration serait interrompue et la base resterait vide. Elle est terminée quand vous pouvez vous reconnecter avec les comptes de l'archive ; le lien « dernier journal d'archivage », dans la liste des archives, en donne le compte rendu.
- **En SSH** :

  ```sh
  sudo docker exec diacamma-syndic diacamma restore auto_syndic_20260101-023000.lbk
  sudo docker restart diacamma-syndic
  ```

- **Instantané d'avant mise à jour** (`.tar.gz`, variante SQLite uniquement) : arrêtez le projet, renommez `data/syndic` en `data/syndic.casse`, extrayez l'archive dans `data/`, remettez dans `docker-compose.yml` la version précédente de l'image (ligne `image:`), puis **Nettoyer** et **Créer** le projet.

## Mise à jour

Les versions s'écrivent `X.Y.Z-N` : `X.Y.Z` est la version de Diacamma (Syndic et Asso sortent ensemble, avec le même numéro), `N` la révision de l'empaquetage. Une révision peut seulement apporter les correctifs de sécurité de Debian et de Python : installez-les aussi. Pour être prévenu, cliquez sur **Watch** → **Custom** → **Releases** en haut de la page GitHub du projet.

1. Faites une sauvegarde : depuis l'interface, ou `sudo docker exec diacamma-syndic diacamma backup`.
2. Lisez les notes de la nouvelle version, puis remplacez `docker-compose.yml` sur le NAS par le fichier du nouveau kit qui correspond à votre base :
   - le dossier du projet contient un dossier `postgresql` : prenez `docker-compose.yml` ;
   - sinon, votre installation utilise SQLite : prenez `docker-compose.sqlite.yml` et renommez-le en `docker-compose.yml`.

   Attention : **Extraire ici** écrase votre `docker-compose.yml` par celui du kit, qui est la version PostgreSQL. En cas d'erreur de fichier, le conteneur refuse de démarrer, sans toucher aux données, et son journal indique le bon fichier. Si vous aviez modifié la ligne `ports` (option B), refaites la modification. Une autre façon de faire : dans votre fichier, changez seulement le numéro de version à la fin de la ligne `image:`. **Ne touchez pas à `data/`, `backups/`, `postgresql/`, `secrets/` ni `.env`.**
3. Dans **Container Manager** → **Projet**, sélectionnez le projet, puis choisissez successivement :
   - **Arrêter** ;
   - **Nettoyer** : les conteneurs sont supprimés, mais les dossiers de données du projet ne sont pas touchés ;
   - **Créer** : Container Manager relit le compose et `.env`, télécharge la nouvelle image et recrée les conteneurs.

   « Démarrer » ne suffit pas : il relance les conteneurs existants avec l'ancienne configuration. En SSH, depuis `/volume1/docker/diacamma-syndic` :

   ```sh
   sudo docker compose pull && sudo docker compose up -d
   ```

4. Au démarrage, le conteneur détecte la nouvelle version. Avec SQLite, il prend d'abord un instantané. Il applique ensuite les migrations de la base, puis régénère les fichiers statiques. Suivez l'opération dans le journal.
5. Supprimez l'ancienne image : **Container Manager** → **Image** → sélectionner l'image inutilisée → **Supprimer**.

### Installations d'avant la version 2.7.10-4

Depuis la version 2.7.10-4, l'image s'appelle `ghcr.io/jegweb/diacamma`, car elle contient aussi Diacamma Asso. Il n'y a rien de particulier à faire : le nouveau kit utilise ce nom, et la mise à jour se déroule comme ci-dessus. Depuis une version 2.7.10-1 à 2.7.10-3, Diacamma Syndic reste en version 2.7.10 : le conteneur n'applique aucune migration. Supprimez ensuite l'ancienne image `ghcr.io/jegweb/diacamma-syndic` (étape 5).

L'ancien nom, `ghcr.io/jegweb/diacamma-syndic`, garde les versions jusqu'à 2.7.10-4 pour les anciens kits, mais ne reçoit plus les suivantes : un ancien `docker-compose.yml` dont on change seulement le numéro de version pour une version plus récente échoue (« manifest unknown »).

Depuis 2.7.10-4, la base n'a plus de réseau : Diacamma la joint par son socket. **Prenez donc le `docker-compose.yml` du nouveau kit** ; ne vous contentez pas de changer le numéro de version dans l'ancien. Au premier démarrage, le journal indique `Adresse de la base mise à jour dans settings.py : /var/run/postgresql`. Les réseaux `diacamma-syndic_default` et `diacamma-syndic_backend` des versions précédentes ne servent plus. Container Manager les supprime normalement de lui-même ; s'ils figurent encore dans **Container Manager** → **Réseau**, supprimez-les.

**Revenir à une version d'avant 2.7.10-4 (PostgreSQL)** : l'ancienne version ne connaît pas le socket. Arrêtez le projet, remettez l'ancien `docker-compose.yml`, puis rendez à `settings.py` l'ancienne adresse de la base. En SSH, depuis le dossier du projet :

```sh
sudo sed -i 's|"HOST": "/var/run/postgresql",|"HOST": "db",|' data/syndic/settings.py
```

Ensuite, **Nettoyer** et **Créer**. Sans cette commande, l'ancienne version redémarre en boucle, sans toucher aux données (voir [Dépannage](#dépannage)). Avec SQLite, il suffit de remettre l'ancien fichier.

### Installations d'avant la version 2.7.10-3

Jusqu'à la version 2.7.10-2, `docker-compose.yml` utilisait SQLite. Si votre projet n'a pas de dossier `postgresql`, votre installation est en SQLite. Deux possibilités :

- garder SQLite : à chaque mise à jour, prenez `docker-compose.sqlite.yml` et renommez-le en `docker-compose.yml` ;
- passer à PostgreSQL, recommandé si plusieurs personnes saisissent : voir [Changer de base de données](#changer-de-base-de-données).

Les installations qui utilisaient déjà `docker-compose.postgresql.yml` prennent désormais `docker-compose.yml`. Leur fichier `secrets/db_password.txt` est conservé tel quel.

### Passer d'une image construite sur le NAS à l'image publiée

Les premières versions du projet construisaient l'image sur le NAS (`diacamma-syndic:local`). Pour passer à l'image publiée :

1. Faites une sauvegarde.
2. Remplacez `docker-compose.yml` par celui du kit, et refaites vos éventuelles modifications de la ligne `ports`.
3. Dans Container Manager : **Arrêter**, **Nettoyer**, puis **Créer**. Gardez l'image `diacamma-syndic:local` jusqu'à ce que tout fonctionne : pour revenir en arrière, il suffit de remettre l'ancien `docker-compose.yml` et de recommencer cette étape.

Tant que la version de Diacamma est la même, le conteneur ne voit aucune différence : pas de migration, données intactes. Vous pouvez ensuite supprimer l'image `diacamma-syndic:local` ainsi que les fichiers `Dockerfile`, `requirements.lock` et le dossier `docker/` du NAS.

## Commandes d'administration

En SSH, préfixez chaque commande par `sudo docker exec -it diacamma-syndic`, par exemple `sudo docker exec -it diacamma-syndic diacamma version`.

| Commande | Effet |
| --- | --- |
| `diacamma backup` | Crée une archive manuelle `backups/manuel_syndic_….lbk` |
| `diacamma restore <fichier.lbk>` | Restaure une archive de `backups/` (remplace les données) |
| `diacamma reset-admin-password` | Génère un nouveau mot de passe pour `admin` et réactive le compte |
| `diacamma version` | Affiche les versions de Diacamma, Lucterios et Django |
| `diacamma manage <args>` | Lance une commande Django `manage.py` sur l'instance |
| `diacamma admin <args>` | Lance une commande `lucterios_admin` (usage avancé). `check` et `update` ne fonctionnent pas : les mises à jour passent par une nouvelle image. |

## Choix de la base de données

Le kit propose deux variantes. L'image et les fonctions de Diacamma sont les mêmes.

| | PostgreSQL (`docker-compose.yml`, recommandé) | SQLite (`docker-compose.sqlite.yml`) |
| --- | --- | --- |
| Saisies simultanées | Plusieurs personnes peuvent enregistrer en même temps | Une seule à la fois : une seconde saisie simultanée peut échouer |
| Conteneurs | Trois : la base a le sien | Deux : la base est un fichier dans `data/` |
| Dossiers à créer | `data`, `backups`, `postgresql`, `secrets` | `data`, `backups` |
| Avant une mise à jour | Sauvegarde à faire soi-même | Instantané automatique, en plus de la sauvegarde |

**Pourquoi PostgreSQL par défaut.** Diacamma est une application web : le syndic, le conseil syndical et les copropriétaires, ou le bureau d'une association et ses adhérents, peuvent s'y connecter en même temps. Lucterios traite chaque requête dans une transaction. Avec SQLite, une écriture verrouille toute la base. Si deux personnes enregistrent en même temps, ou pendant une opération longue (clôture d'exercice, appels de fonds, renouvellement des adhésions, envoi de courriels par lots, sauvegarde), l'une d'elles peut recevoir l'erreur « database is locked ». Sa saisie est alors perdue, mais pas les données déjà enregistrées. PostgreSQL ne verrouille que les lignes modifiées. C'est aussi la base retenue par le paquet YunoHost de Diacamma, maintenu par son auteur.

**Quand SQLite suffit.** Une seule personne saisit à la fois, par exemple un syndic bénévole seul ou le trésorier d'une petite association, les autres se contentant de consulter. SQLite est la base des installations de bureau de Diacamma.

**Pourquoi pas MariaDB ou MySQL.** Lucterios sait les utiliser, mais leurs changements de structure ne sont pas transactionnels : une mise à jour interrompue laisserait la base à moitié migrée, alors qu'avec PostgreSQL une migration qui échoue est annulée. Leurs comparaisons de texte ignorent aussi, par défaut, la casse et les accents. Le paquet MariaDB de Synology n'est pas utilisé : la base reste dans le projet, isolée.

### Mot de passe de la base PostgreSQL

Au premier démarrage, le conteneur `diacamma-syndic-db` crée un mot de passe aléatoire dans `secrets/db_password.txt`. Il n'apparaît ni dans le compose ni dans `.env`.

Vous n'avez pas à le connaître ni à le noter. Il ne sert qu'entre Diacamma et sa base, jamais pour se connecter à Diacamma, et les archives `.lbk` n'en ont pas besoin. Laissez simplement le fichier en place : s'il disparaît, la base refuse de démarrer. Diacamma en garde une copie dans `data/syndic/settings.py`, qui permet de le recréer (voir [Dépannage](#dépannage)).

La base n'a aucun accès réseau. Seuls les conteneurs du projet la joignent, par son socket : un fichier de connexion partagé en mémoire (volume `db-socket`, propre au projet). Par ce socket, PostgreSQL ne vérifie pas le mot de passe : c'est l'absence de réseau qui protège la base. Le mot de passe ne serait exigé que pour une connexion par le réseau.

### Variante SQLite

1. Avant la première installation, supprimez `docker-compose.yml`, puis renommez `docker-compose.sqlite.yml` en `docker-compose.yml`.
2. Créez seulement les dossiers `data` et `backups`.
3. Créez le projet comme décrit dans [Installation](#installation).

### Changer de base de données

Le moteur de base d'une instance existante ne peut pas être changé en modifiant la configuration : le conteneur refuse de démarrer, sans toucher aux données. Pour passer de SQLite à PostgreSQL :

1. Créez une archive, depuis l'interface ou en SSH : `sudo docker exec diacamma-syndic diacamma backup`. Elle est rangée dans `backups/`.
2. Dans Container Manager, sélectionnez le projet : **Arrêter**, puis **Nettoyer**.
3. Dans File Station, renommez `data` en `data.sqlite`. Gardez-le jusqu'à ce que tout fonctionne.
4. Créez les dossiers vides `data`, `postgresql` et `secrets`. Si `postgresql` ou `secrets` existent déjà, créés par Docker après une erreur de fichier, supprimez-les d'abord.
5. Remplacez `docker-compose.yml` par celui du kit, la version PostgreSQL. Gardez `.env` et `backups/`.
6. **Créez** le projet. Une instance vide est créée, avec un nouveau mot de passe `admin` (voir le journal). Attendez que `diacamma-syndic` soit « sain ».
7. Restaurez l'archive en SSH : `sudo docker exec diacamma-syndic diacamma restore <archive>.lbk`. La commande peut durer plusieurs minutes : attendez la ligne `[diacamma] Restauration terminée`. Redémarrez ensuite le conteneur `diacamma-syndic`. Sans accès SSH, restaurez depuis l'interface, en attendant la fin comme expliqué dans [Restaurer](#restaurer), avant de redémarrer.
8. Vérifiez vos données. Les comptes et leurs mots de passe sont ceux de l'archive.

Pour revenir en arrière : **Arrêter**, **Nettoyer**, supprimez `data`, `postgresql` et `secrets`, renommez `data.sqlite` en `data`, remettez `docker-compose.sqlite.yml` renommé en `docker-compose.yml`, puis **Créer**.

Le passage de PostgreSQL à SQLite suit les mêmes étapes, avec la variante SQLite. Un changement de version majeure de PostgreSQL aussi, avec un dossier `postgresql` vide.

## Permissions (PUID/PGID)

Les conteneurs tournent sans privilèges, sous l'utilisateur `PUID:PGID` (par défaut `1026:100`, le premier compte créé sur DSM et le groupe `users`). Cet utilisateur doit pouvoir écrire dans `data`, `backups`, `postgresql` et `secrets`.

- Pour connaître l'identifiant d'un compte, en SSH : `id nom_du_compte`. Reportez `uid` dans `PUID` et `gid` dans `PGID`.
- Si les droits ne conviennent pas, le conteneur s'arrête avec un message explicite dans son journal : `le dossier /data (propriétaire …) n'est pas accessible en écriture…`. Il indique le propriétaire actuel du dossier et la commande de correction. Le cas le plus courant est un dossier créé automatiquement par Docker, qui appartient alors à `root` (`0:0`). Pour corriger, en SSH, depuis le dossier du projet :

  ```sh
  sudo chown -R 1026:100 data backups postgresql secrets
  ```

  Remplacez `1026:100` par vos `PUID:PGID`. Redémarrez ensuite le projet.
- Pour la base PostgreSQL, le message est dans le journal de `diacamma-syndic-db` : `[diacamma-db] ERREUR : impossible d'écrire dans le dossier secrets…`, ou `Permission denied` sur `/var/lib/postgresql/data`. La correction est la même.
- Les fichiers créés par l'application ne sont lisibles que par leur propriétaire : `settings.py` contient la clé secrète de l'instance.

## Construire l'image soi-même

Utile si le NAS n'a pas accès à `ghcr.io`, ou pour tester une image modifiée. Il faut un ordinateur équipé de Docker et une copie de ce dépôt.

1. Construisez l'image pour l'architecture du NAS : `scripts/build-image.sh amd64` (Intel/AMD) ou `scripts/build-image.sh arm64` (ARM). L'image porte le nom et la version écrits dans `docker-compose.yml`. Le script l'exporte dans `dist/diacamma-<version>-<arch>.tar`. La même image sert aux deux kits.
2. Importez ce fichier : **Container Manager** → **Image** → **Ajouter** → **Ajouter à partir d'un fichier**.
3. Dans `docker-compose.yml` sur le NAS, décommentez la ligne `# pull_policy: never` (retirez le `#`). Sans cela, Container Manager essaie de télécharger l'image et remplace la vôtre, ou échoue s'il n'a pas accès à Internet.
4. Créez le projet comme d'habitude. S'il existe déjà : **Arrêter**, **Nettoyer**, puis **Créer**.

Avec un accès SSH, vous pouvez aussi construire directement sur le NAS, depuis une copie du dépôt. Le nom de l'image doit être celui de la ligne `image:` du compose, par exemple : `sudo docker build -t ghcr.io/jegweb/diacamma:2.7.10-5 .`

## Dépannage

Commencez par le journal du conteneur : **Container Manager** → **Conteneur** → double-clic sur `diacamma-syndic` (ou bouton **Détails**) → onglet **Journal**. Les messages propres au conteneur commencent par `[diacamma]`. En SSH, pour n'afficher qu'eux :

```sh
sudo docker logs diacamma-syndic 2>&1 | grep '\[diacamma\]'
```

Un démarrage normal se termine par `[diacamma] Démarrage de Diacamma Syndic (…, image X.Y.Z-N).` (ou `Diacamma Asso`), suivi des lignes de gunicorn.

| Symptôme | Cause probable et solution |
| --- | --- |
| « 400 Bad Request » | Le nom de domaine utilisé n'est pas dans `DIACAMMA_ALLOWED_HOSTS`. Avec l'option B, la box a peut-être réécrit l'en-tête `Host` : ajoutez l'IP du NAS. Corrigez `.env`, puis recréez le projet (**Arrêter**, **Nettoyer**, puis **Créer**) : un simple redémarrage ne relit pas `.env`. |
| La connexion échoue sans message en HTTP | Avec `DIACAMMA_HTTPS=true`, le cookie de session n'est envoyé qu'en HTTPS. Passez par le proxy inverse ou, pour un essai, mettez `DIACAMMA_HTTPS=false`. |
| « Build project … failed » avec « container diacamma-syndic is unhealthy » (ou `diacamma-syndic-db`) | Le conteneur `diacamma-syndic` s'arrête au démarrage. Ce message venait d'une ancienne version de `docker-compose.yml` : avec la version actuelle, le projet est créé et le conteneur apparaît « en redémarrage ». La cause est dans **son** journal (Container Manager → Conteneur → `diacamma-syndic` → Journal), sur les lignes `[diacamma] ERREUR`. Si le conteneur n'apparaît pas, lancez-le au premier plan en SSH, depuis le dossier du projet : `sudo docker compose up diacamma` (Ctrl+C pour arrêter). Le plus souvent, ce sont les droits sur les dossiers du projet (voir [Permissions](#permissions-puidpgid)). |
| Le conteneur redémarre en boucle | Lisez son journal. Le message commence par `[diacamma] ERREUR`. |
| « l'instance existante utilise SQLite, mais ce docker-compose.yml est celui de PostgreSQL » | Votre installation est en SQLite et le `docker-compose.yml` du kit a remplacé le vôtre. Prenez `docker-compose.sqlite.yml`, renommez-le en `docker-compose.yml`, puis **Nettoyer** et **Créer**. Supprimez les dossiers `postgresql` et `secrets` s'ils ont été créés. Pour passer à PostgreSQL, voir [Changer de base de données](#changer-de-base-de-données). |
| « … mais ce kit est celui de Diacamma Asso » (ou de Diacamma Syndic) | Le dossier contient les données de l'autre application : le kit n'est pas le bon. Remettez le `docker-compose.yml` du kit de votre application, puis **Nettoyer** et **Créer**. Pour installer la seconde application à côté, créez un projet séparé (voir [Syndic ou Asso ?](#syndic-ou-asso-)). Les données n'ont pas été modifiées. |
| « En attente de la base PostgreSQL » qui se répète, puis « la base PostgreSQL … ne répond pas » | Lisez le journal de `diacamma-syndic-db`. Le plus souvent, `postgresql` ou `secrets` ont été créés par Docker et appartiennent à `root` (voir [Permissions](#permissions-puidpgid)). Si le message cite `db:5432` au lieu de `socket /var/run/postgresql`, le `docker-compose.yml` est celui d'une version d'avant 2.7.10-4 : prenez celui du kit. |
| « connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: No such file or directory » en boucle | Une version d'avant 2.7.10-4 a été remise sur une installation déjà passée en 2.7.10-4 : rétablissez l'ancienne adresse de la base (voir [Installations d'avant la version 2.7.10-4](#installations-davant-la-version-2710-4)). Sinon, le `docker-compose.yml` n'est pas celui du kit. |
| Les courriels ne partent pas (délai dépassé), alors que le pare-feu de DSM est activé | Le pare-feu doit laisser passer le réseau « bridge » de Docker : une règle qui autorise la source `172.17.0.0`, masque `255.255.0.0` (ou `172.16.0.0/12`, qui couvre tous les réseaux Docker en `172.x`). |
| Les courriels ne partent pas : nom du serveur de courriel introuvable (« Name or service not known ») | Sur le réseau « bridge », Diacamma reçoit les serveurs DNS du NAS. Si le NAS se sert de lui-même comme DNS (`127.0.0.1`, paquet DNS Server), Docker les remplace par des DNS publics, qui ne connaissent pas les noms du réseau local. Indiquez dans Diacamma l'adresse IP du serveur de courriel, ou un nom public. |
| « [diacamma-db] ERREUR : la base existe déjà dans postgresql/, mais secrets/db_password.txt manque » | Le fichier a été supprimé. Recréez-le à partir de la copie gardée par Diacamma. En SSH, depuis le dossier du projet : `sudo grep -o '"PASSWORD": "[^"]*' data/syndic/settings.py \| cut -d'"' -f4 \| sudo tee secrets/db_password.txt >/dev/null`, puis `sudo chown 1026:100 secrets/db_password.txt && sudo chmod 600 secrets/db_password.txt` (vos `PUID:PGID`). Redémarrez ensuite le projet. |
| « LegalEntity matching query does not exist » à chaque connexion, après une restauration | La restauration a été interrompue, le plus souvent par un redémarrage du conteneur pendant qu'elle tournait : la base est vide. Relancez-la en SSH, `sudo docker exec diacamma-syndic diacamma restore <archive>.lbk`, attendez `[diacamma] Restauration terminée`, puis redémarrez le conteneur. |
| Dans le journal de `diacamma-syndic-db` : « relation "CORE_parameter" does not exist » ou « the database system is starting up » au premier démarrage, « chmod: changing permissions of '/run/postgresql': Operation not permitted », ou « violates foreign key constraint » pendant une restauration | Sans conséquence. Lucterios interroge ses paramètres avant de créer les tables, et vide les tables sans tenir compte de leur ordre avant une restauration (PostgreSQL signale chaque tentative refusée). La base tourne sans droits root, dans un dossier déjà accessible. |
| « SyntaxWarning: invalid escape sequence » ou « Your models in app(s): … have changes that are not yet reflected in a migration » à chaque démarrage | Sans conséquence : ces messages viennent du code de Diacamma et Lucterios eux-mêmes. Ne lancez pas `makemigrations`. |
| « pull access denied » ou « denied » | Si le message cite `diacamma-syndic` sans `ghcr.io`, votre `docker-compose.yml` vient d'une ancienne version, qui construisait l'image sur le NAS : remplacez-le par celui du kit (voir [Mise à jour](#mise-à-jour)). S'il cite `ghcr.io/jegweb/diacamma` ou `ghcr.io/jegweb/diacamma-syndic`, l'image n'est pas accessible publiquement : signalez-le dans un ticket. |
| « Error » lors du téléchargement de l'image (« Pulling ») | Container Manager n'affiche pas la cause. Pour la voir, en SSH depuis le dossier du projet : `sudo docker compose pull`. |
| « manifest unknown » | La version écrite à la fin de la ligne `image:` de `docker-compose.yml` n'existe pas. Le plus souvent, le fichier a été copié depuis la page du dépôt au lieu du kit de la Release ; or il peut viser une version en préparation. Autre cas : la ligne `image:` porte l'ancien nom, `ghcr.io/jegweb/diacamma-syndic`, qui s'arrête à 2.7.10-4. Prenez le fichier du kit, ou corrigez la version d'après les [Releases](https://github.com/jegweb/diacamma-synology/releases), puis **Nettoyer** et **Créer**. |
| « no such host », « i/o timeout » ou « x509: certificate » lors du téléchargement | Le NAS n'arrive pas à joindre `ghcr.io` : vérifiez son DNS, son accès à Internet et son horloge (Panneau de configuration → Options régionales). À défaut, voir [Construire l'image soi-même](#construire-limage-soi-même). |
| Une image importée est remplacée ou ignorée | Décommentez `pull_policy: never` dans `docker-compose.yml` (voir [Construire l'image soi-même](#construire-limage-soi-même)). |

## Sécurité : récapitulatif

Ce que fait le projet :

- Le compte `admin`/`admin` est remplacé dès le premier démarrage par un mot de passe aléatoire ou par celui fourni.
- La base PostgreSQL n'a aucun accès réseau : seuls Diacamma et le service de sauvegarde, lui aussi sans réseau, la joignent par son socket, dans un volume propre au projet. C'est ce qui la protège : par le socket, PostgreSQL ne vérifie pas le mot de passe. Ce mot de passe aléatoire, créé au premier démarrage, ne serait exigé que pour une connexion par le réseau ; il n'apparaît ni dans le compose ni dans `.env`.
- Diacamma est sur le réseau « bridge » de Docker : les autres conteneurs de ce réseau peuvent atteindre son port web, qui demande une connexion, mais pas la base.
- Le mode débogage de Django est désactivé, alors que c'est le réglage par défaut de Lucterios.
- Les noms d'hôte autorisés sont contrôlés, et le cookie de session est marqué `Secure`, `HttpOnly` et `SameSite=Lax`.
- L'application n'est exposée que sur `127.0.0.1`, derrière le proxy inverse HTTPS de DSM (option A, réglage par défaut).
- Conteneurs sans root : système de fichiers en lecture seule, toutes les capacités Linux retirées, `no-new-privileges`, limite de mémoire.
- Les réglages, la base et les documents ne peuvent pas être servis par `/static/`. Lucterios les y copierait sinon (ils sont exclus puis vérifiés à chaque démarrage).
- La configuration est validée au démarrage : valeurs invalides ou dangereuses refusées, changement de moteur de base bloqué.
- Les versions de toutes les dépendances sont figées. PyQt6, qui ne sert qu'à l'interface de bureau, n'est pas installé.

Ce qui reste à votre charge :

- Changer le mot de passe initial et choisir des mots de passe solides pour tous les comptes.
- Tenir DSM et Container Manager à jour, et installer les nouvelles versions de l'image, révisions comprises.
- Copier les sauvegardes hors du NAS (Hyper Backup) et tester une restauration de temps en temps.
- N'ouvrir l'accès depuis Internet que si c'est nécessaire, et activer le blocage automatique des adresses IP dans DSM.

Pour signaler une faille, voir [SECURITY.md](SECURITY.md) ; ne publiez pas de ticket public.

## Contribuer, licence

Les retours d'installation, questions et corrections sont les bienvenus : voir [CONTRIBUTING.md](CONTRIBUTING.md). Les questions vont dans les [Discussions](https://github.com/jegweb/diacamma-synology/discussions), les problèmes du conteneur dans les tickets.

Pour l'application Diacamma elle-même, adressez-vous à l'équipe Diacamma : les questions d'utilisation sur son [forum](https://forum.diacamma.org), les bogues dans ses tickets, ceux de [Diacamma Syndic](https://github.com/Diacamma2/syndic/issues) ou de [Diacamma Asso](https://github.com/Diacamma2/asso/issues).

Ce projet (Dockerfile, scripts, fichiers Compose, documentation) est distribué sous licence **GPL-3.0-or-later** : voir [LICENSE](LICENSE). Copyright (C) 2026 jegweb.

Diacamma Syndic, Diacamma Asso et le framework Lucterios, inclus dans l'image, sont des logiciels libres publiés par leurs auteurs sous leurs propres licences. Ce projet ne fait que les empaqueter, sans les modifier.

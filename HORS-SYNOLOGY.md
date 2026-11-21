# Diacamma sans NAS Synology

Le [README](README.md) décrit l'installation dans Container Manager, sur un NAS Synology. L'image et les kits fonctionnent pourtant sur n'importe quel hôte Docker : serveur Linux, VPS, Raspberry Pi, NAS d'une autre marque. Ce guide donne les différences, pour une personne à l'aise avec la ligne de commande.

Ce qui ne change pas : l'image, les kits, les deux fichiers Compose, le fichier `.env`, les sauvegardes et toutes les fonctions de Diacamma. Les sections communes du README s'appliquent telles quelles : [Syndic ou Asso ?](README.md#syndic-ou-asso-), [Fonctionnement](README.md#fonctionnement), [Choix de la base de données](README.md#choix-de-la-base-de-données), [Sécurité](README.md#sécurité--récapitulatif).

Ce qui change :

- pas d'interface graphique : le projet se pilote avec `docker compose`, depuis son dossier ;
- pas de Web Station : le proxy inverse qui assure le HTTPS est à installer soi-même ;
- les dossiers appartiennent à votre compte, pas au premier compte de DSM : `PUID` et `PGID` sont à adapter.

Le projet est testé en continu sur Ubuntu (intégration continue de GitHub) et essayé sous Docker Desktop pour macOS, qui convient pour un essai mais pas pour la production. Les retours sur d'autres systèmes sont les bienvenus dans les [Discussions](https://github.com/jegweb/diacamma-synology/discussions).

Comme dans le README, les exemples sont ceux de Diacamma Syndic. Pour Diacamma Asso, remplacez `syndic` par `asso` et le port `8100` par `8101`.

## Prérequis

- Linux 64 bits, sur processeur Intel/AMD (`x86_64`) ou ARM (`aarch64`). Sur Raspberry Pi, il faut un système 64 bits.
- Docker Engine 24 ou plus récent, avec le plugin Compose v2 : `docker compose version` doit répondre. L'ancien `docker-compose` (v1) ne convient pas.
- `curl` et `unzip` (sur Debian ou Ubuntu : `sudo apt install curl unzip`).
- Un compte ordinaire, pas `root` : les conteneurs prennent son identifiant (voir plus bas). Sur un VPS où l'on se connecte en `root`, créez-en un (`adduser diacamma`).
- Environ 3 Go d'espace disque pour les images et 300 Mo de mémoire vive.
- Un accès à `ghcr.io` (image Diacamma) et à Docker Hub (image `postgres:17`).
- Pour un accès depuis Internet : un nom de domaine qui pointe vers la machine, et les ports 80 et 443 ouverts vers elle.

Les commandes ci-dessous supposent que votre compte peut lancer Docker (groupe `docker`). Sinon, préfixez-les par `sudo`.

## Installation

```sh
# Numéro de la dernière version publiée (page « Releases » du dépôt)
VERSION=$(curl -fsSLo /dev/null -w '%{url_effective}' https://github.com/jegweb/diacamma-synology/releases/latest)
VERSION=${VERSION##*/v}; echo "$VERSION"

sudo mkdir -p /srv/diacamma-syndic && sudo chown "$(id -u):$(id -g)" /srv/diacamma-syndic
cd /srv/diacamma-syndic
curl -fLO "https://github.com/jegweb/diacamma-synology/releases/download/v$VERSION/diacamma-syndic-$VERSION.zip"
unzip "diacamma-syndic-$VERSION.zip" && rm "diacamma-syndic-$VERSION.zip"
mkdir data backups postgresql secrets
cp .env.example .env
```

Créez les quatre dossiers vous-même, avec votre compte, avant le premier démarrage : sinon Docker les crée au nom de `root` et les conteneurs ne peuvent pas y écrire. Pour la variante SQLite, voir [Variante SQLite](README.md#variante-sqlite).

Dans `.env`, renseignez au moins le nom de domaine et votre propre identifiant. Les valeurs `1026` et `100` du modèle sont celles du premier compte de DSM ; `id -u` et `id -g` donnent les vôtres. N'indiquez jamais `0` (`root`) : sans privilèges, la base ne démarre pas sous cet identifiant.

```ini
DIACAMMA_ALLOWED_HOSTS=syndic.mondomaine.fr
PUID=1000
PGID=1000
```

Démarrez ensuite le projet et suivez la première initialisation :

```sh
docker compose up -d
docker compose logs -f diacamma     # Ctrl+C pour quitter le journal
```

Le démarrage est terminé quand `docker compose ps` affiche `diacamma-syndic` à l'état `healthy`. Le mot de passe du compte `admin` est dans le journal et dans `data/MOT_DE_PASSE_ADMIN_INITIAL.txt` : changez-le à la première connexion, puis supprimez le fichier (voir [Récupérer le mot de passe administrateur](README.md#4-récupérer-le-mot-de-passe-administrateur)).

## Accès en HTTPS

Le conteneur ne parle que HTTP, sur le port 8100 de la machine, et seulement pour elle (`127.0.0.1:8100:8000` dans `docker-compose.yml`). Un proxy inverse installé sur la même machine reçoit les visiteurs en HTTPS et leur transmet les pages. Il doit :

- conserver l'en-tête `Host` d'origine, qui doit figurer dans `DIACAMMA_ALLOWED_HOSTS` (sinon « 400 Bad Request ») ;
- envoyer l'en-tête `X-Forwarded-Proto` ;
- attendre la réponse au moins 300 secondes, pour les gros états PDF ;
- accepter des envois volumineux, pour l'import d'archives `.lbk`.

Gardez `DIACAMMA_HTTPS=true` : le cookie de session n'est alors envoyé qu'en HTTPS.

Pour un essai sans HTTPS ni proxy, mettez `DIACAMMA_HTTPS=false` dans `.env`, puis `docker compose up -d`, et ouvrez `http://localhost:8100` sur la machine elle-même. Sur un serveur distant, passez par un tunnel SSH depuis votre ordinateur : `ssh -L 8100:127.0.0.1:8100 compte@serveur`, puis `http://localhost:8100` dans votre navigateur. N'ouvrez pas le port à tout le réseau comme dans l'[essai sur le réseau local](README.md#essai-sur-le-réseau-local) du README : sur un serveur exposé à Internet, les mots de passe circuleraient en clair. Remettez ensuite `DIACAMMA_HTTPS=true`.

### Caddy

[Caddy](https://caddyserver.com) obtient et renouvelle seul le certificat Let's Encrypt, et transmet `Host` et `X-Forwarded-Proto` sans réglage. Dans `/etc/caddy/Caddyfile` :

```caddy
syndic.mondomaine.fr {
	reverse_proxy 127.0.0.1:8100
}
```

### nginx

Certificat obtenu par exemple avec `certbot --nginx` :

```nginx
server {
    listen 443 ssl;
    server_name syndic.mondomaine.fr;
    ssl_certificate     /etc/letsencrypt/live/syndic.mondomaine.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/syndic.mondomaine.fr/privkey.pem;

    client_max_body_size 1g;    # import d'archives .lbk

    location / {
        proxy_pass http://127.0.0.1:8100;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;    # adresse du visiteur dans le journal
        proxy_read_timeout 300s;
    }
}
```

### Proxy lancé dans un conteneur

Traefik, Caddy ou Nginx Proxy Manager lancés dans Docker ne peuvent pas joindre Diacamma par le nom `diacamma-syndic` : le projet ne crée aucun réseau, et Diacamma est sur le réseau « bridge » par défaut de Docker. Ils ne peuvent pas non plus viser `127.0.0.1`, qui désigne alors leur propre conteneur.

Le plus simple est de lancer le proxy sur le réseau de la machine (`network_mode: host`) : il vise alors `127.0.0.1:8100` comme ci-dessus. Par exemple, avec Caddy et le `Caddyfile` précédent dans le même dossier :

```yaml
services:
  caddy:
    image: caddy:2
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy-data:/data
```

Brancher plutôt Diacamma sur le réseau du proxy oblige à modifier son `docker-compose.yml` (retirer `network_mode: bridge`, déclarer le réseau externe du proxy), et donc à refaire la modification à chaque mise à jour.

### Proxy sur une autre machine

Si le proxy est ailleurs sur le réseau local (box, autre serveur), publiez le port pour tout le réseau, comme pour l'[option B du README](README.md#option-b--proxy-inversé-de-la-box-vers-le-conteneur) : remplacez `"127.0.0.1:8100:8000"` par `"8100:8000"` dans `docker-compose.yml`, puis `docker compose up -d`. Le port 8100 devient alors joignable en HTTP clair depuis le réseau. Attention : sous Linux, les ports publiés par Docker contournent les règles d'ufw, et souvent celles de firewalld. Ne comptez pas sur le pare-feu de la machine pour les filtrer.

## Mise à jour

1. Faites une sauvegarde : `docker compose exec diacamma diacamma backup`.
2. Lisez les notes de la nouvelle version, téléchargez son kit, puis remplacez `docker-compose.yml` par celui qui correspond à votre base :

   ```sh
   VERSION=$(curl -fsSLo /dev/null -w '%{url_effective}' https://github.com/jegweb/diacamma-synology/releases/latest)
   VERSION=${VERSION##*/v}; echo "$VERSION"
   curl -fLO "https://github.com/jegweb/diacamma-synology/releases/download/v$VERSION/diacamma-syndic-$VERSION.zip"
   # Une seule des deux lignes suivantes :
   unzip -o "diacamma-syndic-$VERSION.zip" docker-compose.yml                               # PostgreSQL (dossier postgresql/ présent)
   unzip -p "diacamma-syndic-$VERSION.zip" docker-compose.sqlite.yml > docker-compose.yml   # SQLite
   rm "diacamma-syndic-$VERSION.zip"
   ```

   Refaites ensuite vos éventuelles modifications (ligne `ports`…). Ne touchez pas à `data/`, `backups/`, `postgresql/`, `secrets/` ni `.env`.
3. Téléchargez la nouvelle image et recréez les conteneurs :

   ```sh
   docker compose pull && docker compose up -d
   ```

   `docker compose up -d` tient lieu de la séquence « Arrêter, Nettoyer, Créer » du README. Il suffit aussi après une modification de `.env` : les conteneurs dont la configuration a changé sont recréés.
4. Suivez la mise à jour dans le journal (`docker compose logs -f diacamma`), puis supprimez l'ancienne image : `docker image rm ghcr.io/jegweb/diacamma:<ancienne version>`.

## Administration et dépannage

Les [commandes d'administration](README.md#commandes-dadministration) et le [dépannage](README.md#dépannage) du README s'appliquent, depuis le dossier du projet. Les lignes propres à Container Manager et au pare-feu de DSM ne vous concernent pas. Équivalents courants :

| Pour | Commande |
| --- | --- |
| Voir les messages du conteneur | `docker compose logs diacamma 2>&1 \| grep '\[diacamma\]'` |
| Créer une archive | `docker compose exec diacamma diacamma backup` |
| Restaurer une archive | `docker compose exec diacamma diacamma restore <archive>.lbk`, puis `docker compose restart diacamma` |
| Nouveau mot de passe `admin` | `docker compose exec diacamma diacamma reset-admin-password` |
| Voir les versions | `docker compose exec diacamma diacamma version` |
| Arrêter le projet | `docker compose down` (les dossiers de données ne sont pas touchés) |

Les droits sur les dossiers se corrigent comme dans [Permissions](README.md#permissions-puidpgid), avec vos `PUID:PGID` : `sudo chown -R "$(id -u):$(id -g)" data backups postgresql secrets`.

Courriels : sur le réseau « bridge », Diacamma reçoit les serveurs DNS de la machine. S'ils ne sont joignables que localement (`127.0.0.1`), Docker les remplace par des DNS publics, qui ne connaissent pas les noms de votre réseau local : indiquez dans Diacamma l'adresse IP du serveur de courriel, ou un nom public.

## Sauvegardes hors de la machine

Les archives quotidiennes restent dans `backups/`. Copiez ce dossier ailleurs avec l'outil de votre choix (restic, borg, rsync vers un autre support…). Les archives `.lbk` sont cohérentes, alors qu'une copie de `data/` ou de `postgresql/` prise pendant une écriture peut ne pas l'être. Voir aussi [Sauvegardes et restauration](README.md#sauvegardes-et-restauration).

## Plusieurs installations

Même procédure que dans [Plusieurs copropriétés ou associations](README.md#plusieurs-copropriétés-ou-associations) : un dossier par installation, et dans son `docker-compose.yml` un autre nom de projet, d'autres noms de conteneurs et un autre port. Ajoutez au proxy inverse une entrée par nom de domaine.

## Construire l'image soi-même

Depuis une copie du dépôt, sur la machine elle-même : `docker build -t ghcr.io/jegweb/diacamma:<version> .`, avec le nom et la version de la ligne `image:` du compose. `docker compose up -d` ne télécharge que les images absentes : il prend donc la vôtre. La ligne `pull_policy: never` du compose ne sert qu'à éviter qu'un `docker compose pull` ne la remplace.

## Cas non testés

- **Docker sans root (rootless) et Podman** : les identifiants du conteneur y correspondent à d'autres identifiants sur la machine, et `PUID`/`PGID` ne désignent plus votre compte. Non pris en charge pour l'instant.
- **SELinux actif** (Fedora, RHEL, Rocky Linux…) : les dossiers montés doivent porter le type `container_file_t`, sinon le conteneur ne peut pas y écrire malgré des droits corrects. Par exemple, depuis le dossier du projet : `sudo chcon -R -t container_file_t data backups postgresql secrets`.

Si vous faites fonctionner le projet dans l'un de ces cas, dites-le dans les [Discussions](https://github.com/jegweb/diacamma-synology/discussions).

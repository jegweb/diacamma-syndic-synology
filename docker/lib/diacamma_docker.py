"""Outils internes du conteneur Diacamma Syndic, appelés par bin/diacamma.

Usage : python diacamma_docker.py <commande> [arguments]
"""
import ipaddress
import json
import os
import re
import secrets
import shutil
import sqlite3
import string
import sys
import tarfile
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DATA_DIR = Path('/data')
BACKUP_DIR = Path('/backups')
DEFAULT_ADMIN_PASSWORD = 'admin'  # créé par la migration CORE 0001 de Lucterios
ADMIN_PASSWORD_FILE = DATA_DIR / 'MOT_DE_PASSE_ADMIN_INITIAL.txt'

SETTING_KEY_RE = re.compile(r'^[A-Z][A-Z0-9_]*$')
HOST_RE = re.compile(r'^\.?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$')
# Lucterios lit ces clés lui-même ; elles ne doivent pas passer par les réglages additionnels.
FORBIDDEN_KEYS = {'SECRET_KEY', 'DATABASES', 'BASE_DIR'}
# lucterios_admin écrit les chaînes de premier niveau entre guillemets, sans échappement.
UNSAFE_CHARS = set('"\\\n\r')

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {'simple': {'format': '%(asctime)s %(levelname)s %(name)s: %(message)s'}},
    'handlers': {'console': {'class': 'logging.StreamHandler', 'formatter': 'simple'}},
    'loggers': {
        'django': {'handlers': ['console'], 'level': 'ERROR', 'propagate': False},
        'lucterios': {'handlers': ['console'], 'level': 'WARNING', 'propagate': False},
        'diacamma': {'handlers': ['console'], 'level': 'WARNING', 'propagate': False},
        'apscheduler': {'handlers': ['console'], 'level': 'WARNING', 'propagate': False},
    },
}


def log(message):
    print(f'[diacamma] {message}', file=sys.stderr, flush=True)


def fail(message):
    log(f'ERREUR : {message}')
    sys.exit(2)


def env_bool(name, default):
    value = os.environ.get(name, '').strip().lower()
    if value == '':
        return default
    if value in ('1', 'true', 'yes', 'oui', 'on'):
        return True
    if value in ('0', 'false', 'no', 'non', 'off'):
        return False
    fail(f'{name} doit valoir true ou false (valeur reçue : {value!r}).')


def allowed_hosts():
    hosts = ['localhost', '127.0.0.1']
    for raw in re.split(r'[\s,]+', os.environ.get('DIACAMMA_ALLOWED_HOSTS', '').strip()):
        # Tolère une URL complète (https://syndic.fr/, syndic.fr:443) : seul le nom compte.
        host = re.sub(r'^[A-Za-z][A-Za-z0-9+.-]*://', '', raw).split('/')[0]
        host = re.sub(r':\d+$', '', host)
        if host != raw:
            log(f'DIACAMMA_ALLOWED_HOSTS : « {raw} » interprété comme « {host} ».')
        if not host or host in hosts:
            continue
        if host == '*':
            log('ATTENTION : DIACAMMA_ALLOWED_HOSTS=* accepte n\'importe quel nom d\'hôte.')
        elif not HOST_RE.match(host):
            fail(f'nom d\'hôte invalide dans DIACAMMA_ALLOWED_HOSTS : {host!r}.')
        hosts.append(host)
    if len(hosts) == 2:
        log('ATTENTION : DIACAMMA_ALLOWED_HOSTS est vide ; seul l\'accès par localhost fonctionnera.')
    return hosts


def is_ip_address(host):
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return False
    return True


def root_url(hosts, https):
    """Adresse du site dans les liens envoyés par courriel (LUCTERIOS_ROOT_URL).

    Sans elle, Lucterios retient l'adresse de la première requête qui en a besoin,
    jusqu'au redémarrage suivant, et les envois par lots repris au démarrage partent
    avec des liens incomplets. On prend le premier nom de DIACAMMA_ALLOWED_HOSTS qui
    n'est pas une adresse IP. En HTTP (essai local, port 8100), on ne la fixe pas :
    le port compte dans l'adresse.
    """
    if not https:
        return ''
    for host in hosts:
        if host in ('localhost', '*') or host.startswith('.') or is_ip_address(host):
            continue
        return f'https://{host}'
    return ''


def check_admin_password():
    password = os.environ.get('DIACAMMA_ADMIN_PASSWORD', '')
    if password and len(password) < 12:
        fail(f'DIACAMMA_ADMIN_PASSWORD doit contenir au moins 12 caractères (il en a {len(password)}). '
             'Allongez-le ou laissez-le vide pour qu\'un mot de passe soit généré.')


def extra_settings():
    """Réglages Django passés à lucterios_admin (option -e), au format JSON.

    Valide aussi le reste de la configuration, avant toute création d'instance.
    """
    check_admin_password()
    language = os.environ.get('DIACAMMA_LANGUAGE', 'fr').strip()
    if language not in ('fr', 'en'):
        fail('DIACAMMA_LANGUAGE doit valoir fr ou en.')
    time_zone = os.environ.get('TZ', 'Europe/Paris').strip()
    try:
        ZoneInfo(time_zone)
    except (ZoneInfoNotFoundError, ValueError):
        fail(f'fuseau horaire TZ inconnu : {time_zone!r}.')
    https = env_bool('DIACAMMA_HTTPS', True)
    hosts = allowed_hosts()
    extra = {
        'DEBUG': False,
        'LANGUAGE_CODE': language,
        'TIME_ZONE': time_zone,
        'ALLOWED_HOSTS': hosts,
        # Toujours écrite, même vide : « modif » conserve sinon une ancienne valeur.
        'LUCTERIOS_ROOT_URL': root_url(hosts, https),
        'BACKUP_DIRECTORY': str(BACKUP_DIR),
        'BACKUP_READONLY': env_bool('DIACAMMA_BACKUP_READONLY', False),
        'SESSION_COOKIE_SECURE': https,
        # Sûr uniquement parce que le port n'est publié que vers le proxy inverse.
        'SECURE_PROXY_SSL_HEADER': ['HTTP_X_FORWARDED_PROTO', 'https'] if https else None,
        'LOGGING': LOGGING,
    }
    advanced = os.environ.get('DIACAMMA_EXTRA_SETTINGS', '').strip()
    if advanced:
        try:
            advanced = json.loads(advanced)
        except ValueError as error:
            fail(f'DIACAMMA_EXTRA_SETTINGS n\'est pas du JSON valide : {error}.')
        if not isinstance(advanced, dict):
            fail('DIACAMMA_EXTRA_SETTINGS doit être un objet JSON ({"CLE": valeur}).')
        for key in advanced:
            if not SETTING_KEY_RE.match(key) or key in FORBIDDEN_KEYS:
                fail(f'clé interdite ou invalide dans DIACAMMA_EXTRA_SETTINGS : {key!r}.')
        extra.update(advanced)
    for key, value in extra.items():
        if isinstance(value, str) and UNSAFE_CHARS & set(value):
            fail(f'la valeur de {key} contient un caractère interdit (guillemet, antislash ou saut de ligne).')
    if extra['LUCTERIOS_ROOT_URL']:
        log(f'Adresse du site dans les courriels : {extra["LUCTERIOS_ROOT_URL"]}')
    print(json.dumps(extra, separators=(',', ':')))


def generate_password(length=20):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def setup_django(instance):
    sys.path.insert(0, str(DATA_DIR))
    os.environ['DJANGO_SETTINGS_MODULE'] = f'{instance}.settings'
    import django
    django.setup()


def secure_admin(instance, force=False):
    """Remplace le mot de passe par défaut admin/admin (ou force un nouveau mot de passe)."""
    setup_django(instance)
    from lucterios.CORE.models import LucteriosUser
    admin = LucteriosUser.objects.filter(username='admin').first()
    if admin is None:
        if force:
            fail('aucun utilisateur « admin » dans cette instance.')
        return
    if not force and not admin.check_password(DEFAULT_ADMIN_PASSWORD):
        return
    password = '' if force else os.environ.get('DIACAMMA_ADMIN_PASSWORD', '')
    if password:
        check_admin_password()
        source = 'DIACAMMA_ADMIN_PASSWORD'
    else:
        password = generate_password()
        source = None
    admin.set_password(password)
    if force:
        admin.is_active = True
    admin.save()
    if source:
        log(f'Mot de passe du compte « admin » défini depuis {source}.')
        return
    ADMIN_PASSWORD_FILE.write_text(
        f'Compte : admin\nMot de passe : {password}\n\n'
        'Changez ce mot de passe dès la première connexion, puis supprimez ce fichier.\n',
        encoding='utf-8')
    ADMIN_PASSWORD_FILE.chmod(0o600)
    banner = '=' * 64
    log(banner)
    log('Compte administrateur Diacamma : admin')
    log(f'Mot de passe généré : {password}')
    log(f'(copie dans {ADMIN_PASSWORD_FILE} — à changer dès la première connexion)')
    log(banner)


def clean_static(instance):
    """Retire de STATIC_ROOT tout ce que collectstatic a copié depuis le répertoire de l'instance.

    Lucterios déclare le répertoire de l'instance dans STATICFILES_DIRS : sans ce
    nettoyage, settings.py (clé secrète), la base SQLite et les documents
    pourraient être servis publiquement sous /static/.
    """
    instance_dir = DATA_DIR / instance
    static_root = instance_dir / 'static'
    if not static_root.is_dir():
        return
    for entry in instance_dir.iterdir():
        target = static_root / entry.name
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.is_dir():
            shutil.rmtree(target)
    leaked = [path for path in static_root.rglob('*')
              if path.name in ('settings.py', 'db.sqlite3') or path.suffix in ('.sqlite3', '.lbk')]
    if leaked:
        fail(f'fichiers sensibles détectés dans {static_root} : {", ".join(map(str, leaked[:5]))}.')


def snapshot_sqlite(instance, destination):
    """Instantané cohérent (base SQLite, réglages, documents) avant une mise à jour."""
    instance_dir = DATA_DIR / instance
    database = instance_dir / 'db.sqlite3'
    destination = Path(destination)
    work_copy = destination.with_name(f'.{destination.name}.db.part')
    # Ouverture en lecture-écriture : si un démarrage précédent a été interrompu
    # en pleine transaction, SQLite doit annuler son journal, ce qu'une
    # ouverture en lecture seule refuse (« attempt to write a readonly database »).
    source = sqlite3.connect(database)
    target = sqlite3.connect(work_copy)
    try:
        source.backup(target)
    finally:
        target.close()
        source.close()
    try:
        with tarfile.open(destination, 'w:gz') as archive:
            archive.add(DATA_DIR / f'manage_{instance}.py', arcname=f'manage_{instance}.py')
            archive.add(instance_dir / '__init__.py', arcname=f'{instance}/__init__.py')
            archive.add(instance_dir / 'settings.py', arcname=f'{instance}/settings.py')
            archive.add(work_copy, arcname=f'{instance}/db.sqlite3')
            if (instance_dir / 'usr').is_dir():
                archive.add(instance_dir / 'usr', arcname=f'{instance}/usr')
    finally:
        work_copy.unlink(missing_ok=True)


def db_password():
    """Mot de passe PostgreSQL, lu comme dans bin/diacamma (fichier d'abord).

    Lève OSError si le fichier n'existe pas encore : au premier démarrage, il
    est créé par le conteneur de la base, qui démarre en même temps.
    """
    path = os.environ.get('DIACAMMA_DB_PASSWORD_FILE', '')
    if not path:
        return os.environ.get('DIACAMMA_DB_PASSWORD', '')
    return Path(path).read_text(encoding='utf-8').rstrip('\n')


def wait_postgresql(timeout=300):
    """Attend le mot de passe et que PostgreSQL accepte la connexion.

    Le compose ne fait pas attendre l'état « healthy » de la base : un échec
    de « Créer » dans Container Manager ne laisserait aucun journal lisible.
    """
    import time
    import psycopg2

    host = os.environ.get('DIACAMMA_DB_HOST', '')
    port = os.environ.get('DIACAMMA_DB_PORT', '5432')
    params = {
        'host': host, 'port': port, 'connect_timeout': 5,
        'dbname': os.environ.get('DIACAMMA_DB_NAME', ''),
        'user': os.environ.get('DIACAMMA_DB_USER', ''),
    }
    start = time.monotonic()
    next_log = 0
    while True:
        try:
            params['password'] = db_password()
            psycopg2.connect(**params).close()
            return
        except OSError as exc:
            detail = f'{exc.filename} : {exc.strerror}'
        except psycopg2.OperationalError as exc:
            detail = ' '.join(str(exc).split())
            if 'password authentication failed' in detail:
                fail('PostgreSQL refuse le mot de passe de secrets/db_password.txt : la base du dossier '
                     'postgresql/ a été créée avec un autre mot de passe. Le bon est gardé dans '
                     'data/syndic/settings.py : recréez le fichier à partir de lui (README, « Dépannage »).')
            if 'does not exist' in detail:
                fail(f'la base du dossier postgresql/ ne correspond pas à ce projet : {detail}')
        elapsed = time.monotonic() - start
        if elapsed >= timeout:
            fail(f'la base PostgreSQL ({host}:{port}) ne répond pas après {timeout} s. Consultez le journal '
                 'du conteneur diacamma-syndic-db : le plus souvent, les dossiers postgresql ou secrets '
                 f'n\'ont pas été créés avec File Station (README, « Permissions »). Détail : {detail}')
        if elapsed >= next_log:
            log(f'En attente de la base PostgreSQL ({host}:{port})…')
            next_log += 15
        time.sleep(2)


def main(argv):
    commands = {
        'extra-settings': lambda: extra_settings(),
        'secure-admin': lambda instance: secure_admin(instance),
        'reset-admin-password': lambda instance: secure_admin(instance, force=True),
        'clean-static': lambda instance: clean_static(instance),
        'snapshot-sqlite': lambda instance, destination: snapshot_sqlite(instance, destination),
        'wait-postgresql': lambda: wait_postgresql(),
    }
    if not argv or argv[0] not in commands:
        fail(f'commande interne inconnue : {" ".join(argv)!r}.')
    commands[argv[0]](*argv[1:])


if __name__ == '__main__':
    main(sys.argv[1:])

# Sécurité

Diacamma contient des données personnelles (copropriétaires ou adhérents, comptes bancaires, documents) et ce projet l'expose souvent sur Internet. Les failles sont donc prises au sérieux.

## Signaler une faille

**Ne publiez pas de ticket public.** Utilisez le signalement privé de GitHub : onglet **Security** du dépôt → **Report a vulnerability**, ou directement [ce formulaire](https://github.com/jegweb/diacamma-synology/security/advisories/new).

Indiquez la version de l'image (`diacamma version`), la configuration concernée et, si possible, comment reproduire le problème.

Le projet est maintenu bénévolement. Vous recevrez une réponse dès que possible, en général sous quelques jours. Un correctif est publié sous forme de nouvelle révision de l'image, annoncée dans les Releases.

## Ce qui relève de ce projet

- L'image Docker : configuration de Django et de gunicorn, fichiers servis par `/static/`, droits des fichiers, compte `admin` par défaut.
- Les fichiers Compose : ports publiés, durcissement des conteneurs, gestion des secrets.
- Les scripts et la documentation, par exemple une configuration recommandée qui serait dangereuse.

Une faille de l'application Diacamma ou du framework Lucterios eux-mêmes doit être signalée en privé à l'équipe Diacamma, par courriel à `contribute@diacamma.org`, et jamais dans un ticket public. Vous pouvez aussi la signaler ici : elle sera transmise, et le projet peut parfois l'atténuer dans le conteneur en attendant un correctif.

## Versions suivies

Seule la dernière version publiée reçoit des correctifs. Mettez à jour régulièrement : les révisions (`-2`, `-3`…) apportent aussi les correctifs de sécurité de Debian et de Python.

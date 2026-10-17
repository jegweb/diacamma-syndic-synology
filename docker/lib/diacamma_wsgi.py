"""Application WSGI servie par gunicorn.

DEBUG étant désactivé, Django ne sert plus /static/ : WhiteNoise s'en charge
(/web/ reste servi par une vue Lucterios). bin/diacamma nettoie STATIC_ROOT
avant le démarrage.
"""
from django.conf import settings
from lucterios.framework.wsgi import application as lucterios_application
from whitenoise import WhiteNoise

application = WhiteNoise(lucterios_application, root=settings.STATIC_ROOT,
                         prefix=settings.STATIC_URL, max_age=3600)

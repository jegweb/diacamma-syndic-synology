# Image Diacamma Syndic pour Synology Container Manager (amd64 et arm64).
# Debian trixie est requis : les roues aarch64 de certaines dépendances
# demandent glibc >= 2.39.
ARG PYTHON_IMAGE=python:3.13-slim-trixie

FROM ${PYTHON_IMAGE} AS builder
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1
COPY requirements.lock /tmp/requirements.lock
# --no-deps : le verrou est complet et exclut volontairement PyQt6.
# pip check : arrête la construction si le verrou viole une exigence déclarée
# par un paquet (seule l'absence de PyQt6 est attendue).
# pip est ensuite retiré du venv : il ne sert pas à l'exécution (seuls
# « lucterios_admin check/update » l'appellent, et les mises à jour passent par
# l'image), et ses bibliothèques embarquées (urllib3, msgpack, setuptools) ont
# leurs propres failles.
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-deps -r /tmp/requirements.lock \
 && (/opt/venv/bin/pip check || true) > /tmp/pip-check.txt \
 && if grep -viE 'requires pyqt6,|^No broken requirements' /tmp/pip-check.txt | grep -q .; then \
      echo "Verrou incohérent :" >&2; cat /tmp/pip-check.txt >&2; exit 1; \
    fi \
 && /opt/venv/bin/python -m compileall -q -j 0 /opt/venv \
 && /opt/venv/bin/pip freeze > /opt/venv/versions.txt \
 && /opt/venv/bin/python -c "import importlib.metadata as m; print('-'.join(m.version(p) for p in ('diacamma-syndic', 'diacamma-financial', 'lucterios', 'lucterios-contacts', 'lucterios-documents')))" > /opt/venv/diacamma-build-id \
 && /opt/venv/bin/python -m pip uninstall -y -q pip

FROM ${PYTHON_IMAGE}
ARG DEBIAN_FRONTEND=noninteractive
# locales : Lucterios bascule en anglais si fr_FR.UTF-8 est absente.
# libcairo2 (CairoSVG), poppler-utils (pdf2image), libmagic1 (détection MIME).
# apt-get upgrade : correctifs de sécurité Debian publiés après l'image de base.
# Le pip du Python système est retiré (inutile à l'exécution, voir plus haut).
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      locales tzdata tini libcairo2 poppler-utils libmagic1 fonts-dejavu-core \
 && sed -i -E 's/^# *((fr_FR|en_US)\.UTF-8 UTF-8)/\1/' /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y -q --root-user-action=ignore pip \
 && rm -rf /root/.cache

COPY --from=builder /opt/venv /opt/venv
COPY docker/ /opt/diacamma/
RUN chmod 0755 /opt/diacamma/bin/* \
 && ln -s /opt/diacamma/bin/diacamma /usr/local/bin/diacamma \
 && mv /opt/venv/diacamma-build-id /opt/venv/versions.txt /opt/diacamma/ \
 && install -d -o 1026 -g 100 -m 0700 /data /backups

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONPATH=/opt/diacamma/lib:/data \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LANG=fr_FR.UTF-8 \
    LC_ALL=fr_FR.UTF-8 \
    TZ=Europe/Paris \
    HOME=/tmp

# UID/GID par défaut du premier utilisateur DSM ; surchargeables par PUID/PGID.
USER 1026:100
WORKDIR /data
VOLUME ["/data", "/backups"]
EXPOSE 8000

# Long délai de démarrage : la première initialisation (migrations) peut
# prendre plusieurs minutes sur un NAS modeste.
HEALTHCHECK --interval=30s --timeout=10s --start-period=15m --retries=3 \
  CMD ["python", "/opt/diacamma/lib/healthcheck.py"]

# Version de l'image (X.Y.Z-N), fournie par la publication ; en dernier pour ne
# pas invalider le cache des étapes précédentes.
ARG VERSION=dev
ENV DIACAMMA_IMAGE_VERSION=${VERSION}
LABEL org.opencontainers.image.title="Diacamma Syndic pour Synology" \
      org.opencontainers.image.description="Diacamma Syndic (gestion de copropriété) pour Synology Container Manager. Projet communautaire non officiel." \
      org.opencontainers.image.source="https://github.com/jegweb/diacamma-syndic-synology" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}"

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/diacamma/bin/diacamma"]
CMD ["serve"]

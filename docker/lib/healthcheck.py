"""Sonde de santé : le client web Lucterios répond-il via Django ?"""
import sys
import urllib.request

try:
    with urllib.request.urlopen('http://127.0.0.1:8000/web/index.html', timeout=8) as response:
        sys.exit(0 if response.status == 200 else 1)
except Exception:
    sys.exit(1)

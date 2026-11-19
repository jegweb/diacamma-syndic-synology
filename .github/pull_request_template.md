## Ce que change cette pull request

<!-- Décrivez le changement et ce qu'il apporte. S'il corrige un ticket, écrivez « Corrige #123 ». -->

## Vérifications

- [ ] `scripts/smoke-test.sh` passe ; avec `--sqlite` aussi si le changement touche la base, avec `--depuis ghcr.io/jegweb/diacamma-syndic:latest` s'il touche l'image ou la mise à jour
- [ ] ShellCheck passe (commande dans CONTRIBUTING.md)
- [ ] Le README est à jour si le comportement visible change
- [ ] Les contraintes de Container Manager décrites dans CLAUDE.md sont respectées : pas de section `logging`, port publié en valeur fixe, pas de `pids_limit`, dépendance `service_started`
- [ ] Aucun nom de domaine, adresse IP publique ni mot de passe réel dans les fichiers ou les journaux joints

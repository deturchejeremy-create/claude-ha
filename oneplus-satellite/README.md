# Kit satellite vocal OnePlus NE2215 → Alfred

## Mode d'emploi (Windows)

1. Récupère ce dossier sur le PC relié au téléphone :
   - sans Git : télécharge le ZIP
     https://github.com/deturchejeremy-create/claude-ha/archive/refs/heads/ccr-261b2865-xdqojv.zip
     puis décompresse-le ;
   - avec Git : `git clone -b ccr-261b2865-xdqojv https://github.com/deturchejeremy-create/claude-ha.git`
2. Ouvre PowerShell dans le dossier `oneplus-satellite` et lance :
   `powershell -ExecutionPolicy Bypass -File .\install.ps1`
   Le script installe Git, ADB, scrcpy et Claude Code, puis affiche `adb devices`.
3. Ferme puis rouvre PowerShell dans ce même dossier, et tape `claude`.
   Au premier lancement, connecte-toi avec ton compte Claude.
4. Ouvre `PROMPT.md`, remplace l'IP de Home Assistant, puis colle son contenu dans Claude Code.

## Contenu
- `install.ps1` : installation des outils. Il ne modifie rien sur le téléphone.
- `CLAUDE.md` : contexte et contraintes, chargés automatiquement par Claude Code.
- `.claude/settings.json` : garde-fous. Les lectures ADB sont autorisées et les actions demandent
  confirmation. Sont bloqués : la désinstallation, le vidage des données, la désactivation d'apps,
  fastboot et toute commande visant l'app Home Assistant Companion.
- `PROMPT.md` : le message de départ à coller.

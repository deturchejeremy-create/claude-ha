# Projet : OnePlus NE2215 → satellite vocal Home Assistant « Alfred »

Ce dossier tourne sur le PC de l'utilisateur. Le OnePlus NE2215 y est branché en USB.
Son écran est cassé : tout passe par ADB, et scrcpy sert à voir l'écran. Réponds en français.

## État côté serveur (déjà fait, NE PAS MODIFIER)
- Home Assistant OS + Supervisor. Add-ons : Whisper, Piper, openWakeWord 2.1.1 (core-openwakeword:10400).
- Entité wake word : `wake_word.openwakeword`.
- Pipeline « Alfred Hermes local », id `01m46ed0psbk4vhq7pym6xaehh` : agent `conversation.alfred_hermes`,
  STT `stt.faster_whisper` (fr), TTS `tts.piper` `fr_FR-siwis-medium`, wake word `ok_nabu`.
  Configuration vérifiée le 2026-10-09.
- Tablette : VACA, `assist_satellite.vaca_5a902d816` (était `unavailable` le 2026-10-09). Ne pas y toucher.
- Le OnePlus est déjà dans HA via l'app Companion (entités `*.ne2215`) et sert de caméra/micro.

## Objectif
Le OnePlus apparaît dans HA comme `assist_satellite`, écoute en continu, se réveille sur le mot-clé
et utilise le pipeline « Alfred Hermes local ».

## Plan
1. `adb devices` → doit afficher « device ». Si « unauthorized » : S'ARRÊTER et prévenir l'utilisateur.
2. Lancer `scrcpy` en arrière-plan.
3. Installer VACA (View Assist Companion App) depuis la dernière release officielle
   de `msp1974/ViewAssist_Companion_App` sur GitHub. Si VACA ne convient pas, proposer
   Termux + wyoming-satellite avec ses compromis AVANT de l'installer.
4. Permissions via ADB : RECORD_AUDIO, POST_NOTIFICATIONS, `dumpsys deviceidle whitelist +PKG`,
   appops RUN_ANY_IN_BACKGROUND / RUN_IN_BACKGROUND allow, `am set-standby-bucket PKG active`,
   puis réglages batterie OxygenOS via scrcpy (pas d'optimisation, app verrouillée dans les récents).
5. Configurer l'app vers HA : DEMANDER l'URL locale de HA, ne jamais la deviner.
6. Côté HA : découverte Wyoming/zeroconf (ou ajout manuel host:port), puis affecter le pipeline
   « Alfred Hermes local » au NOUVEAU satellite uniquement.
7. Test de bout en bout : wake word → phrase en français → réponse vocale. Vérifier les logs HA.

## Contraintes strictes
- Ne JAMAIS désinstaller, vider ou reconfigurer l'app Home Assistant Companion
  (`io.homeassistant.companion.android*`). Ses entités ne2215 servent à une automatisation batterie.
- Ne pas toucher aux autres pipelines, add-ons, ni à la tablette.
- Pas de reset usine, pas de root, pas de bootloader/fastboot.
- Demander confirmation avant toute action irréversible (dont `adb install`).
- Micro : avant d'installer VACA, vérifier qui capture le micro
  (`adb shell dumpsys audio`, section recording). Signaler si l'usage caméra le monopolise :
  sur Android 10+, une seule app reçoit le vrai son, les autres reçoivent du silence.

# Audit de sécurité Home Assistant — 23/09/2026

**Instance** : Home Assistant OS 18.2 · Core 2026.9.2 · Supervisor 2026.09.2 · hôte x86-64 `192.168.1.74`
**Méthode** : lecture seule via l'API Home Assistant / Supervisor (intégration HA-MCP). Aucune modification n'a été faite.
**Limite** : aucun scan de ports n'a été fait depuis Internet ou depuis le LAN. L'exposition réseau est déduite de la configuration.

> Tous les secrets rencontrés (mots de passe, jetons, clé de sauvegarde, URL de webhooks) sont **volontairement masqués** dans ce document.

---

## Synthèse

| # | Gravité | Constat | Action |
|---|---------|---------|--------|
| 1 | 🔴 Critique | Un même mot de passe, stocké en clair, est réutilisé pour Mosquitto et PostgreSQL | Changer les deux, avec des mots de passe uniques |
| 2 | 🔴 Critique | L'utilisateur HA `shelly_mqtt` est **administrateur** et peut se connecter à distance | Retirer les droits admin et le passer en « local uniquement », ou le remplacer par un login MQTT dédié |
| 3 | 🟠 Élevé | PostgreSQL (5432) écoute sur tout le LAN (host network), ses sauvegardes ne sont pas chiffrées | Restreindre l'accès, chiffrer les sauvegardes |
| 4 | 🟠 Élevé | MQTT en clair (1883) et en WebSocket (1884) sur le LAN, avec les IoT sur le même réseau | Séparer les IoT dans un VLAN, fermer 1884 |
| 5 | 🟠 Élevé | Des agents IA ont des droits **admin** (HA-MCP, Home Generative Agent, MCP Assist) | Réduire les droits et l'exposition |
| 6 | 🟠 Élevé | Accès distant double (Nabu Casa + Tailscale), et la MFA du propriétaire n'a pas pu être vérifiée | Activer la MFA (TOTP) |
| 7 | 🟠 Élevé | IPv6 public sur l'hôte HA : il faut vérifier le pare-feu IPv6 de la Bbox | Bloquer toute connexion IPv6 entrante vers l'hôte |
| 8 | 🟡 Moyen | 6 mises à jour en attente (Core, OS, HGA, HA-MCP, VACA) | Les installer |
| 9 | 🟡 Moyen | ADB réseau actif sur la Bbox TV (192.168.1.44) | Accepter le risque ou le limiter |
| 10 | 🟡 Moyen | Google Assistant expose automatiquement les nouvelles entités (y compris `lock`), sans PIN | Désactiver l'exposition automatique, définir un PIN |
| 11 | 🟡 Moyen | Jeton Conso API (Linky) en clair, valable jusqu'en 2029 | Le régénérer si la config a pu fuiter |
| 12 | 🟡 Moyen | Échecs d'authentification depuis le LAN (19/09) | Vérifier leur origine |
| 13 | 🟢 Faible | Durcissements divers (UPnP, add-ons actifs, rétention des sauvegardes, Zigbee) | Voir le détail |

---

## Détail des constats

### 1. 🔴 Mot de passe réutilisé et stocké en clair
- **Mosquitto broker** → `logins` : l'utilisateur `jeremy` a un mot de passe en clair.
- **PostgreSQL with pgvector** → `ha_user_password` : c'est **le même mot de passe**.
- Les options des add-ons sont lisibles en clair par tout administrateur HA et par tout outil qui a un jeton admin (y compris les agents IA). Cet audit a pu les lire.
- Si ce mot de passe sert aussi ailleurs (compte HA, Bbox, Gmail…), le risque déborde de Home Assistant.

**Remédiation**
1. Générer deux mots de passe **uniques** (gestionnaire de mots de passe, 20 caractères ou plus).
2. Mosquitto : supprimer le login local `jeremy` s'il ne sert pas (les utilisateurs HA suffisent), ou utiliser `password_pre_hashed: true`.
3. PostgreSQL : changer `ha_user_password`, puis mettre à jour l'URI de connexion de Home Generative Agent.
4. Si ce mot de passe a servi ailleurs, le changer là aussi.

### 2. 🔴 Compte `shelly_mqtt` administrateur et accessible à distance
- Utilisateur HA non système, groupe `system-admin`, `local_only: false`.
- Son mot de passe est stocké en clair dans un équipement Shelly (config MQTT).
- Si un Shelly est compromis (firmware, accès web local, sauvegarde), l'attaquant obtient un **accès admin complet** à HA, y compris depuis Internet via l'URL Nabu Casa.

**Remédiation** (Paramètres → Personnes → Utilisateurs)
- Décocher **Administrateur** et cocher **Peut se connecter uniquement depuis le réseau local**.
- Mieux : créer un login dédié dans l'add-on Mosquitto pour les Shelly et désactiver ce compte HA.

### 3. 🟠 PostgreSQL exposé au LAN
- L'add-on tourne en `host_network: true` avec le port `5432/tcp`. Il écoute donc sur `192.168.1.74`, et aussi sur l'interface Tailscale.
- Il a le privilège `SYS_ADMIN`. `backup_encrypt: false` : les dumps de la base (mémoire et embeddings de l'agent IA) ne sont pas chiffrés.
- Add-on tiers peu répandu (note 3/8, version 0.1.0).

**Remédiation** : mot de passe fort et unique (point 1), `backup_encrypt: true` avec une clé GPG, vérifier que `pg_hba.conf` n'autorise que `127.0.0.1` et le réseau Docker `172.30.32.0/23`. Envisager un add-on mieux maintenu.

### 4. 🟠 MQTT en clair sur le LAN
- Ports publiés : `1883` (clair), `1884` (WebSocket clair), `8883/8884` (TLS). `require_certificate: false`.
- Les identifiants MQTT (Shelly, etc.) circulent en clair. Tout appareil compromis du LAN (TV, prise Tuya, PC) peut les intercepter et publier des commandes, par exemple sur les onduleurs OpenDTU ou la batterie.

**Remédiation**
- Désactiver `1884` s'il ne sert pas (onglet Réseau de l'add-on, laisser le champ vide).
- À moyen terme : placer les IoT dans un **VLAN/SSID dédié**, sans accès aux PC ni à Internet quand c'est possible.
- Passer les clients qui le supportent sur `8883` (TLS).

### 5. 🟠 Agents IA avec privilèges admin
- **HA-MCP Server** : utilisateur `system-admin` avec un jeton longue durée **sans expiration**. Il peut lire les secrets des add-ons, les sauvegardes, piloter les équipements et redémarrer HA.
- **Home Generative Agent** (Gemini/OpenAI/Ollama), **MCP Server Assist**, et le relais « 1minAI » en préparation.
- Risque principal : **injection de prompt**. Un texte malveillant (nom d'appareil, e-mail, page web, titre de média) lu par un LLM peut déclencher des actions.

**Remédiation**
- Mode *Read Only* du serveur HA-MCP quand il n'y a pas d'édition à faire. Régénérer son jeton régulièrement.
- Limiter les entités exposées à Assist/LLM (Paramètres → Assistants vocaux → Exposer) au strict nécessaire.
- Garder une confirmation humaine pour les actions sensibles : batterie, onduleurs, chauffe-eau, clim.
- Ne pas brancher de relais tiers (1minAI) sur un agent qui a des droits d'écriture.

### 6. 🟠 Accès distant et authentification
- Nabu Casa Remote UI actif (`remote_enabled`, `remote_allow_remote_enable: true`) et Tailscale actif, sans Funnel, ce qui est bien.
- Le propriétaire `deturche jeremy` est admin et accessible à distance. La MFA n'a pas pu être vérifiée par l'API.
- Aucun `internal_url` n'est défini.

**Remédiation**
- **Activer la MFA TOTP** : Profil → Sécurité → Modules d'authentification multifacteur.
- Choisir **une** voie d'accès distant. Si Tailscale suffit, désactiver Remote UI Nabu Casa (on peut garder l'abonnement pour Google et les sauvegardes).
- Ajouter dans `configuration.yaml` :
  ```yaml
  http:
    ip_ban_enabled: true
    login_attempts_threshold: 5
  ```

### 7. 🟠 IPv6 public
- `eno1` a une adresse IPv6 globale `2001:861:2440:8340:…`, publiée via zeroconf.
- Si le pare-feu IPv6 de la Bbox est permissif, les ports 8123, 1883, 5432, etc. **peuvent être joignables depuis Internet** sans aucune redirection de port.

**Remédiation** : Bbox → Services de la box → Pare-feu IPv6 : bloquer tout trafic entrant non sollicité. Tester depuis la 4G, par exemple avec un scanner de ports IPv6 en ligne sur l'adresse de l'hôte.

### 8. 🟡 Mises à jour en attente
| Composant | Installé | Disponible |
|---|---|---|
| Home Assistant Core | 2026.9.2 | 2026.9.3 |
| Home Assistant OS | 18.2 | 18.3 |
| Home Generative Agent | v3.39.4 | v3.42.0 |
| HA-MCP Custom Component | v2.1.3 | v2.2.0 |
| HA-MCP Server | 8.4.3 | 8.5.0 (bloqué par le composant) |
| View Assist Companion App | v0.13.2 | v0.13.3 |

Les add-ons sont à jour et en mise à jour automatique (sauf Linky). HACS : 15 dépôts, tous connus.

### 9. 🟡 ADB réseau sur la Bbox TV
- L'intégration `androidtv` (192.168.1.44) utilise ADB par TCP, avec une interrogation toutes les 30 s par `automation.bbox_memorise_chaine_via_adb`.
- Tout appareil du LAN qui atteint le port ADB peut demander l'autorisation d'installer des apps ou d'exécuter des commandes. La clé ADB de HA peut aussi être réutilisée.
- **Remédiation** : accepter le risque si les IoT restent isolés. Sinon, n'autoriser ADB que depuis l'IP de HA (VLAN/ACL), et vérifier régulièrement la liste des clés autorisées sur la box TV.

### 10. 🟡 Google Assistant
- 23 entités exposées, dont `climate.clim_airton`, `switch.omnibattery_vacation_mode`, une scène « Éteindre tout » et de nombreux scripts.
- `google_default_expose` inclut `lock` et `switch` : **toute nouvelle entité de ces domaines est exposée automatiquement**.
- `google_secure_devices_pin: null`.

**Remédiation** : Paramètres → Assistants vocaux → Google : désactiver « Exposer les nouvelles entités ». Définir un **code PIN pour les appareils sécurisés**.

### 11. 🟡 Jeton Linky (Conso API)
- Le jeton est en clair dans les options de l'add-on Linky, avec une expiration en 2029. Il donne accès à tes données de consommation (profil de présence dans le logement).
- **Remédiation** : le régénérer sur conso.boris.sh si des sauvegardes ou exports de config ont pu circuler.

### 12. 🟡 Échecs d'authentification
- 19/09 14:22 : `DESKTOP-5VG5F8S.lan (192.168.1.199)`, client `node`, sur `/api/`. Probablement un script ou un outil avec un jeton invalide ou révoqué.
- 19/09 20:49 : `fe80::cc6a:…`, Edge sur Windows, 3 échecs sur `login_flow`.
- Pas de tentative externe dans la fenêtre de logs analysée. Les connexions de l'app mobile arrivent de plusieurs IP publiques (4G), ce qui est normal.
- **Remédiation** : confirmer que ces tentatives venaient de toi. Supprimer le script `node` ou lui donner un jeton valide.

### 13. 🟢 Durcissements mineurs
- **UPnP** : l'intégration `upnp` (Bbox) est active. Si UPnP est ouvert sur la box, n'importe quel IoT peut ouvrir un port vers Internet. Le désactiver sur la Bbox si rien n'en dépend.
- **Terminal & SSH** : aucun mot de passe ni clé, port 22 non publié. Accès seulement par l'ingress, ce qui est **correct**. L'arrêter quand il ne sert pas (rôle `manager` sur le Supervisor).
- **File editor** : accès par l'ingress seulement, `enforce_basepath: true`, ce qui est correct.
- **Grocy** : arrêté. Le désinstaller s'il n'est plus utilisé.
- **Sauvegardes** : une sauvegarde automatique hebdomadaire (mercredi), **chiffrée**, base incluse, vers Nabu Casa. C'est bien. Il n'existe **qu'une seule destination** : ajouter une copie hors-ligne ou locale (règle 3-2-1). Conserver la clé de chiffrement hors de HA.
- **Zigbee2MQTT** : vérifier que `network_key` n'est pas la clé par défaut (`GENERATE` à la création) et que `permit_join` est désactivé.
- **Intégration Tuya cloud** : elle tourne en parallèle de `tuya_local`. Si tous les appareils passent en local, supprimer l'intégration cloud réduit la surface d'attaque.

---

## Points positifs
- HAOS, Supervisor et add-ons à jour. Système `healthy` et `supported`, aucune réparation en attente.
- Sauvegardes automatiques chiffrées, plus des sauvegardes manuelles avant chaque modification importante.
- SSH non exposé, File editor limité à `/config`, Tailscale sans Funnel ni exit node.
- Un seul utilisateur humain, et aucun webhook d'automatisation exposé.
- Alexa désactivé, iBeacon et Bluetooth inutilisés ignorés.

## Plan d'action conseillé
1. **Aujourd'hui** : points 1 et 2 (mots de passe, compte `shelly_mqtt`), MFA (point 6).
2. **Cette semaine** : pare-feu IPv6 de la Bbox (7), mises à jour (8), exposition Google (10), jeton HA-MCP (5).
3. **Ce mois** : VLAN IoT (4, 9), PostgreSQL (3), seconde destination de sauvegarde, UPnP.

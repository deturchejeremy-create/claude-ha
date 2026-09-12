# Audit Home Assistant — Installation « Maison »

**Date de l'audit :** 12 septembre 2026
**Périmètre :** instance Home Assistant accessible via le serveur MCP `Home_assistant` depuis l'espace de travail Claude Code
**Mode :** strictement lecture seule — aucune modification, suppression, redémarrage ou reconfiguration n'a été effectuée
**Auditeur :** Claude Code (architecture HA / cybersécurité / DevOps-SRE / revue de code)

> **Note de confidentialité :** aucune valeur de secret (mot de passe, token, hash, salt, clé API, URL d'ingress) n'est reproduite dans ce rapport. Les emplacements sont désignés, jamais les valeurs.

---

## 1. Résumé exécutif

L'installation auditée est une domotique **résidentielle de niveau avancé**, très au-dessus de la moyenne : 702 entités, 106 intégrations, une orchestration énergétique maison (photovoltaïque + batterie Marstek/Omnibattery + chauffe-eau + climatisation) d'une sophistication réelle, avec gestion de saisons, hystérésis, anti-court-cycle, garde de disponibilité capteurs et arbitrage de priorités. La qualité conceptuelle des automatisations énergétiques est notable : usage correct des `trigger id`, des conditions natives plutôt que Jinja, des `mode: restart`, et des garde-fous de sécurité.

Cette sophistication a cependant produit **trois dettes structurelles** et **deux expositions de sécurité qui doivent être traitées en priorité**.

**Les deux points les plus urgents :**

1. **Le serveur MCP `ha_mcp_tools` écoute sur `0.0.0.0:9584` avec un webhook dont l'authentification est explicitement désactivée** (`webhook_auth: "none"`) et l'API LLM activée. C'est un canal de contrôle quasi total de Home Assistant, ouvert à tout hôte du réseau local.
2. **Le mot de passe du broker MQTT est stocké en clair** dans les options de l'add-on Mosquitto, et le broker est mappé sur les ports hôte (1883/1884/8883/8884) sans exigence de certificat client. Ce mot de passe se retrouve dans les 30 sauvegardes existantes.

**Les trois dettes structurelles :**

- **Recorder SQLite sans exclusions** : 1,04 GiB accumulés en 9 jours, alimentés par des capteurs à ~10 changements/minute.
- **Une chaîne de 16 cartes Lovelace JavaScript inline** (`omni-energy-flow-card-v5` → `v20`), chacune héritant de la précédente, soit 146,7 KB de JS chargés à chaque ouverture de dashboard.
- **Un sous-système « Routeur IA » entièrement mort** : 31 helpers, un dashboard et une automatisation désactivée, dont le moteur (Gemini) est en erreur 401 depuis le 11/09.

**Un défaut fonctionnel confirmé** mérite attention : deux automatisations en `mode: restart` se déclenchent **à la même seconde** (`seconds: "/30"`) et commandent toutes deux `climate.clim_airton`. Preuve mesurée : exécutions à `17:30:30.104` et `17:30:30.305` le 12/09.

**Score global de santé : 58 / 100.**

L'installation est **fonctionnelle et bien pensée**, mais elle est arrivée au point où la complexité accumulée dépasse les garde-fous mis en place. Le risque principal n'est pas la panne : c'est l'exposition réseau et l'impossibilité croissante de diagnostiquer (logs saturés à 99 % par un seul composant).

---

## 2. Cartographie de l'architecture

### 2.1 Socle système

| Élément | Valeur |
|---|---|
| Type d'installation | **Home Assistant OS** (Supervised, conteneurisé) |
| Home Assistant Core | **2026.9.1** |
| Home Assistant OS | **18.2** |
| Supervisor | **2026.09.0** |
| Docker | 29.6.2 |
| Python | 3.14.6 |
| Noyau | 6.18.39-haos |
| Matériel | `generic-x86-64`, amd64 |
| Disque | 116,7 GB total — 13,2 GB utilisés (11 %) |
| RAM | ~7,6 GiB (limite conteneur observée : 8 209 620 992 octets) |
| Fuseau / langue | Europe/Paris / fr |
| État | `RUNNING`, `healthy: true`, `supported: true`, NTP synchronisé |
| `config_dir` | `/config` |

### 2.2 Réseau

| Interface | Adresse | Rôle |
|---|---|---|
| `eno1` | 192.168.1.74/24 (+ IPv6 publique /64) | LAN principal, interface par défaut |
| `tailscale0` | 100.101.146.79/32 | VPN Tailscale (add-on) |
| `hassio` | 172.30.32.1/23 | Réseau interne des add-ons |
| `docker0` | 172.30.232.1/23 | Réseau Docker |
| 11 × `veth*` | — | Interfaces virtuelles de conteneurs |

- **DNS :** 192.168.1.254 (box) + résolveur IPv6 du FAI.
- **Accès externe :** Home Assistant Cloud (Nabu Casa) — `remote_enabled: true`, `remote_connected: true`, région `eu-central-1`. Certificat valide jusqu'au **14/11/2026**, abonnement jusqu'au **12/10/2026**.
- **Google Assistant :** activé. **Alexa :** désactivé.
- **Tailscale :** `share_homeassistant: "disabled"` → **pas** d'exposition Funnel sur Internet. Bon point.
- **Aucun reverse proxy tiers détecté** (pas de NGINX/Traefik/Caddy add-on installé). L'accès externe passe exclusivement par Nabu Casa et Tailscale.

### 2.3 Inventaire fonctionnel

| Catégorie | Volume |
|---|---|
| Entités | **702** réparties sur **40 domaines** |
| Services | 311 |
| Intégrations (config entries) | **106** — 99 chargées, **7 non chargées** |
| Helpers | **143** |
| Automatisations | **15** (14 actives, 1 désactivée) |
| Scripts | 5 |
| Scènes | 1 |
| Dashboards | 8 déclarés (+ défaut), **31 vues**, mode `storage` |
| Ressources Lovelace | **26** (dont **19 inline**) |
| Add-ons | **8** (7 démarrés, 1 arrêté) |
| Dépôts HACS | **15** installés / 4 131 disponibles |
| Zones (areas) | 7 — **aucun étage (floor) défini** |
| Sauvegardes | 30 |

**Répartition des entités par domaine (top 10) :**
`sensor` 328 · `number` 63 · `switch` 60 · `select` 33 · `update` 29 · `binary_sensor` 28 · `input_number` 23 · `input_text` 16 · `automation` 15 · `button` 14

**Répartition des helpers :**
`template` 48 · `input_number` 23 · `input_text` 16 · `input_datetime` 9 · `timer` 7 · `input_button` 6 · `integration` 6 · `counter` 5 · `input_boolean` 5 · `threshold` 5 · `input_select` 4 · `statistics` 3 · `utility_meter` 2 · `filter` 1 · `group` 1 · `person` 1 · `zone` 1

**Zones et occupation :**
`domotique` 134 · `salon` 124 · `wc` 24 · `chambre` 7 · `placard` 1 · **`cuisine` 0** · **`bureau` 0**

### 2.4 Sous-systèmes techniques

**Énergie (cœur de l'installation) :**
- **Production PV :** 2 micro-onduleurs Hoymiles via OpenDTU (`sensor.opendtu_528ecc_ac_power`), pilotage du bridage via `number.onduleur1_limit_nonpersistent_relative` et `number.onduler_2_limit_nonpersistent_relative`.
- **Stockage :** batterie Marstek Venus 1 pilotée par l'intégration custom **Omnibattery v1.4.0** en **Modbus TCP** sur `192.168.1.92:502`.
- **Mesure réseau :** Shelly Pro EM 50 (`shellyproem50-ece334f85344`) sur `192.168.1.162`, lissé par une intégration `filter` (moyenne mobile 30 s) → `sensor.reseau_lisse_30_s`.
- **Comptage fournisseur :** add-on **Linky** 1.8.0.
- **Prévision :** **Solcast PV Forecast v4.6.1** (HACS) **et** `forecast_solar` (natif) en parallèle.
- **Charges pilotées :** chauffe-eau (`switch.disjoncteur_chauffe_eau`, Tuya Local), climatisation Airton (`climate.clim_airton` via `airton_ir_broadlink` + Broadlink RM4 Pro), machine à laver, lave-vaisselle, Airfryer, TV.

**Radio / protocoles :**
- **Zigbee :** Zigbee2MQTT 2.14.1-1 + dongle Sonoff ZB 3.0 USB Plus (`zstack`). **ZHA désactivé** (`disabled_by: user`) — cohérent, pas de conflit.
- **MQTT :** Mosquitto 7.1.1, discovery activé, préfixe `homeassistant`.
- **Z-Wave / Thread / Matter :** **absents**.
- **Bluetooth :** 1 adaptateur Intel ignoré, 1 adaptateur Raspberry Pi désactivé, 1 entrée Shelly active.
- **Infrarouge :** 2 Broadlink (RM4 Pro `192.168.1.170`, LB1 `192.168.1.26`).
- **ESPHome :** **aucun appareil détecté**.

**IA / assistants :**
- **Home Generative Agent v3.39.4** (HACS, custom) — agent principal, provider Gemini, 6 sous-entrées (Conversation, Camera Image Analysis, Conversation Summary, Embeddings, Primary Gemini, Database).
- **PostgreSQL avec pgvector** 0.1.0 (add-on) — base vectorielle pour les embeddings HGA.
- **View Assist** 2026.7.0 + **View Assist Companion App** (`vaca`) 0.13.2 — satellite vocal.
- **Google Generative AI** (natif) — **désactivé, erreur 401**.
- **Local OpenAI LLM** 1.12.0 — **non chargée, erreur de config_flow**.
- **ha_mcp_tools v2.1.3** — serveur MCP (le canal de cet audit).

**Bases de données :**
- **Recorder :** SQLite 3.53.2, **1 038,90 MiB**, plus ancienne exécution enregistrée le **03/09/2026** (~9 jours de rétention, cohérent avec `purge_keep_days: 10` par défaut).
- **PostgreSQL + pgvector :** add-on dédié pour HGA.

---

## 3. Scores

### Score global : **58 / 100**

| Catégorie | Score | Commentaire |
|---|---|---|
| **Sécurité** | **42 / 100** | Deux expositions réseau non authentifiées, un secret en clair, un contournement de PIN connu et ignoré |
| **Fiabilité** | **61 / 100** | Boucle de reconnexion permanente, SPOF Modbus, 39 entités indisponibles |
| **Performance** | **56 / 100** | Recorder sans exclusions, 146,7 KB de JS inline, capteurs très bavards |
| **Maintenabilité** | **50 / 100** | Automatisations monolithiques, chaîne de cartes v5→v20, sous-système mort |
| **Qualité des automatisations** | **68 / 100** | Conception réellement soignée, mais race condition et monolithes |
| **Sauvegardes / reprise** | **70 / 100** | 30 sauvegardes protégées, mais majoritairement sans base de données |
| **Observabilité** | **35 / 100** | Logs saturés à 99,7 % par un seul composant |

**Méthode de notation :** chaque catégorie part de 100, avec déduction pondérée par gravité (Critical −25, High −12, Medium −6, Low −2), plafonnée, puis ajustée à la hausse pour les bonnes pratiques constatées (Tailscale non exposé, ZHA désactivé proprement, garde-fous capteurs, sauvegardes avant chaque modification).

---

## 4. Constats détaillés

### Légende des niveaux de preuve

- 🔴 **Confirmé** — observé directement dans la configuration, les états ou les logs.
- 🟠 **Risque probable** — déduit de faisceaux d'indices concordants, non observé directement en situation de panne.
- 🔵 **Optimisation recommandée** — pas un défaut, un gain net disponible.
- ⚪ **Non vérifiable** — hors de portée des outils disponibles en lecture seule.

---

## CRITICAL

### 🔴 C1 — Serveur MCP exposé sur toutes les interfaces avec webhook non authentifié

**Preuve observée** — configuration de l'intégration `ha_mcp_tools` (entry_id `01M0MD68ZRDC0K5A7026PZDMNF`) :

```yaml
bind_host: "0.0.0.0"      # écoute sur TOUTES les interfaces
server_port: 9584
enable_webhook: true
webhook_auth: "none"      # aucune authentification
enable_llm_api: true
llm_api_exposure: "tool_search"
auto_update: true
```

**Impact concret.** Le serveur MCP expose les outils de contrôle de Home Assistant : création/modification/suppression d'automatisations, appel de n'importe quel service, lecture de l'intégralité des états, accès aux diagnostics d'intégration (qui contiennent des configurations), gestion des sauvegardes. Avec `bind_host: 0.0.0.0`, ce service est joignable depuis :

- tout appareil du LAN `192.168.1.0/24` (y compris objets connectés compromis : TV Android, Xbox, ampoules Tuya, décodeur Bbox) ;
- tout nœud du tailnet via `100.101.146.79` ;
- les réseaux Docker internes.

`webhook_auth: "none"` signifie qu'un webhook déclenchable **sans aucun credential** est actif. Un attaquant sur le LAN — ou un script malveillant exécuté dans le navigateur d'un appareil du LAN via SSRF — peut potentiellement piloter la domotique, y compris les charges électriques de forte puissance (chauffe-eau, climatisation) et la batterie.

**Cause probable.** Configuration `0.0.0.0` choisie pour permettre l'accès depuis un client MCP distant (Claude Desktop, Claude Code), sans restriction ultérieure une fois le fonctionnement validé. `webhook_auth: "none"` est vraisemblablement un réglage de mise au point resté en place.

**Recommandation précise.**

1. **Immédiat** — passer `webhook_auth` à un mode authentifié, ou désactiver `enable_webhook` s'il n'est pas utilisé.
2. **Immédiat** — restreindre `bind_host` à `127.0.0.1` si le client MCP tourne sur la même machine, ou à l'adresse tailnet `100.101.146.79` si l'accès distant passe par Tailscale.
3. Désactiver `auto_update` sur un composant disposant d'un tel niveau de privilège : une mise à jour automatique non revue modifie une surface de contrôle total.

**Exemple de correction (à appliquer via l'UI des options de l'intégration, non appliqué ici) :**

```yaml
bind_host: "127.0.0.1"     # ou 100.101.146.79 pour un accès Tailscale
enable_webhook: false      # si le webhook n'est pas consommé
webhook_auth: "bearer"     # sinon, authentification obligatoire
auto_update: false
```

**Vérification après correction :** depuis un autre poste du LAN, `curl -m 3 http://192.168.1.74:9584/` doit échouer (connexion refusée).

---

### 🔴 C2 — Identifiants MQTT en clair et broker exposé sur le LAN

**Preuve observée** — options de l'add-on `core_mosquitto` :

```yaml
logins:
  - username: jeremy
    password: "<valeur en clair — non reproduite dans ce rapport>"
require_certificate: false
```

Mapping réseau de l'add-on (ports hôte) :

```json
"network": { "1883/tcp": 1883, "1884/tcp": 1884, "8883/tcp": 8883, "8884/tcp": 8884 }
```

**Impact concret.** Trois problèmes distincts se cumulent :

1. **Secret en clair.** Le mot de passe est stocké non haché dans la configuration de l'add-on. Or l'option `password_pre_hashed` existe précisément pour l'éviter (visible dans le schéma de l'add-on). Le mot de passe observé suit un schéma de mot de passe personnel réutilisable — s'il est partagé avec d'autres services, la compromission du broker devient une compromission plus large.
2. **Propagation dans les sauvegardes.** Les **30 sauvegardes** listées embarquent la configuration des add-ons. Elles sont `protected: true` (chiffrées), mais une seule est stockée hors site (`cloud.cloud`) — les 29 autres sont sur `hassio.local`, c'est-à-dire sur le disque de la machine elle-même.
3. **Exposition LAN sans TLS obligatoire.** Les quatre ports MQTT sont mappés sur l'hôte : le broker est accessible sur `192.168.1.74:1883` depuis tout le réseau local. `require_certificate: false` signifie qu'un simple couple identifiant/mot de passe suffit. Or MQTT porte ici **tout le trafic Zigbee2MQTT** : capteurs, boutons, et surtout les commandes.

**Cause probable.** Configuration initiale suivant le tutoriel standard de Mosquitto, jamais durcie après la mise en service.

**Recommandation précise.**

1. **Immédiat** — changer le mot de passe MQTT, et le reconfigurer en **pré-haché** via l'outil `pw` fourni dans le conteneur :
   ```bash
   # dans le conteneur Mosquitto
   pw -p '<nouveau_mot_de_passe>'
   ```
   puis dans les options de l'add-on :
   ```yaml
   logins:
     - username: jeremy
       password: "<sortie hachée de pw>"
       password_pre_hashed: true
   ```
2. Répercuter le nouveau mot de passe dans Zigbee2MQTT (section `mqtt`) et dans l'intégration MQTT de HA.
3. **Envisager** de supprimer le mapping des ports hôte si aucun client MQTT externe au Supervisor n'existe : Zigbee2MQTT et HA joignent le broker par le réseau interne `hassio` (`172.30.33.0`), le mapping hôte n'est donc pas nécessaire.
4. Utiliser plutôt un **utilisateur Home Assistant dédié** (le broker sait s'authentifier contre HA sans `logins` local, comme l'indique la documentation de l'add-on).

---

## HIGH

### 🔴 H1 — Le PIN d'action critique de l'agent IA est contourné par les intents locaux, et l'alerte a été ignorée

**Preuve observée** — élément de réparation actif :

```json
{
  "issue_id": "pin_bypassed_by_local_intents_01KZR7D5RACZJ8C91Z5CARW908",
  "domain": "home_generative_agent",
  "translation_key": "pin_bypassed_by_local_intents",
  "translation_placeholders": { "pipelines": "Gemini" },
  "severity": "warning",
  "ignored": true,
  "dismissed_version": "2026.8.2",
  "active": true,
  "created": "2026-09-06T09:36:08"
}
```

Configuration HGA correspondante :

```yaml
critical_action_pin_enabled: true
critical_action_pin_hash: "<non reproduit>"
critical_action_pin_salt: "<non reproduit>"
llm_hass_api: ["assist"]
```

**Impact concret.** Un PIN d'action critique a été délibérément configuré pour protéger les opérations sensibles de l'agent IA. Home Assistant signale que **ce PIN est contourné par le pipeline d'intents locaux** : les commandes passant par le pipeline « Gemini » atteignent les actions sans franchir la barrière du PIN. La protection sur laquelle repose la confiance accordée à l'agent est donc inopérante sur au moins un chemin.

Aggravant : **l'alerte a été explicitement ignorée** (`ignored: true`) depuis la version 2026.8.2, mais reste `active: true` — la cause n'a pas été corrigée, seule la notification a été masquée.

Le contexte élargit la portée : 14 entités sont exposées à Google Assistant, dont `climate.clim_airton`, `switch.omnibattery_vacation_mode` (mode vacances de la batterie), `scene.eteindre_tout` et trois scripts de préparation énergétique. Une commande vocale mal interprétée ou injectée atteint donc des charges réelles.

**Cause probable.** Limitation connue de l'intégration `home_generative_agent` : le pipeline d'intents locaux court-circuite la couche de confirmation lorsqu'une intention est résolue localement avant d'atteindre l'agent.

**Recommandation précise.**

1. Réactiver l'alerte (ne plus l'ignorer) afin de suivre sa résolution en amont.
2. Mettre à jour HGA de **v3.39.4 vers v3.39.6** (mise à jour disponible) et vérifier si le correctif est inclus dans les notes de version.
3. Dans l'intervalle, **retirer de l'exposition vocale** les entités à effet physique irréversible ou coûteux — en particulier `switch.omnibattery_vacation_mode` et `scene.eteindre_tout`.
4. Consulter le guide de bonnes pratiques embarqué avant toute modification de l'exposition :
   `ha_get_skill_guide(skill="home-assistant-best-practices")`.

---

### 🔴 H2 — Boucle de reconnexion permanente du satellite vocal VACA : 99,7 % des logs

**Preuve observée** — analyse structurée du log d'erreur sur une fenêtre de 3 h 07 (16:21:07 → 19:28:07 le 12/09) :

| Composant | Occurrences | Part |
|---|---|---|
| `custom_components.vaca.assist_satellite` | **1 981** | **99,70 %** |
| `ha_mcp.client.rest_client` | 3 | 0,15 % |
| `ha_mcp.tools.tools_system` | 2 | 0,10 % |
| `homeassistant.components.xbox` | 1 | 0,05 % |

Message unique répété :
```
Satellite vaca_5a902d816 has been disconnected. Reconnecting in 10 second(s)
```
Source : `custom_components/vaca/assist_satellite.py:112`
Compteur cumulé sur le log système : **3 824 occurrences**.

État actuel de l'entité : `assist_satellite.vaca_5a902d816` = `idle` (le satellite finit par se reconnecter, puis retombe).

**Impact concret.**

- **Cadence :** 1 981 occurrences / 187 minutes ≈ **10,6 événements/minute**, soit environ **15 250 lignes par jour**.
- **Observabilité détruite.** C'est le point le plus grave : avec 99,7 % du log occupé par un seul message, **toute autre erreur devient invisible**. Lors de l'incident réseau du 12/09 (voir H5), les erreurs Modbus, Broadlink, Tuya et DNS ont été noyées dans ce flux.
- **Charge I/O et CPU** continue : écriture disque permanente, cycle de reconnexion toutes les 10 s.
- **Usure du stockage** sur la durée.

**Cause probable.** Le satellite VACA (View Assist Companion App, tablette Android) perd sa connexion WebSocket de façon répétée. Trois hypothèses, par ordre de vraisemblance : mise en veille agressive du Wi-Fi de la tablette Android ; instabilité du réseau Wi-Fi ; bug de gestion de keepalive dans `vaca` v0.13.2. L'hypothèse « veille Android » est renforcée par les entités `switch.vaca_5a902d816_screen_saver`, `switch.vaca_5a902d816_screen_on_with_motion` et `select.vaca_5a902d816_screen_timeout` présentes dans l'inventaire.

À noter : les déconnexions WebSocket observées pour l'application mobile (`No PONG received after 27.5 seconds`, depuis 3 adresses IP publiques différentes) suggèrent également une instabilité de la liaison montante.

**Recommandation précise.**

1. **Traiter la cause côté tablette** : désactiver l'optimisation de batterie pour l'application View Assist, et désactiver la mise en veille du Wi-Fi (Paramètres Android → Wi-Fi → Avancé → « Wi-Fi activé en veille »).
2. **Endiguer l'effet immédiat** en abaissant le niveau de log du composant, sans masquer les vraies erreurs :
   ```yaml
   # configuration.yaml
   logger:
     default: warning
     logs:
       custom_components.vaca.assist_satellite: error
   ```
   *(Cette modification nécessite un redémarrage ou un `logger.set_level`. Elle n'a pas été appliquée.)*
3. Vérifier la qualité du signal Wi-Fi à l'emplacement de la tablette.
4. Si le problème persiste après correction côté Android, ouvrir un ticket sur `msp1974/ViewAssist_Companion_App` avec l'extrait de log.

---

### 🔴 H3 — Recorder SQLite sans exclusions : 1,04 GiB en 9 jours

**Preuve observée** — santé du composant `recorder` :

```json
{
  "oldest_recorder_run": "2026-09-03T02:46:40",
  "current_recorder_run": "2026-09-11T11:28:31",
  "estimated_db_size": "1038.90 MiB",
  "database_engine": "sqlite",
  "database_version": "3.53.2"
}
```

Volumétrie mesurée sur 2 heures d'historique (12/09, 15:30 → 17:30 UTC) :

| Entité | Changements d'état / 2 h | Extrapolation / jour |
|---|---|---|
| `sensor.reseau_lisse_30_s` | **1 215** | ~14 580 |
| `sensor.opendtu_528ecc_ac_power` | **720** | ~8 640 |
| `input_text.energie_decision_arbitre` | 4 | ~48 |

**Impact concret.**

- **1,04 GiB pour 9 jours** de rétention sur **SQLite**. SQLite est mono-écrivain : chaque commit verrouille la base. À ce volume, les requêtes de l'interface (graphiques, historiques, dashboard énergie) se dégradent, et les opérations de purge nocturne deviennent longues.
- Deux capteurs à eux seuls génèrent **plus de 23 000 lignes par jour**. Sur 328 capteurs, dont beaucoup de mesures électriques rafraîchies toutes les 5 s, le total est considérable.
- **Aucune exclusion détectée** : les valeurs à haute fréquence (`sensor.reseau_lisse_30_s` est déjà une moyenne mobile — donc une donnée dérivée) sont enregistrées à pleine résolution.
- Effet secondaire : la sauvegarde automatique avec base incluse pèse **468 MB**, contre ~65 MB pour les sauvegardes de configuration seule.

**Cause probable.** Configuration `recorder` laissée aux valeurs par défaut, alors que l'installation a triplé de volume avec l'ajout de la chaîne énergétique (Shelly + OpenDTU + Omnibattery + 48 entités template).

**Recommandation précise.**

1. **Exclure les capteurs dérivés à haute fréquence** dont l'historique long n'a pas de valeur — ils sont recalculables et déjà agrégés :

   ```yaml
   # configuration.yaml — exemple, à adapter et NON appliqué
   recorder:
     purge_keep_days: 10
     commit_interval: 5
     exclude:
       entities:
         - sensor.reseau_lisse_30_s          # déjà une moyenne mobile 30 s
         - input_text.energie_decision_arbitre
         - input_text.energie_activite_automatique
         - sensor.omnibattery_daily_operation_timeline
       entity_globs:
         - sensor.onduleur1_*_tx_*           # statistiques radio Hoymiles
         - sensor.onduler_2_*_tx_*
         - sensor.*_rx_*
       domains:
         - update
   ```

2. **Conserver les statistiques long terme.** Les capteurs portant un `state_class` (`measurement`, `total`, `total_increasing`) alimentent les statistiques permanentes indépendamment de l'exclusion du recorder — l'onglet Énergie ne perd rien si l'on exclut les capteurs *dérivés* sans `state_class`. Vérifier au cas par cas avant exclusion.

3. **Migrer vers PostgreSQL.** L'add-on **PostgreSQL avec pgvector est déjà installé et démarré** pour HGA. Y basculer le recorder supprime la contrainte mono-écrivain de SQLite :
   ```yaml
   recorder:
     db_url: !secret recorder_db_url   # postgresql://...
   ```
   *(Opération à réaliser après une sauvegarde complète avec base — l'historique n'est pas migré automatiquement.)*

4. Vérifier l'effet après quelques jours via `ha_get_system_health` → `recorder.estimated_db_size`.

---

### 🔴 H4 — Race condition : deux arbitres commandent la climatisation à la même seconde

**Preuve observée.** Deux automatisations en `mode: restart` déclarent un déclencheur `time_pattern` sur la **même seconde** :

| Automatisation | Déclencheur | Mode |
|---|---|---|
| `automation.clim_maintien_automatique_19degc` (« Énergie - arbitre climatisation ») | `{"id": "reconciliation", "seconds": "/30"}` | `restart` |
| `automation.solaire_p1_orchestration_30s` (« Énergie - arbitre solaire et chauffe-eau ») | `{"id": "controle", "seconds": "/30"}` | `restart` |

Exécutions réellement observées dans les traces (12/09) :

```
clim_maintien_automatique_19degc   17:30:30.104194 → 17:30:30.110844
solaire_p1_orchestration_30s       17:30:30.305057 → 17:30:30.321348
                                   ↑ 201 ms d'écart, même tick
```

Les deux écrivent sur les mêmes entités. Extraction des actions de l'orchestrateur :

```
3 × climate.set_hvac_mode  → climate.clim_airton
3 × timer.start            → timer.clim_anti_court_cycle
3 × timer.start            → timer.clim_arret_automatique_contexte
```

Or la description de `clim_maintien_automatique_19degc` affirme explicitement : **« Seul arbitre de la clim Airton »**.

Les branches de l'orchestrateur qui commandent la climatisation sont : `Couper clim à 20 % pendant test chauffe-eau` (3 occurrences dans l'arbre `choose`), `Pré-rampage gros usage`, `Pré-rampage première tentative`, `Pré-rampage seconde chance`.

**Impact concret.** La documentation interne et le code divergent : le principe d'« arbitre unique » est violé. Deux automatisations `restart` peuvent, dans la même fenêtre de 200 ms, évaluer des conditions sur `climate.clim_airton` et émettre des commandes contradictoires — l'une démarrant le refroidissement sur surplus, l'autre coupant pour donner priorité au chauffe-eau. Le résultat dépend de l'ordonnancement de la boucle asyncio, donc **non déterministe**.

Un garde-fou existe et fonctionne : `timer.clim_arret_automatique_contexte` (10 s) marque les arrêts automatiques pour qu'ils ne soient pas confondus avec un arrêt manuel utilisateur par `automation.clim_manual_nest_summer`. Ce mécanisme est bien conçu. **Mais il protège de la mauvaise interprétation d'un arrêt, pas de la commande concurrente.**

À décharge : aucune commande contradictoire n'a été observée dans la fenêtre auditée, et les conditions des branches sont largement disjointes (`test_chauffe_eau_solaire_effectue_aujourd_hui`, `autour_pic`). Le risque est réel mais **conditionnel** — il se matérialise pendant la fenêtre de test chauffe-eau solaire, quand les deux arbitres sont simultanément actifs sur le sujet clim.

**Cause probable.** Ajout progressif de la logique de priorité chauffe-eau dans l'orchestrateur solaire, sans remonter les commandes clim vers l'arbitre dédié.

**Recommandation précise.**

1. **Décaler les déclencheurs** pour supprimer la simultanéité — correction minimale, effet immédiat :
   ```yaml
   # automation.solaire_p1_orchestration_30s
   triggers:
     - trigger: time_pattern
       seconds: "/30"
       # → devient :
     - trigger: time_pattern
       seconds: "15"     # et 45 : décalage de 15 s par rapport à l'arbitre clim
   ```
   *(Un `time_pattern` avec `seconds: "/30"` décalé s'obtient plus proprement par deux déclencheurs à secondes fixes 15 et 45.)*

2. **Correction de fond (recommandée)** — rétablir le principe d'arbitre unique : l'orchestrateur ne doit **pas** appeler `climate.set_hvac_mode`. Il doit poser une demande dans un helper (`input_boolean.energie_demande_suspension_clim` par exemple), et l'arbitre climatisation l'intègre comme condition dans sa branche « Été priorité chauffe-eau » déjà existante. Cela restaure la propriété exclusive de `climate.clim_airton` par un seul acteur.

3. Aligner les descriptions sur le comportement réel une fois la correction faite.

---

### 🔴 H5 — Point unique de défaillance : le lien Modbus vers la batterie Marstek

**Preuve observée** — extraits du log système du 12/09 :

```
[Marstek Venus 1] Failed to read ['user_work_mode']                     ×98
[Marstek Venus 1] All 21 read attempts failed (consecutive failures: 5) ×5
[Marstek Venus 1] 5 consecutive failures - attempting fresh reconnection ×3
[Marstek Venus 1] Polling suspended after 5 consecutive failures. Will retry in 2 minutes.
[Marstek Venus 1] Reconnection failed, suspending for another 2 minutes ×3
Failed to connect to Modbus server at 192.168.1.92:502 with unit 1      ×6
pymodbus: Failed to connect [Errno 101] Network unreachable
```

L'incident est **corrélé à une coupure réseau générale** : au même horodatage, on observe `Network unreachable` sur Broadlink (2 appareils), Tuya Local (3 appareils), Chromecast, AndroidTV, zeroconf, SSDP, et `Timeout while contacting DNS servers` sur le cloud Nabu Casa (`snitun`, 24 erreurs).

État actuel : batterie opérationnelle (`sensor.marstek_venus_1_battery_soc` = 87, `omnibattery: batteries_connected: 1/1, non_responsive: 0`). L'incident est **résolu**.

**Impact concret.** Toute la chaîne de décision énergétique dépend de la batterie Marstek en Modbus TCP :

- L'**arbitre batterie** a 16 conditions de garde, dont `numeric_state` sur `sensor.marstek_venus_1_battery_soc` — quand la batterie devient indisponible, **l'automatisation entière ne s'exécute pas** (les conditions échouent). C'est un choix de conception défendable (ne pas commander à l'aveugle), mais il signifie que la batterie reste figée dans son dernier état de consigne pendant toute la panne.
- L'**arbitre climatisation** conditionne le démarrage été à `SOC > 84,9` — un SOC indisponible bloque le démarrage.
- L'**orchestrateur solaire** utilise le SOC dans 5 branches.

Un seul appareil Wi-Fi/Modbus indisponible gèle donc la totalité du pilotage énergétique.

Point positif notable : `binary_sensor.energie_capteurs_critiques_valides` implémente une **garde de fraîcheur** bien conçue (`< 120 s` sur le compteur Shelly, `< 43 200 s` sur la température, exemption solaire la nuit), et l'arbitre climatisation coupe la clim avec notification si cette garde tombe. **C'est une excellente pratique**, rare dans les installations résidentielles.

**Cause probable.** L'incident réseau global du 12/09 (~18:15 heure locale) a affecté simultanément le LAN et le DNS. Les sauvegardes nommées `Avant_migration_reseau_Huawei_B525_2026-09-09` suggèrent un **changement récent d'équipement réseau**, cohérent avec une instabilité résiduelle.

**Recommandation précise.**

1. **Fiabiliser le lien de la batterie** : si la Marstek est en Wi-Fi, la basculer en Ethernet, ou à défaut lui réserver un bail DHCP statique et vérifier la couverture Wi-Fi. Le passage sur `192.168.1.92` doit être stable.
2. **Stabiliser le réseau** : l'incident a touché DNS, Wi-Fi et liaison montante. Vérifier la configuration du nouvel équipement (Huawei B525), notamment le serveur DNS distribué en DHCP (`192.168.1.254`) et l'isolation AP éventuelle.
3. **Ajouter une supervision explicite** : un `binary_sensor` template signalant une indisponibilité prolongée de la batterie, avec notification — aujourd'hui, une panne longue est silencieuse côté utilisateur.
4. **Documenter le comportement de repli attendu** : que doit faire l'installation si la batterie est injoignable 6 h ? Le comportement actuel (gel des consignes) est implicite, pas décidé.

---

## MEDIUM

### 🔴 M1 — Chaîne de 16 cartes Lovelace inline héritant les unes des autres

**Preuve observée** — 26 ressources Lovelace, dont **19 inline**. Parmi elles, une chaîne d'héritage :

```
omni-energy-flow-card-v5   (classe de base, 74 698 octets)
  └─ v6  ← extends v5      (947 o)
      └─ v7  ← extends v6  (2 574 o)     ─┐
      └─ v8  ← extends v6  (3 355 o)      │  v7 est court-circuitée :
          └─ v9  ← extends v8 (2 664 o)   │  v9 hérite de v8, pas de v7
              └─ v10 ← v9   (2 472 o)    ─┘
                  └─ v11 ← v10 (2 103 o)
                      └─ v12 ← v11 (4 512 o)
                          └─ v13 ← v12 (4 495 o)
                              └─ v14 ← v13 (3 494 o)
                                  └─ v15 ← v14 (1 054 o)
                                      └─ v16 ← v15 (11 060 o)
                                          └─ v17 ← v16 (20 262 o)
                                              └─ v18 ← v17 (2 751 o)
                                                  └─ v19 ← v18 (3 243 o)
                                                      └─ v20 ← v19 (1 946 o)
```

Motif répété dans chaque ressource :
```javascript
const ParentV19 = customElements.get('omni-energy-flow-card-v19');
if (ParentV19 && !customElements.get('omni-energy-flow-card-v20')) {
  class OmniEnergyFlow... extends ParentV19 { ... }
}
```

**Volumétrie :** 146,7 KB de JavaScript inline au total, dont **138,3 KB pour la seule chaîne omni-energy-flow**.

**Impact concret.**

- **Performance frontend** : 19 modules inline sont chargés et évalués à **chaque ouverture de dashboard**, sur tous les appareils — y compris la tablette View Assist et le téléphone. Aucun de ces modules n'est mis en cache par le navigateur comme le serait un fichier statique versionné.
- **Fragilité de la chaîne** : chaque niveau teste `if (Parent && !customElements.get(...))`. Si un seul maillon échoue à s'enregistrer (erreur JS, ordre de chargement non garanti), **tous les niveaux suivants sont silencieusement ignorés** — la carte affichée est alors une version antérieure, sans erreur visible.
- **Ordre de chargement non garanti** : les ressources Lovelace sont chargées en parallèle. Cette chaîne suppose un ordre séquentiel qui n'est pas contractuel.
- **Maintenabilité** : déterminer quel comportement est effectivement actif impose de lire 16 fichiers. Un correctif appliqué à v12 peut être écrasé par v17.
- **Anomalie détectée** : v7 (2 574 o) hérite de v6, mais v9 hérite de v8 — **v7 est du code mort**, jamais utilisé dans la chaîne finale.

**Cause probable.** Itérations successives de développement de la carte, chaque version ajoutée sans refactorisation de la précédente, pour éviter de casser l'existant.

**Recommandation précise.**

1. **Aplatir la chaîne** : générer une seule classe `omni-energy-flow-card` consolidée, reprenant le comportement final effectif (v20). Supprimer les 15 ressources intermédiaires.
2. **Externaliser** : placer le résultat dans `/config/www/omni-energy-flow-card.js` et le référencer par URL versionnée (`?v=1.0.0`), ce qui restaure la mise en cache navigateur.
3. Supprimer en priorité **v7** (code mort confirmé).
4. Faire une sauvegarde avant : la suppression d'une ressource casse immédiatement les dashboards qui l'utilisent.

---

### 🔴 M2 — Sous-système « Routeur IA » entièrement non fonctionnel

**Preuve observée.** L'ensemble du sous-système est hors service :

| Composant | État |
|---|---|
| `automation.ia_routeur_unique` | **`off`** — seule automatisation désactivée de l'installation |
| `conversation.google_ai_conversation` | **`unavailable`** depuis le 11/09 13:29 |
| Intégration `google_generative_ai_conversation` | **`not_loaded`**, `disabled_by: user` |
| Erreur de configuration | `401 UNAUTHENTICATED — ACCESS_TOKEN_TYPE_UNSUPPORTED` |
| Helpers dédiés | **31** |
| Dashboard | `agents-ia` (« Agents IA ») |
| Ressources Lovelace associées | 3 (`AiAgentCard`, `AiMetricCard`, `AiRouterChatCard`) |

Détail des 31 helpers : 13 `input_text`, 6 `input_number`, 6 `input_button`, 4 `counter`, 1 `input_boolean`, 1 `input_select`.

**Parmi eux, 20 ne sont référencés par aucune automatisation ni script** (résultat de recherche : `match_in_config: false`) — ils n'existent que pour l'affichage du dashboard. Exemples : `input_number.routeur_ia_confiance_routage`, `input_number.routeur_ia_score_equipe`, `input_text.routeur_ia_conseil_du_jour`, `input_text.routeur_ia_equipe_disponible`, `input_text.routeur_ia_etat_1minai`.

Les états résiduels confirment l'abandon : `input_text.routeur_ia_etat_1minai` = *« En préparation : relais privé 1min-relay requis avant connexion à HGA. »*, `counter.routeur_ia_requetes_1minai` = 0, `counter.routeur_ia_requetes_gemini` = 0, `counter.routeur_ia_requetes_hga` = 2.

**Impact concret.** 31 entités inutiles sur 702 (4,4 %) alourdissent le registre, le recorder, l'autocomplétion et la charge cognitive de maintenance. Un dashboard entier affiche des données figées. Le coût n'est pas la performance — c'est la **confusion** : lors d'un futur diagnostic, ces entités seront prises pour des composants actifs.

**Cause probable.** Projet d'orchestrateur multi-agents (Gemini / HGA / HA natif / 1minAI) abandonné après échec d'authentification Google, dont l'infrastructure n'a pas été démontée.

**Recommandation précise.** Deux options, selon l'intention :

- **Si le projet est abandonné** — supprimer les 31 helpers, le dashboard `agents-ia`, les 3 ressources Lovelace associées et l'automatisation. Gain : −4,4 % d'entités, un dashboard de moins.
- **Si le projet est à reprendre** — corriger d'abord l'authentification Google (le message `ACCESS_TOKEN_TYPE_UNSUPPORTED` indique une **clé API Google AI Studio attendue, pas un token OAuth**), réactiver l'intégration, puis l'automatisation.

Dans les deux cas, **trancher** : l'état intermédiaire actuel est le plus coûteux.

---

### 🔴 M3 — Sept intégrations non chargées, dont une en erreur permanente

**Preuve observée :**

| Intégration | État | Cause |
|---|---|---|
| `local_openai` (Cerebras) | `not_loaded` | **Erreur** : `Platform local_openai.config_flow not found` + repair « redémarrage requis » actif |
| `google_generative_ai_conversation` | `not_loaded` | `disabled_by: user` — erreur 401 (voir M2) |
| `zha` | `not_loaded` | `disabled_by: user` — **normal**, Zigbee2MQTT est utilisé |
| `bluetooth` (Raspberry Pi bcm43438) | `not_loaded` | `disabled_by: user` — matériel absent |
| `bluetooth` (Intel 8087:0a2a) | `not_loaded` | `source: ignore` |
| `rpi_power` | `not_loaded` | `disabled_by: user` — **non pertinent** sur x86-64 |
| `ibeacon` | `not_loaded` | `source: ignore` |

Repair actif correspondant :
```json
{"issue_id": "restart_required_1078613636_tags/1.12.0",
 "domain": "hacs", "issue_domain": "local_openai",
 "is_fixable": true, "ignored": false,
 "created": "2026-09-12T02:32:36"}
```

**Impact concret.** Seul `local_openai` est réellement problématique : l'intégration a été téléchargée par HACS (v1.12.0) mais **son `config_flow` est introuvable**, ce qui bloque son chargement. L'entité `conversation.cerebras_gpt_oss_120b_ai_agent` est en conséquence `unavailable`. Le repair est `is_fixable: true` et **non ignoré** — il attend une action.

Les six autres entrées sont soit correctes (`zha` désactivée au profit de Z2M, c'est une bonne pratique), soit du bruit de découverte sans impact.

**Recommandation précise.**

1. Appliquer le repair `restart_required` de HACS pour `local_openai` (redémarrage de HA), qui résoudra probablement le `config_flow not found` — l'intégration a été installée sans redémarrage.
2. Si l'erreur persiste après redémarrage, l'intégration est incompatible avec HA 2026.9 : la désinstaller.
3. Supprimer l'entrée `rpi_power` (Raspberry Pi Power Supply Checker) : sans objet sur `generic-x86-64`.

---

### 🔴 M4 — 39 entités indisponibles ou inconnues

**Preuve observée** — dénombrement par template : **39 entités** sur 702 (5,6 %) en état `unavailable` ou `unknown`. Parmi les 14 explicitement `unavailable` :

| Entité | Diagnostic |
|---|---|
| `light.ampoule_1`, `light.ampoule_2`, `light.ampoule_3`, `light.lampe_placard` | **4 des 5 lampes de l'installation** sont mortes |
| `conversation.google_ai_conversation`, `stt.google_ai_stt`, `tts.google_ai_tts`, `ai_task.google_ai_task` | Chaîne Google AI complète — voir M2 |
| `conversation.cerebras_gpt_oss_120b_ai_agent` | Voir M3 |
| `sensor.shelly_reseau_rapide_mqtt` | Orphelin — voir L3 |
| `media_player.bureau_2` (« JARVIS ») | Résidu — une sauvegarde `Avant_suppression_JARVIS` existe (04/09) |
| `media_player.android_tv_192_168_1_44` | Erreurs ADB récurrentes |
| `button.disjoncteur_clim_refresh` | Tuya Local |
| `select.marstek_venus_1_battery_phase` | Registre Modbus non supporté |

**Impact concret.** Chaque entité indisponible référencée dans une automatisation produit un avertissement à l'exécution. Exemple confirmé dans les logs :
```
Referenced entities remote.remote_ir are missing or not currently available
```
Le domaine `light` est le plus dégradé : **4 lampes sur 5 sont hors service**. Seule `light.smart_bulb` (Broadlink LB1) fonctionne — et c'est précisément la seule ciblée par les automatisations `reveil_simulateur_d_aube_rgb` et `eteindre_lumiere`. Ce nettoyage a donc déjà été fait côté automatisations (la description d'`eteindre_lumiere` le documente explicitement : *« Les anciennes lampes indisponibles ont été retirées de la cible »*) — **mais les entités elles-mêmes subsistent dans le registre**.

**Recommandation précise.**

1. Supprimer du registre les 4 lampes mortes (`light.ampoule_1/2/3`, `light.lampe_placard`) si le matériel n'est plus en service, ainsi que `media_player.bureau_2` (JARVIS).
2. Traiter `sensor.shelly_reseau_rapide_mqtt` (L3).
3. Les entités Google AI / Cerebras se résoudront avec M2 et M3.
4. Avant toute suppression, vérifier les références avec `ha_search(query="<entity_id>")` — la recherche remonte les automatisations, scripts et scènes concernés même si leur configuration n'est pas lisible.

---

### 🔴 M5 — Automatisations monolithiques : un fichier de 56 003 caractères

**Preuve observée** — `automation.solaire_p1_orchestration_30s` (« Énergie - arbitre solaire et chauffe-eau ») :

| Métrique | Valeur |
|---|---|
| Taille de la configuration | **56 003 caractères** |
| Déclencheurs | **14** |
| Branches `choose` nommées | **30** |
| Variables Jinja de haut niveau | 6 (dont `potentiel_export`, 4 lignes) |
| Longueur de la description | ~1 900 caractères |
| Mode | `restart` |

Comparaison : `automation.batterie_reglages_nuit_apres_arret_solaire` compte 7 déclencheurs, **16 conditions de garde** et 12 branches ; `automation.clim_maintien_automatique_19degc` compte 12 déclencheurs et 17 branches, avec une description de ~2 400 caractères.

Les 30 branches de l'orchestrateur : `Anticipation vocale gros usage`, `Charge vocale détectée`, `Chauffe-eau - protéger batterie et réseau hors tampon`, `Comptabiliser arrêt externe`, `Couper clim à 20 % pendant test chauffe-eau`, `Débrider pour charge ou déficit`, `Détecter cycle`, `Expiration forçage chauffe-eau`, `Fin anticipation vocale`, `Fin heures creuses`, `Forçage manuel arrêt`, `Forçage manuel marche`, `Hiver chauffe-eau solaire strict sans batterie ni réseau`, `Lave-vaisselle - maintien débridage total`, `Machine à laver démarre`, `Planifier le pic Solcast`, `Première tentative chauffe solaire`, `Priorité chauffage hiver`, `Pré-rampage gros usage`, `Pré-rampage première tentative`, `Pré-rampage seconde chance`, `Préparer machine à laver`, `Reset journalier chauffe-eau robuste`, `Resynchroniser onduleurs`, `Réguler export résiduel 100–150 W`, `Réhydrater verrou seconde chance après redémarrage`, `Seconde chance solaire`, `Secours 48 h en heures creuses`, `Sécurité capteurs`, `Thermostat atteint`.

**Impact concret.**

- **Diagnostic quasi impossible** : seules **5 traces** sont conservées par automatisation (valeur par défaut). Sur une automatisation déclenchée toutes les 30 s, les 5 traces couvrent **2 minutes 30**. Un comportement anormal survenu il y a une heure est indiagnosticable.
- **Éditeur UI inutilisable** à cette taille — toute modification se fait en YAML, ce qui multiplie le risque d'erreur.
- **Tests impossibles** : on ne peut pas exercer une branche isolément.
- **Effet de bord du mode `restart`** : chaque déclenchement (14 sources, dont un `time_pattern` à 30 s et un à 5 min) **annule l'exécution en cours**. Une branche longue peut être interrompue à mi-parcours, laissant des helpers dans un état intermédiaire.

**À décharge — ce qui est bien fait.** L'exécution mesurée est **rapide** : 5 à 17 ms par run (traces du 12/09). Il n'y a **pas** de problème de charge CPU. Les branches sont nommées (`alias`), les conditions sont majoritairement natives plutôt que Jinja, les `trigger id` sont systématiquement utilisés, et les gardes de sécurité (`Sécurité capteurs`) sont placées en premier. **C'est du travail de qualité** — le problème est le volume, pas la méthode.

**Recommandation précise.**

1. **Augmenter la rétention des traces** sur les automatisations complexes — correction à coût nul et à bénéfice immédiat :
   ```yaml
   automation:
     - id: "1787..."
       alias: Énergie - arbitre solaire et chauffe-eau
       trace:
         stored_traces: 50     # au lieu de 5
   ```
2. **Scinder par domaine fonctionnel.** Les 30 branches se regroupent naturellement en 4 automatisations cohérentes :
   - *Chauffe-eau solaire* (tentatives, seconde chance, secours 48 h, thermostat, reset journalier) — ~12 branches ;
   - *Bridage/débridage OpenDTU* (régulation export, resynchronisation, anti-rebridage) — ~6 branches ;
   - *Préparation vocale gros usage* (machine à laver, lave-vaisselle, anticipation) — ~7 branches ;
   - *Forçages manuels et resets* — ~5 branches.
3. **Factoriser les variables Jinja dupliquées** (`potentiel_export`, `autour_pic`, `belle_journee`, `confort_hiver_ok`) en **capteurs template** réutilisables. Elles sont aujourd'hui recalculées à chaque déclenchement dans chaque automatisation ; en capteurs template, elles sont évaluées une fois et deviennent observables dans l'UI — un gain de diagnostic considérable.
4. Consulter `ha_get_skill_guide(skill="home-assistant-best-practices")` avant refactorisation.

---

### 🟠 M6 — Add-on File editor démarré en permanence

**Preuve observée :** add-on `core_configurator` v6.1.0, `state: started`, `boot: auto`, consommation 25 MB.

**Impact concret.** File editor donne un accès **en lecture et écriture à l'ensemble de `/config`**, y compris `secrets.yaml`, via l'interface web de Home Assistant. Toute session HA authentifiée — ou tout détournement de session — accède ainsi aux secrets en clair et peut modifier n'importe quel fichier de configuration. L'add-on est en `ingress`, donc protégé par l'authentification HA, mais il élargit significativement l'impact d'une compromission de compte.

**Recommandation.** Passer `boot` à `manual` et arrêter l'add-on quand il n'est pas utilisé. Terminal & SSH (également installé, correctement configuré : pas de mot de passe, pas de clé, port 22 non mappé, ingress uniquement) couvre déjà le besoin d'édition ponctuelle.

---

### 🔴 M7 — Blueprint ciblant un `device_id` codé en dur

**Preuve observée** — `automation.lumiere_chambre_manuelle` :

```yaml
use_blueprint:
  path: ferezvi/TS004F_1_Button.yaml
  input:
    remote_device: 69057cf7619edcc3c0a0d8f7680cdafe   # device_id opaque
    single_press_action:
      - action: light.turn_on
        target:
          area_id: chambre                             # ciblage par zone
    long_press_action:
      - action: switch.turn_on
        target:
          entity_id: switch.prise_chambre_socket_1     # ciblage par entité — correct
```

**Impact concret.** Deux problèmes de nature différente :

1. **`device_id` codé en dur** — anti-pattern documenté par Home Assistant. Si le bouton Zigbee TS004F est ré-appairé (pile changée, reset, migration de coordinateur), un **nouveau `device_id` est généré** et l'automatisation cesse silencieusement de fonctionner, sans erreur.
2. **`area_id: chambre`** — la zone `chambre` contient 7 entités. Un `light.turn_on` sur la zone allume **toutes les lumières** qu'elle contient. Or les lampes de cette zone sont majoritairement `unavailable` (voir M4), ce qui génère des avertissements à chaque appui.

La description de l'automatisation montre que le problème est **partiellement connu** : *« La prise est ciblée par entity_id pour rester robuste si le périphérique est réappairé. »* La bonne pratique a été appliquée à la prise, mais pas au déclencheur ni aux lumières.

**Recommandation précise.** Le `remote_device` est imposé par le blueprint (son sélecteur attend un appareil) — c'est une limite du blueprint, pas de la configuration. En revanche :

```yaml
single_press_action:
  - action: light.turn_on
    target:
      entity_id: light.smart_bulb     # au lieu de area_id: chambre
    data:
      color_temp_kelvin: 4000
      brightness_pct: 100
double_press_action:
  - action: light.turn_off
    target:
      entity_id: light.smart_bulb
```

Documenter le `device_id` et sa correspondance (« Bouton chambre TS004F ») dans la description, pour faciliter la reconstruction après ré-appairage.

---

### 🔵 M8 — Aucun étage défini, aucun helper rangé en zone

**Preuve observée :**
- `floor_count: 0`, `area_count: 7`, `unassigned_count: 7` — **les 7 zones sont sans étage**.
- **143 helpers sur 143 sans `area_id`.**
- Deux zones vides : `cuisine` (0 entité) et `bureau` (0 entité).
- La zone `domotique` concentre 134 entités, `salon` 124.

**Impact.** Pas de dysfonctionnement, mais une perte réelle d'ergonomie : les vues automatiques par zone, le ciblage vocal par pièce (« éteins tout dans le salon ») et les futures fonctionnalités structurées par étage sont indisponibles. La zone `domotique` sert de fourre-tout technique.

**Recommandation.** Créer au minimum un étage, y rattacher les 7 zones, supprimer ou peupler `cuisine` et `bureau`. Le rangement des helpers est facultatif mais améliore le filtrage.

---

### 🟠 M9 — Stratégie de sauvegarde : 29 copies sur 30 stockées localement

**Preuve observée** — 30 sauvegardes, toutes `protected: true` (chiffrées) :

| Critère | Constat |
|---|---|
| Stockage | **29 sur `hassio.local`** (disque de la machine), **1 seule sur `cloud.cloud`** |
| Base de données incluse | **3 sur 30** seulement |
| Sauvegarde automatique | **1 seule conservée** — « Automatic backup 2026.8.2 », datée du **09/09** (3 jours) |
| Sauvegarde la plus récente | `avant_corrections_audit_20260911` — 11/09, **sans base de données** |
| Version HA des sauvegardes | 29 sur 30 en **2026.8.2**, une seule en 2026.9.1 |
| Volume total local | ~2,5 GB |

**Impact concret.**

1. **Règle 3-2-1 non respectée.** 29 sauvegardes sur le disque de la machine qu'elles sont censées protéger. En cas de panne disque, de corruption du système de fichiers ou de vol, **une seule sauvegarde subsiste** — celle du 09/09 sur le cloud Nabu Casa, en version 2026.8.2, soit **antérieure à la version actuellement en production (2026.9.1)**.
2. **Perte d'historique garantie.** 27 sauvegardes sur 30 sont `database_included: false`. Une restauration signifie la perte de tout l'historique et de toutes les statistiques long terme (consommation, production solaire, coûts) — l'actif le plus difficile à reconstituer d'une installation énergétique.
3. **Dépendance à l'abonnement Nabu Casa**, qui **expire le 12/10/2026** (dans 30 jours). À son expiration, la seule sauvegarde hors site disparaît.

**À décharge — une excellente pratique constatée :** les sauvegardes sont systématiquement créées **avant chaque modification significative**, avec un nommage explicite et daté (`Avant_migration_reseau_Huawei_B525_2026-09-09`, `Avant_maj_OmniBattery_1.4.0`, `Avant_protections_disjoncteur_clim`, `Avant_refonte_energie_2026-09-02`). C'est une discipline rare et précieuse. Le problème est la **destination**, pas la fréquence.

**Recommandation précise.**

1. **Immédiat** — créer une sauvegarde complète **avec base de données** de la version 2026.9.1 actuelle, et la copier hors de la machine (NAS, disque externe, stockage cloud tiers).
2. **Configurer un second agent de sauvegarde** (Google Drive, OneDrive, Samba/NAS via l'intégration correspondante) afin de ne plus dépendre du seul Nabu Casa.
3. **Activer la base de données dans les sauvegardes automatiques** et porter la rétention à au moins 3 copies.
4. **Purger les sauvegardes locales anciennes** en version 2026.8.2 : conserver 5 à 7 jalons, libérer ~2 GB.
5. **Tester une restauration** au moins une fois : une sauvegarde jamais restaurée est une hypothèse, pas une garantie.

---

### 🔵 M10 — Les descriptions d'automatisation servent de journal de modifications

**Preuve observée** — extraits de descriptions :

> « [Durci le 11/09/2026 : si l'agent Gemini est indisponible (identifiants invalides), l'échec est maintenant signalé explicitement au lieu d'échouer silencieusement.] » — `ia_routeur_unique`

> « [Durci le 11/09/2026 : coercition en chaîne avant regex pour éviter un IndexError si adb_response n'est pas une chaîne exploitable.] » — `bbox_memorise_chaine_via_adb`

> « Mise à jour 10/09/2026 : cible thermique centrale 19 °C. […] Ajustement hiver 10/09 : à la fin du surplus utile, un boost à 23 °C est coupé si la pièce est encore >19,2 °C » — `clim_maintien_automatique_19degc` (description de ~2 400 caractères)

**Impact.** Les descriptions mêlent trois choses : la spécification fonctionnelle, l'historique des modifications et les notes de mise au point. Elles deviennent illisibles et, surtout, **elles divergent du code** — la description de l'arbitre climatisation affirme être « seul arbitre de la clim », ce que le code contredit (voir H4). Une description fausse est pire qu'une description absente.

**Recommandation.** Réserver la description à **ce que fait l'automatisation aujourd'hui**, au présent. Déporter l'historique vers un versionnement Git du dossier `/config` — ce qui donnerait en outre un vrai filet de sécurité et une traçabilité des modifications. Le dépôt `claude-ha` présent dans l'espace de travail pourrait servir à cela (il ne contient actuellement qu'un `README.md`).

---

## LOW

### 🔴 L1 — Trois mises à jour en attente

| Composant | Version installée | Disponible |
|---|---|---|
| Tailscale (add-on) | 0.29.0 | **0.30.0** |
| Grocy (add-on) | 0.26.0 | disponible |
| Home Generative Agent (HACS) | v3.39.4 | **v3.39.6** |

Entités `update` à l'état `on` : `update.tailscale_mise_a_jour`, `update.grocy_mise_a_jour`, `update.home_generative_agent_update`.

**Priorité.** Tailscale d'abord (composant réseau privilégié : `NET_ADMIN`, `NET_RAW`, `SYS_ADMIN`, `host_network: true`). HGA ensuite (susceptible de corriger H1). Grocy est sans enjeu (add-on arrêté).

### 🔵 L2 — Add-on Grocy installé mais arrêté

`a0d7b954_grocy` v0.26.0, `state: stopped`, `boot: auto`, aucune statistique. Une sauvegarde `Grocy 0.25.2` existe (30/08). S'il n'est plus utilisé, le désinstaller libère l'espace et une entité `update`.

### 🔴 L3 — Capteur MQTT orphelin

`sensor.shelly_reseau_rapide_mqtt` est `unavailable` depuis le 12/09 09:15 UTC. **Vérification effectuée : aucune référence** dans les automatisations, scripts, scènes, helpers ou dashboards (`ha_search` → 0 résultat).

Précision importante : ce capteur **n'est pas** dans la chaîne critique. `sensor.reseau_lisse_30_s` est alimenté par `sensor.shellyproem50_ece334f85344_energy_meter_0_puissance` (intégration Shelly native), pas par MQTT :

```yaml
# entry 01M148FN273GZH7GSFYCNAQ6GX (filter)
entity_id: sensor.shellyproem50_ece334f85344_energy_meter_0_puissance
filter: time_simple_moving_average
window_size: { seconds: 30 }
```

Il s'agit donc d'un vestige d'une tentative d'accès MQTT au Shelly, à supprimer sans risque.

### 🔵 L4 — Deux fournisseurs de prévision solaire en parallèle

`solcast_solar` v4.6.1 (HACS) **et** `forecast_solar` (natif) sont tous deux chargés. Les automatisations utilisent **exclusivement Solcast** (`sensor.solcast_pv_forecast_*` apparaît dans les branches de l'orchestrateur, de l'arbitre batterie et de l'automatisation de figeage). Deux capteurs template consomment encore Forecast.Solar (`Forecast.Solar coefficient adaptatif`, `Forecast.Solar corrigé aujourd'hui`), apparemment pour une comparaison de performance.

Si la comparaison n'est plus exploitée, supprimer `forecast_solar` retire un appel réseau périodique et deux entités template. Un repair signale par ailleurs que le capteur Solcast de production restante est recommandé par Omnibattery (`solar_forecast_remaining_recommended`, **ignoré**).

### 🔴 L5 — Erreurs récurrentes de l'intégration Xbox

```
Error fetching xbox data: Failed to connect to Xbox Network            ×12
Error fetching xbox data: ... due to a connection timeout
```
Première occurrence il y a ~26 h. L'intégration produit 4 entités (`binary_sensor` Game Pass, 3 `image`). Si la console est éteinte ou le service indisponible, ces erreurs sont récurrentes et sans valeur. Envisager la désactivation si l'usage est marginal.

### 🔴 L6 — Capteur `total_increasing` non strictement croissant

```
Entity sensor.omnibattery_consumption_profile_capture from integration omnibattery
has state class total_increasing, but its state is not strictly increasing.
Triggered by state 1.894 (previous state: 1.899)
```
Bug de l'intégration custom Omnibattery : un capteur déclaré `total_increasing` décroît, ce qui provoque une réinitialisation du compteur de statistiques long terme et fausse les totaux. À signaler en amont : `https://github.com/ffunes/omnibattery/issues`.

Dans le même registre, une alerte de performance :
```
Updating state for sensor.omnibattery_daily_operation_timeline took 0.726 seconds
```
0,726 s dans la boucle d'événements est significatif — à signaler également.

### 🔵 L7 — Rétention de traces insuffisante pour la complexité

5 traces conservées par automatisation (défaut). Sur les automatisations à `time_pattern` 30 s, cela couvre **2 min 30 d'historique**. Voir M5, recommandation 1.

### 🔵 L8 — Deux zones vides

`cuisine` et `bureau` contiennent 0 entité. À peupler ou supprimer.

---

## Informationnel

- **Analytics Home Assistant** : intégration `analytics` chargée (`source: system`) — comportement standard.
- **`go2rtc`** chargé (`source: system`) — standard depuis 2024, aucune caméra configurée dans cette installation.
- **Abonnement Nabu Casa** : expire le **12/10/2026** (30 jours). Certificat TLS valide jusqu'au 14/11/2026, `certificate_status: ready`.
- **`hassio_role`** des add-ons : `core_ssh` en `manager` (élevé mais inhérent à sa fonction), les autres en `default`. Aucun add-on en `full_access` ou `privileged` hors Tailscale (justifié par sa fonction VPN).
- **Zigbee2MQTT** : `socat` désactivé (bon point — pas de port série exposé en TCP), accès en `ingress` uniquement, port frontend 8099 non mappé sur l'hôte.
- **`pref_disable_polling`** : `false` sur toutes les intégrations — aucune optimisation de polling en place.
- **HACS** : 5 000 appels API GitHub restants, 15 dépôts sur 4 131 disponibles, stage `running`.

---

## 5. Quick wins

Actions à fort rapport bénéfice/effort, réalisables en moins de 30 minutes chacune.

| # | Action | Effort | Gain | Risque |
|---|---|---|---|---|
| 1 | `webhook_auth` ≠ `none` et `bind_host` → `127.0.0.1` sur `ha_mcp_tools` | 5 min | **Ferme la surface d'attaque C1** | Reconfigurer le client MCP |
| 2 | Abaisser le niveau de log de `custom_components.vaca.assist_satellite` | 5 min | **−99 % de volume de log**, observabilité restaurée | Aucun |
| 3 | Porter `stored_traces` à 50 sur les 3 automatisations énergie | 10 min | Diagnostic enfin possible | Aucun |
| 4 | Créer une sauvegarde complète **avec base** en 2026.9.1 et la sortir de la machine | 15 min | Couvre le risque de perte totale | Aucun |
| 5 | Décaler le `time_pattern` de l'orchestrateur à `seconds: 15,45` | 5 min | **Supprime la simultanéité de H4** | Faible, à tester |
| 6 | Mettre à jour Tailscale 0.29.0 → 0.30.0 | 5 min | Correctifs de sécurité réseau | Coupure VPN brève |
| 7 | Supprimer `sensor.shelly_reseau_rapide_mqtt` (orphelin vérifié) | 2 min | −1 entité morte | **Nul** (0 référence) |
| 8 | Appliquer le repair HACS `restart_required` pour `local_openai` | 5 min | Résout M3 | Redémarrage HA |
| 9 | Supprimer la ressource Lovelace `omni-energy-flow-card-v7` (code mort) | 5 min | −2,5 KB, chaîne clarifiée | Vérifier d'abord |
| 10 | Passer l'add-on File editor en `boot: manual` et l'arrêter | 2 min | Réduit l'exposition de `/config` | Aucun |

---

## 6. Plan de durcissement sécurité

### Phase 1 — Fermer les accès non authentifiés (immédiat)

1. **Serveur MCP (C1).** `webhook_auth` authentifié ou `enable_webhook: false` ; `bind_host` restreint à `127.0.0.1` ou à l'adresse tailnet ; `auto_update: false`.
2. **MQTT (C2).** Rotation du mot de passe, passage en `password_pre_hashed: true`, répercussion sur Zigbee2MQTT et l'intégration MQTT.
3. **Vérification externe.** Depuis un autre poste du LAN : `nmap -p 1883,1884,8883,8884,9584 192.168.1.74` — seuls les ports volontairement ouverts doivent répondre.

### Phase 2 — Réduire la surface (7 jours)

4. **Supprimer le mapping des ports MQTT** vers l'hôte si aucun client externe au Supervisor ne les utilise (Z2M et HA passent par le réseau `hassio` interne).
5. **File editor** en démarrage manuel (M6).
6. **Réduire l'exposition vocale** : retirer `switch.omnibattery_vacation_mode` et `scene.eteindre_tout` de Google Assistant tant que H1 n'est pas résolu.
7. **Réactiver et suivre le repair `pin_bypassed_by_local_intents`** (H1) plutôt que de le masquer ; mettre HGA à jour.
8. **Auditer les comptes utilisateurs et les tokens de longue durée** de Home Assistant (Profil → Jetons d'accès) — révoquer ceux qui ne sont plus utilisés. *(Non vérifiable en lecture seule depuis les outils disponibles.)*

### Phase 3 — Durcir dans la durée (30 jours)

9. **Segmenter le réseau.** L'IoT (Tuya, Broadlink, TV Android, Xbox, Shelly, Marstek) partage le LAN `192.168.1.0/24` avec les postes de travail. Un VLAN IoT filtré réduirait fortement l'impact d'un objet compromis — c'est la mesure structurante la plus efficace au vu de C1 et C2.
10. **TLS sur MQTT** (ports 8883/8884 avec certificats) si le broker doit rester joignable sur le LAN.
11. **Revue des composants personnalisés** — voir section 9.
12. **Versionner `/config` dans Git** avec `secrets.yaml` en `.gitignore` : traçabilité des modifications et détection des dérives de configuration.

---

## 7. Optimisations de performance

| Priorité | Action | Gain attendu |
|---|---|---|
| **1** | Exclusions recorder sur les capteurs dérivés haute fréquence (H3) | Réduction estimée de 40 à 60 % de la croissance de la base |
| **2** | Migration du recorder vers PostgreSQL (add-on déjà installé) | Supprime le verrou mono-écrivain SQLite ; requêtes d'historique nettement plus rapides |
| **3** | Aplatir la chaîne de cartes v5→v20 et l'externaliser en fichier statique (M1) | −146,7 KB par chargement de dashboard, mise en cache navigateur restaurée |
| **4** | Factoriser les variables Jinja répétées en capteurs template (M5) | Évaluation unique au lieu de N ; variables devenues observables |
| **5** | Supprimer les 31 helpers du Routeur IA et les 4 lampes mortes (M2, M4) | −5 % d'entités dans le registre et le recorder |
| **6** | Signaler à l'amont le capteur Omnibattery à 0,726 s (L6) | Réduit la latence de la boucle d'événements |
| **7** | Désactiver l'intégration Xbox si peu utilisée (L5) | Supprime un coordinateur en échec récurrent |

**Point d'attention :** contrairement à ce que la cadence de 30 s pourrait laisser craindre, **les automatisations ne sont pas un problème de performance**. Les traces mesurées montrent des exécutions de 5 à 17 ms. L'optimisation doit porter sur le recorder et le frontend, pas sur la logique d'automatisation.

---

## 8. Améliorations de fiabilité

1. **Résoudre la boucle VACA (H2)** — priorité absolue, car elle conditionne la capacité à diagnostiquer tout le reste.
2. **Fiabiliser le lien Modbus de la batterie (H5)** — Ethernet si possible, bail statique, vérification de la couverture Wi-Fi.
3. **Stabiliser le réseau** après la migration vers le Huawei B525 : l'incident du 12/09 a simultanément affecté DNS, Wi-Fi et liaison montante.
4. **Superviser explicitement les composants critiques.** Créer des `binary_sensor` template et des notifications pour : indisponibilité prolongée de la batterie, du Shelly, ou du satellite vocal. Le modèle existe déjà et il est bon — `binary_sensor.energie_capteurs_critiques_valides` avec ses gardes de fraîcheur — il suffit de l'étendre.
5. **Définir le comportement de repli** en cas de perte prolongée de la batterie ou du compteur : aujourd'hui, les consignes gèlent, ce qui est implicite et non documenté.
6. **Sauvegardes hors site** (M9) — au moins deux destinations, dont une indépendante de Nabu Casa avant son expiration le 12/10.
7. **Tester une restauration** sur une instance de test.
8. **Augmenter la rétention des traces** (M5) — condition préalable à tout diagnostic sérieux.

---

## 9. Risques liés aux composants personnalisés

L'installation compte **8 intégrations custom** et **6 cartes Lovelace custom**. Home Assistant émet l'avertissement standard pour chacune :

> *« We found a custom integration X which has not been tested by Home Assistant. This component might cause stability problems »*

| Composant | Version | Popularité | Évaluation du risque |
|---|---|---|---|
| `tuya_local` | 2026.9.0 | 3 441 ★ | **Faible** — très mature, à jour |
| `hacs` | 2.0.5 | 7 707 ★ | **Faible** — standard de fait |
| `solcast_solar` | v4.6.1 | 450 ★ | **Faible** — maintenu activement |
| `omnibattery` | v1.4.0 | 133 ★ | **Moyen** — 2 bugs confirmés (L6) ; **pilote une batterie et des charges de forte puissance** |
| `home_generative_agent` | v3.39.4 | 298 ★ | **Élevé** — contournement de PIN confirmé (H1), 1 version de retard, accès LLM aux actions |
| `view_assist` | 2026.7.0 | 86 ★ | **Moyen** — faible base d'utilisateurs |
| `vaca` | v0.13.2 | 482 ★ | **Élevé** — boucle de reconnexion permanente (H2) |
| `local_openai` | 1.12.0 | 279 ★ | **Moyen** — actuellement en échec de chargement (M3) |
| `ha_mcp_tools` | v2.1.3 | 44 ★ | **Élevé** — **très faible base d'utilisateurs**, privilèges maximaux, exposé réseau (C1), `auto_update: true` |
| `mcp_proxy` | — | — | Détecté dans les logs, non listé dans HACS — **origine à clarifier** |

**Analyse.** Le risque se concentre sur trois composants : `ha_mcp_tools`, `home_generative_agent` et `vaca`.

`ha_mcp_tools` mérite une attention particulière : **44 étoiles GitHub** signifient une revue communautaire quasi inexistante, pour un composant qui expose la totalité du contrôle de Home Assistant sur le réseau, en mise à jour automatique. C'est la combinaison la moins favorable possible entre privilège, exposition et maturité. Cela ne signifie pas que le composant est malveillant — il est le canal de cet audit et fonctionne correctement — mais son profil de risque justifie le durcissement décrit en C1.

**Recommandations.**

1. Désactiver `auto_update` sur `ha_mcp_tools` et `home_generative_agent` ; revoir les notes de version avant chaque montée.
2. **Clarifier l'origine de `mcp_proxy`** : présent dans les logs de chargement mais absent de la liste HACS. Un composant non tracé dans `/config/custom_components` doit être identifié.
3. Remonter les bugs Omnibattery en amont (L6).
4. Systématiser la sauvegarde avant chaque mise à jour de composant custom — pratique **déjà en place** (`Avant_maj_OmniBattery_1.4.0`), à conserver.

---

## 10. Dette technique et refactorisations

| Élément | Nature | Effort | Priorité |
|---|---|---|---|
| Chaîne de cartes `omni-energy-flow-card` v5→v20 | 16 niveaux d'héritage, 138,3 KB inline, v7 morte | Élevé | **Haute** |
| `automation.solaire_p1_orchestration_30s` | 56 003 caractères, 14 déclencheurs, 30 branches | Élevé | **Haute** |
| Sous-système « Routeur IA » | 31 helpers + dashboard + 3 cartes, non fonctionnel | Faible | **Haute** |
| Variables Jinja dupliquées | `potentiel_export`, `autour_pic`, `belle_journee`, `confort_hiver_ok` recalculées à chaque déclenchement | Moyen | Moyenne |
| Descriptions-journaux | Historique et spécification mêlés, divergence code/doc | Faible | Moyenne |
| 48 capteurs template | Croissance organique, nommage hétérogène (`Écart…`, `Performance…`, `Rendement…`, `Taux…` pour des concepts proches) | Moyen | Moyenne |
| 4 lampes mortes + JARVIS | Entités fantômes dans le registre | Faible | Moyenne |
| Absence d'étages, helpers sans zone | Structure spatiale incomplète | Faible | Basse |
| `forecast_solar` en doublon de Solcast | Intégration redondante | Faible | Basse |
| Absence de versionnement de `/config` | Aucune traçabilité des modifications | Moyen | Moyenne |

**Observation sur le nommage des capteurs solaires.** L'inventaire compte **49 entités** correspondant à `solcast|solaire|simulation`. On y trouve des concepts très proches sous des noms différents : `Écart solaire OpenDTU Shelly`, `Écart relatif solaire OpenDTU Shelly`, `Écart solaire réel vs Solcast`, `Écart énergie solaire journalier`, `Écart prévision journée`, `Écart solaire cumulé actuel`, `Écart estimation fin de journée vs Solcast`, `Écart puissance solaire instantané kW`, `Écart estimation journée kWh` — neuf capteurs « Écart », auxquels s'ajoutent six « Performance » et trois « Rendement/Taux ». Une convention de nommage explicite (`solaire_ecart_<période>_<unité>`) et une revue de l'utilité réelle de chacun réduiraient significativement la charge cognitive.

---

## 11. Éléments obsolètes ou inutilisés

**Confirmés inutilisés (0 référence vérifiée) :**
- `sensor.shelly_reseau_rapide_mqtt`
- Ressource Lovelace `omni-energy-flow-card-v7`
- 20 des 31 helpers « Routeur IA » (`match_in_config: false`)

**Non fonctionnels :**
- `automation.ia_routeur_unique` (désactivée) + les 11 helpers restants du Routeur IA
- Dashboard `agents-ia` + 3 cartes Lovelace associées
- Intégration `google_generative_ai_conversation` (401) et ses 4 entités
- Intégration `local_openai` (config_flow introuvable) et son entité conversation
- `light.ampoule_1`, `light.ampoule_2`, `light.ampoule_3`, `light.lampe_placard`
- `media_player.bureau_2` (« JARVIS »)

**Sans objet sur ce matériel :**
- `rpi_power` (Raspberry Pi Power Supply Checker sur x86-64)
- Entrée Bluetooth Raspberry Pi `bcm43438`

**Probablement inutilisés (à confirmer) :**
- Add-on Grocy (arrêté)
- Intégration `forecast_solar` (si la comparaison avec Solcast n'est plus exploitée)
- Intégration Xbox (erreurs récurrentes)
- Zones `cuisine` et `bureau` (vides)
- 24 sauvegardes locales en version 2026.8.2 (~2 GB)

---

## 12. Plan d'action priorisé

### 🚨 Immédiat (aujourd'hui)

| # | Action | Référence |
|---|---|---|
| 1 | `webhook_auth` ≠ `none`, `bind_host` → `127.0.0.1` sur `ha_mcp_tools` | **C1** |
| 2 | Rotation du mot de passe MQTT + `password_pre_hashed: true` | **C2** |
| 3 | Sauvegarde complète **avec base**, copiée hors de la machine | **M9** |
| 4 | Abaisser le niveau de log de `custom_components.vaca.assist_satellite` | **H2** |
| 5 | Vérifier depuis le LAN que les ports 9584 et 1883 ne répondent plus | **C1, C2** |

### 📅 Sous 7 jours

| # | Action | Référence |
|---|---|---|
| 6 | Corriger la cause de la boucle VACA (veille Wi-Fi Android / signal) | **H2** |
| 7 | Décaler le `time_pattern` de l'orchestrateur (`seconds: 15,45`) | **H4** |
| 8 | Porter `stored_traces` à 50 sur les 3 automatisations énergie | **M5, L7** |
| 9 | Exclusions recorder sur les capteurs dérivés haute fréquence | **H3** |
| 10 | Mettre à jour Tailscale (0.30.0) puis HGA (v3.39.6) | **L1, H1** |
| 11 | Réactiver le repair `pin_bypassed_by_local_intents` et réduire l'exposition vocale | **H1** |
| 12 | Appliquer le repair HACS `local_openai` ; désinstaller si l'erreur persiste | **M3** |
| 13 | Fiabiliser le lien Modbus de la batterie (Ethernet / bail statique) | **H5** |
| 14 | File editor en `boot: manual` | **M6** |
| 15 | Supprimer `sensor.shelly_reseau_rapide_mqtt` et la carte v7 | **L3, M1** |
| 16 | Configurer un second agent de sauvegarde hors site | **M9** |

### 🗓️ Sous 30 jours

| # | Action | Référence |
|---|---|---|
| 17 | Trancher sur le Routeur IA : réparer l'authentification Google **ou** supprimer les 31 helpers, le dashboard et les 3 cartes | **M2** |
| 18 | Migrer le recorder vers PostgreSQL (add-on déjà en service) | **H3** |
| 19 | Aplatir la chaîne v5→v20 en une carte unique externalisée | **M1** |
| 20 | Scinder l'orchestrateur en 4 automatisations thématiques | **M5** |
| 21 | Rétablir l'arbitre unique de la climatisation (helper de demande) | **H4** |
| 22 | Nettoyer les entités mortes (4 lampes, JARVIS, `rpi_power`) | **M4** |
| 23 | Corriger le ciblage `area_id` → `entity_id` dans le blueprint bouton | **M7** |
| 24 | Créer les étages et rattacher les 7 zones ; traiter `cuisine` et `bureau` | **M8, L8** |
| 25 | Signaler les bugs Omnibattery en amont | **L6** |
| 26 | Renouveler ou remplacer l'abonnement Nabu Casa (expire le 12/10) | **Info** |
| 27 | Clarifier l'origine du composant `mcp_proxy` | **§9** |
| 28 | Purger les sauvegardes locales 2026.8.2 obsolètes | **M9** |

### 🎯 Long terme (3 à 6 mois)

| # | Action | Référence |
|---|---|---|
| 29 | **Segmenter le réseau en VLAN IoT** — mesure structurante la plus efficace | **§6** |
| 30 | Versionner `/config` dans Git (`secrets.yaml` exclu) | **M10** |
| 31 | Factoriser les variables Jinja en capteurs template partagés | **M5** |
| 32 | Convention de nommage unifiée pour les 49 entités solaires | **§10** |
| 33 | Revue annuelle des composants custom (maintenance amont, alternatives natives) | **§9** |
| 34 | TLS obligatoire sur MQTT (8883/8884) | **§6** |
| 35 | Tester une restauration complète sur instance de test | **M9** |
| 36 | Documenter l'architecture énergétique (schéma des flux, propriété des entités, comportements de repli) | **H4, H5** |

---

## 13. Limites de l'audit

Les éléments suivants **n'ont pas pu être vérifiés** avec les outils disponibles en lecture seule, et ne doivent pas être considérés comme conformes ou non conformes :

| Élément | Raison |
|---|---|
| Contenu de `configuration.yaml` et des fichiers inclus | Aucun accès au système de fichiers `/config` via le canal MCP |
| Présence et contenu de `secrets.yaml` | Idem |
| Configuration `http:` — `trusted_proxies`, `ip_ban_enabled`, `login_attempts_threshold`, `use_x_forwarded_for` | Non exposée par l'API |
| Configuration exacte du `recorder` — exclusions, `purge_keep_days`, `commit_interval` | Déduite de la volumétrie et de `oldest_recorder_run`, non lue directement |
| Permissions POSIX des fichiers | Aucun accès au système de fichiers |
| Comptes utilisateurs HA, jetons d'accès de longue durée, sessions actives | Non exposés en lecture seule |
| Règles de pare-feu de la box et redirections de ports (NAT) | Hors périmètre de l'instance |
| Configuration interne de Zigbee2MQTT (`/config/zigbee2mqtt/configuration.yaml`), clé réseau Zigbee, `permit_join` | Non exposée par l'API Supervisor |
| Topologie du réseau Zigbee (LQI, RSSI, routage) | `ZHA` désactivé, données Z2M non exposées via MCP |
| Contenu détaillé des 31 vues de dashboard | Non exploré exhaustivement (métadonnées et ressources seulement) |
| Configuration de l'add-on PostgreSQL (authentification, exposition réseau) | Non listée dans les options exposées |
| ACL du broker Mosquitto | Fichier `customize` inactif (`customize.active: false`) — pas d'ACL personnalisée détectée |

**Recommandation.** Un second passage avec accès au système de fichiers (via Terminal & SSH, en lecture seule) permettrait de lever ces réserves — en particulier sur `http: trusted_proxies`, la configuration du recorder et les ACL MQTT, qui sont les trois angles morts les plus significatifs de cet audit.

---

## 14. Synthèse finale

Cette installation est le fruit d'un travail d'ingénierie domotique sérieux. L'orchestration énergétique — arbitrage saisonnier, anti-court-cycle, hystérésis, gardes de fraîcheur des capteurs, marqueurs de contexte pour distinguer arrêt manuel et arrêt automatique, sauvegarde systématique avant modification — relève de pratiques que l'on rencontre rarement dans une installation résidentielle. Ces points méritent d'être soulignés autant que les défauts.

Les problèmes identifiés ne remettent pas en cause cette conception. Ils relèvent de trois causes distinctes :

1. **Des réglages de mise au point restés en production** — `bind_host: 0.0.0.0`, `webhook_auth: "none"`, mot de passe MQTT en clair. Ce sont les plus graves, et paradoxalement les plus rapides à corriger.
2. **Une croissance organique sans phase de consolidation** — la chaîne de 16 cartes, l'orchestrateur à 56 000 caractères, les 49 entités solaires, le Routeur IA abandonné en l'état.
3. **Un défaut d'observabilité qui masque tout le reste** — quand 99,7 % des logs proviennent d'un seul composant en boucle, plus rien d'autre n'est visible. C'est pourquoi la correction de H2 conditionne la valeur de toutes les autres.

**L'ordre recommandé est donc :** fermer les deux expositions réseau (C1, C2), restaurer la visibilité (H2), puis consolider (H3, H4, M1, M2, M5).

Avec les actions immédiates et à 7 jours, le score global passerait raisonnablement de **58/100 à environ 76/100**. Le plan à 30 jours, en traitant la dette structurelle, permettrait d'atteindre **85/100 et au-delà**.

---

*Audit réalisé en lecture seule le 12 septembre 2026. Aucune modification n'a été apportée à l'installation. Toutes les valeurs de secrets rencontrées ont été délibérément omises de ce rapport.*

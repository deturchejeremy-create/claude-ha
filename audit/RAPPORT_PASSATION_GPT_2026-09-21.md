# Rapport de passation — Installation Home Assistant « Maison »

**Destinataire :** assistant IA reprenant le dossier (ChatGPT / GPT), sans accès à l'historique de conversation précédent
**Émetteur :** Claude Code (audits du 12/09 et 21/09/2026, corrections du 21/09)
**Date :** 21 septembre 2026
**Propriétaire de l'installation :** Jérémy

> **Règle de confidentialité appliquée dans tout ce document :** aucune valeur de secret n'est reproduite (mots de passe, tokens, hash, salt, clés API, URL d'ingress). Les emplacements sont désignés précisément, jamais les valeurs. **Merci de maintenir cette règle.**

---

## 0. Comment lire ce document

Ce rapport est **auto-porteur** : il ne suppose aucune connaissance préalable du dossier. Il contient :

- §1–§2 : le contexte et l'inventaire complet de l'installation
- §3 : ce qui a déjà été fait (2 audits + corrections appliquées aujourd'hui)
- §4 : **les 3 chantiers critiques restants**, avec pour chacun la preuve, la procédure exacte, et **pourquoi ils n'ont pas pu être exécutés automatiquement**
- §5 : le reste du backlog, priorisé
- §6 : **les contraintes techniques à connaître impérativement avant d'agir** — plusieurs pièges peuvent provoquer une panne réelle
- §7 : commandes de vérification

**Si vous ne lisez qu'une section, lisez le §6.** Trois des actions recommandées peuvent couper l'accès à Home Assistant ou arrêter la gestion énergétique si elles sont exécutées sans précaution.

---

## 1. Contexte

Installation domotique résidentielle **avancée**, centrée sur l'autoconsommation photovoltaïque. Le propriétaire pilote lui-même ses configurations et a une bonne maîtrise technique. L'installation est fonctionnelle et globalement bien conçue — les problèmes relevés relèvent de la dette accumulée, pas d'erreurs de conception.

Deux audits complets ont été menés en lecture seule :

| Audit | Date | Score global | Fichier |
|---|---|---|---|
| Initial | 12/09/2026 | 58/100 | `audit/AUDIT_HOME_ASSISTANT_2026-09-12.md` |
| Suivi | 21/09/2026 | 55/100 | `audit/AUDIT_HOME_ASSISTANT_2026-09-21.md` |

Le score a **baissé malgré un vrai travail de fiabilisation** entre les deux dates : l'effort a porté sur la fiabilité fonctionnelle pendant que la dette de sécurité restait intacte et que la charge augmentait. C'est le constat central à garder en tête.

---

## 2. Inventaire de l'installation

### 2.1 Socle

| Élément | Valeur |
|---|---|
| Type | **Home Assistant OS** (Supervised, conteneurisé) |
| Core | **2026.9.2** |
| OS | Home Assistant OS 18.2 |
| Supervisor | 2026.09.2 |
| Docker / Python | 29.6.2 / 3.14.6 |
| Matériel | `generic-x86-64`, amd64, ~7,6 GiB RAM |
| Disque | 116,7 GB — 13,9 GB utilisés (12 %) |
| Config dir | `/config` |
| Fuseau / langue | Europe/Paris / fr |
| Dernier redémarrage | 16/09/2026 05:30 |

### 2.2 Réseau

| Interface | Adresse |
|---|---|
| `eno1` (LAN principal) | **192.168.1.74/24** + IPv6 publique |
| `tailscale0` (VPN) | 100.101.146.79/32 |
| `hassio` (add-ons) | 172.30.32.1/23 |
| `docker0` | 172.30.232.1/23 |

- **DNS** : 192.168.1.254 (box) — équipement **Huawei B525**, migration récente (09/09)
- **Accès externe** : Home Assistant Cloud (Nabu Casa), `remote_enabled`, région eu-central-1
- ⚠️ **Abonnement Nabu Casa expire le 12/10/2026** — dans 21 jours. C'est aussi la seule destination de sauvegarde hors site actuelle.
- **Google Assistant** activé (14 entités exposées), Alexa désactivé
- **Tailscale** : `share_homeassistant: "disabled"` — pas d'exposition Funnel sur Internet ✅
- Aucun reverse proxy tiers

### 2.3 Volumétrie

| Catégorie | Volume |
|---|---|
| Entités | **716** sur 39 domaines |
| Dont indisponibles/inconnues | **83 (11,6 %)** — dont 48 pour la tablette VACA hors ligne |
| Automatisations | **21** (20 actives, 1 désactivée) |
| Scripts / scènes | 5 / 1 |
| Helpers | ~143 |
| Dashboards | 8 (+ défaut), 31 vues, mode `storage` |
| Ressources Lovelace | 26, dont **19 inline (146,7 KB)** |
| Add-ons | 8 (7 démarrés, Grocy arrêté) |
| Dépôts HACS | 15 |
| Zones | 7, **aucun étage défini** |
| Sauvegardes | 36 |
| Base recorder | **SQLite, 1 547,84 MiB**, ~10 j de rétention |

### 2.4 Équipements et sous-systèmes

**Chaîne énergétique (cœur de l'installation) :**

| Rôle | Équipement | Adresse / intégration |
|---|---|---|
| Production PV | 2 micro-onduleurs Hoymiles via **OpenDTU** | `sensor.opendtu_528ecc_ac_power` |
| Bridage PV | — | `number.onduleur1_limit_nonpersistent_relative`, `number.onduler_2_limit_nonpersistent_relative` |
| Stockage | Batterie **Marstek Venus 1** | Modbus TCP **192.168.1.92:502**, intégration custom `omnibattery` v1.4.0 |
| Mesure réseau rapide | **Shelly Pro EM 50** + script embarqué « Grid power fast » → MQTT | **192.168.1.162** |
| Mesure réseau lente | Shelly Pro EM 50, intégration native | `sensor.shellyproem50_ece334f85344_energy_meter_0_puissance` |
| Comptage fournisseur | Add-on **Linky** 1.8.0 | — |
| Prévision solaire | **Solcast** v4.6.1 (utilisée) + `forecast_solar` (doublon quasi inutilisé) | — |
| Charges pilotées | Chauffe-eau (Tuya Local), clim **Airton** (IR via Broadlink RM4 Pro), machine à laver, lave-vaisselle, Airfryer, TV | — |

**Architecture de mesure réseau (mise en place entre le 17 et le 19/09) :**

```
Shelly Pro EM 50 (192.168.1.162)
  ├── script embarqué « Grid power fast » ──MQTT──> sensor.shelly_reseau_rapide_mqtt   (~2 s)
  └── intégration Shelly native ─────────────────> sensor.shellyproem50_..._puissance  (lent)
                                    │
                                    ▼
                    sensor.reseau_omnibattery_hybride
              (template, fraîcheur <5 s MQTT / <30 s Shelly)
                                    │
         ┌──────────────┬───────────┼────────────┬──────────────┐
         ▼              ▼           ▼            ▼              ▼
   arbitre         sécurité     alerte ×2   rafraîchissement  watchdog
   batterie      (0 W si non                forcé (/2 s)      script Shelly
                  numérique)
```

**Radio / protocoles :** Zigbee via **Zigbee2MQTT** 2.14.1-1 (dongle Sonoff ZB 3.0 USB Plus) · **MQTT** Mosquitto 7.1.1 · ZHA désactivé volontairement ✅ · **Pas de Z-Wave, Thread, Matter ni ESPHome**

**IA / assistants :** `home_generative_agent` v3.39.4 (agent principal, provider Gemini) · PostgreSQL+pgvector (embeddings) · View Assist + `vaca` (satellite vocal, **hors ligne**) · `ha_mcp_tools` v2.1.3 (serveur MCP)

### 2.5 Composants personnalisés et niveau de risque

| Composant | Installé | Disponible | ⭐ GitHub | Risque |
|---|---|---|---|---|
| `tuya_local` | 2026.9.1 | à jour | 3 475 | Faible |
| `hacs` | 2.0.5 | à jour | 7 732 | Faible |
| `solcast_solar` | v4.6.1 | à jour | 450 | Faible |
| `omnibattery` | v1.4.0 | à jour | 152 | Moyen — 2 bugs confirmés, non remontés |
| `home_generative_agent` | **v3.39.4** | **v3.42.0** | 304 | **Élevé** — 3 versions de retard, contournement de PIN actif |
| `view_assist` | 2026.7.0 | à jour | 87 | Moyen |
| `vaca` | **v0.13.2** | **v0.13.3** | 488 | **Élevé** — satellite hors ligne |
| `local_openai` | 1.12.0 | à jour | 282 | Moyen — non chargée (erreur `config_flow`) |
| `ha_mcp_tools` | **v2.1.3** | **v2.2.0** | **51** | **Élevé** — privilèges maximaux, très faible revue communautaire |
| `smartir` | ? | ? | — | **À clarifier** — absent de HACS |
| `mcp_proxy` | ? | ? | — | **À clarifier** — absent de HACS |

---

## 3. Ce qui a déjà été fait

### 3.1 Corrections appliquées par le propriétaire (12/09 → 21/09)

| Action | Effet |
|---|---|
| Refonte de la chaîne de mesure réseau | Capteur hybride double source + contrôle de fraîcheur + watchdog + repli 0 W + alertes — répond au point unique de défaillance identifié |
| Verrou `input_boolean.chauffe_eau_preparation_en_cours` | Coordination entre l'arbitre clim et l'orchestrateur solaire sur les **démarrages** |
| Mises à jour | HA Core 2026.9.1→2026.9.2 · Tailscale 0.29.0→0.30.0 · Terminal & SSH 10.4.0→10.5.0 · Tuya Local→2026.9.1 |
| Suppression des intégrations mortes | Google Generative AI et Cerebras retirées |
| Discipline de sauvegarde | Maintenue : une sauvegarde nommée et datée avant **chaque** modification |

### 3.2 Corrections appliquées par Claude Code le 21/09 (aujourd'hui)

Une sauvegarde a été créée **avant toute modification** :

```
backup_id : cf525952
nom       : Avant_corrections_critiques_audit_20260921
date      : 2026-09-21T13:24:03+02:00
taille    : 65 751 040 octets (config uniquement, sans base de données)
statut    : Backup completed successfully (6 s)
```

**Correction 1 — Race condition sur la climatisation (constat H4)**

*Problème :* deux automatisations en `mode: restart` se déclenchaient sur la **même seconde** (`time_pattern seconds: "/30"`) et commandaient toutes deux `climate.clim_airton`. Preuve mesurée le 12/09 : exécutions à `17:30:30.104` et `17:30:30.305`.

*Action :* le déclencheur de l'orchestrateur solaire a été décalé.

```python
# appliqué via python_transform sur automation.solaire_p1_orchestration_30s
config['triggers'][0] = {'id': 'controle', 'seconds': '15', 'trigger': 'time_pattern'}
config['triggers'].insert(1, {'id': 'controle', 'seconds': '45', 'trigger': 'time_pattern'})
```

L'`id` `controle` est conservé sur les deux déclencheurs : la logique de branchement par `condition: trigger` reste intacte.

*Vérification par traces d'exécution réelles :*

| Automatisation | Avant | Après |
|---|---|---|
| `clim_maintien_automatique_19degc` | :00 / :30 | **:00 / :30** (11:25:00, 11:25:30) |
| `solaire_p1_orchestration_30s` | **:00 / :30** ⚠️ | **:15 / :45** ✅ (11:25:15, 11:25:45) |

Séparation : **15 secondes**. Plus aucune collision.

**Correction 2 — Rétention de traces (constats N2 / L7)**

*Problème :* 5 traces conservées par défaut. Sur une automatisation déclenchée toutes les 30 s, cela représente **2 min 30 d'historique** ; sur celles à 2 s, **10 secondes**. Tout diagnostic était impossible.

*Action :* `config['trace'] = {'stored_traces': 50}` appliqué sur `solaire_p1_orchestration_30s` et `clim_maintien_automatique_19degc`.

*Vérification :* `total_available` observé à 8 et 6 et croissant, au-delà de l'ancien plafond de 5. ✅

**Hashes de configuration après modification** (utiles pour un verrouillage optimiste ultérieur) :

| Automatisation | Avant | Après |
|---|---|---|
| `solaire_p1_orchestration_30s` | `2b6293316bf793e8` | **`b5da5e0e1a5db5ae`** |
| `clim_maintien_automatique_19degc` | `11bd844880fa18bc` | **`923a650fd3c88d56`** |

**Rollback si nécessaire :** restaurer la sauvegarde `cf525952`, ou remettre `config['triggers'][0] = {'id': 'controle', 'seconds': '/30', 'trigger': 'time_pattern'}` et supprimer le second déclencheur.

---

## 4. Les 3 chantiers critiques restants

> Ces trois points **n'ont pas pu être exécutés automatiquement**. Pour chacun, la raison du blocage est technique et précise — ce n'est pas un oubli. Lisez le §6 avant d'agir.

---

### 🔴 CRITIQUE 1 — Serveur MCP exposé sur toutes les interfaces, webhook sans authentification

**Preuve.** Configuration de l'intégration `ha_mcp_tools` (entry_id `01M0MD68ZRDC0K5A7026PZDMNF`), **identique au caractère près entre le 12/09 et le 21/09** — `modified_at` inchangé, l'entrée n'a jamais été ouverte :

```yaml
bind_host: "0.0.0.0"       # écoute sur TOUTES les interfaces
server_port: 9584
enable_webhook: true
webhook_auth: "none"       # AUCUNE authentification
enable_llm_api: true
llm_api_exposure: "tool_search"
auto_update: true
```

**Impact.** Le serveur MCP expose le contrôle quasi total de Home Assistant : création/modification/suppression d'automatisations, appel de n'importe quel service, lecture de tous les états, accès aux diagnostics d'intégration, gestion des sauvegardes. Avec `bind_host: 0.0.0.0`, ce service est joignable depuis :

- tout appareil du LAN `192.168.1.0/24`, **y compris les objets connectés** (TV Android, Xbox, ampoules Tuya, décodeur Bbox, Shelly) — dont plusieurs sont des cibles classiques de compromission ;
- tout nœud du tailnet via `100.101.146.79` ;
- les réseaux Docker internes.

`webhook_auth: "none"` signifie qu'un webhook déclenchable **sans aucun credential** est actif.

**⚠️ Deux précisions de portée, à ne pas confondre :**

1. **`0.0.0.0` signifie « écoute sur toutes les interfaces de la machine », PAS « port ouvert sur Internet ».** La surface réelle est celle listée ci-dessus : LAN, tailnet, réseaux Docker. Aucune exposition Internet n'a été constatée — et elle n'est pas vérifiable depuis Home Assistant, les règles de pare-feu et de redirection de ports de la box étant hors périmètre (§6.2). Ne pas requalifier ce constat en « exposé sur Internet » sans preuve issue d'un scan externe.

2. **Tant que `webhook_auth` vaut `none`, l'URL complète du webhook est un secret de plein droit** — elle vaut credential à elle seule. Elle ne doit apparaître dans aucun rapport, message, ticket ou export. Elle ne figure nulle part dans ce document ni dans les deux audits : elle n'a jamais été récupérée (`webhook_id_override` est vide, donc l'identifiant est auto-généré). **Ne pas aller la chercher pour la documenter.**

**Élément contextuel.** Les logs enregistrent 2 tentatives de connexion échouées le 19/09 à 20:49 depuis une adresse IPv6 lien-local (donc un appareil **du LAN**, pas d'Internet), sur `/auth/login_flow/`, User-Agent Windows. Il s'agit très probablement d'une erreur de saisie domestique, **pas d'une attaque**. Mais cela illustre que des hôtes du LAN sollicitent l'interface d'authentification — alors que le port 9584, lui, n'en demande aucune.

**⚠️ POURQUOI CE N'A PAS ÉTÉ EXÉCUTÉ AUTOMATIQUEMENT.** Le serveur MCP `ha_mcp_tools` **est le canal par lequel un assistant IA pilote cette instance Home Assistant**. Toute modification de son entrée de configuration déclenche un rechargement de l'intégration, ce qui coupe la connexion en cours. Pire : si la connexion distante transite par ce port ou par le webhook non authentifié, passer `bind_host` à `127.0.0.1` ou activer l'authentification **supprime définitivement l'accès distant**, et il faut alors une intervention locale sur la machine pour le rétablir.

**➡️ TOPOLOGIE CONFIRMÉE PAR LE PROPRIÉTAIRE (21/09).**

> Connexion **historiquement configurée via le webhook Nabu Casa** — ni en direct sur le port 9584, ni via Tailscale. Le chemin exact emprunté aujourd'hui par le connecteur ChatGPT reste **à confirmer dans les paramètres du connecteur**.

Cohérent avec la sauvegarde `Nabu Casa - Webhook Proxy for HA MCP 3.0.1` (25/08). **Conséquence directe : `webhook_auth: "none"` est structurant pour l'accès distant actuel. Le basculer sèchement coupe l'accès.**

**➡️ SÉQUENCE VALIDÉE — à suivre dans cet ordre, sans raccourci.**

La règle est de **construire le nouveau chemin avant de démonter l'ancien**, ce qui supprime toute fenêtre de coupure. Ne pas inverser :

| Étape | Action | Critère de passage à l'étape suivante |
|---|---|---|
| 1 | **Ne rien modifier.** Conserver la configuration actuelle | — |
| 2 | Confirmer le chemin réellement utilisé par le connecteur ChatGPT dans ses paramètres | Chemin identifié |
| 3 | Configurer un **nouvel accès authentifié** en parallèle de l'existant | Nouvel accès créé, ancien toujours actif |
| 4 | **Tester le nouvel accès par une requête de lecture** (ex. `ha_get_overview`) | Lecture réussie |
| 5 | Basculer le connecteur sur le nouvel accès | Connecteur opérationnel sur le nouveau chemin |
| 6 | Vérifier qu'un **accès local de secours** fonctionne (LAN ou console) | Accès de secours confirmé |
| 7 | **Seulement alors** : désactiver ou renouveler l'ancien webhook, puis appliquer `bind_host` et `auto_update` | — |

**Réglage cible — à n'appliquer qu'à l'étape 7 :**

```yaml
bind_host: "127.0.0.1"     # ou l'adresse tailnet selon le cas
enable_webhook: false      # si le webhook n'est pas consommé
webhook_auth: "bearer"     # sinon, authentification obligatoire
auto_update: false         # un composant à ce niveau de privilège ne doit pas s'auto-mettre à jour
```

**Vérification après application**, depuis un autre poste du LAN :
```bash
curl -m 3 http://192.168.1.74:9584/     # doit échouer : connexion refusée
```

---

### 🔴 CRITIQUE 2 — Identifiants MQTT en clair, broker exposé sur le LAN

**Preuve.** Options de l'add-on `core_mosquitto`, inchangées entre le 12/09 et le 21/09 :

```yaml
logins:
  - username: jeremy
    password: "<valeur en clair — NE PAS REPRODUIRE>"
require_certificate: false
```

Mapping réseau (ports hôte) :
```json
"network": { "1883/tcp": 1883, "1884/tcp": 1884, "8883/tcp": 8883, "8884/tcp": 8884 }
```

**Impact — trois problèmes cumulés :**

1. **Secret en clair.** Le mot de passe est stocké non haché, alors que l'option `password_pre_hashed: true` existe précisément pour l'éviter (visible dans le schéma de l'add-on).
2. **Propagation.** Les **36 sauvegardes** embarquent la configuration des add-ons. Elles sont chiffrées (`protected: true`), mais **35 sur 36 sont sur le disque de la machine elle-même**.
3. **Exposition LAN sans TLS obligatoire.** Le broker est joignable sur `192.168.1.74:1883` depuis tout le réseau local, avec un simple couple identifiant/mot de passe.

**⚠️ AGGRAVATION IMPORTANTE ENTRE LES DEUX AUDITS.** Au 12/09, `sensor.shelly_reseau_rapide_mqtt` était un capteur **orphelin**, indisponible et sans aucune référence. Aujourd'hui, il alimente `sensor.reseau_omnibattery_hybride`, dont dépendent **cinq automatisations**, dont l'arbitre batterie et le repli de sécurité.

**Conséquence : un accès non autorisé au broker permet désormais d'injecter de fausses mesures de puissance réseau et, par ce biais, d'influencer directement les commandes de charge et de décharge de la batterie.** Le risque de ce constat a matériellement augmenté sans qu'une ligne de configuration ait changé.

**⚠️ POURQUOI CE N'A PAS ÉTÉ EXÉCUTÉ AUTOMATIQUEMENT — DANGER RÉEL.**

Le mot de passe MQTT est utilisé par **quatre consommateurs**, dont un est hors de portée de Home Assistant :

| Consommateur | Accessible depuis HA ? |
|---|---|
| Intégration MQTT de HA | ✅ oui |
| Add-on Zigbee2MQTT | ✅ oui (options de l'add-on) |
| Add-on Mosquitto lui-même | ✅ oui |
| **Script embarqué « Grid power fast » dans le Shelly Pro EM 50 (192.168.1.162)** | ❌ **NON — il réside sur l'appareil** |

**Si le mot de passe est changé sans mettre à jour le script du Shelly :**
`sensor.shelly_reseau_rapide_mqtt` cesse de publier → `sensor.reseau_omnibattery_hybride` devient indisponible → l'automatisation `energie_securite_omnibattery_sans_mesure_reseau` (déclenchée toutes les 10 s) force `number.omnibattery_system_max_charge_power` **et** `number.omnibattery_system_max_discharge_power` **à 0 W** → **la gestion énergétique s'arrête complètement.**

C'est un arrêt de production réel, pas une dégradation cosmétique.

**Procédure correcte, dans cet ordre strict :**

1. **Générer un hash** depuis un terminal dans le conteneur Mosquitto :
   ```bash
   pw -p '<nouveau_mot_de_passe>'
   ```
2. **Mettre à jour le script du Shelly EN PREMIER** — interface web `http://192.168.1.162`, onglet Scripts, script « Grid power fast ». Modifier les identifiants MQTT et redémarrer le script.
3. **Mettre à jour Zigbee2MQTT** — options de l'add-on, section `mqtt`.
4. **Mettre à jour l'intégration MQTT** de Home Assistant.
5. **En dernier, mettre à jour Mosquitto** :
   ```yaml
   logins:
     - username: jeremy
       password: "<sortie hachée de la commande pw>"
       password_pre_hashed: true
   ```
6. Redémarrer Mosquitto, puis vérifier :
   ```
   sensor.shelly_reseau_rapide_mqtt      → doit être numérique
   sensor.reseau_omnibattery_hybride     → doit être numérique
   number.omnibattery_system_max_discharge_power → doit être > 0
   ```

**Alternative plus propre à proposer :** l'add-on Mosquitto sait authentifier contre les comptes Home Assistant sans `logins` local (voir sa documentation). Créer un utilisateur HA dédié supprime le secret en clair à la racine.

**Durcissement complémentaire :** supprimer le mapping des ports hôte si aucun client MQTT externe au Supervisor n'en a besoin — Zigbee2MQTT et HA joignent le broker par le réseau interne `hassio` (172.30.33.0). ⚠️ **Vérifier d'abord que le Shelly n'a pas besoin du port hôte** : il publie depuis le LAN, donc il en a très probablement besoin. Dans ce cas, conserver le mapping de 1883 et envisager plutôt le TLS (8883).

---

### 🔴 CRITIQUE 3 — Base de données sans exclusions : +49 % en 9 jours

**Preuve.** Croissance mesurée :

| Date | Taille | Rétention | Rythme |
|---|---|---|---|
| 12/09 | 1 038,90 MiB | 9 j | ≈115 MiB/j |
| 21/09 | **1 547,84 MiB** | 10 j | **≈155 MiB/j** |

Moteur : **SQLite** 3.53.2.

Volumétrie mesurée sur 1 heure (21/09, 10:12→11:12 UTC) :

| Entité | Changements / h | Par jour |
|---|---|---|
| `sensor.reseau_omnibattery_hybride` | **1 766** | **42 384** |
| `sensor.shelly_reseau_rapide_mqtt` | **1 766** | **42 384** |
| `sensor.reseau_lisse_30_s` | 389 | 9 336 |

**Impact.** Deux capteurs produisent ~85 000 lignes par jour. `sensor.reseau_omnibattery_hybride` est un **template dérivé**, doublon exact de la source MQTT (mêmes valeurs, mêmes horodatages à 5 ms près — vérifié dans l'historique). Son archivage n'apporte rien : il est intégralement reconstructible.

SQLite est mono-écrivain : à ce volume, les requêtes d'historique se dégradent et la purge nocturne s'allonge.

**⚠️ POURQUOI CE N'A PAS ÉTÉ EXÉCUTÉ AUTOMATIQUEMENT.** La configuration du `recorder` réside dans `configuration.yaml`. **Le serveur MCP `ha_mcp_tools` n'expose aucun outil d'édition de fichier ni d'édition YAML managée** (vérifié par recherche dans le catalogue d'outils). Il faut passer par l'add-on **File editor** (installé, démarré) ou **Terminal & SSH** (installé, en ingress).

**Procédure — à appliquer dans `configuration.yaml` :**

```yaml
recorder:
  purge_keep_days: 10
  commit_interval: 5
  exclude:
    entities:
      - sensor.reseau_omnibattery_hybride    # template dérivé, doublon exact du MQTT
      - sensor.shelly_reseau_rapide_mqtt     # 42 384 chg/jour, usage temps réel uniquement
      - sensor.reseau_lisse_30_s             # moyenne mobile déjà agrégée
      - input_text.energie_decision_arbitre
      - input_text.energie_activite_automatique
      - sensor.omnibattery_daily_operation_timeline
    entity_globs:
      - sensor.onduleur1_*_tx_*              # statistiques radio Hoymiles
      - sensor.onduler_2_*_tx_*
    domains:
      - update
```

**⚠️ Vérification obligatoire avant application.** L'exclusion recorder **n'affecte pas** la disponibilité des entités pour les automatisations — elles continuent de fonctionner normalement. En revanche, **vérifier qu'aucun capteur exclu ne porte un `state_class`** alimentant le tableau de bord Énergie (`measurement`, `total`, `total_increasing`). Les trois capteurs réseau listés ci-dessus sont des mesures instantanées dérivées et ne devraient pas en porter — **à confirmer entité par entité** avant d'appliquer.

Après modification : valider avec **Développeur → YAML → Vérifier la configuration**, puis redémarrer.

**Gain attendu : 50 à 60 % de la croissance quotidienne.**

**Solution de fond recommandée.** L'add-on **PostgreSQL avec pgvector est déjà installé et démarré** (il sert les embeddings de l'agent IA). Y basculer le recorder supprime la contrainte mono-écrivain de SQLite :
```yaml
recorder:
  db_url: !secret recorder_db_url    # postgresql://...
```
⚠️ L'historique **n'est pas migré automatiquement**. Faire une sauvegarde complète **avec base** avant.

---

## 5. Backlog restant, priorisé

### Sous 7 jours

| # | Action | Constat | Note |
|---|---|---|---|
| 1 | Mettre à jour **HA-MCP 2.1.3 → 2.2.0** via HACS (débloque le serveur 8.5.0) | N6 | ⚠️ Coupe la connexion MCP le temps du rechargement. À faire en même temps que CRITIQUE 1 — même interface |
| 2 | Mettre à jour **HGA v3.39.4 → v3.42.0** | H1 | 3 versions de retard. Peut contenir le correctif du contournement de PIN. Lire les notes de version |
| 3 | **Second agent de sauvegarde hors site** | M9 | ⚠️ **Avant le 12/10** (expiration Nabu Casa). 35 sauvegardes sur 36 sont sur le disque de la machine ; 3 sur 36 contiennent la base |
| 4 | Réactiver le suivi des **3 repairs ignorés** | H1, N6 | Les 3 repairs actifs sont tous mis en sourdine. Le mécanisme de diagnostic est neutralisé |
| 5 | Diagnostiquer la **tablette VACA** (48 entités mortes) | N5 | Si abandonnée : supprimer l'entrée → −6,7 % du registre |
| 6 | Rendre **persistante** la config `logger:` pour VACA | N5 | Voir §5.1 |
| 7 | Corriger la **référence Android TV** | N4 | Voir §5.2 |
| 8 | Supprimer l'**alerte dupliquée** | N3 | `automation.energie_alerte_mesure_reseau_omnibattery_indisponible` fait doublon avec la V2.3 |
| 9 | **Compteur d'échecs** sur le watchdog Shelly | H5 | `shelly_garde_flux_reseau_mqtt_rapide` relance sans plafond — risque de boucle |

### Sous 30 jours

| # | Action | Constat |
|---|---|---|
| 10 | Migrer le recorder vers **PostgreSQL** | CRITIQUE 3 |
| 11 | Remplacer le rafraîchissement forcé `/2 s` par un **trigger-based template sensor** | N2 |
| 12 | Étendre le verrou de coordination aux **arrêts** de climatisation | H4 (reste) |
| 13 | Trancher sur le **Routeur IA** : réparer ou supprimer (31 helpers + dashboard + 3 cartes) | M2 |
| 14 | **Aplatir la chaîne de 16 cartes** Lovelace v5→v20 | M1 |
| 15 | **Scinder l'orchestrateur** (36 branches, 65 987 caractères) en 4 automatisations | M5 |
| 16 | Fiabiliser la **liaison Modbus** de la batterie (Ethernet / bail statique) | H5 |
| 17 | Nettoyer les **entités mortes** (4 lampes, JARVIS, `local_openai`, `rpi_power`) | M3, M4 |
| 18 | Corriger le ciblage `area_id` → `entity_id` du **blueprint bouton** | M7 |
| 19 | Créer les **étages**, rattacher les 7 zones, traiter `cuisine` et `bureau` (vides) | M8 |
| 20 | Remonter les **bugs Omnibattery** en amont | L6 |
| 21 | **Clarifier l'origine** de `smartir` et `mcp_proxy` (absents de HACS) | §9 audit |

### Long terme

**Segmenter le réseau en VLAN IoT** — c'est la mesure structurante la plus efficace au vu des CRITIQUE 1 et 2 · Versionner `/config` dans Git (`secrets.yaml` exclu) · TLS obligatoire sur MQTT · Tester une restauration complète · Documenter l'architecture énergétique

### 5.1 Détail — config `logger:` persistante

Le satellite VACA générait 99,7 % des logs (1 981 messages en 3 h). Un abaissement de niveau a été appliqué en runtime le 12/09, mais **perdu au redémarrage du 16/09**. Actuellement les messages ne réapparaissent pas — non parce que c'est corrigé, mais parce que **le satellite est entièrement hors ligne**. Si la tablette revient, la boucle reprendra.

```yaml
# configuration.yaml
logger:
  default: warning
  logs:
    custom_components.vaca.assist_satellite: error
```

### 5.2 Détail — référence Android TV cassée

L'appareil a changé d'IP (192.168.1.44 → **192.168.1.45**, visible dans les erreurs Chromecast du 21/09), mais l'`entity_id` contient l'ancienne IP :

- `media_player.android_tv_192_168_1_44` → **`unavailable`**
- `remote.android_tv_192_168_1_44` → **`unavailable`**
- Consommateurs : `automation.bbox_memorise_chaine_via_adb` **et** `script.preparer_tele` (ce dernier est exposé à Google Assistant)
- Logs : `Referenced entities media_player.android_tv_192_168_1_44 are missing` — 8 occurrences

L'automatisation interroge cette entité **toutes les 30 secondes** : elle échoue silencieusement ~2 880 fois par jour, masquée par `continue_on_error: true`.

**Correction :** ré-appairer sur la nouvelle IP, **renommer l'entité sans l'IP** (`media_player.android_tv_salon`), réserver un bail DHCP statique, puis mettre à jour les deux consommateurs. Le nommage par IP est la cause racine.

---

## 6. ⚠️ Contraintes techniques impératives

**À lire avant toute action sur cette installation.**

### 6.1 Trois actions peuvent provoquer une panne réelle

| Action | Conséquence si mal exécutée |
|---|---|
| Changer `bind_host` ou `webhook_auth` du serveur MCP | **Perte définitive de l'accès distant** — intervention locale nécessaire pour rétablir |
| Changer le mot de passe MQTT sans mettre à jour le script du Shelly | **Arrêt complet de la gestion énergétique** (batterie forcée à 0 W en 10 s) |
| Mettre à jour le composant HA-MCP | Coupe la connexion MCP pendant le rechargement |

### 6.2 Ce qui n'est PAS accessible depuis le serveur MCP Home Assistant

| Élément | Conséquence |
|---|---|
| `configuration.yaml`, includes, `secrets.yaml` | **Aucun outil d'édition YAML managée** — passer par File editor ou Terminal & SSH |
| Système de fichiers `/config` | Permissions, contenu des fichiers, origine de `smartir` / `mcp_proxy` |
| Configuration `http:` | **`trusted_proxies`, `ip_ban_enabled`, `login_attempts_threshold` non vérifiés** — angle mort de sécurité |
| Config exacte du `recorder` | Déduite de la volumétrie, non lue directement |
| Comptes utilisateurs, jetons de longue durée, sessions | Non exposés |
| Script embarqué du Shelly | Réside sur l'appareil (192.168.1.162) |
| Type de liaison de la batterie Marstek (Ethernet / Wi-Fi) | Empêche de conclure sur la fiabilisation Modbus |
| Config interne Zigbee2MQTT, clé réseau Zigbee | Non exposée par l'API Supervisor |
| Règles de pare-feu et NAT de la box | Hors périmètre |

**Recommandation :** un passage avec accès au système de fichiers (Terminal & SSH, en lecture seule) lèverait la plupart de ces réserves — en priorité `http: trusted_proxies`, la config du recorder et les ACL MQTT.

### 6.3 Bonnes pratiques à respecter sur cette installation

1. **Toujours sauvegarder avant modification.** Le propriétaire a cette discipline, avec un nommage explicite et daté (`Avant_securisation_mesure_OmniBattery_20260919`). La maintenir.
2. **Utiliser le verrouillage optimiste** (`config_hash`) sur les éditions d'automatisation.
3. **Préférer les constructions natives aux templates Jinja** dans les positions `condition:` et `trigger:` — les templates échouent silencieusement à l'exécution. L'installation contient déjà beaucoup de templates en position de condition (dette connue, constat M5).
4. **Ne jamais utiliser `device_id`** dans les automatisations — préférer `entity_id`.
5. **Vérifier les références croisées avant tout renommage ou suppression** d'entité.
6. **Ne jamais reproduire une valeur de secret** dans un rapport ou un message. Sont à traiter comme des secrets, au-delà des mots de passe et tokens : **l'URL complète du webhook MCP tant que `webhook_auth` vaut `none`** (elle vaut credential à elle seule), l'URL publique Nabu Casa de l'instance, l'`instance_id`, l'empreinte du certificat, et les URL d'ingress des add-ons. Aucun de ces éléments ne figure dans ce document ni dans les deux audits — vérifié par recherche. Ne pas les y ajouter.
7. **Ne pas requalifier un constat au-delà de la preuve.** Exemple concret : `bind_host: 0.0.0.0` établit une exposition LAN/tailnet/Docker, pas une exposition Internet — laquelle n'est pas vérifiable depuis Home Assistant.

### 6.4 Points forts à préserver

L'installation est **bien conçue** sur plusieurs plans, et ces acquis ne doivent pas être cassés :

- `binary_sensor.energie_capteurs_critiques_valides` — garde de fraîcheur bien pensée (<120 s sur le compteur, <43 200 s sur la température, exemption solaire la nuit)
- `timer.clim_arret_automatique_contexte` — marqueur de 10 s distinguant un arrêt automatique d'un arrêt manuel utilisateur
- Anti-court-cycle 15 min sur la climatisation
- Alertes explicitement découplées de la logique de régulation
- ZHA désactivé proprement au profit de Zigbee2MQTT
- Tailscale sans exposition Funnel

---

## 7. Commandes de vérification

**État général :**
```
ha_get_overview(detail_level="minimal")
ha_get_system_health(include="repairs")
```

**Chaîne énergétique — santé :**
```
sensor.reseau_omnibattery_hybride              → doit être numérique
sensor.shelly_reseau_rapide_mqtt               → doit être numérique, âge < 5 s
switch.domotique_shelly_domo_grid_power_fast   → doit être "on"
number.omnibattery_system_max_discharge_power  → > 0 en fonctionnement normal
number.omnibattery_system_max_charge_power     → > 0 en fonctionnement normal
binary_sensor.energie_capteurs_critiques_valides → "on"
```

**Valeurs de référence relevées le 21/09 à 13:12 (installation saine) :**
```
HYBRIDE = 156.9 W       MQTT_RAPIDE = 156.9 W      âge MQTT = 1,8 s
SHELLY_LENT = 137.1 W   SCRIPT_SHELLY = on         COMPENSATION = off
MAX_DECHARGE = 2000 W   MAX_CHARGE = 1800 W
omnibattery : batteries_connected 1/1, suspended 0, non_responsive 0
```

**Non-régression de la correction H4 (race condition) :**
```
ha_get_automation_traces("automation.solaire_p1_orchestration_30s")
  → doit se déclencher à :15 et :45
ha_get_automation_traces("automation.clim_maintien_automatique_19degc")
  → doit se déclencher à :00 et :30
```

**Croissance de la base :**
```
ha_get_system_health()  →  recorder.estimated_db_size
Référence 21/09 : 1 547,84 MiB. Après exclusions, la croissance doit tomber sous ~70 MiB/jour.
```

---

## 8. Synthèse pour reprise

**En une phrase :** installation domotique avancée et bien conçue, dont la gestion énergétique a été correctement fiabilisée, mais qui porte **deux expositions réseau non traitées depuis au moins 9 jours** et une base de données qui croît de ~155 MiB par jour sans aucune exclusion.

**Fait aujourd'hui :** sauvegarde `cf525952` · race condition climatisation corrigée et vérifiée · rétention de traces portée de 5 à 50.

**À faire en priorité, dans cet ordre :**

1. **CRITIQUE 1** — serveur MCP : topologie **confirmée** (webhook Nabu Casa). Suivre la séquence validée en 7 étapes du §4 — **construire et tester le nouvel accès authentifié avant de démonter l'ancien**. Ne rien modifier tant que l'étape 4 (test de lecture réussi) n'est pas franchie
2. **CRITIQUE 2** — MQTT : suivre l'ordre strict en 6 étapes, **le Shelly en premier**
3. **CRITIQUE 3** — exclusions recorder via File editor ou SSH, après vérification des `state_class`
4. Second agent de sauvegarde **avant le 12/10** (expiration Nabu Casa)

**Estimation d'effort :** les trois chantiers critiques représentent environ 45 minutes de travail effectif, hors temps de vérification. Une fois traités, le score d'audit passerait raisonnablement de **55/100 à ~68/100**.

**Ce qu'il ne faut surtout pas faire :** changer le mot de passe MQTT sans commencer par le Shelly · basculer `webhook_auth` avant qu'un nouvel accès authentifié ait été créé **et testé par une requête de lecture** · documenter ou transmettre l'URL du webhook · supprimer `sensor.shelly_reseau_rapide_mqtt` (une recommandation de suppression figurait dans l'audit du 12/09, elle est **caduque** — ce capteur est devenu central).

**Note de traçabilité.** Aucune configuration ni aucun identifiant n'a été modifié lors de la vérification de topologie du 21/09. Les seules écritures effectuées sur l'installation à cette date sont les deux corrections documentées au §3.2 (décalage du déclencheur de l'orchestrateur, rétention de traces), précédées de la sauvegarde `cf525952`.

---

*Rapport établi le 21 septembre 2026. Les deux audits complets référencés en §1 contiennent le détail de chaque constat (preuve, impact, cause probable, remédiation, exemple de correction). Aucune valeur de secret n'est reproduite dans ce document ni dans les audits.*

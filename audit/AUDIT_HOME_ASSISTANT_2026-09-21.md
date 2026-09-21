# Audit Home Assistant — Installation « Maison »

**Date de l'audit :** 21 septembre 2026
**Audit précédent :** 12 septembre 2026 (`AUDIT_HOME_ASSISTANT_2026-09-12.md`) — utilisé comme référence de comparaison
**Périmètre :** instance Home Assistant accessible via le serveur MCP `Home_assistant`
**Mode :** strictement lecture seule — aucune modification, suppression, redémarrage ou reconfiguration
**Auditeur :** Claude Code (architecture HA / cybersécurité / DevOps-SRE / revue de code)

> **Confidentialité :** aucune valeur de secret (mot de passe, token, hash, salt, clé API, URL d'ingress) n'est reproduite. Les emplacements sont désignés, jamais les valeurs.

---

## 1. Résumé exécutif

Neuf jours se sont écoulés depuis le premier audit. Le bilan est **contrasté, et le contraste est lui-même le constat principal.**

**Ce qui a réellement progressé.** Un travail de fiabilisation sérieux a été mené sur la chaîne de mesure réseau — exactement le point faible identifié comme **H5 (SPOF Modbus)**. Six nouvelles automatisations ont été créées autour d'un capteur hybride `sensor.reseau_omnibattery_hybride` avec contrôle de fraîcheur, un watchdog du script embarqué Shelly, un repli de sécurité à 0 W et un système d'alertes indépendant. La conception est bonne : vérification `last_reported`, alertes découplées de la logique de régulation, sauvegarde avant chaque étape. **L'observabilité a été restaurée** : là où 99,7 % des logs venaient d'un seul composant, on distingue aujourd'hui **118 problèmes distincts sur 24 composants**. Un verrou de coordination (`input_boolean.chauffe_eau_preparation_en_cours`) a été introduit entre l'arbitre climatisation et l'orchestrateur solaire — c'est précisément le correctif de fond recommandé pour **H4**.

**Ce qui n'a pas bougé.** Les **deux constats Critical sont intacts, au caractère près.** Le serveur MCP écoute toujours sur `0.0.0.0:9584` avec `webhook_auth: "none"` et `auto_update: true` — la date de modification de l'entrée de configuration est inchangée, elle n'a pas été ouverte. Le mot de passe MQTT est toujours en clair, avec le même contenu, et les quatre ports du broker restent mappés sur l'hôte. Le contournement de PIN de l'agent IA **(H1)** est toujours ignoré, et l'intégration a pris trois versions de retard (v3.39.4 contre v3.42.0 disponible).

**Ce qui s'est dégradé.** Le travail de fiabilisation a eu un coût mesurable qui n'a pas été compensé :

- **La base de données a grossi de 49 %** en 9 jours (1 038,90 → 1 547,84 MiB), et son rythme de croissance a lui-même augmenté de ~35 % (≈115 → ≈155 MiB/jour). Les deux nouveaux capteurs rapides produisent **42 384 changements d'état par jour chacun**. Aucune exclusion recorder n'a été mise en place.
- **Trois nouvelles automatisations tournent en permanence** à 2 s, 2 s et 10 s d'intervalle, soit ~95 000 exécutions supplémentaires par jour.
- **Les entités indisponibles ont plus que doublé** : 39 → **83 sur 716** (11,6 %), dont 48 pour la seule tablette VACA, totalement hors ligne.
- **L'orchestrateur a encore grossi** : 56 003 → 65 987 caractères (+18 %), 30 → 36 branches.

**Score global : 55 / 100** (contre 58 le 12/09).

Le score baisse alors que du bon travail a été fait. C'est le message central de cet audit : **l'effort s'est porté sur la fiabilité fonctionnelle, pendant que la dette de sécurité restait intacte et que la dette de performance s'aggravait.** La chaîne énergétique est aujourd'hui plus robuste face à une panne de capteur ; l'installation est tout aussi exposée sur le réseau, et sensiblement plus lourde.

---

## 2. Tableau de bord comparatif

| Indicateur | 12/09/2026 | 21/09/2026 | Évolution |
|---|---|---|---|
| HA Core | 2026.9.1 | **2026.9.2** | ✅ à jour |
| Supervisor | 2026.09.0 | 2026.09.2 | ✅ |
| Entités totales | 702 | **716** | +14 |
| Automatisations | 15 | **21** | **+6** |
| Entités indisponibles/inconnues | 39 (5,6 %) | **83 (11,6 %)** | 🔴 **+113 %** |
| Base recorder | 1 038,90 MiB | **1 547,84 MiB** | 🔴 **+49 %** |
| Croissance quotidienne DB | ≈115 MiB/j | **≈155 MiB/j** | 🔴 +35 % |
| Disque utilisé | 13,2 GB | 13,9 GB | +0,7 GB |
| Orchestrateur solaire | 56 003 car. / 30 branches | **65 987 car. / 36 branches** | 🔴 +18 % |
| Ressources Lovelace inline | 19 (146,7 KB) | **19 (146,7 KB)** | ⏸️ inchangé |
| Sauvegardes | 30 | **35** | +5 |
| Problèmes distincts visibles dans les logs | 5 | **118** | ✅ observabilité restaurée |
| Composants distincts en erreur | 4 | 24 | ✅ (effet du même gain) |
| Repairs actifs | 3 (2 ignorés) | 3 (**3 ignorés**) | 🔴 |
| `bind_host` MCP | `0.0.0.0` | **`0.0.0.0`** | 🔴 inchangé |
| `webhook_auth` MCP | `none` | **`none`** | 🔴 inchangé |
| Mot de passe MQTT | en clair | **en clair** | 🔴 inchangé |

### État des 25 constats du 12/09

| Statut | Nombre | Constats |
|---|---|---|
| ✅ **Corrigé** | 4 | L1 (Tailscale 0.30.0), L3 (capteur orphelin — devenu central), une partie de M2/M4 (intégrations Google AI et Cerebras supprimées), H2 (boucle de logs éteinte) |
| 🟡 **Partiellement corrigé** | 3 | H4 (verrou de coordination créé, simultanéité /30 maintenue), H5 (filet de sécurité ajouté, lien Modbus non fiabilisé), M9 (sauvegardes plus récentes, toujours 1 seule copie hors site) |
| 🔴 **Non corrigé** | 16 | **C1, C2, H1, H3**, M1, M2 (reste), M3, M5 (aggravé), M6, M7, M8, M10, L2, L4, L5, L6, L7, L8 |
| 🆕 **Nouveau** | 6 | N1 à N6 (voir §5) |

---

## 3. Cartographie de l'architecture (état au 21/09)

### 3.1 Socle système

| Élément | Valeur |
|---|---|
| Type | **Home Assistant OS** (Supervised) |
| Core | **2026.9.2** |
| OS | Home Assistant OS 18.2 |
| Supervisor | 2026.09.2 |
| Docker / Python | 29.6.2 / 3.14.6 |
| Matériel | `generic-x86-64`, amd64, ~7,6 GiB RAM |
| Disque | 116,7 GB — 13,9 GB utilisés (12 %) |
| État | `RUNNING`, `healthy`, `supported`, NTP synchronisé |
| Dernier redémarrage HA | **16/09/2026 05:30** (mise à jour Core + Tuya) |

### 3.2 Réseau et accès externe

Inchangé par rapport au 12/09 : `eno1` 192.168.1.74/24, `tailscale0` 100.101.146.79, réseaux internes `hassio` 172.30.32.1/23 et `docker0` 172.30.232.1/23. Une interface `veth` supplémentaire (16 contre 15).

- **Nabu Casa** : `remote_enabled`, connecté, région eu-central-1. Certificat valide jusqu'au 14/11/2026. **Abonnement expirant le 12/10/2026 — dans 21 jours.**
- **Google Assistant** activé, Alexa désactivé.
- **Tailscale** : `share_homeassistant: "disabled"` — pas d'exposition Funnel. Add-on mis à jour en 0.30.0.
- Aucun reverse proxy tiers.

### 3.3 Inventaire

| Catégorie | Volume |
|---|---|
| Entités | **716** sur 39 domaines |
| Automatisations | **21** (20 actives, 1 désactivée) |
| Scripts / scènes | 5 / 1 |
| Dashboards | 8 (+ défaut), 31 vues, mode `storage` |
| Ressources Lovelace | 26 (dont **19 inline**) |
| Add-ons | 8 (7 démarrés, Grocy arrêté) |
| Dépôts HACS | 15 |
| Zones | 7, **toujours aucun étage** |
| Sauvegardes | **35** |

**Domaines principaux :** `sensor` 331 · `number` 63 · `switch` 61 · `select` 33 · `update` 29 · `binary_sensor` 28 · `input_number` 25 · `automation` 21 · `input_text` 16 · `button` 14

### 3.4 La nouvelle chaîne de mesure réseau

C'est le changement structurel majeur de la période. Architecture désormais en place :

```
Shelly Pro EM 50 (192.168.1.162)
  ├── script embarqué « Grid power fast »  → MQTT
  │     └── sensor.shelly_reseau_rapide_mqtt      (≈2 s, 42 384 chg/jour)
  └── intégration Shelly native
        └── sensor.shellyproem50_..._puissance    (repli lent)
                    │
                    ▼
        sensor.reseau_omnibattery_hybride
        (template, fraîcheur <5 s MQTT / <30 s Shelly)
                    │
     ┌──────────────┼──────────────┬──────────────┐
     ▼              ▼              ▼              ▼
  arbitre      sécurité       alertes ×2      rafraîchissement
  batterie     (0 W si        (60 s / 10 min)  forcé (/2 s)
               non numérique)
```

Cinq automatisations référencent ce capteur hybride. Un watchdog séparé (`shelly_garde_flux_reseau_mqtt_rapide`) surveille et relance le script embarqué du Shelly.

**Appréciation.** La conception est solide : le contrôle de fraîcheur par `last_reported` est la bonne méthode (un capteur figé ne se détecte pas par son état), le repli à 0 W est conservateur et sûr, et les alertes sont explicitement découplées de la logique de régulation — la description le revendique et le code le confirme. C'est une vraie réponse à H5. Les réserves portent sur le coût (§5, N1) et la fragmentation (§5, N3).

---

## 4. Scores

### Score global : **55 / 100** (12/09 : 58/100)

| Catégorie | 12/09 | 21/09 | Commentaire |
|---|---|---|---|
| **Sécurité** | 42 | **40** | Les deux Critical intacts ; H1 aggravé par le retard de version ; un 3ᵉ repair ignoré ; tentatives de connexion échouées |
| **Fiabilité** | 61 | **58** | Filet de sécurité réseau ajouté (+), mais 83 entités indisponibles et 2 références cassées (−) |
| **Performance** | 56 | **45** | +49 % de base, 2 capteurs à 42 k chg/jour, 3 automatisations sub-10 s |
| **Maintenabilité** | 50 | **44** | Orchestrateur +18 %, 6 automatisations de plus, alertes dupliquées, chaîne de cartes inchangée |
| **Qualité des automatisations** | 68 | **70** | Les nouvelles sont bien conçues ; verrou de coordination introduit |
| **Sauvegardes / reprise** | 70 | **70** | Discipline maintenue, mais toujours 1 copie hors site et 32/35 sans base |
| **Observabilité** | 35 | **72** | **Le gain le plus net de la période** |

**Pondération employée :** Sécurité 25 %, Fiabilité 20 %, Performance 15 %, Maintenabilité 15 %, Qualité 10 %, Sauvegardes 8 %, Observabilité 7 %.

**Lecture du score.** Le gain massif en observabilité (+37) est en grande partie neutralisé par les pertes en performance (−11) et maintenabilité (−6), pondérées plus lourdement. Et la catégorie au poids le plus élevé — la sécurité — n'a pas progressé. Un score qui baisse malgré du travail réel est le signal qu'il faut lire : **l'effort n'a pas porté là où le risque se concentre.**

---

## 5. Nouveaux constats (période 12/09 → 21/09)

### 🔴 N1 — HIGH — Le nouveau socle de mesure a doublé la charge du recorder

**Preuve observée.** Volumétrie mesurée sur 1 heure (21/09, 10:12 → 11:12 UTC) :

| Entité | Changements / h | Extrapolation / jour |
|---|---|---|
| `sensor.reseau_omnibattery_hybride` | **1 766** | **42 384** |
| `sensor.shelly_reseau_rapide_mqtt` | **1 766** | **42 384** |
| `sensor.reseau_lisse_30_s` | 389 | 9 336 |

Croissance de la base :

| Date | Taille | Rétention | Rythme |
|---|---|---|---|
| 12/09 | 1 038,90 MiB | 9 j | ≈115 MiB/j |
| 21/09 | **1 547,84 MiB** | 10 j | **≈155 MiB/j** |

Moteur : **SQLite** 3.53.2 (inchangé).

**Impact concret.** Deux capteurs produisent à eux seuls ~85 000 lignes par jour. Le capteur hybride est un **template dérivé** : sa valeur est intégralement reconstructible à partir de ses deux sources, son historique n'apporte rien. Il est pourtant enregistré à pleine résolution, en doublon exact de `sensor.shelly_reseau_rapide_mqtt` (mêmes valeurs, mêmes horodatages à 5 ms près — visible dans l'historique : `137.1` à 13:11:47.911 et 13:11:47.917).

Sur SQLite, mono-écrivain, ce volume dégrade les requêtes d'historique et allonge la purge nocturne. La sauvegarde automatique avec base pèse désormais 440 MB.

**Cause probable.** Les nouveaux capteurs ont été créés pour la régulation temps réel, sans ajuster la configuration du recorder — qui était déjà aux valeurs par défaut (constat H3 du 12/09, non traité).

**Recommandation précise.** Exclure les capteurs dérivés haute fréquence. Ils restent pleinement disponibles pour les automatisations : l'exclusion recorder n'affecte que l'archivage.

```yaml
# configuration.yaml — exemple, NON appliqué
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
    entity_globs:
      - sensor.onduleur1_*_tx_*
      - sensor.onduler_2_*_tx_*
    domains:
      - update
```

Vérifier avant exclusion qu'aucun de ces capteurs ne porte de `state_class` alimentant le tableau de bord Énergie. Gain attendu : **50 à 60 % de la croissance quotidienne.**

La migration vers PostgreSQL (add-on **déjà installé et démarré** pour HGA) reste la réponse de fond.

---

### 🟠 N2 — MEDIUM — Trois automatisations permanentes sous les 10 secondes

**Preuve observée.**

| Automatisation | Déclencheur | Exécutions/jour | Mode |
|---|---|---|---|
| `energie_rafraichir_fraicheur_mesure_omnibattery` | `time_pattern` `seconds: "/2"` | **43 200** | `single` |
| `energie_hysteresis_compensation_import_omnibattery` | `time_pattern` `seconds: "/2"` + 2 déclencheurs d'état haute fréquence | **> 43 200** | `restart` |
| `energie_securite_omnibattery_sans_mesure_reseau` | `time_pattern` `seconds: "/10"` | **8 640** | `single` |
| `energie_alertes_mesure_reseau_et_compensation_import` | `time_pattern` `seconds: "/30"` | 2 880 | `parallel` (max 5) |

Traces réelles mesurées sur `energie_rafraichir_fraicheur_mesure_omnibattery` (21/09, 11:12:06 → 11:12:14) :

```
11:12:14.344 → 11:12:14.347   (3 ms)
11:12:12.344 → 11:12:12.349   (5 ms)
11:12:10.344 → 11:12:10.347   (3 ms)
11:12:08.344 → 11:12:08.347   (3 ms)
11:12:06.345 → 11:12:06.348   (3 ms)
```

**Impact concret.** Les exécutions sont **courtes** (3 à 5 ms) — il n'y a pas de saturation CPU, et il faut le dire clairement. Le coût réel est ailleurs :

1. **Le rafraîchissement forcé à 2 s** appelle `homeassistant.update_entity` sur le capteur hybride, ce qui **génère les 42 384 changements/jour** de N1. La charge recorder est une conséquence directe de cette automatisation.
2. **`energie_alertes_mesure_reseau_et_compensation_import`** évalue, à chaque déclenchement /30 s, un template qui itère sur `states.sensor` (331 entités) pour comparer des `last_reported`. Modéré, mais récurrent.
3. **Diagnostic impossible** : avec 5 traces conservées par défaut, une automatisation à 2 s ne garde que **10 secondes d'historique**. C'est le constat L7 du 12/09, non traité, et désormais bien plus pénalisant.

**Cause probable.** `homeassistant.update_entity` a été employé pour contourner le fait qu'un capteur template ne se réévalue pas sans changement de ses sources. C'est une solution fonctionnelle, mais coûteuse.

**Recommandation précise.**

1. **Remplacer le rafraîchissement forcé par un `trigger`-based template sensor**, qui gère nativement la périodicité sans automatisation ni écriture recorder :
   ```yaml
   # exemple — NON appliqué
   template:
     - trigger:
         - trigger: time_pattern
           seconds: "/5"
         - trigger: state
           entity_id: sensor.shelly_reseau_rapide_mqtt
       sensor:
         - name: Réseau OmniBattery hybride
           state: "{{ ... }}"
   ```
   Cela supprime une automatisation, réduit la cadence de 2 s à 5 s, et permet d'exclure proprement l'entité du recorder.
2. **Porter `stored_traces` à 50** sur les automatisations sub-10 s, sans quoi elles sont indiagnosticables.
3. Évaluer si la cadence de 2 s est réellement nécessaire, ou si 5 s suffisent au contrôle de fraîcheur (le seuil testé est `<5 s`).

---

### 🟠 N3 — MEDIUM — Deux automatisations alertent sur le même événement

**Preuve observée.** Deux automatisations créées à **10 minutes d'intervalle** (identifiants `1789802095253` et `1789802722562`) déclenchent toutes deux sur l'indisponibilité du capteur hybride pendant 60 secondes :

| | `energie_alerte_mesure_reseau_omnibattery_indisponible` | `energie_alertes_mesure_reseau_et_compensation_import` |
|---|---|---|
| Déclencheur | `to: unavailable` / `to: unknown`, `for: 60 s` | `to: [unavailable, unknown]`, `for: 60 s` (id `hybride_indisponible_60s`) |
| Action | `persistent_notification.create` | `notify.mobile_app_nx769j` **+** `persistent_notification.create` |
| Portée | 1 cas | 7 cas (rappel 10 min, rétablissement, démarrage, mesures figées, compensation 30 min / 2 h) |
| Version | — | « V2.3 validée par copie de test le 19/09/2026 » |

**Impact concret.** Lors d'une panne réelle de mesure réseau, **deux notifications persistantes** sont créées pour le même événement. La seconde automatisation couvre intégralement le périmètre de la première, avec en plus la notification mobile et six cas supplémentaires. La première est un vestige de l'itération V1/V2.

Au-delà du doublon : la redondance d'alerte érode la confiance dans les notifications. Une alerte qui arrive en double est une alerte qu'on finit par ignorer — ce qui est exactement le mécanisme qui a conduit à voir trois repairs successivement mis en sourdine (§6, H1).

**Recommandation précise.** Supprimer `automation.energie_alerte_mesure_reseau_omnibattery_indisponible` après avoir vérifié que la V2.3 est stable. Vérifier au préalable les références :
```
ha_search(query="energie_alerte_mesure_reseau_omnibattery_indisponible")
```
Sauvegarder avant suppression — la discipline déjà en place.

---

### 🔴 N4 — MEDIUM — Références cassées vers l'Android TV et l'agent Gemini supprimé

**Preuve observée — Android TV.** L'appareil a changé d'adresse IP (192.168.1.44 → 192.168.1.45, visible dans les erreurs Chromecast du 21/09 04:08), mais l'entité conserve l'ancienne IP dans son `entity_id` :

- `media_player.android_tv_192_168_1_44` → **`unavailable`**
- `remote.android_tv_192_168_1_44` → **`unavailable`**
- Référencée par : `automation.bbox_memorise_chaine_via_adb` **et** `script.preparer_tele`
- Conséquence dans les logs : `Referenced entities media_player.android_tv_192_168_1_44 are missing or not currently available` — **8 occurrences**, dernière le 19/09 20:27
- Également : `Referenced entities remote.bboxtv are missing or not currently available` — 6 occurrences

L'automatisation `bbox_memorise_chaine_via_adb` interroge cette entité **toutes les 30 secondes** (`time_pattern seconds: "/30"`) : elle échoue silencieusement 2 880 fois par jour, protégée par `continue_on_error: true`.

**Preuve observée — Gemini.** L'intégration `google_generative_ai_conversation` a été supprimée (bon point, constat M3 partiellement traité), mais l'entité `conversation.google_ai_conversation` reste référencée par :
- `automation.ia_routeur_unique` (désactivée, donc sans erreur d'exécution)
- le dashboard **`agents-ia`**

**Impact concret.** Le nommage d'entité par adresse IP est la cause racine : toute réattribution DHCP casse la référence. Le script `preparer_tele` — exposé à Google Assistant — échoue donc sur sa cible principale.

**Recommandation précise.**

1. **Ré-appairer l'Android TV** sur sa nouvelle IP et, surtout, **renommer l'entité** pour supprimer l'IP de l'`entity_id` (`media_player.android_tv_salon`). Réserver un bail DHCP statique côté box.
2. Mettre à jour les deux consommateurs (`bbox_memorise_chaine_via_adb`, `preparer_tele`) après renommage — utiliser `ha_search` avec l'`entity_id` exact pour ne rien oublier.
3. Trancher sur le Routeur IA (voir §6, M2) : la référence Gemini cassée n'est qu'un symptôme du sous-système abandonné.

---

### 🔴 N5 — MEDIUM — La tablette VACA est entièrement hors ligne : 48 entités mortes

**Preuve observée.** `assist_satellite.vaca_5a902d816` = **`unavailable`**. Sur les 60 entités strictement `unavailable`, **48 appartiennent à VACA** : capteurs, boutons, sélecteurs, interrupteurs, lecteur média, événements.

Les avertissements de reconnexion se sont arrêtés le **12/09 à 20:06:37** — exactement au moment de l'abaissement du niveau de log appliqué ce jour-là. Or Home Assistant a redémarré le **16/09 à 05:30**, ce qui a effacé ce réglage runtime. **Aucun message VACA n'apparaît après le redémarrage** : le composant ne tente plus de se reconnecter du tout.

**Impact concret.** Il faut être précis sur ce point, car l'apparence est trompeuse : **la boucle de logs ne s'est pas arrêtée parce qu'elle a été corrigée, mais parce que le satellite a cessé complètement de fonctionner.** Le symptôme a disparu avec la fonction.

Conséquences :
- 48 entités mortes polluent le registre, l'autocomplétion et les dashboards.
- La fonction d'assistant vocal View Assist est perdue.
- Le dashboard `view-assist` affiche des données figées.
- Une mise à jour `vaca` v0.13.2 → **v0.13.3** est disponible et non appliquée.

**Cause probable.** Trois hypothèses, non départageables depuis Home Assistant : tablette éteinte ou déchargée ; application View Assist arrêtée par l'optimisation de batterie Android ; perte de connexion Wi-Fi durable. La cadence de déconnexion observée le 12/09 (~6 s alors que le message annonçait 10 s) orientait déjà vers une coupure réseau plutôt qu'un simple délai de retry.

**Recommandation précise.**

1. **Vérifier physiquement la tablette** : allumée, chargée, application View Assist lancée.
2. Désactiver l'optimisation de batterie Android pour View Assist et la mise en veille Wi-Fi.
3. Mettre à jour `vaca` en v0.13.3.
4. **Si le satellite n'est plus utilisé**, supprimer l'entrée de configuration : cela retire 48 entités d'un coup (−6,7 % du registre) et élimine la première source de bruit potentielle.
5. **Rendre persistant** l'abaissement du niveau de log, qui a été perdu au redémarrage du 16/09 :
   ```yaml
   logger:
     default: warning
     logs:
       custom_components.vaca.assist_satellite: error
   ```

---

### 🟠 N6 — LOW — Un troisième repair mis en sourdine, et une mise à jour MCP bloquée

**Preuve observée.** Nouveau repair du 16/09, **déjà ignoré** (`ignored: true`, `dismissed_version: 2026.9.2`) :

```json
{"issue_id": "server_update_held", "domain": "ha_mcp_tools",
 "translation_placeholders": {"latest": "8.5.0", "shipped": "2.2.0", "running": "2.1.3"},
 "created": "2026-09-16T15:33:17", "ignored": true, "active": true}
```

Message associé, **20 occurrences** dans les logs entre le 16/09 et le 21/09 :

> `HA-MCP server 8.5.0 is available, but that release also updated the custom component (2.2.0; running 2.1.3); holding the automatic server update until the component is updated via HACS.`

**Impact concret.** Le composant HA-MCP est bloqué en 2.1.3 alors que 2.2.0 est disponible via HACS, et le serveur reste en 8.4.3 au lieu de 8.5.0. `auto_update: true` est activé mais **ne peut pas s'appliquer** — l'automatisme sur lequel on compte est en fait à l'arrêt, silencieusement.

Les trois repairs actifs sont désormais **tous les trois ignorés**. C'est un motif : les alertes sont mises en sourdine plutôt que traitées, ce qui neutralise progressivement le mécanisme de Repairs comme outil de diagnostic.

**Recommandation.** Mettre à jour le composant HA-MCP via HACS (2.1.3 → 2.2.0), ce qui débloquera le serveur en 8.5.0. Traiter cette mise à jour **conjointement avec le durcissement C1** : c'est la même interface de configuration, autant le faire en une seule intervention.

---

## 6. Constats du 12/09 — état au 21/09

### 🔴 C1 — CRITICAL — **NON CORRIGÉ** — Serveur MCP exposé avec webhook non authentifié

**Preuve observée au 21/09** — configuration `ha_mcp_tools`, identique au caractère près :

```yaml
bind_host: "0.0.0.0"
server_port: 9584
enable_webhook: true
webhook_auth: "none"
enable_llm_api: true
auto_update: true
```

`modified_at: 1787391563.840334` — **valeur identique à celle du 12/09**. L'entrée de configuration n'a pas été ouverte.

L'impact reste celui décrit le 12/09 : contrôle quasi total de Home Assistant (création/modification d'automatisations, appel de tout service, lecture des diagnostics, gestion des sauvegardes) joignable depuis tout hôte du LAN `192.168.1.0/24`, tout nœud du tailnet, et les réseaux Docker internes.

**Élément aggravant nouveau.** Les logs enregistrent deux tentatives de connexion échouées le **19/09 à 20:49** :

```
Login attempt or request with invalid authentication from fe80::cc6a:74f7:fb39:f3d2
Requested URL: '/auth/login_flow/...'  (Mozilla/5.0 (Windows...))
```

L'adresse est en lien-local IPv6 — donc un appareil **du réseau local**, pas d'Internet. Il s'agit très probablement d'une erreur de saisie sur un poste Windows de la maison, et non d'une attaque. Mais cela illustre concrètement que des hôtes du LAN sollicitent l'interface d'authentification — et que le port 9584, lui, n'en demande aucune.

**Recommandation — inchangée et prioritaire.**

```yaml
bind_host: "127.0.0.1"     # ou 100.101.146.79 pour un accès Tailscale
enable_webhook: false      # si le webhook n'est pas consommé
webhook_auth: "bearer"     # sinon, authentification obligatoire
auto_update: false
```

**Vérification :** depuis un autre poste du LAN, `curl -m 3 http://192.168.1.74:9584/` doit échouer.

---

### 🔴 C2 — CRITICAL — **NON CORRIGÉ** — Identifiants MQTT en clair, broker exposé sur le LAN

**Preuve observée au 21/09** — options de l'add-on `core_mosquitto`, inchangées :

```yaml
logins:
  - username: jeremy
    password: "<même valeur en clair qu'au 12/09 — non reproduite>"
require_certificate: false
```
```json
"network": { "1883/tcp": 1883, "1884/tcp": 1884, "8883/tcp": 8883, "8884/tcp": 8884 }
```

**Élément aggravant.** Le nombre de sauvegardes contenant ce secret est passé de **30 à 35**. Et surtout : **MQTT est devenu critique pour le pilotage énergétique.** Au 12/09, `sensor.shelly_reseau_rapide_mqtt` était un capteur orphelin sans référence. Aujourd'hui, il alimente le capteur hybride dont dépendent cinq automatisations, dont l'arbitre batterie et le repli de sécurité. **Un accès non autorisé au broker permet désormais d'injecter de fausses mesures de puissance réseau** et, par ce biais, d'influencer directement les commandes de charge et de décharge de la batterie.

Le risque de ce constat a donc matériellement augmenté, sans que la configuration change.

**Recommandation — inchangée, priorité renforcée.**

1. Rotation du mot de passe, en **pré-haché** :
   ```bash
   pw -p '<nouveau_mot_de_passe>'   # dans le conteneur Mosquitto
   ```
   ```yaml
   logins:
     - username: jeremy
       password: "<sortie hachée>"
       password_pre_hashed: true
   ```
2. Répercuter dans Zigbee2MQTT, dans l'intégration MQTT **et dans le script embarqué du Shelly** (« Grid power fast ») — ce dernier point est nouveau et facile à oublier.
3. Supprimer le mapping des ports hôte si aucun client externe au Supervisor n'en a besoin.

---

### 🔴 H1 — HIGH — **NON CORRIGÉ, AGGRAVÉ** — Contournement du PIN de l'agent IA

**Preuve au 21/09.** Repair toujours actif et toujours ignoré :

```json
{"issue_id": "pin_bypassed_by_local_intents_...", "domain": "home_generative_agent",
 "translation_placeholders": {"pipelines": "Gemini"},
 "ignored": true, "dismissed_version": "2026.8.2", "active": true,
 "created": "2026-09-06T09:36:08"}
```

**Aggravation.** Au 12/09, une mise à jour v3.39.6 était disponible. Aujourd'hui c'est **v3.42.0** — l'installation est en **v3.39.4**, soit **trois versions mineures de retard**. Un éventuel correctif du contournement de PIN n'a donc pas été capté.

14 entités restent exposées à Google Assistant, dont `climate.clim_airton`, `switch.omnibattery_vacation_mode`, `scene.eteindre_tout` et quatre scripts de préparation énergétique.

**Recommandation.** Mettre HGA à jour (v3.39.4 → v3.42.0) et consulter les notes de version. Réactiver le suivi du repair. Dans l'intervalle, retirer de l'exposition vocale `switch.omnibattery_vacation_mode` et `scene.eteindre_tout`.

---

### 🔴 H3 — HIGH — **NON CORRIGÉ, AGGRAVÉ** — Recorder sans exclusions

Voir **N1** : la base est passée de 1 038,90 à 1 547,84 MiB (+49 %) et le rythme de croissance a augmenté de 35 %. Aucune exclusion n'a été mise en place. Les recommandations de N1 remplacent et complètent celles de H3.

---

### 🟡 H4 — HIGH — **PARTIELLEMENT CORRIGÉ** — Race condition sur la climatisation

**Ce qui a été corrigé.** Un verrou de coordination a été introduit. La description de l'arbitre climatisation le documente :

> « Correctif 21/09/2026 : les démarrages automatiques sur surplus (été, mi-saison chaud/froid) et le lancement du boost solaire hiver attendent la fin d'une vraie préparation chauffe-eau (`input_boolean.chauffe_eau_preparation_en_cours` OFF). Le verrou est borné à 20 min par l'arbitre solaire. »

Vérification : la condition `input_boolean.chauffe_eau_preparation_en_cours == off` est présente dans les branches « Été démarrage surplus », « Mi-saison chaleur », « Mi-saison froid » et « Hiver boost solaire ». Le helper est référencé **19 fois** dans l'orchestrateur solaire. Le hash de l'arbitre climatisation a changé : `ce5aa1b3fa80b22a` → `11bd844880fa18bc`.

**C'est exactement le correctif de fond recommandé le 12/09** (« poser une demande dans un helper, l'arbitre l'intègre comme condition »). Bien vu.

**Ce qui subsiste.**

1. **La simultanéité des déclencheurs est intacte.** Les deux automatisations conservent `time_pattern` `seconds: "/30"` :
   - `clim_maintien_automatique_19degc` → `{"id": "reconciliation", "seconds": "/30"}`
   - `solaire_p1_orchestration_30s` → `{"id": "controle", "seconds": "/30"}`

   Elles s'exécutent donc toujours dans la même fenêtre de quelques centaines de millisecondes (mesure du 12/09 : 17:30:30.104 et 17:30:30.305).

2. **L'orchestrateur commande toujours directement la climatisation** : 2 appels `climate.set_hvac_mode` (contre 3 au 12/09), plus `timer.clim_anti_court_cycle` et `timer.clim_arret_automatique_contexte`. La branche « Couper clim à 20 % pendant test chauffe-eau » subsiste.

3. La description de l'arbitre affirme toujours être **« Seul arbitre de la clim Airton »**, ce que le code contredit.

**Impact résiduel.** Le verrou couvre les **démarrages**. Il ne couvre pas les **arrêts** émis par l'orchestrateur. Le risque de commande concurrente est donc réduit mais non éliminé.

**Recommandation pour terminer la correction.**

1. **Décaler le déclencheur de l'orchestrateur** — 5 minutes de travail :
   ```yaml
   triggers:
     - trigger: time_pattern
       seconds: "15"
     - trigger: time_pattern
       seconds: "45"
   ```
2. **Étendre le verrou aux arrêts** : remplacer les 2 `climate.set_hvac_mode` restants de l'orchestrateur par la pose d'un helper de demande, traité par l'arbitre climatisation — même mécanisme que celui qui vient d'être mis en place pour les démarrages.
3. Corriger la description une fois la propriété exclusive rétablie.

---

### 🟡 H5 — HIGH — **PARTIELLEMENT CORRIGÉ** — Point unique de défaillance sur la mesure

**Ce qui a été corrigé.** Le filet de sécurité décrit au §3.4 : capteur hybride à double source avec contrôle de fraîcheur, repli à 0 W si la mesure n'est pas numérique, watchdog du script embarqué Shelly, alertes à 60 s / 10 min / au démarrage / sur mesures figées. C'est une réponse substantielle et bien construite.

État relevé au moment de l'audit — chaîne saine :

```
HYBRIDE = 156.9 W      MQTT_RAPIDE = 156.9 W     âge MQTT = 1,8 s
SHELLY_LENT = 137.1 W  SCRIPT_SHELLY = on        COMPENSATION = off
MAX_DECHARGE = 2000 W  MAX_CHARGE = 1800 W
```

`omnibattery: batteries_connected 1/1, suspended 0, non_responsive 0`. Aucune erreur Modbus dans la fenêtre de logs (3 occurrences `pymodbus` seulement, contre plusieurs dizaines le 12/09).

**Ce qui subsiste.**

1. **Le lien Modbus lui-même n'a pas été fiabilisé.** La recommandation du 12/09 (Ethernet ou bail DHCP statique pour la Marstek sur `192.168.1.92`) ne peut être vérifiée depuis Home Assistant — voir §10. Le filet de sécurité protège contre une panne de **mesure réseau**, pas contre une panne de **liaison batterie**.
2. **Le SPOF s'est déplacé, pas supprimé.** Toute la chaîne dépend désormais du **script embarqué dans le Shelly**. Le watchdog le relance, mais si le Shelly lui-même devient injoignable, les deux sources tombent ensemble — le repli « lent » vient du même appareil physique.
3. **Risque de boucle du watchdog.** `shelly_garde_flux_reseau_mqtt_rapide` se déclenche sur `switch.domotique_shelly_domo_grid_power_fast → off for: 5 s` et rallume l'interrupteur. Si le script Shelly échoue en boucle, l'automatisation le relance indéfiniment, sans compteur d'échecs ni plafond. À surveiller.

**Recommandation.**

1. Fiabiliser physiquement la liaison de la batterie Marstek (Ethernet si possible, sinon bail statique + vérification de couverture Wi-Fi).
2. Ajouter un **compteur d'échecs** au watchdog : au-delà de N relances en M minutes, cesser et notifier, plutôt que de boucler.
3. Documenter le comportement de repli attendu en cas de perte prolongée du Shelly — aujourd'hui implicite.

---

### 🟡 M9 — **PARTIELLEMENT CORRIGÉ** — Stratégie de sauvegarde

**Progrès.** 35 sauvegardes (contre 30). La discipline « sauvegarde avant chaque modification » est **pleinement maintenue**, avec un nommage explicite et daté :

```
19/09  Avant_securisation_mesure_OmniBattery_20260919
19/09  Avant_alerte_securite_OmniBattery_V2_3_2026_09_19
17/09  Avant_compensation_import_OmniBattery_20260917
16/09  Avant_MAJ_2026-09-16_Core_Tuya
```

La sauvegarde automatique la plus récente (`Automatic backup 2026.9.1`, 16/09, 440 MB, **base incluse**) est en version 2026.9.1 — bien plus proche de la production (2026.9.2) que la précédente référence.

**Ce qui subsiste.**

| Critère | État au 21/09 |
|---|---|
| Copies hors site | **1 sur 35** (`cloud.cloud`) — 34 sur le disque de la machine |
| Base de données incluse | **3 sur 35** |
| Sauvegarde automatique conservée | **1 seule**, datée du 16/09 |
| Dépendance | Abonnement Nabu Casa, **expirant le 12/10/2026 (21 jours)** |

**Recommandation.** Inchangée et désormais datée : configurer un **second agent de sauvegarde** (Google Drive, OneDrive, NAS Samba) **avant le 12/10**, activer la base dans les sauvegardes automatiques, porter la rétention à 3 copies, et purger les sauvegardes locales antérieures à 2026.9.x.

---

### 🔴 Constats inchangés — synthèse

Les constats suivants du 12/09 sont **vérifiés comme inchangés** au 21/09. Leur analyse détaillée reste valable dans le rapport précédent ; seul l'état est actualisé ici.

| Réf. | Constat | Vérification au 21/09 |
|---|---|---|
| **M1** | Chaîne de 16 cartes Lovelace inline v5→v20 | **Inchangée** : 26 ressources, 19 inline, 146,7 KB. `omni-energy-flow-card-v7` toujours présente et toujours court-circuitée (v9 hérite de v8) |
| **M2** | Sous-système « Routeur IA » mort | **Partiellement traité** : intégrations Google AI et Cerebras supprimées, mais les 31 helpers, le dashboard `agents-ia` et les 3 cartes subsistent. La référence à `conversation.google_ai_conversation` est désormais **cassée** (voir N4) |
| **M3** | `local_openai` non chargée | **Inchangé** : toujours installée en 1.12.0, toujours signalée par `homeassistant.loader` |
| **M4** | Entités indisponibles | **Aggravé** : 39 → 83. Les 4 lampes mortes et `media_player.bureau_2` (JARVIS) sont toujours là |
| **M5** | Automatisations monolithiques | **Aggravé** : orchestrateur 56 003 → **65 987 caractères**, 30 → **36 branches**, 14 déclencheurs, mode `restart` |
| **M6** | File editor démarré en permanence | **Inchangé** : `state: started`, `boot: auto` |
| **M7** | Blueprint avec `device_id` codé en dur | **Inchangé** : `automation.lumiere_chambre_manuelle`, ciblage `area_id: chambre` dont 4 lampes sur 5 sont mortes |
| **M8** | Aucun étage, helpers sans zone | **Inchangé** : 0 étage, 7 zones non rattachées, `cuisine` et `bureau` toujours vides |
| **M10** | Descriptions-journaux | **Aggravé** : la description de l'arbitre clim dépasse désormais 2 900 caractères et accumule les datations (10/09, 21/09) |
| **L2** | Grocy installé mais arrêté | **Inchangé** (mis à jour en 0.26.2, toujours `stopped`) |
| **L4** | `forecast_solar` en doublon de Solcast | **Inchangé** |
| **L5** | Erreurs Xbox récurrentes | **Aggravé** : 34 erreurs sur la fenêtre (12→20/09), contre 12 le 12/09 |
| **L6** | Bugs Omnibattery (`total_increasing`, latence) | **Inchangé**, non remonté en amont |
| **L7** | 5 traces conservées | **Inchangé**, et bien plus pénalisant avec les automatisations à 2 s (voir N2) |
| **L8** | Zones `cuisine` et `bureau` vides | **Inchangé** |

**Corrigé depuis le 12/09 :**

| Réf. | Action constatée |
|---|---|
| **L1** | Tailscale 0.29.0 → **0.30.0** ✅ · Terminal & SSH 10.4.0 → 10.5.0 ✅ · Tuya Local → 2026.9.1 ✅ · HA Core 2026.9.1 → 2026.9.2 ✅ |
| **L3** | `sensor.shelly_reseau_rapide_mqtt` n'est plus orphelin — il est devenu **le capteur central** de la chaîne énergétique. La recommandation de suppression du 12/09 était correcte à cette date (0 référence, indisponible) ; **elle est aujourd'hui caduque et ne doit pas être appliquée** |
| **H2** | Boucle de logs éteinte — mais par disparition du satellite, pas par correction (voir N5) |

---

## 7. Quick wins

| # | Action | Effort | Gain | Réf. |
|---|---|---|---|---|
| 1 | `webhook_auth` ≠ `none` et `bind_host` → `127.0.0.1` | 5 min | **Ferme la surface d'attaque critique** | C1 |
| 2 | Rotation du mot de passe MQTT en pré-haché | 15 min | **Ferme la 2ᵉ surface critique** | C2 |
| 3 | Exclusions recorder sur les 3 capteurs dérivés | 10 min | **−50 à 60 % de croissance DB** | N1 |
| 4 | Mettre à jour HGA v3.39.4 → v3.42.0 | 10 min | Correctif PIN potentiel, 3 versions de retard | H1 |
| 5 | Mettre à jour HA-MCP 2.1.3 → 2.2.0 (débloque le serveur 8.5.0) | 5 min | Lève le repair, restaure l'auto-update | N6 |
| 6 | Décaler le `time_pattern` de l'orchestrateur à `15,45` | 5 min | **Termine la correction de H4** | H4 |
| 7 | Rendre persistant le `logger:` pour VACA | 5 min | Protège contre le retour de la boucle | N5 |
| 8 | Supprimer l'automatisation d'alerte dupliquée | 5 min | Fin des doubles notifications | N3 |
| 9 | Porter `stored_traces` à 50 sur les automatisations sub-10 s | 10 min | Diagnostic redevenu possible | N2, L7 |
| 10 | Second agent de sauvegarde (avant le 12/10) | 20 min | Couvre l'expiration Nabu Casa | M9 |

---

## 8. Plan d'action priorisé

### 🚨 Immédiat

| # | Action | Réf. |
|---|---|---|
| 1 | `bind_host` → `127.0.0.1`, `webhook_auth` authentifié, `auto_update: false` | **C1** |
| 2 | Rotation du mot de passe MQTT en pré-haché + répercussion Z2M / intégration / **script Shelly** | **C2** |
| 3 | Vérifier depuis le LAN que 9584 et 1883 ne répondent plus | C1, C2 |
| 4 | Exclusions recorder sur `reseau_omnibattery_hybride`, `shelly_reseau_rapide_mqtt`, `reseau_lisse_30_s` | **N1** |

### 📅 Sous 7 jours

| # | Action | Réf. |
|---|---|---|
| 5 | Mettre à jour HGA (v3.42.0) et HA-MCP (2.2.0) ; réactiver le suivi des 3 repairs | H1, N6 |
| 6 | Décaler le déclencheur de l'orchestrateur (`seconds: 15,45`) | H4 |
| 7 | Second agent de sauvegarde **avant le 12/10** + base incluse dans les sauvegardes automatiques | M9 |
| 8 | Diagnostiquer la tablette VACA ; la supprimer si abandonnée (−48 entités) | N5 |
| 9 | Rendre persistante la configuration `logger:` | N5 |
| 10 | Corriger la référence Android TV (renommer sans l'IP + bail statique) | N4 |
| 11 | Supprimer l'alerte dupliquée `energie_alerte_mesure_reseau_omnibattery_indisponible` | N3 |
| 12 | Porter `stored_traces` à 50 sur les automatisations sub-10 s | N2 |
| 13 | Ajouter un compteur d'échecs au watchdog Shelly | H5 |

### 🗓️ Sous 30 jours

| # | Action | Réf. |
|---|---|---|
| 14 | Migrer le recorder vers PostgreSQL (add-on déjà en service) | N1, H3 |
| 15 | Remplacer le rafraîchissement forcé /2 s par un `trigger`-based template sensor | N2 |
| 16 | Étendre le verrou de coordination aux **arrêts** de climatisation | H4 |
| 17 | Trancher sur le Routeur IA : réparer ou supprimer (31 helpers + dashboard + 3 cartes) | M2, N4 |
| 18 | Aplatir la chaîne de cartes v5→v20 en une carte unique externalisée | M1 |
| 19 | Scinder l'orchestrateur (36 branches) en 4 automatisations thématiques | M5 |
| 20 | Fiabiliser la liaison Modbus de la batterie (Ethernet / bail statique) | H5 |
| 21 | Nettoyer les entités mortes (4 lampes, JARVIS, `local_openai`, `rpi_power`) | M3, M4 |
| 22 | Corriger le ciblage `area_id` → `entity_id` du blueprint bouton | M7 |
| 23 | Créer les étages, rattacher les 7 zones, traiter `cuisine` et `bureau` | M8, L8 |
| 24 | Remonter les bugs Omnibattery en amont | L6 |

### 🎯 Long terme

| # | Action | Réf. |
|---|---|---|
| 25 | **Segmenter le réseau en VLAN IoT** — mesure structurante la plus efficace au vu de C1 et C2 | §9 |
| 26 | Versionner `/config` dans Git (`secrets.yaml` exclu) | M10 |
| 27 | Factoriser les variables Jinja répétées en capteurs template partagés | M5 |
| 28 | Convention de nommage unifiée pour les entités solaires et énergie | M5 |
| 29 | TLS obligatoire sur MQTT (8883/8884) | C2 |
| 30 | Tester une restauration complète sur instance de test | M9 |
| 31 | Documenter l'architecture énergétique : schéma des flux, propriété des entités, comportements de repli | H4, H5 |

---

## 9. Risques liés aux composants personnalisés

| Composant | Version | Disponible | Étoiles | Risque | Évolution |
|---|---|---|---|---|---|
| `tuya_local` | 2026.9.1 | à jour | 3 475 | Faible | ✅ mis à jour |
| `hacs` | 2.0.5 | à jour | 7 732 | Faible | = |
| `solcast_solar` | v4.6.1 | à jour | 450 | Faible | = |
| `omnibattery` | v1.4.0 | à jour | 152 | **Moyen** | = (bugs L6 non remontés) |
| `home_generative_agent` | **v3.39.4** | **v3.42.0** | 304 | **Élevé** | 🔴 3 versions de retard |
| `view_assist` | 2026.7.0 | à jour | 87 | Moyen | = |
| `vaca` | **v0.13.2** | **v0.13.3** | 488 | **Élevé** | 🔴 satellite hors ligne (N5) |
| `local_openai` | 1.12.0 | à jour | 282 | Moyen | = (toujours non chargée) |
| `ha_mcp_tools` | **v2.1.3** | **v2.2.0** | 51 | **Élevé** | 🔴 MAJ bloquée (N6) |
| `smartir` | — | — | — | **À clarifier** | 🆕 apparaît dans les logs de chargement |
| `mcp_proxy` | — | — | — | **À clarifier** | = non listé dans HACS |

**Analyse.** Le risque reste concentré sur `ha_mcp_tools` : **51 étoiles GitHub** pour un composant qui expose le contrôle total de Home Assistant sur le réseau, avec `auto_update: true` — un automatisme qui, comme le montre N6, est actuellement bloqué sans que cela ait été traité. C'est la combinaison la moins favorable entre privilège, exposition et maturité.

Deux composants apparaissent dans les logs de chargement sans figurer dans l'inventaire HACS : **`mcp_proxy`** (déjà signalé le 12/09) et **`smartir`**. Leur origine doit être clarifiée — un composant présent dans `/config/custom_components` sans traçabilité HACS n'est suivi par aucun mécanisme de mise à jour ni de revue.

---

## 10. Limites de l'audit

Éléments **non vérifiables** avec les outils disponibles en lecture seule, inchangés depuis le 12/09 :

| Élément | Raison |
|---|---|
| `configuration.yaml`, includes, `secrets.yaml` | Aucun accès au système de fichiers `/config` |
| Configuration `http:` — `trusted_proxies`, `ip_ban_enabled`, `login_attempts_threshold` | Non exposée par l'API |
| Configuration exacte du `recorder` (exclusions, `purge_keep_days`) | Déduite de la volumétrie et de `oldest_recorder_run` |
| Permissions POSIX | Aucun accès au système de fichiers |
| Comptes utilisateurs, jetons de longue durée, sessions | Non exposés |
| Règles de pare-feu et NAT de la box | Hors périmètre |
| Configuration interne Zigbee2MQTT, clé réseau Zigbee, `permit_join` | Non exposée par l'API Supervisor |
| Topologie du réseau Zigbee (LQI, RSSI) | ZHA désactivé, données Z2M non exposées via MCP |
| Contenu du script embarqué Shelly « Grid power fast » | Réside sur l'appareil, hors de Home Assistant |
| Type de liaison physique de la batterie Marstek (Ethernet / Wi-Fi) | Non exposé — **empêche de conclure sur H5-1** |
| Origine et contenu de `smartir` et `mcp_proxy` | Absents de HACS, système de fichiers inaccessible |
| Contenu détaillé des 31 vues de dashboard | Non exploré exhaustivement |

**Recommandation.** Un passage avec accès au système de fichiers (Terminal & SSH, en lecture seule) lèverait ces réserves — en particulier sur `http: trusted_proxies`, la configuration du recorder, les ACL MQTT et l'origine des deux composants non tracés.

---

## 11. Synthèse finale

Neuf jours de travail réel ont été investis, et cela se voit : la chaîne de mesure réseau est passée d'un point unique de défaillance à une architecture à double source avec contrôle de fraîcheur, watchdog, repli sûr et alertes découplées. Le verrou de coordination entre les deux arbitres est exactement le correctif de fond recommandé. Les logs sont redevenus lisibles. La discipline de sauvegarde avant modification ne s'est jamais démentie. **C'est du bon travail d'ingénierie, et il faut le dire.**

Mais ce travail s'est fait **à côté** des deux constats critiques, pas **après** eux. Le serveur MCP est toujours ouvert sur le réseau sans authentification. Le mot de passe MQTT est toujours en clair — et il protège désormais un canal devenu critique pour le pilotage de la batterie, ce qui a matériellement augmenté le risque sans qu'une ligne de configuration ait changé.

Et l'effort a eu un coût non compensé : **+49 % de base de données, +113 % d'entités indisponibles, +18 % sur l'automatisation la plus complexe.** Chaque brique de fiabilité ajoutée a apporté ses capteurs, ses automatisations et son historique, sans que les réglages de fond — exclusions recorder, moteur de base de données — soient ajustés en conséquence.

Le score baisse de 58 à 55 malgré des progrès réels. Ce n'est pas une contradiction : c'est la mesure de l'écart entre là où l'effort s'est porté et là où le risque se concentre.

**Trois interventions, pour un total d'environ 30 minutes, changeraient le profil de risque de l'installation :**

1. `bind_host` → `127.0.0.1` et `webhook_auth` ≠ `none` (5 min)
2. Rotation du mot de passe MQTT en pré-haché (15 min)
3. Exclusions recorder sur les trois capteurs dérivés (10 min)

Avec ces trois actions, le score passerait raisonnablement à **68/100**. Le plan à 7 jours l'amènerait autour de **76/100**, et celui à 30 jours au-delà de **85/100**.

---

*Audit réalisé en lecture seule le 21 septembre 2026. Aucune modification n'a été apportée à l'installation. Toutes les valeurs de secrets rencontrées ont été délibérément omises de ce rapport.*

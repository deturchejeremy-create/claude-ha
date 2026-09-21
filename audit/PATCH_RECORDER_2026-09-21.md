# Correctif Recorder — préparation mesurée

**Date :** 21 septembre 2026
**Statut :** **préparé, NON appliqué.** Aucune exclusion posée, aucun redémarrage effectué.
**Méthode :** mesure directe des écritures réelles sur fenêtre glissante de 1 heure (21/09, 12:42→13:43 heure locale), via l'API d'historique. Aucune estimation.

> Ce document répond à la demande de méthode : comparer la liste proposée à la configuration existante, mesurer quelles entités génèrent réellement le plus d'écritures, vérifier leurs dépendances, et produire un YAML minimal préservant l'existant.

---

## 1. Deux corrections aux hypothèses de départ

### 1.1 🔴 Une configuration `recorder: exclude:` existe DÉJÀ

**C'est le point le plus important de ce document.** Le correctif ne doit **pas** être ajouté comme un nouveau bloc : il doit être **fusionné** dans celui qui existe. Un second bloc `recorder:` dans `configuration.yaml` provoque une erreur de clé dupliquée, et un second `exclude:` écrase le premier.

**Preuve — asymétrie mesurée entre entités jumelles**, sur la même fenêtre d'1 heure, alors que les deux micro-onduleurs fonctionnent normalement :

| Entité | Lignes / h | Jumelle | Lignes / h |
|---|---|---|---|
| `sensor.onduleur1_tx_requests` | **0** | `sensor.onduler_2_tx_requests` | **361** |
| `sensor.onduleur1_rx_success` | **0** | `sensor.onduler_2_rx_success` | **351** |
| `sensor.onduleur1_rx_fail_receive_nothing` | **0** | `sensor.onduler_2_rx_fail_receive_nothing` | **11** |
| `sensor.onduleur1_rssi` | **0** | `sensor.onduler_2_rssi` | **307** |
| `sensor.opendtu_528ecc_heap_free` | **0** | — | — |
| `sensor.opendtu_528ecc_heap_size` | **0** | — | — |
| `sensor.opendtu_528ecc_wifi_signal` | **0** | — | — |

**Contrôle de validité** — l'onduleur 1 n'est ni en panne ni globalement exclu :

| Entité de contrôle | Lignes / h |
|---|---|
| `sensor.onduleur1_ch1_power` | 241 (vs 242 pour `onduler_2_ch1_power`) |
| `sensor.onduleur1_efficiency` | 310 |
| `sensor.onduleur1_tx_re_request_fragment` | 21 |

Un compteur comme `tx_requests` s'incrémente en permanence : **0 ligne sur une heure ne peut pas s'expliquer par une absence de changement.** La seule explication cohérente est une exclusion explicite.

**Hypothèse sur la cause de l'asymétrie.** Les deux onduleurs sont nommés de façon incohérente : **`onduleur1`** et **`onduler_2`** (le second sans le « u » de *onduleur*). Une exclusion écrite pour le premier ne couvre pas le second. Comme `onduleur1_tx_re_request_fragment` **est** enregistrée alors que `onduleur1_tx_requests` ne l'est pas, il s'agit vraisemblablement d'une **liste explicite d'entités**, pas d'un glob.

⚠️ **La forme exacte du bloc existant (liste, globs, domaines, `include` éventuel) n'est pas déterminable sans lire `configuration.yaml`.** Aucun outil de lecture ou d'édition YAML n'est disponible dans ce serveur MCP (§6.2 du rapport de passation). **Ouvrir le fichier et lire le bloc réel est un prérequis absolu.**

### 1.2 🔴 Les trois capteurs proposés initialement portent tous `state_class: measurement`

Les audits du 12/09 et du 21/09 proposaient d'exclure `sensor.reseau_omnibattery_hybride`, `sensor.shelly_reseau_rapide_mqtt` et `sensor.reseau_lisse_30_s`. **Cette recommandation était trop hâtive et est corrigée ici.**

| Entité | `state_class` | `device_class` |
|---|---|---|
| `sensor.reseau_omnibattery_hybride` | **measurement** | power |
| `sensor.shelly_reseau_rapide_mqtt` | **measurement** | power |
| `sensor.reseau_lisse_30_s` | **measurement** | power |
| `sensor.shellyproem50_ece334f85344_energy_meter_0_puissance` | **measurement** | power |
| `sensor.opendtu_528ecc_ac_power` | **measurement** | power |
| `sensor.omnibattery_home_consumption` | **measurement** | power |
| `sensor.marstek_venus_1_battery_power` | **measurement** | power |

**Conséquence.** Dans Home Assistant, une entité exclue du recorder **ne génère plus de statistiques long terme**. Exclure un capteur `measurement`, c'est donc perdre aussi ses agrégats 5 min et horaires — pas seulement son historique brut.

Sur 331 capteurs : **212 portent un `state_class`** (à ne pas exclure sans décision explicite) et **119 n'en portent pas** (exclusion sans aucune perte statistique).

---

## 2. Mesures — écritures réelles sur 1 heure

### 2.1 Palier 1 — sans `state_class` : exclusion sans aucune perte

| Entité | Lignes / h | Lignes / jour |
|---|---|---|
| `sensor.energie_marge_preparation_vocale` | **1 459** | **35 016** |
| `sensor.ecart_relatif_solaire_opendtu_shelly` | **982** | **23 568** |
| `sensor.onduler_2_tx_requests` | 361 | 8 664 |
| `sensor.onduler_2_rx_success` | 351 | 8 424 |
| `sensor.onduleur1_efficiency` | 310 | 7 440 |
| `sensor.onduler_2_rssi` | 307 | 7 368 |
| `sensor.onduler_2_efficiency` | 306 | 7 344 |
| `sensor.onduler_2_rx_fail_receive_nothing` | 11 | 264 |
| **Total palier 1** | **4 087** | **98 088** |

**Les deux premières entités n'avaient été repérées dans aucun des deux audits.** À elles seules, elles pèsent **58 584 lignes/jour** — davantage que les deux capteurs réseau rapides réunis, et leur exclusion ne coûte strictement rien.

Les cinq entités `onduler_2_*` sont les **jumelles oubliées** de l'exclusion existante (§1.1) : les ajouter ne fait que rendre cohérent ce qui a déjà été décidé pour l'onduleur 1.

### 2.2 Palier 2 — avec `state_class: measurement` : arbitrage requis

| Entité | Lignes / h | Lignes / jour | Recommandation |
|---|---|---|---|
| `sensor.shelly_reseau_rapide_mqtt` | 1 779 | 42 696 | **Conserver** — référence statistique de la puissance réseau |
| `sensor.reseau_omnibattery_hybride` | 1 779 | 42 696 | **Exclure** — voir §2.3 |
| `sensor.omnibattery_home_consumption` | 1 037 | 24 888 | Conserver (consommation maison, valeur analytique réelle) |
| `sensor.opendtu_528ecc_ac_power` | 595 | 14 280 | **Conserver** — production PV, cœur du suivi énergie |
| `sensor.reseau_lisse_30_s` | 452 | 10 848 | Conserver dans un premier temps |
| `sensor.shellyproem50_..._puissance` | 452 | 10 848 | **Conserver** — mesure canonique de l'appareil |
| `sensor.marstek_venus_1_battery_power` | 430 | 10 320 | Conserver (flux batterie) |

### 2.3 Le seul cas du palier 2 qui se tranche sans perte réelle

`sensor.reseau_omnibattery_hybride` et `sensor.shelly_reseau_rapide_mqtt` présentent sur la fenêtre mesurée :

- un **nombre de lignes rigoureusement identique** : 1 779 chacune ;
- des **valeurs identiques** aux mêmes instants (`114.0` / `114` à 13:42:47.831 et 13:42:47.826, soit 5 ms d'écart) ;
- la **même grandeur physique**, la même unité et le même `device_class`.

L'hybride est un **pass-through** de la source MQTT tant que celle-ci est fraîche. Ses statistiques sont donc **redondantes** avec celles de `shelly_reseau_rapide_mqtt`, qui reste enregistrée. Son exclusion ne fait perdre aucune information réelle.

⚠️ **Nuance à connaître :** l'hybride bascule sur la source Shelly lente en cas de perte du MQTT. Dans ce cas de repli, son historique différerait de celui du MQTT. Cette divergence ne se produit **que pendant une panne** — période pour laquelle l'automatisation d'alerte (`energie_alertes_mesure_reseau_et_compensation_import`) produit déjà une trace horodatée. La perte est donc acceptable, mais elle doit être un choix conscient.

### 2.4 Entités vérifiées et écartées (volume négligeable)

Mesurées à **1 ligne/h ou moins** sur la fenêtre — aucune exclusion justifiée :
`sensor.marstek_venus_1_battery_soc` · `sensor.disjoncteur_chauffe_eau_puissance_2` · `sensor.omnibattery_daily_operation_timeline` · `sensor.omnibattery_pd_control_quality` · `sensor.marstek_venus_1_delta_trend` · `sensor.omnibattery_expected_home_consumption_profile` · `sensor.onduleur1_ch1_irradiation`

> `sensor.omnibattery_daily_operation_timeline` figurait dans la liste proposée par l'audit du 21/09. **La mesure l'écarte : 1 ligne/h.** Son problème est une latence de mise à jour de 0,726 s (constat L6), pas un volume d'écriture.

---

## 3. Bilan du correctif proposé

| | Lignes / jour |
|---|---|
| Palier 1 — zéro risque | **98 088** |
| Palier 2 — `reseau_omnibattery_hybride` seul | **42 696** |
| **Total retiré** | **≈ 140 800** |

Les 12 entités les plus bavardes mesurées totalisent ≈ 240 000 lignes/jour ; le correctif en retire **≈ 59 %**.

⚠️ **Ne pas convertir ce chiffre en MiB avant mesure.** Le poids d'une ligne varie selon la longueur de l'état et des attributs. Référence actuelle : **1 547,84 MiB**, croissance ≈ **155 MiB/jour**. L'effet réel se constate après application (§5).

---

## 4. YAML — bloc minimal à FUSIONNER

> ⚠️ **NE PAS COLLER TEL QUEL.** Ouvrir `configuration.yaml`, localiser le bloc `recorder:` existant (§1.1), et **ajouter uniquement les entrées manquantes dans son `exclude: entities:` existant.** Ne pas créer un second bloc `recorder:` ni un second `exclude:`.

```yaml
# À FUSIONNER dans le bloc recorder: existant.
# Conserver toutes les entrées déjà présentes — notamment les exclusions
# onduleur1_* et opendtu_528ecc_* détectées au §1.1.
recorder:
  exclude:
    entities:
      # ── Palier 1 : sans state_class, aucune perte statistique ──
      - sensor.energie_marge_preparation_vocale          # 35 016 lignes/jour
      - sensor.ecart_relatif_solaire_opendtu_shelly      # 23 568 lignes/jour
      # Jumelles oubliées de l'exclusion existante (nommage onduler_2 ≠ onduleur1)
      - sensor.onduler_2_tx_requests                     #  8 664
      - sensor.onduler_2_rx_success                      #  8 424
      - sensor.onduler_2_rssi                            #  7 368
      - sensor.onduler_2_efficiency                      #  7 344
      - sensor.onduler_2_rx_fail_receive_nothing         #    264
      - sensor.onduleur1_efficiency                      #  7 440
      # ── Palier 2 : doublon exact, statistiques redondantes (§2.3) ──
      - sensor.reseau_omnibattery_hybride                # 42 696
```

**Sur `purge_keep_days` et `commit_interval` :** ne rien écrire. Les audits suggéraient `purge_keep_days: 10` et `commit_interval: 5`. La valeur 10 correspond **déjà** au comportement observé (plus ancienne exécution enregistrée le 11/09 pour une mesure au 21/09) — et il s'agit du défaut de Home Assistant. **Réécrire une valeur déjà en vigueur n'apporte rien et risque d'écraser un réglage volontaire.** Ne les ajouter que si le bloc existant ne les définit pas et qu'un changement est voulu.

**Sur les globs :** les audits proposaient `sensor.onduleur1_*_tx_*` et `sensor.onduler_2_*_tx_*`. **Écartés au profit d'une liste explicite** : la mesure montre que certaines entités du même préfixe doivent rester enregistrées (`onduleur1_tx_re_request_fragment`, 21 lignes/h, utile au diagnostic radio). Un glob les emporterait toutes.

---

## 5. Procédure d'application

**Prérequis — dans cet ordre :**

1. **Sauvegarde complète AVEC base de données.** Les sauvegardes existantes sont à 33 sur 36 sans base. Une exclusion ne supprime pas l'historique passé, mais une erreur de syntaxe dans `configuration.yaml` empêche le démarrage.
   ```
   ha_manage_backup(scope="snapshot", action="create",
                    name="Avant_exclusions_recorder_20260921")
   ```
   ⚠️ La création par défaut est **config seule**. Pour inclure la base, passer par **Paramètres → Système → Sauvegardes** dans l'interface.

2. **Lire le bloc `recorder:` existant** via File editor (installé, démarré) ou Terminal & SSH (installé, en ingress). Relever son contenu exact avant toute modification.

3. **Fusionner** les entrées du §4 dans l'`exclude: entities:` existant.

4. **Valider la syntaxe** : Outils de développement → YAML → **Vérifier la configuration**. Ne pas redémarrer avant un retour valide.

5. **Redémarrer Home Assistant.**

**Vérification après redémarrage :**

| Contrôle | Attendu |
|---|---|
| Les 9 entités exclues sont toujours présentes et à jour dans l'UI | ✅ — l'exclusion ne touche que l'archivage |
| `binary_sensor.energie_capteurs_critiques_valides` | `on` |
| `sensor.reseau_omnibattery_hybride` | numérique (l'automatisation de sécurité s'en sert) |
| `number.omnibattery_system_max_discharge_power` | `> 0` |
| Tableau de bord Énergie | inchangé |
| Historique des entités exclues | plus de nouveaux points — **normal** |

**Mesure de l'effet, à J+2 puis J+7 :**
```
ha_get_system_health()  →  recorder.estimated_db_size
```
Référence de départ : **1 547,84 MiB**, ≈155 MiB/jour. Une baisse nette du rythme quotidien doit être visible dès 48 h.

**Rollback :** retirer les lignes ajoutées et redémarrer. L'historique déjà enregistré n'est pas affecté ; seuls les points non collectés pendant la période d'exclusion manqueront.

---

## 6. Traitement de la cause racine — alternative supérieure à l'exclusion

Le volume de `sensor.reseau_omnibattery_hybride` n'est pas intrinsèque : il est **produit** par l'automatisation `energie_rafraichir_fraicheur_mesure_omnibattery`, qui appelle `homeassistant.update_entity` toutes les **2 secondes** (43 200 exécutions/jour) pour forcer la réévaluation du template.

Remplacer ce mécanisme par un **capteur template déclenché** supprime l'automatisation **et** réduit la cadence, sans exclusion ni perte statistique :

```yaml
# Exemple — NON appliqué. Supprime le besoin de update_entity forcé.
template:
  - trigger:
      - trigger: time_pattern
        seconds: "/5"
      - trigger: state
        entity_id: sensor.shelly_reseau_rapide_mqtt
    sensor:
      - name: Réseau OmniBattery hybride
        # … logique de fraîcheur existante, inchangée …
```

Effet attendu : cadence divisée par ~2,5 (1 779 → ~720 lignes/h), une automatisation à 2 s supprimée, statistiques conservées.

⚠️ **Ce changement modifie une entité au cœur de la chaîne énergétique** (5 automatisations en dépendent, dont le repli de sécurité). Il relève du plan à 30 jours, pas d'un correctif immédiat, et exige de vérifier que l'`entity_id` reste identique après migration. **Le correctif du §4 reste la bonne action de court terme.**

---

## 7. Limites de cette préparation

| Élément | Statut |
|---|---|
| Contenu réel du bloc `recorder:` | **Non lu** — aucun outil YAML dans ce serveur MCP. Son existence est établie par mesure (§1.1), pas sa forme |
| Présence éventuelle d'un `include:` | Non vérifiable — un `include:` rendrait l'`exclude:` inopérant |
| Exhaustivité des exclusions existantes | Partielle : 7 entités confirmées exclues, d'autres possibles |
| Périmètre de mesure | 33 entités sur 716, ciblées sur les familles suspectées. Un balayage complet des 331 capteurs révélerait probablement d'autres cas comparables à `energie_marge_preparation_vocale` |
| Représentativité de la fenêtre | 1 heure en journée, production PV active (598 W). La nuit, les capteurs solaires se taisent : le volume réel sur 24 h est inférieur à l'extrapolation ×24 pour les entités liées au PV. **Les chiffres « par jour » de ce document sont donc des majorants** pour `onduler_2_*`, `onduleur1_efficiency` et `ecart_relatif_solaire_opendtu_shelly` |

**Non couvert et recommandé en complément :** balayage des 331 capteurs pour identifier tout autre cas à fort volume sans `state_class`, sur une fenêtre de 24 h plutôt que d'1 h.

---

## 8. État à l'issue de cette préparation

- **Aucune exclusion appliquée.** Aucun redémarrage effectué.
- **C1 (serveur MCP) reste gelé** — conformément à la séquence validée : ne rien modifier avant qu'un accès authentifié ait été créé et testé.
- **Identifiants MQTT inchangés.**
- Dernières écritures effectuées sur l'installation : les deux corrections du 21/09 (décalage du déclencheur de l'orchestrateur, rétention de traces), précédées de la sauvegarde `cf525952`.

---

*Préparé le 21 septembre 2026. Toutes les valeurs de ce document proviennent de mesures directes horodatées, non d'estimations. Aucune valeur de secret n'y est reproduite.*

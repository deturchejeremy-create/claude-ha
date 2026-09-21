# Diff Recorder proposé — 10 entrées

**Date :** 21 septembre 2026
**Statut :** **proposition. Rien n'a été écrit dans Home Assistant.** Aucune exclusion posée, aucun redémarrage, Recorder inchangé.
**Base de mesure :** audit 24 h sur **331/331 capteurs** (`AUDIT_RECORDER_331_CAPTEURS_2026-09-21.md`)

> Ce diff n'est **pas applicable en l'état**. Il ne pourra l'être qu'après lecture du bloc `recorder:` réel (§4). Toute entrée ci-dessous doit être **fusionnée** dans la configuration existante, jamais collée en bloc.

---

## 1. Périmètre retenu

**Seuil appliqué : > 1 000 lignes/24 h.** Dix entrées satisfont les quatre critères cumulatifs :

| Critère | Vérification |
|---|---|
| **(a)** Aucun `state_class` | Aucune perte de statistiques long terme |
| **(b)** Aucune référence | Automatisations, scripts, scènes, helpers, dashboards |
| **(c)** N'alimente aucun helper `statistics` | L'intégration `statistics` s'amorce depuis la base du Recorder |
| **(d)** Volume mesuré significatif | > 1 000 lignes sur 24 h réelles |

**Résultat : 10 entrées, ≈ 89 700 lignes/jour.** C'est **96 % du gain atteignable** pour un tiers des lignes de configuration qu'exigerait la liste exhaustive (§3).

---

## 2. Le diff, entrée par entrée

Chaque entrée précise le volume observé, ses dépendances, l'historique perdu et la règle Recorder applicable.

---

### 1. `sensor.energie_marge_preparation_vocale`

```diff
   recorder:
     exclude:
       entities:
         # … entrées existantes conservées …
+        - sensor.energie_marge_preparation_vocale
```

| | |
|---|---|
| **Volume 24 h** | **28 964 lignes** — 1ʳᵉ du diff, 3ᵉ de l'installation |
| **`state_class`** | aucun |
| **Dépendances** | `script.preparer_airfryer`, `script.preparer_lave_vaisselle`, `script.preparer_machine_a_laver`, `script.preparer_tele` — les 4 via `condition: numeric_state` et `wait_for_trigger` sur l'**état vivant** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | La marge de puissance instantanée pendant les préparations vocales. Valeur dérivée, recalculée en continu à partir de la consommation et de la réserve ; aucune analyse a posteriori ne s'y appuie |
| **Impact fonctionnel** | **Nul.** L'exclusion ne porte que sur l'archivage : l'entité conserve son état vivant, les 4 scripts continuent de fonctionner à l'identique |
| **Règle Recorder** | `exclude.entities` — liste explicite |

---

### 2. `sensor.energie_hausse_charge_vocale`

```diff
+        - sensor.energie_hausse_charge_vocale
```

| | |
|---|---|
| **Volume 24 h** | **23 906 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | `automation.solaire_p1_orchestration_30s` — branche de détection de charge vocale, sur l'état vivant |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | La hausse de consommation détectée pendant une préparation. Même nature que l'entrée 1 : indicateur instantané de détection, sans usage rétrospectif |
| **Impact fonctionnel** | **Nul** |
| **Règle Recorder** | `exclude.entities` |

---

### 3. `sensor.onduler_2_tx_requests`

```diff
+        - sensor.onduler_2_tx_requests
```

| | |
|---|---|
| **Volume 24 h** | **10 922 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Compteur de requêtes radio émises vers le micro-onduleur 2. **Sa jumelle `sensor.onduleur1_tx_requests` n'est déjà pas enregistrée** (0 ligne/24 h) : l'historique correspondant n'existe déjà pas pour l'onduleur 1 |
| **Impact fonctionnel** | **Nul.** Aligne le traitement des deux onduleurs |
| **Règle Recorder** | `exclude.entities`. ⚠️ **Ne pas utiliser de glob** : `sensor.onduler_2_tx_*` emporterait `tx_re_request_fragment` (368 lignes/24 h), utile au diagnostic radio et à conserver |

---

### 4. `sensor.onduler_2_rx_fail_receive_nothing`

```diff
+        - sensor.onduler_2_rx_fail_receive_nothing
```

| | |
|---|---|
| **Volume 24 h** | **7 656 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Compteur d'échecs de réception radio. **Jumelle `onduleur1_rx_fail_receive_nothing` déjà non enregistrée.** Le compteur cumulé reste lisible en temps réel sur l'entité |
| **Impact fonctionnel** | **Nul** |
| **Règle Recorder** | `exclude.entities`. ⚠️ Un glob `rx_fail_*` emporterait `rx_fail_receive_partial` (28) et `rx_fail_receive_corrupt` (9), qui signalent une dégradation de qualité radio — à conserver |
| **Note** | C'est l'entité qui avait été sous-estimée d'un facteur 29 par extrapolation horaire. Elle fonctionne par salves |

---

### 5. `sensor.opendtu_528ecc_largest_free_heap_block`

```diff
+        - sensor.opendtu_528ecc_largest_free_heap_block
```

| | |
|---|---|
| **Volume 24 h** | **4 095 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Fragmentation mémoire de l'ESP32 OpenDTU. **`heap_free` et `heap_size`, de la même famille, ne sont déjà pas enregistrés.** Cette entité est le seul diagnostic mémoire encore archivé — l'exclure achève un choix déjà fait |
| **Impact fonctionnel** | **Nul.** Diagnostic matériel bas niveau, sans usage domotique |
| **Règle Recorder** | `exclude.entities`. ⚠️ Pas de glob `opendtu_528ecc_*` : il emporterait `ac_power` (6 768), `dc_power` (6 564), `yield_day`/`yield_total` (4 290) et `temperature` (8 193), tous essentiels |

---

### 6. `sensor.onduleur1_efficiency`

```diff
+        - sensor.onduleur1_efficiency
```

| | |
|---|---|
| **Volume 24 h** | **4 078 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Rendement instantané de conversion DC→AC de l'onduleur 1, oscillant autour de 95 %. Le rendement réel est reconstituable à tout moment à partir de `onduleur1_power` (4 058) et `onduleur1_powerdc` (3 915), **tous deux conservés** |
| **Impact fonctionnel** | **Nul** — la donnée reste calculable |
| **Règle Recorder** | `exclude.entities` |

---

### 7. `sensor.onduler_2_rx_success`

```diff
+        - sensor.onduler_2_rx_success
```

| | |
|---|---|
| **Volume 24 h** | **3 423 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Compteur de réceptions radio réussies. **Jumelle `onduleur1_rx_success` déjà non enregistrée** |
| **Impact fonctionnel** | **Nul** |
| **Règle Recorder** | `exclude.entities` |

---

### 8. `sensor.onduler_2_efficiency`

```diff
+        - sensor.onduler_2_efficiency
```

| | |
|---|---|
| **Volume 24 h** | **3 142 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** — vérifié explicitement, 0 résultat sur automatisations, scripts, scènes, helpers et dashboards |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Symétrique de l'entrée 6. Reconstituable depuis `onduler_2_power` (3 141) et `onduler_2_powerdc` (3 081), conservés |
| **Impact fonctionnel** | **Nul** |
| **Règle Recorder** | `exclude.entities` |

---

### 9. `sensor.onduler_2_rssi`

```diff
+        - sensor.onduler_2_rssi
```

| | |
|---|---|
| **Volume 24 h** | **2 099 lignes** |
| **`state_class`** | aucun (mais `device_class: signal_strength`) |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Puissance du signal radio 868 MHz vers l'onduleur 2. **Jumelle `onduleur1_rssi` déjà non enregistrée.** ⚠️ **Seule entrée du diff dont l'historique aurait une valeur diagnostique réelle** : une dégradation progressive du RSSI annonce une perte de liaison. Contrepartie : `rx_fail_receive_partial`, `rx_fail_receive_corrupt` et `tx_re_request_fragment` restent enregistrés et signalent la même dégradation par leurs compteurs d'erreur |
| **Impact fonctionnel** | **Nul**, mais c'est l'entrée à retirer en premier si l'on veut un diff encore plus conservateur |
| **Règle Recorder** | `exclude.entities` |

---

### 10. `sensor.dudditz746284_status`

```diff
+        - sensor.dudditz746284_status
```

| | |
|---|---|
| **Volume 24 h** | **1 394 lignes** |
| **`state_class`** | aucun |
| **Dépendances** | **aucune** |
| **Helper `statistics`** | non |
| **Dashboards** | aucun |
| **Historique perdu** | Statut du compte Xbox. Valeur actuelle : `Last seen 2d ago: Home`. 1 394 réécritures/jour d'une chaîne qui n'évolue pas réellement — l'intégration Xbox réécrit son horodatage relatif |
| **Impact fonctionnel** | **Nul** |
| **Règle Recorder** | `exclude.entities` |
| **Note** | L'intégration Xbox cumule 34 erreurs de connexion sur la fenêtre (`Failed to connect to Xbox Network`). **Si elle est peu utilisée, la désactiver règle ce cas et une dizaine d'autres d'un coup** — voir §3 |

---

## 3. Écartés délibérément

### 3.1 Volume insuffisant pour justifier une ligne de configuration

| Entités | Volume cumulé | Motif |
|---|---|---|
| `onduler_2_ch1→ch4_irradiation` (4) | 1 800 | 450/jour chacune — 4 lignes de config pour 2 % du gain |
| `onduleur1_ch1→ch4_irradiation` (4) | 642 | 160/jour chacune |
| Grappe Xbox restante (9) | ≈ 536 | 49/jour chacune. **Désactiver l'intégration Xbox est le bon geste, pas 9 exclusions** |
| `onduler_2_tx_re_request_fragment` | 368 | Diagnostic radio utile |
| `onduleur1_tx_re_request_fragment` | 225 | Idem |
| `bbox_ip_externe` | 193 | ⚠️ **À investiguer plutôt qu'à exclure** : une IP externe ne devrait pas changer 193 fois par jour. Symptôme probable d'un capteur qui oscille, ou d'une instabilité de la liaison montante — cohérent avec la migration réseau Huawei B525 du 09/09 |

**Total écarté : ≈ 3 800 lignes/jour pour 20 lignes de configuration.** Mauvais rapport.

### 3.2 Écartés pour cause de dépendance

| Entité | Volume 24 h | Motif du refus |
|---|---|---|
| `sensor.reseau_omnibattery_hybride` | 43 290 | **Les 821 lignes d'écart avec la source MQTT sont les bascules en mode dégradé** — l'historique le plus utile au diagnostic, enregistré nulle part ailleurs |
| `sensor.ecart_relatif_solaire_opendtu_shelly` | 9 960 | **Source du helper `statistics` « Écart relatif solaire moyen 24 h »** (`sampling_size: 10 000`, `max_age: 24 h`), qui s'amorce depuis la base du Recorder |
| `sensor.ecart_solaire_opendtu_shelly` | 14 439 | **Source du helper `statistics` « Écart solaire moyen 5 min »** |
| `sensor.temperature_interieure_reference` | 32 | Source du helper `statistics` « Température intérieure moyenne 24 h » |
| Tous les `total` / `total_increasing` | — | Alimentent le tableau de bord Énergie |
| `opendtu_528ecc_temperature` | **8 193** | `state_class: measurement` ; température d'onduleur, valeur de surveillance matérielle réelle |
| `marstek_venus_1_min`/`max_cell_voltage` | 22 898 | `state_class: measurement`. **Décision à prendre à part** — ferait perdre le diagnostic rétrospectif d'un déséquilibre de cellules |

---

## 4. Conditions préalables — aucune n'est levée à ce jour

| # | Condition | Statut |
|---|---|---|
| 1 | **Ouvrir le bloc `recorder:`** dans File editor et relever son contenu exact | ❌ **non fait** — aucun outil de lecture YAML dans le serveur MCP |
| 2 | **Vérifier l'absence d'un `include:`** | ❌ **non fait** — bloquant absolu : un `include:` rend tout `exclude:` inopérant et **invalide ce diff en entier** |
| 3 | Vérifier si les 10 entrées sont déjà présentes sous une autre forme (glob, domaine) | ❌ non fait |
| 4 | Relever `purge_keep_days` et `commit_interval` s'ils sont définis | ❌ non fait — **ne rien écrire les concernant** : la valeur 10 observée correspond au défaut |
| 5 | **Sauvegarde complète AVEC base de données** | ❌ non faite. Les sauvegardes actuelles sont à 33 sur 36 sans base. À créer via **Paramètres → Système → Sauvegardes** (la création par défaut est config seule) |
| 6 | **Validation YAML** : Outils de développement → YAML → Vérifier la configuration | — après fusion, avant redémarrage |

**Les 24 entités à 0 ligne sont un indice d'exclusions existantes, pas une preuve de leur configuration.** Zéro ligne établit qu'une entité n'est pas enregistrée ; cela n'établit ni le mécanisme (liste, glob, domaine, `include:` restrictif), ni même qu'il s'agisse du Recorder — une entité désactivée dans le registre produirait le même résultat.

---

## 5. Après application — quel indicateur suivre

⚠️ **Une exclusion ne réduit pas la taille du fichier SQLite, ni immédiatement ni à moyen terme.** Trois mécanismes distincts :

| Étape | Effet | Délai |
|---|---|---|
| Exclusion active | **Arrête les nouvelles écritures** | immédiat |
| Purge nocturne automatique | Supprime les lignes > `purge_keep_days` | ≈ 10 jours |
| `recorder.purge` + `repack: true` | **Seule opération qui rend l'espace au disque** (VACUUM) | manuel |

La purge nocturne **ne repacke pas** : elle libère des pages *à l'intérieur* du fichier, que SQLite réutilise ensuite. La taille reste stable. Conclure à l'échec de l'exclusion en regardant `estimated_db_size` à J+2 serait une erreur d'interprétation.

**Indicateur correct, dès J+1 :**
```
ha_get_history(entity_ids=[<les 10 entrées>], start_time="24h",
               significant_changes_only=False)
→ chaque total_count doit valoir 0
```
Puis le total des 331 capteurs doit avoir baissé d'**environ 89 700 lignes/jour**.

**Taille du fichier :** attendre ≥ 10 jours, puis déclencher explicitement `recorder.purge` avec `repack: true`. Le repack exige temporairement ~1,5 Go libres ; le disque en compte 102 Go.

**Rollback :** retirer les 10 lignes et redémarrer. L'historique déjà enregistré n'est pas affecté ; seuls les points non collectés pendant la période d'exclusion manqueront.

---

## 6. Traitement de la cause racine — hors de ce diff

Les deux plus gros volumes de l'installation ne relèvent **pas** de l'exclusion :

| Entité | Volume 24 h | Traitement |
|---|---|---|
| `reseau_omnibattery_hybride` | 43 290 | Produit par `energie_rafraichir_fraicheur_mesure_omnibattery` (`update_entity` toutes les **2 s**, 43 200 exécutions/jour). Un **capteur template déclenché** (`time_pattern seconds: "/5"` + déclencheur d'état sur la source) réduirait la cadence de ~60 % **sans exclusion et sans perte d'historique** |
| `shelly_reseau_rapide_mqtt` | 42 469 | Cadence native du script embarqué Shelly. Modifiable côté appareil si 2 s s'avère plus fin que nécessaire |

**Gain potentiel ≈ 26 000 lignes/jour sur le seul hybride, sans rien exclure.** C'est le meilleur rapport gain/risque de tout le dossier, mais il touche une entité au cœur de la chaîne énergétique (5 automatisations en dépendent, dont le repli de sécurité) et exige de vérifier que l'`entity_id` reste identique après migration. **Plan à 30 jours, pas correctif immédiat.**

---

## 7. État de l'installation

- **Aucune exclusion appliquée. Aucun redémarrage. Recorder inchangé.**
- **C1 (serveur MCP) gelé** — rien ne bouge avant qu'un accès authentifié ait été créé et testé par une requête de lecture.
- **Identifiants MQTT inchangés.**
- Dernières écritures sur l'installation : les deux corrections du 21/09 (décalage du déclencheur de l'orchestrateur à :15/:45, rétention de traces portée à 50), précédées de la sauvegarde `cf525952`.

---

*Diff préparé le 21 septembre 2026 à partir de comptages directs sur 24 h pleines, couverture 331/331 capteurs. Non applicable avant lecture du bloc `recorder:` réel. Aucune valeur de secret n'y est reproduite.*

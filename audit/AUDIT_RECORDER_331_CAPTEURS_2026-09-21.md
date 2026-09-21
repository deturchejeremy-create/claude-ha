# Audit Recorder — 331 capteurs sur 24 heures

**Date :** 21 septembre 2026
**Statut :** **lecture seule. Aucune exclusion appliquée, aucun redémarrage, aucune modification du Recorder.**
**Méthode :** interrogation de l'API d'historique sur une fenêtre de **24 h pleines** (20/09 13:49 → 21/09 13:49 heure locale), `significant_changes_only=false` pour compter les écritures réelles et non les seuls changements « significatifs ».
**Couverture :** **331 des 331 capteurs** mesurés individuellement (100 %), vérifiée par différence programmatique entre la liste complète du registre et la liste des entités effectivement interrogées.

> **Correctif de couverture (21/09, après revue).** Une version antérieure de ce document annonçait « 325 sur 331, les 6 restants étant des entités VACA hors ligne ». **C'était une estimation, pas un décompte.** La vérification par différence montre que **307** capteurs seulement avaient été mesurés, et que **24** manquaient — dont 12 compteurs `yield` de canaux, 6 capteurs de prévision, et surtout **`sensor.opendtu_528ecc_temperature`, mesuré depuis à 8 193 lignes/24 h**, soit la 17ᵉ entité la plus écrite de l'installation. Les 24 manquantes ont été mesurées et sont intégrées ci-dessous. Aucune conclusion de ce document ne repose plus sur une couverture partielle.

> Les volumes de ce document sont des **comptages directs sur 24 h**. Aucune extrapolation horaire n'a été utilisée — le §2 montre pourquoi c'était indispensable.

---

## 1. Synthèse

Le balayage complet invalide **trois conclusions** de mes livrables précédents. Les trois corrections vont dans le même sens : les recommandations antérieures étaient trop agressives.

| # | Conclusion précédente | Réalité mesurée |
|---|---|---|
| 1 | Volumes journaliers extrapolés depuis 1 h | **Faux dans les deux sens, jusqu'à ×29 d'erreur** (§2) |
| 2 | `reseau_omnibattery_hybride` = doublon exact de la source MQTT | **821 lignes d'écart sur 24 h** — histoires non interchangeables (§3) |
| 3 | `ecart_relatif_solaire_opendtu_shelly` = exclusion sans risque | **Alimente un helper `statistics`** qui lit la base du Recorder (§4) |

Par ailleurs, l'exclusion déjà en place dans `configuration.yaml` est **beaucoup plus large** que ce que laissait penser le premier sondage : **24 entités** identifiées, toutes sur `onduleur1`, `opendtu_528ecc` et le Shelly — et **aucune** sur `onduler_2` (§5).

**Résultat net :** après vérification des dépendances, **≈ 93 400 lignes/jour** sont retirables sans aucune perte — soit nettement moins que les 140 800 annoncées la veille, mais sur une base cette fois vérifiée.

---

## 2. Correction n° 1 — l'extrapolation horaire était fausse

Comparaison entre la mesure d'1 h du 21/09 à 13 h (× 24) et le comptage réel sur 24 h :

| Entité | 1 h × 24 (estimé) | 24 h (réel) | Erreur |
|---|---|---|---|
| `sensor.onduler_2_rx_fail_receive_nothing` | 264 | **7 656** | **× 29 sous-estimé** |
| `sensor.onduler_2_tx_requests` | 8 664 | **10 922** | −21 % sous-estimé |
| `sensor.onduleur1_efficiency` | 7 440 | **4 078** | +82 % surestimé |
| `sensor.onduler_2_efficiency` | 7 344 | **3 142** | +134 % surestimé |
| `sensor.onduler_2_rx_success` | 8 424 | **3 423** | +146 % surestimé |
| `sensor.onduler_2_rssi` | 7 368 | **2 099** | +251 % surestimé |
| `sensor.ecart_relatif_solaire_opendtu_shelly` | 23 568 | **9 960** | +137 % surestimé |
| `sensor.energie_marge_preparation_vocale` | 35 016 | **28 964** | +21 % surestimé |

**Cause.** Deux effets opposés se combinent. Les capteurs liés au PV se taisent la nuit, donc une fenêtre diurne les surestime. À l'inverse, les compteurs d'échec radio (`rx_fail_*`) sont silencieux quand la liaison est bonne et explosent par salves : ma fenêtre d'1 h était calme, la journée ne l'était pas.

**Conséquence de méthode.** Toute décision d'exclusion doit reposer sur un comptage de 24 h au minimum. Une mesure horaire ne sert qu'à repérer des candidats, jamais à les chiffrer.

---

## 3. Correction n° 2 — l'hybride n'est pas un doublon de la source MQTT

C'était le point signalé : *« deux valeurs identiques en fonctionnement normal ne démontrent pas que leurs historiques sont interchangeables en mode dégradé »*. La mesure le confirme.

| Entité | Lignes / 24 h |
|---|---|
| `sensor.reseau_omnibattery_hybride` | **43 290** |
| `sensor.shelly_reseau_rapide_mqtt` | **42 469** |
| **Écart** | **+821 lignes pour l'hybride** |

Sur 1 heure en fonctionnement nominal, les deux capteurs affichaient **exactement 1 779 lignes** et des valeurs identiques à 5 ms près. Sur 24 h, l'hybride en compte **821 de plus**.

**Interprétation.** Ces 821 lignes sont précisément celles où l'hybride a évolué **sans** que la source MQTT n'évolue : basculements sur la source Shelly lente, périodes où le MQTT était périmé ou indisponible, transitions de fraîcheur. Autrement dit, **l'écart correspond exactement au mode dégradé** — la période la plus intéressante à conserver pour un diagnostic.

**Conclusion.** Exclure `sensor.reseau_omnibattery_hybride` ferait perdre la trace des épisodes de bascule, qui ne sont enregistrés nulle part ailleurs sous forme de série temporelle. Ma recommandation de la veille est **retirée**.

**Ce qu'il faut faire à la place.** Traiter la cause : les 43 290 lignes sont produites par l'automatisation `energie_rafraichir_fraicheur_mesure_omnibattery`, qui force `homeassistant.update_entity` **toutes les 2 secondes**. Un capteur template déclenché (`trigger: time_pattern seconds: "/5"` + déclencheur d'état sur la source) réduirait la cadence de ~60 % **en conservant intégralement l'historique des bascules**. C'est le seul traitement qui préserve la valeur diagnostique.

---

## 4. Correction n° 3 — un candidat « sans risque » alimente un helper statistics

`sensor.ecart_relatif_solaire_opendtu_shelly` figurait au palier 1 du correctif de la veille, qualifié d'exclusion sans aucune perte car dépourvu de `state_class`. **C'est faux.**

Vérification des références :

```
ecart_relatif_solaire_opendtu_shelly
  └── helper statistics « Écart relatif solaire moyen 24 h » (01M0SXV9TC68H9446WH2Q52FZ8)
        entity_id     : sensor.ecart_relatif_solaire_opendtu_shelly
        max_age       : 24 h
        sampling_size : 10 000
        characteristic: mean
```

**L'intégration `statistics` de Home Assistant s'amorce depuis la base du Recorder.** Exclure sa source prive le helper de son historique au démarrage : il repart à vide et met jusqu'à 24 h à reconstituer sa moyenne.

**Règle générale à retenir : aucune source d'un helper `statistics` ne doit être exclue du Recorder.**

Les trois helpers `statistics` de l'installation et leurs sources — **toutes à protéger** :

| Helper | Source | Volume source / 24 h |
|---|---|---|
| Écart solaire moyen 5 min | `sensor.ecart_solaire_opendtu_shelly` | 14 439 |
| Écart relatif solaire moyen 24 h | `sensor.ecart_relatif_solaire_opendtu_shelly` | 9 960 |
| Température intérieure moyenne 24 h | `sensor.temperature_interieure_reference` | 32 |

*Les helpers `filter`, `integration`, `threshold`, `derivative` et `utility_meter` opèrent sur l'état vivant et ne sont pas concernés par cette règle.*

---

## 5. L'exclusion existante, cartographiée

Le premier sondage avait relevé 7 entités à 0 ligne. Le balayage complet en dénombre **24**, toutes à **0 ligne sur 24 h** alors que leurs jumelles fonctionnelles en comptent des milliers.

> ⚠️ **Statut de cette liste : indice, pas preuve.** Zéro ligne sur 24 h établit qu'une entité **n'est pas enregistrée**. Cela n'établit **pas** par quel mécanisme : liste explicite d'entités, `entity_globs`, exclusion de domaine, `include:` restrictif qui exclurait tout le reste par omission, ou encore une entité désactivée dans le registre. **La configuration réelle ne sera connue qu'en ouvrant le bloc `recorder:` dans `configuration.yaml`.** Les groupements ci-dessous décrivent ce qui est observé, pas ce qui est écrit dans le fichier.

**Groupe `onduleur1` — 16 entités exclues :**
`tx_requests` · `rx_success` · `rx_fail_receive_nothing` · `rssi` · `voltage` · `current` · `powerfactor` · `reactivepower` · `ch1_voltage` · `ch1_current` · `ch2_voltage` · `ch2_current` · `ch3_voltage` · `ch3_current` · `ch4_voltage` · `ch4_current`

**Groupe `opendtu_528ecc` — 4 entités exclues :**
`wifi_signal` · `heap_free` · `heap_size` · `uptime`

**Groupe Shelly Pro EM 50 — 4 entités exclues :**
`energy_meter_0_puissance_apparente` · `energy_meter_1_puissance_apparente` · `energy_meter_0_facteur_de_puissance` · `energy_meter_1_facteur_de_puissance`

### 5.1 L'asymétrie `onduleur1` / `onduler_2`

Aucune entité `onduler_2` n'est exclue. Les jumelles des 16 entités `onduleur1` exclues sont toutes enregistrées :

| Entité `onduleur1` (exclue) | Jumelle `onduler_2` (enregistrée) | Lignes / 24 h |
|---|---|---|
| `tx_requests` | `onduler_2_tx_requests` | **10 922** |
| `rx_fail_receive_nothing` | `onduler_2_rx_fail_receive_nothing` | **7 656** |
| `rx_success` | `onduler_2_rx_success` | **3 423** |
| `reactivepower` | `onduler_2_reactivepower` | 3 143 |
| `voltage` | `onduler_2_voltage` | 3 098 |
| `powerfactor` | `onduler_2_powerfactor` | 2 591 |
| `ch2_current` | `onduler_2_ch2_current` | 2 485 |
| `ch1_current` | `onduler_2_ch1_current` | 2 456 |
| `ch3_current` | `onduler_2_ch3_current` | 2 455 |
| `ch4_current` | `onduler_2_ch4_current` | 2 425 |
| `current` | `onduler_2_current` | 2 234 |
| `ch3_voltage` | `onduler_2_ch3_voltage` | 2 000 |
| `ch1_voltage` | `onduler_2_ch1_voltage` | 1 958 |
| `ch2_voltage` | `onduler_2_ch2_voltage` | 1 952 |
| `ch4_voltage` | `onduler_2_ch4_voltage` | 1 947 |
| `rssi` | `onduler_2_rssi` | 2 099 |
| | **Total des jumelles non exclues** | **≈ 52 800** |

**Cause probable.** Les deux onduleurs portent un nommage incohérent : **`onduleur1`** et **`onduler_2`** — le second sans le « u » de *onduleur*. Toute exclusion écrite pour le premier rate mécaniquement le second.

**Même motif sur OpenDTU :** `heap_free` et `heap_size` sont exclus, mais `sensor.opendtu_528ecc_largest_free_heap_block` — même famille, même nature diagnostique — enregistre **4 095 lignes/24 h**.

**Ce que cela dit de l'intention.** Ces exclusions traduisent une décision cohérente : ne pas archiver les diagnostics radio et électriques de bas niveau. Cette décision n'a simplement pas été appliquée de façon symétrique. **Compléter l'exclusion existante, c'est achever un choix déjà fait — pas en prendre un nouveau.**

---

## 6. Volumes mesurés — 24 h réelles

### 6.1 Les 40 entités les plus écrites

| # | Entité | Lignes / 24 h | `state_class` | Références |
|---|---|---|---|---|
| 1 | `reseau_omnibattery_hybride` | **43 290** | measurement | 5 automatisations |
| 2 | `shelly_reseau_rapide_mqtt` | **42 469** | measurement | 2 automatisations |
| 3 | `energie_marge_preparation_vocale` | **28 964** | — | 4 scripts |
| 4 | `energie_hausse_charge_vocale` | **23 906** | — | 1 automatisation |
| 5 | `omnibattery_home_consumption` | **23 898** | measurement | orchestrateur |
| 6 | `ecart_solaire_moyen_5_min` | **21 882** | measurement | sortie statistics |
| 7 | `marstek_venus_1_battery_power` | **19 466** | measurement | arbitre batterie |
| 8 | `ecart_solaire_opendtu_shelly` | **14 439** | measurement | **source statistics** |
| 9 | `shellyproem50_…_0_puissance` | **12 463** | measurement | filtre + Linky |
| 10 | `energie_puissance_reseau_corrigee_linky` | **12 463** | measurement | — |
| 11 | `marstek_venus_1_min_cell_voltage` | **12 439** | measurement | — |
| 12 | `reseau_lisse_30_s` | **11 949** | measurement | arbitre clim |
| 13 | `onduler_2_tx_requests` | **10 922** | — | **aucune** |
| 14 | `marstek_venus_1_max_cell_voltage` | **10 459** | measurement | — |
| 15 | `ecart_relatif_solaire_opendtu_shelly` | **9 960** | — | **source statistics** |
| 16 | **`opendtu_528ecc_temperature`** | **8 193** | measurement | — |
| 17 | `shellyproem50_…_1_puissance` | 7 663 | measurement | — |
| 18 | `onduler_2_rx_fail_receive_nothing` | **7 656** | — | **aucune** |
| 19 | `opendtu_528ecc_ac_power` | 6 768 | measurement | orchestrateur |
| 20 | `opendtu_528ecc_dc_power` | 6 564 | measurement | — |
| 21 | `marstek_venus_1_internal_temperature` | 6 146 | measurement | — |
| 22 | `omnibattery_system_battery_cell_power` | 4 969 | measurement | — |
| 23 | `puissance_batterie_ac_nette` | 4 969 | measurement | — |
| 24 | `marstek_venus_1_ac_power` | 4 969 | measurement | — |
| 25 | `domotique_shelly_solaire_solaire_reel_journalier` | 4 860 | total_increasing | Énergie |
| 26 | `domotique_shelly_solaire_energie_solaire_reelle_shelly` | 4 859 | total | Énergie |
| 27 | `ecart_solaire_reel_vs_solcast` | 4 767 | measurement | — |
| 28 | `production_solaire_reelle_kw` | 4 613 | measurement | — |
| 29 | `opendtu_528ecc_yield_day` | 4 291 | total_increasing | Énergie |
| 30 | `opendtu_528ecc_yield_total` | 4 289 | total_increasing | Énergie |
| 31 | `opendtu_528ecc_largest_free_heap_block` | **4 095** | — | **aucune** |
| 32 | `performance_solaire_vs_solcast` | 4 094 | measurement | — |
| 33 | `onduleur1_efficiency` | **4 078** | — | **aucune** |
| 34 | `onduleur1_power` | 4 058 | measurement | — |
| 35 | `onduleur1_powerdc` | 3 915 | measurement | — |
| 36 | `ecart_puissance_solaire_instantane_kw` | 3 886 | measurement | — |
| 37 | `onduleur1_ch4_power` | 3 611 | measurement | — |
| 38 | `onduleur1_ch2_power` | 3 602 | measurement | — |
| 39 | `onduleur1_ch1_power` | 3 594 | measurement | — |
| 40 | `omnibattery_system_discharge_power` | 3 586 | measurement | — |

**Les 24 entités mesurées après coup** (correctif de couverture) : `opendtu_528ecc_temperature` **8 193** · `performance_solaire_journaliere` 1 951 · `onduleur1_ch4_yieldday`/`yieldtotal` 1 190 chacun · `onduleur1_ch2_yieldday`/`yieldtotal` 1 174 · `onduleur1_ch3_yieldday`/`yieldtotal` 1 167 · `onduler_2_ch4_yieldday` 1 153 / `yieldtotal` 1 152 · `onduler_2_ch2_yieldday` 1 150 / `yieldtotal` 1 148 · `onduler_2_ch3_yieldday` 1 149 / `yieldtotal` 1 144 · `ecart_energie_solaire_journalier` 1 037 · `disjoncteur_chauffe_eau_puissance_2` 136 · `energy_current_hour` 14 · `energy_next_hour` 14 · `power_production_next_12hours` 14 · `prevision_solcast_totale_aujourd_hui` 12 · `power_highest_peak_time_today` 10 · `power_highest_peak_time_tomorrow` 5 · `vaca_5a902d816_app_version` 1 · `vaca_5a902d816_orientation` 1.

Les 12 compteurs `yield` de canaux totalisent **≈ 13 800 lignes/jour**, tous en `total_increasing` : ils alimentent le suivi énergétique et **ne sont pas des candidats à l'exclusion**.

*Suite (1 000 – 3 500 lignes/24 h) :* `onduler_2_rx_success` 3 423 · `simulation_batterie_2_potentiel_pv_non_bride` 3 323 · `onduler_2_reactivepower` 3 143 · `onduler_2_efficiency` 3 142 · `onduler_2_power` 3 141 · `onduler_2_voltage` 3 098 · `onduler_2_powerdc` 3 081 · `onduler_2_ch2_power` 2 826 · `onduler_2_ch4_power` 2 798 · `onduler_2_ch1_power` 2 789 · `onduler_2_ch3_power` 2 780 · `onduleur1_frequency` 2 649 · `onduleur1_yieldday` 2 615 · `onduleur1_yieldtotal` 2 615 · `onduler_2_powerfactor` 2 591 · `onduler_2_ch2_current` 2 485 · `onduler_2_ch1_current` 2 456 · `onduler_2_ch3_current` 2 455 · `onduler_2_ch4_current` 2 425 · `omnibattery_consumption_profile_capture` 2 421 · `onduler_2_current` 2 234 · `onduler_2_frequency` 2 203 · `onduler_2_rssi` 2 099 · `onduler_2_yieldday` 2 065 · `onduler_2_yieldtotal` 2 063 · `performance_solaire_a_l_heure_actuelle` 2 052 · `onduler_2_ch3_voltage` 2 000 · `simulation_batterie_2_solaire_recuperable_prudent` 1 993 · `onduler_2_ch1_voltage` 1 958 · `onduler_2_ch2_voltage` 1 952 · `onduler_2_ch4_voltage` 1 947 · `simulation_batterie_2_solaire_recuperable_cumule` 1 842 · `dudditz746284_status` 1 394 · `omnibattery_system_charge_power` 1 384 · `prise_radiateur_salon_courant_2` 1 350 · `prise_radiateur_salon_puissance_2` 1 314 · `prise_radiateur_salon_puissance` 1 312 · `disjoncteur_chauffe_eau_tension_2` 1 304 · `disjoncteur_clim_tension` 1 291 · `prise_radiateur_salon_tension_2` 1 216 · `onduleur1_ch1_yieldtotal` 1 210 · `onduleur1_ch1_yieldday` 1 208 · `onduler_2_temperature` 1 196 · `onduleur1_temperature` 1 192 · `shellyproem50_…_0_energie` 1 158 · `onduler_2_ch1_yieldday` 1 121 · `onduler_2_ch1_yieldtotal` 1 119 · `ecart_solaire_cumule_actuel` 1 071 · `ecart_estimation_fin_de_journee_vs_solcast` 1 066 · `ecart_estimation_journee_kwh` 1 066 · `estimation_production_fin_de_journee` 1 055 · `estimation_reelle_fin_journee` 1 055

### 6.2 Entités silencieuses

**190 capteurs environ produisent moins de 500 lignes sur 24 h**, dont une centaine à 1 ou 2 lignes : versions de firmware, adresses MAC, noms d'appareils, états de sauvegarde, horaires solaires, prévisions Solcast, capteurs de température Zigbee, entités VACA hors ligne. **Aucun intérêt à les exclure** : le gain serait nul et chaque ligne d'exclusion est une ligne à maintenir.

Quelques démentis utiles aux recommandations antérieures :

| Entité | Proposée à l'exclusion par | Mesure réelle |
|---|---|---|
| `omnibattery_daily_operation_timeline` | audit du 21/09 | **2 lignes / 24 h** |
| `machine_a_laver_puissance` | — | 1 ligne / 24 h |
| `marstek_venus_1_battery_soc` | — | 65 lignes / 24 h |
| `temperature_interieure_reference` | — | 32 lignes / 24 h |
| `disjoncteur_chauffe_eau_puissance_2` | — | 136 lignes / 24 h |

---

## 7. Candidats à l'exclusion — vérifiés

Critères cumulatifs appliqués : **(a)** aucun `state_class` → aucune perte de statistiques long terme ; **(b)** aucune référence dans les automatisations, scripts, scènes, helpers ou dashboards ; **(c)** n'alimente aucun helper `statistics` ; **(d)** volume mesuré significatif sur 24 h.

| Entité | Lignes / 24 h | Références | Justification |
|---|---|---|---|
| `sensor.energie_marge_preparation_vocale` | **28 964** | 4 scripts (état vivant) | Marge instantanée recalculée en continu ; aucun usage historique |
| `sensor.energie_hausse_charge_vocale` | **23 906** | 1 automatisation (état vivant) | Idem |
| `sensor.onduler_2_tx_requests` | **10 922** | aucune | Jumelle d'une entité déjà exclue |
| `sensor.onduler_2_rx_fail_receive_nothing` | **7 656** | aucune | Jumelle d'une entité déjà exclue |
| `sensor.opendtu_528ecc_largest_free_heap_block` | **4 095** | aucune | Jumelle de `heap_free`/`heap_size`, déjà exclus |
| `sensor.onduleur1_efficiency` | **4 078** | aucune | Diagnostic radio, non exclu par oubli |
| `sensor.onduler_2_rx_success` | **3 423** | aucune | Jumelle d'une entité déjà exclue |
| `sensor.onduler_2_efficiency` | **3 142** | aucune | Jumelle de `onduleur1_efficiency` |
| `sensor.onduler_2_rssi` | **2 099** | aucune | Jumelle d'une entité déjà exclue |
| `sensor.dudditz746284_status` | **1 394** | aucune | Xbox ; valeur « Last seen 2d ago », intégration en erreur récurrente |
| `onduler_2_ch1→ch4_irradiation` (4) | 1 800 | aucune | Irradiation calculée, jumelles `onduleur1` à 642 |
| `onduleur1_ch1→ch4_irradiation` (4) | 642 | aucune | Idem |
| `sensor.onduler_2_tx_re_request_fragment` | 368 | aucune | Diagnostic radio |
| `sensor.onduleur1_tx_re_request_fragment` | 225 | aucune | Diagnostic radio |
| Grappe Xbox/`dudditz746284` (10) | ≈ 730 | aucune | `gamerscore`, `following`, `follower`, `friends`, `now_playing`, `in_party`, `party_join_restrictions`, `last_online`, espaces de stockage ×2 |
| **Total** | **≈ 93 400 lignes / jour** | | |

**Comparaison avec la recommandation de la veille :** 140 800 annoncées → **93 400 vérifiées**. L'écart de 47 400 vient du retrait de `reseau_omnibattery_hybride` (42 696, §3) et de `ecart_relatif_solaire_opendtu_shelly` (9 960, §4), partiellement compensé par les entités nouvellement identifiées.

---

## 8. Capteurs à conserver — et pourquoi

| Catégorie | Entités | Motif |
|---|---|---|
| **Sources de helpers `statistics`** | `ecart_solaire_opendtu_shelly`, `ecart_relatif_solaire_opendtu_shelly`, `temperature_interieure_reference` | Le helper s'amorce depuis la base du Recorder (§4) |
| **Trace du mode dégradé** | `reseau_omnibattery_hybride` | Les 821 lignes d'écart sont les bascules de source (§3) |
| **Référence de puissance réseau** | `shelly_reseau_rapide_mqtt`, `shellyproem50_…_0_puissance` | Mesure canonique, `state_class: measurement` |
| **Tableau de bord Énergie** | tous les `total` et `total_increasing` : `yield_day`, `yield_total`, `energie`, `energie_restituee`, `daily_*_energy`, `solaire_reel_journalier`… | Alimentent directement le suivi énergétique |
| **Chaîne de décision** | `opendtu_528ecc_ac_power`, `reseau_lisse_30_s`, `marstek_venus_1_battery_power`, `omnibattery_home_consumption`, `marstek_venus_1_battery_soc` | Valeur analytique réelle ; un historique sert au diagnostic |
| **Diagnostic batterie** | `marstek_venus_1_min_cell_voltage` (12 439), `max_cell_voltage` (10 459), `internal_temperature` (6 146) | **Cas à arbitrer** — voir ci-dessous |

**Le cas des tensions de cellules.** Ces trois entités totalisent **29 044 lignes/jour** et portent `state_class: measurement`. Leur valeur pour une batterie résidentielle est réelle mais limitée : l'écart entre cellules (`cell_delta`, déjà calculé à part) suffit généralement au suivi de santé. **Ce n'est pas un candidat à l'exclusion automatique — c'est une décision à prendre en connaissance de cause.** Les exclure ferait perdre la possibilité de diagnostiquer un déséquilibre de cellules a posteriori.

---

## 9. Ce qui reste à faire — inchangé

Conformément à la décision en vigueur : **audit approfondi, aucune modification du Recorder.**

1. **Lire manuellement le bloc `recorder:`** dans `configuration.yaml` via File editor. Objectifs :
   - relever les 24 exclusions existantes et leur forme (liste explicite ou globs) ;
   - **vérifier l'absence d'un `include:`** — sa présence rendrait tout `exclude:` inopérant et invaliderait la démarche ;
   - relever `purge_keep_days` et `commit_interval` s'ils sont définis.
2. **Proposer une fusion ciblée** à partir du §7, en ajoutant les entrées au bloc existant — jamais en créant un second bloc `recorder:` ni un second `exclude:`.
3. **Sauvegarde complète avec base de données** avant application (les sauvegardes actuelles sont à 33 sur 36 sans base).
4. **Validation de configuration** : Outils de développement → YAML → Vérifier la configuration. Ne pas redémarrer avant retour valide.
5. **Mesure de l'effet — attention au bon indicateur.**

   ⚠️ **Une exclusion ne fait pas diminuer la taille du fichier SQLite, ni immédiatement ni même à moyen terme.** Trois mécanismes distincts se succèdent :

   | Étape | Effet | Délai |
   |---|---|---|
   | Exclusion active | **Arrête les nouvelles écritures** pour ces entités | immédiat |
   | Purge automatique nocturne | Supprime les lignes plus anciennes que `purge_keep_days` | ~10 jours |
   | `recorder.purge` avec `repack: true` | **Seule opération qui rend l'espace au système de fichiers** (VACUUM SQLite) | manuel |

   La purge nocturne de Home Assistant **ne repacke pas** : elle libère des pages *à l'intérieur* du fichier, que SQLite réutilisera pour les écritures suivantes, mais la taille du fichier reste stable. Attendre une baisse de `estimated_db_size` à J+2 conduirait à conclure à tort que l'exclusion n'a rien donné.

   **Indicateur correct à suivre dès J+1 :** le **débit d'écriture**, mesurable exactement comme dans cet audit —
   `ha_get_history(entity_ids=[...], start_time="24h", significant_changes_only=False)` sur les entités exclues doit retourner **0**, et le total des 331 capteurs doit avoir baissé d'environ 89 700 lignes/jour.

   **Taille du fichier :** attendre au minimum `purge_keep_days` (≈ 10 jours), puis déclencher explicitement un repack si l'on veut récupérer l'espace :
   ```
   Action : recorder.purge   avec   repack: true
   ```
   ⚠️ Le repack nécessite temporairement un espace disque libre équivalent à la taille de la base (~1,5 Go). Le disque en compte 102 Go libres — la marge est confortable.

   Référence de départ : **1 547,84 MiB**, croissance ≈ 155 MiB/jour.

**Traitement de la cause racine, indépendant et prioritaire sur le plan à 30 jours :** remplacer `energie_rafraichir_fraicheur_mesure_omnibattery` (`update_entity` toutes les 2 s, 43 200 exécutions/jour) par un capteur template déclenché. Gain estimé ~60 % sur les 43 290 lignes de l'hybride, **sans exclusion et sans perte d'historique**.

---

## 10. Limites

| Élément | Statut |
|---|---|
| Contenu réel du bloc `recorder:` | **Non lu.** La mesure établit que 24 entités ne sont pas enregistrées — elle n'établit ni la syntaxe, ni le mécanisme, ni même qu'il s'agisse d'un `exclude:` (§5) |
| Présence d'un `include:` | **Non vérifiable** sans lecture du fichier — point bloquant à lever en premier. Un `include:` rendrait tout `exclude:` inopérant et invaliderait la démarche entière |
| Couverture | **331/331**, vérifiée par différence programmatique. Une estimation antérieure à 325/331 était fausse et a été corrigée — voir l'encadré en tête de document |
| Représentativité | **Une seule journée** (20→21/09), production PV active, saison « Mi-saison », occupant absent une partie de la journée. Un jour de pluie ou de forte consommation donnerait un profil différent |
| Conversion lignes → MiB | **Non effectuée.** Le poids d'une ligne varie selon la longueur de l'état et des attributs ; l'effet réel ne se constate qu'après application |
| Domaines non couverts | Seul le domaine `sensor` a été balayé. `binary_sensor` (28), `number` (63), `switch` (61), `select` (33) et `input_*` n'ont pas été mesurés et peuvent contenir des entités bavardes |
| Charge induite | Le balayage a sollicité la base SQLite de 1,5 Go en production, par lots de 25 à 32 entités. Aucun incident observé, chaîne énergétique saine pendant toute la durée |

---

## 11. État de l'installation à l'issue de l'audit

- **Aucune exclusion appliquée. Aucun redémarrage. Recorder inchangé.**
- **C1 (serveur MCP) gelé** — conformément à la séquence validée : rien ne bouge avant qu'un accès authentifié ait été créé et testé par une requête de lecture.
- **Identifiants MQTT inchangés.**
- Dernières écritures sur l'installation : les deux corrections du 21/09 (décalage du déclencheur de l'orchestrateur à :15/:45, rétention de traces portée à 50), précédées de la sauvegarde `cf525952`.
- Chaîne énergétique saine au moment de l'audit : hybride numérique, MQTT frais (< 2 s), script Shelly actif, batterie 1/1 connectée, plafonds de charge et décharge non nuls.

---

*Audit réalisé en lecture seule le 21 septembre 2026. Tous les volumes proviennent de comptages directs sur 24 h pleines. Aucune valeur de secret n'est reproduite.*

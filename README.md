# claude-ha

## Claude Code : ECC (Everything Claude Code)

Ce dépôt active le plugin [ECC](https://github.com/affaan-m/ECC) (`ecc@ecc`) via
`.claude/settings.json`. Il est chargé automatiquement à l'ouverture d'une session
Claude Code dans ce dépôt, une fois le dossier approuvé (« trust »).

Installation manuelle si besoin :

```bash
claude plugin marketplace add https://github.com/affaan-m/ECC
claude plugin install ecc@ecc
```

Options du plugin (valeurs par défaut : hooks activés, profil `standard`) :

```
/plugin configure ecc@ecc
```

Remarque : ECC ajoute ~41 500 tokens de contexte permanent à chaque session.
Le profil de hooks `minimal` ou la désactivation des hooks permet de réduire
l'empreinte si nécessaire.

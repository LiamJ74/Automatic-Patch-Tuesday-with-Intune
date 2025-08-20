# Patch Tuesday Automation - Intune

## Objectif
Déployer les KB de Patch Tuesday de manière **granulaire** sur Windows 10/11 via Intune Win32 App.

## Arborescence complète

```
PatchTuesday-Intune/
│
├─ Scripts/
│   ├─ Generate-KBMap.ps1      # Script admin pour télécharger les MSU et générer kbmap.csv
│   └─ Install-KB.ps1          # Script client Intune pour installer le KB correspondant
│
├─ KBs/                        # MSU téléchargés ici par Generate-KBMap.ps1
├─ kbmap.csv                    # Généré automatiquement
├─ PatchTuesday.intunewin       # Package final Intune
└─ README.md                    # Instructions user-friendly
```


## Contenu du package
- `Install-KB.ps1` : script client qui installe le KB correspondant à la build
- `kbmap.csv` : mapping Build ↔ KB (généré automatiquement)
- `KBs/` : les fichiers MSU téléchargés
- `Generate-KBMap.ps1` : script admin pour télécharger les MSU et générer kbmap.csv

## Utilisation

### Administrateur
1. Mettre à jour la liste des builds dans `Generate-KBMap.ps1` chaque Patch Tuesday.
2. Exécuter `Generate-KBMap.ps1` pour télécharger les KB et générer `kbmap.csv`.
3. Packager le dossier avec `IntuneWinAppUtil.exe`.
4. Importer le `.intunewin` dans Intune et déployer aux groupes souhaités.

### Client (Intune)
- `Install-KB.ps1` détecte automatiquement la build du poste et installe le KB correspondant.
- Redémarrage automatique : non (`/norestart`) → permet contrôle via Intune si nécessaire.

## Packaging .intunewin
```
IntuneWinAppUtil.exe -c "PatchTuesday-Intune" -s Scripts\Install-KB.ps1 -o .
```

## Notes
- Compatible Windows 10 et Windows 11.
- kbmap.csv est généré automatiquement, pas besoin de remplir manuellement.
- Mettre à jour `Generate-KBMap.ps1` chaque Patch Tuesday pour ajouter les nouvelles builds/KB.

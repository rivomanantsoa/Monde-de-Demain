# Le Monde de Demain — app mobile (cours de Bible & brochures)

L'APK est une **coquille légère** : elle ne contient aucun contenu. Brochures et
cours sont téléchargés à la demande, dans la langue choisie au premier lancement,
puis lisibles **hors ligne**.

```
content_pipeline/          (à côté de ce dossier)
  build_content.py   site officiel + fichiers de cours  ->  out/ (packs compressés)
  courses/<lang>/…   leçons des cours en Markdown
  out/               à publier sur n'importe quel hébergement statique
flutter_application_1/     l'app
```

## Pourquoi c'est léger

| | PDF du site | Pack de l'app |
|---|---|---|
| 1 brochure | ~3,8 Mo | ~30 Ko |
| 42 brochures FR | ~160 Mo | 1,5 Mo |

- **Données** : le catalogue utilise des requêtes conditionnelles (ETag / Last-Modified) :
  s'il n'a pas changé, le serveur répond `304` sans contenu. Rien n'est téléchargé en arrière-plan.
  Les couvertures sont désactivées par défaut, et les images des brochures ne se chargent que si on les touche.
- **Stockage** : les packs restent compressés en gzip sur le téléphone. Seul ce que
  l'utilisateur a choisi est stocké. On peut supprimer élément par élément ou tout d'un coup.
- **APK** : aucune police ni image embarquée (polices système). Environ 8 Mo à télécharger
  depuis le Play Store, dont la majeure partie est le moteur Flutter.

## Publier / mettre à jour le contenu

```bash
cd content_pipeline
python3 build_content.py            # toutes les langues
python3 build_content.py --lang fr  # une seule langue
```

Envoyez ensuite le dossier `out/` sur un hébergement statique HTTPS (GitHub Pages,
Firebase Hosting, Netlify, serveur de l'organisation…). Quand un texte change, son
hash change et l'app propose « Mettre à jour » sans rien télécharger d'office.

- **Brochures** : le français est extrait de mondedemain.org. Pour les autres langues,
  il faut écrire un « adapter » dans `build_content.py`, car chaque site a sa propre structure.
- **Cours** : coursdebible.org exige une inscription. Les leçons s'ajoutent donc en
  Markdown dans `courses/<lang>/<cours>/` (voir `courses/README.md`).
  `courses/fr/exemple` n'est qu'un modèle à supprimer.
- **Langues** : la liste est dans `LANGUAGES` (build_content.py). L'app la relit
  depuis `out/index.json`, donc on peut ajouter une langue sans republier l'APK.
  Une langue sans contenu affiche « Le contenu arrive bientôt ».

## Lancer / compiler l'app

```bash
# Test local : servir le contenu
cd content_pipeline/out && python3 -m http.server 8000

# Téléphone branché en USB :
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=CONTENT_BASE_URL=http://localhost:8000/

# Émulateur : l'URL par défaut http://10.0.2.2:8000/ fonctionne directement
flutter run

# Production (HTTPS obligatoire en release) :
flutter build appbundle --dart-define=CONTENT_BASE_URL=https://votre-hebergement/mdd/
flutter build apk --split-per-abi --dart-define=CONTENT_BASE_URL=https://votre-hebergement/mdd/
```

## Avant publication

- Changer `applicationId` (`com.example.flutter_application_1`) dans `android/app/build.gradle.kts`.
- Configurer une vraie clé de signature (la release est actuellement signée en debug).
- Icône d'application.
- Obtenir l'autorisation de l'éditeur (Living Church of God / Le Monde de Demain) pour
  redistribuer les textes et utiliser le nom.

## Structure du code (`lib/`)

- `app_state.dart` : réglages, catalogue, téléchargements, cache, espace disque
- `models.dart` : formats des packs (clés courtes pour économiser des octets)
- `l10n.dart` : textes de l'interface (fr, en, es, de, nl, pt, ru, ar, sw)
- `screens/` : langue, accueil (Brochures / Cours / Hors ligne / Réglages), cours, lecteur, réglages
- `theme.dart` : rouge / noir / blanc, clair et sombre

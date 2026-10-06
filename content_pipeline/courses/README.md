# Cours de Bible — format des fichiers

Un dossier par langue, puis un dossier par cours :

```
courses/
  fr/
    cours-24-lecons/
      course.json      {"t": "Cours de Bible en 24 leçons", "s": "Description courte"}
      01.md            première ligne = "# Titre de la leçon"
      02.md
      ...
  en/
    ...
```

Markdown accepté : `## titre`, `### sous-titre`, `> citation`, `- puce`,
`1. liste numérotée`, `**gras**`, `*italique*`, ligne vide entre paragraphes.

Puis relancer `python3 build_content.py --lang fr`.
Le dossier `fr/exemple` est un modèle : supprimez-le une fois les vrais cours ajoutés.

# RELIC RUSH (Roblox)

Jeu de collection et de progression : détruis des trésors, ouvre des caisses, collectionne des reliques magiques qui flottent autour de toi, deviens le plus puissant et débloque 7 mondes.

## Ouvrir et tester
1. Ouvre `RelicRush.rbxlx` dans Roblox Studio, puis clique sur **Jouer**. Le monde se construit au démarrage, ce qui prend quelques secondes.
2. **Sauvegarde** : publie le jeu une fois (Fichier > Publier sur Roblox), puis active **Paramètres du jeu > Sécurité > Accès Studio aux services API**.
3. **Multijoueur** (échanges, boss à plusieurs) : onglet **Test > Clients et serveurs**, avec 2 joueurs ou plus.
4. Teste dans l'ordre des phases (voir `docs/PLAN.md`) et envoie les erreurs de la fenêtre **Sortie**.

## Icônes
- Les 12 icônes de la planche sont découpées automatiquement (`tools/build_icons.py`). Elles sont affichées sans upload grâce à EditableImage, comme dans Pet Rush.
- Pour une qualité maximale, tu peux uploader les PNG de `assets/icons/` et mettre leurs IDs dans `Icons.AssetIds` (`src/ReplicatedStorage/Shared/Icons.lua`).

## Commandes
- **Clic ou toucher sur un trésor ou un boss** : tes reliques l'attaquent.
- **Second clic** : tes reliques reviennent vers toi.
- **E** près d'une caisse, de la boutique, de la forge, de l'autel ou du tableau des quêtes : ouvre l'interface correspondante.
- **E** près d'un portail : voyage vers le monde, ou ouvre le menu Mondes s'il est verrouillé.

## Modifier
- Tout l'équilibrage se trouve dans `src/ReplicatedStorage/Shared/Config.lua` : raretés, mondes, reliques, caisses, trésors, améliorations, boutique, renaissance, boss, quêtes, récompenses quotidiennes.
- Après modification, reconstruis le fichier : `node build-place.js`. Tu peux aussi utiliser Rojo avec `default.project.json`.

# 🐾 PET RUSH – jeu Roblox

Collection de pets + courses. Les joueurs ouvrent des œufs, équipent leurs pets pour ramasser
des coins dans 3 zones, font évoluer leurs animaux (Golden → Rainbow → Cosmic) et les font
courir sur la piste du village.

## Boucle de jeu

Pet gratuit 🐱 → ramasser des 🪙 avec ses pets → ouvrir des 🥚 → débloquer 🌲 Forest puis
🏜️ Desert → évoluer 🧬 → gagner des courses 🏁 → compléter le 📖 Pet Index

## Contenu

- **19 pets**, 7 raretés : ⚪ Common, 🟢 Uncommon, 🔵 Rare, 🟣 Epic, 🟡 Legendary, 🔴 Mythical,
  🌈 Secret. Chaque pet a 4 stats : ⚡ Speed, 💪 Power, 🛡️ Stamina, 🍀 Luck.
- **3 zones** avec leur œuf exclusif, leurs coins et leur coffre :
  🏡 Starter Village (œuf 50) → 🌲 Forest (2 500 coins, œuf 600) → 🏜️ Desert (25 000 coins, œuf 6 000).
- **Collecte** : les pets équipés (3 max) suivent le joueur. Le rayon de collecte grandit avec
  le nombre de pets et les gains avec leur 💪 Power. La 🍀 Luck augmente les chances de
  raretés hautes dans les œufs.
- **Coffres rares** 🎁 : apparaissent aléatoirement dans une zone (annonce + rayon lumineux),
  le premier arrivé les ouvre.
- **Évolution** 🧬 : 3 exemplaires identiques → ✨ Golden (x2,5) → 🌈 Rainbow (x6) → 🌌 Cosmic (x15),
  avec nouvelle apparence et particules.
- **Courses de pets** 🏁 : stand au village, ⚡ Sprint (1 tour, la vitesse compte) ou
  🛡️ Marathon (3 tours, l'endurance compte). Lobby de 25 s, 4 coureurs, bots pour compléter,
  simulation avec Speed / Stamina / Luck, classement en direct, récompenses.
- **Pet Index** 📖, **cadeau du jour** 🎁 (500 coins + œuf gratuit toutes les 20 h),
  **classement** 📈 en jeu (top coins global).
- Sauvegarde DataStore (`PetRush_v1`), leaderstats Coins / Pets / RaceWins.

## Icônes et décor

- **Vraies icônes** : les 20 icônes de menu (PETS, EGGS, INDEX, WORLDS, RACE, DAILY,
  LEADERBOARD, CODES...) viennent de `assets/icon-sheet.webp`, plus 11 petites icônes
  dessinées dans le même style (pièce, stats, cadenas, gemme, fermer...). Toutes sont
  **intégrées au jeu** dans `IconData.lua` et affichées via `EditableImage` : aucun upload
  nécessaire pour les voir dans Studio.
- Si `EditableImage` n'est pas disponible (certaines expériences publiées), le jeu bascule
  sur des icônes vectorielles. Pour garantir les vraies images partout : importe le dossier
  `assets/icons/` avec **Asset Manager → Bulk Import**, puis colle chaque ID dans
  `Config.IconImages` (par ex. `pets = "rbxassetid://123"`).
- Pour changer les icônes : remplace `assets/icon-sheet.webp` (grille 5×4) ou les PNG, puis
  `python3 tools/build_icons.py` et `node build-place.js`.
- **Images des pets** : `assets/pet-sheet.webp` est découpée en 19 PNG transparents
  (`python3 tools/cut_pets.py`, qui retire aussi le damier dessiné), puis intégrée dans
  `PetImageData.lua`. Les pets s'affichent en image dans tous les menus et dans le monde
  (pets qui suivent le joueur, coureurs), avec teinte et étincelles selon l'évolution.
  Si l'image n'est pas disponible, le jeu affiche le modèle 3D à la place. Pour utiliser
  des images uploadées : `Config.PetImages.Chaton = "rbxassetid://..."`.
- **Décor en îles flottantes cartoon** : dessus d'herbe festonné, falaises de terre en escalier, cascades, ponts en bois entre les zones, mer et nuages en contrebas, étangs avec nénuphars,
  rendu lisse et coloré partout. Props cartoon : maisons à toit pointu, arbres ronds,
  sapins, palmiers, champignons, pyramides à degrés, fontaine, lampadaires, stands à auvent
  rayé, arches de pierre avec barrière magique, piste de course avec damier et tribunes.

## Contrôles

| Action | PC | Mobile |
| --- | --- | --- |
| Mes pets (équiper, évoluer, supprimer) | `P` ou bouton | bouton |
| Pet Index | `I` ou bouton | bouton |
| Mondes (débloquer / se téléporter) | `Z` ou bouton | bouton |
| Codes cadeaux (PETRUSH, LAUNCH, RACE) | bouton CODES | bouton |
| Courses | `R`, bouton ou stand 🏁 | bouton |
| Ouvrir un œuf | stand 🥚 de la zone (touche `E`) | bouton de l'invite |
| Débloquer une zone | porte dorée (maintenir `E`) ou menu Zones | idem |
| Cadeau du jour | stand 🎁 ou bouton CADEAU | idem |

## Installation

1. Télécharge `PetRush.rbxlx`.
2. Roblox Studio : **Fichier → Ouvrir depuis un fichier**.
3. **Jouer**. Map, coins, stands et interface sont générés par script.

Avec Rojo : `rojo serve default.project.json`. Régénérer le fichier : `node build-place.js`.

Après publication, active *Paramètres du jeu → Sécurité → Accès aux services API par Studio*
pour la sauvegarde et le classement global.

## Structure

```
src/
  ReplicatedStorage/Shared/
    Config.lua          Raretés, pets, œufs, zones, évolutions, courses (tout l'équilibrage)
    PetModel.lua        Modèles 3D des pets (8 formes) + stats effectives
    Remotes.lua
  ServerScriptService/Server/
    Main.server.lua
    Modules/
      MapBuilder.lua    3 zones, portes, stands, piste de course, classement, ambiance
      PetService.lua    Éclosion, équipement, évolution, index, zones, cadeau du jour
      CoinService.lua   Coins, collecte automatique par les pets, coffres rares
      RaceService.lua   Lobby, compte à rebours, simulation de course, récompenses
      DataService.lua   DataStore + leaderstats + OrderedDataStore
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.lua
    Modules/
      HUD.lua           Interface complète (pets, index, zones, œufs, courses, éclosion)
      PetFollow.lua     Pets qui suivent les joueurs (rendu local fluide)
      Effects.lua       Coins animés, particules, textes flottants, sons
      State.lua
```

## Ajouter un pet, un œuf ou une zone

Tout se fait dans `Config.lua` : ajoute une entrée dans `Pets` (icône, rareté, œuf, forme,
couleur, stats), dans `Eggs` et dans `Zones`. Les formes disponibles : `cat`, `dog`, `bunny`,
`bird`, `dragon`, `snake`, `bear`, `blob`.

## Idées pour la suite

Trading entre joueurs, quêtes quotidiennes, événements temporaires, skins de pets,
nouvelles zones (❄️ Ice World, 🌋 Volcano, 🌌 Space).

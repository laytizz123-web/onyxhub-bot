# WINDMAIL — Les Facteurs du Vent (Roblox)

Jeu Roblox original : tu es facteur dans un archipel, tu planes de falaise en falaise pour livrer des colis.
Le document de conception complet est dans [docs/GDD.md](docs/GDD.md).

## Ouvrir le jeu
1. Ouvre `Windmail.rbxlx` dans Roblox Studio (Fichier > Ouvrir).
2. Pour activer la sauvegarde en test : **Fichier > Paramètres du jeu > Sécurité > Activer l'accès Studio aux services API**.
   Il faut d'abord publier le jeu une fois (Fichier > Publier sur Roblox).
3. Clique sur **Jouer**. Le monde se construit au démarrage du serveur, ce qui prend quelques secondes.

## Commandes
| Action | PC | Mobile / manette |
|---|---|---|
| Ouvrir / fermer le planeur | Espace en l'air, ou Q | Bouton saut en l'air, ou bouton « Planer » / X |
| Diriger | Caméra (souris) | Caméra (glisser) |
| Piquer / remonter | Regarder vers le bas / le haut | Pareil |
| Élan (boost) | Shift | Bouton « Boost » / R2 |
| Prendre des colis / livrer | E près du guichet / de la boîte | Bouton à l'écran |

## Modifier le jeu
- **Équilibrage** (prix, vitesses, récompenses, événements) : `src/ReplicatedStorage/Shared/Config.lua`.
- **Après une modification**, reconstruis le fichier : `node build-place.js`. Tu peux aussi utiliser Rojo avec `default.project.json`.
- **Pour tester un événement tout de suite**, tape dans la barre de commande de Studio (côté serveur) :
  `require(game.ServerScriptService.Server.Modules.EventService).Force("Ballon")`

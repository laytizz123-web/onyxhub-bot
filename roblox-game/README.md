# ONYX FARM – jeu Roblox

Jeu de ferme dans le style des gros succès actuels (type *Grow a Garden*) :
chaque joueur reçoit sa **parcelle**, achète des **graines**, plante, arrose, récolte des
fruits au poids aléatoire avec des **mutations** rares, puis vend pour agrandir sa ferme.
La **météo dynamique** (pluie, orage avec éclairs, vague de froid) accélère la pousse et
mute les plantes en direct.

## Gameplay

| Action | Comment |
| --- | --- |
| Planter | Choisis une graine dans la barre (clic ou touches `1-9`), puis clique une case de ta parcelle |
| Arroser | Clique une plante en croissance : +20 % de pousse (arrosoir : 6 s de recharge) |
| Récolter | Clique une plante mûre (brillante, étiquette « MÛR ») |
| Vendre | Va au stand **VENTE** (touche `E` ou bouton VENDRE) : tout le sac est vendu |
| Acheter | Va au stand **GRAINES** (touche `E` ou bouton BOUTIQUE) |
| Sac | Bouton SAC ou touche `B` : liste des fruits, poids, valeur |
| Agrandir | Bouton AGRANDIR : 9 → 25 → 49 cases |

- **10 plantes** de la carotte (10 pièces) à la fleur de lune (250 000), certaines repoussent après récolte.
- **Boutique à stock limité** qui se réapprovisionne toutes les 5 minutes (compte à rebours à l'écran).
- **Poids aléatoire** : la plupart des fruits sont normaux, parfois un GÉANT vaut plusieurs fois le prix.
- **Mutations** : Doré (x20) et Arc-en-ciel (x50) à la maturation, Mouillé (x2) sous la pluie, Gelé (x10) par temps froid, Choc (x100) quand la foudre frappe une plante pendant l'orage. Les multiplicateurs se cumulent.
- **Croissance hors ligne** : les plantes continuent de pousser jusqu'à 2 h après ta déconnexion.
- **Sauvegarde DataStore** : pièces, graines, fruits, parcelle, agrandissements, récoltes.
- Fonctionne sur PC, mobile (tap) et jusqu'à 8 joueurs par serveur (8 parcelles).

## Installation (2 façons)

### 1. Le plus simple : ouvrir le fichier de place

1. Télécharge `OnyxFarm.rbxlx`.
2. Dans Roblox Studio : **Fichier → Ouvrir depuis un fichier** et choisis `OnyxFarm.rbxlx`.
3. Clique sur **Jouer**. Tout (terrain, stands, parcelles, interface) est généré par script.

Pour tester à plusieurs : onglet **Test → Clients et serveurs**, choisis 2 joueurs ou plus.

### 2. Avec Rojo (pour développer)

```bash
rojo serve default.project.json
```

Puis connecte le plugin Rojo dans Studio. Les sources sont dans `src/`.

Pour régénérer le fichier `.rbxlx` après une modification des scripts :

```bash
node build-place.js
```

## Publication

Après **Fichier → Publier sur Roblox**, active dans *Paramètres du jeu → Sécurité*
l'option **Activer l'accès aux services API par Studio** pour que la sauvegarde fonctionne
aussi en test Studio.

## Structure

```
src/
  ReplicatedStorage/Shared/
    Config.lua          Plantes, mutations, météo, prix, parcelles (tout l'équilibrage)
    Economy.lua         Valeur d'un fruit, poids aléatoire, libellés
    Remotes.lua         RemoteEvents client <-> serveur
  ServerScriptService/Server/
    Main.server.lua     Point d'entrée serveur
    Modules/
      MapBuilder.lua    Génère le terrain, la place, les stands, les 8 parcelles
      PlantVisuals.lua  Modèles de plantes (4 stades, 5 formes, effets de mutation)
      PlotService.lua   Attribution, plantation, croissance, arrosage, récolte, expansion
      ShopService.lua   Stock, réassort, achat, vente, agrandissement
      WeatherService.lua Météo, mutations météo, éclairs
      DataService.lua   DataStore + leaderstats
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.lua     Point d'entrée client
    Modules/
      Input.lua         Clic/tap sur les cases, survol avec info-bulle, raccourcis
      HUD.lua           Interface complète (générée par script)
      Effects.lua       Particules, textes flottants, éclairs, pluie, neige, sons
      State.lua         État partagé côté client
```

## Équilibrage rapide

Tout se règle dans `Config.lua` :

- `Plants` : prix, temps de pousse, valeur, poids, repousse, stock de chaque plante.
- `Mutations` : multiplicateurs et couleurs.
- `Weather` : fréquence, durée et effets des événements.
- `Plot.ExpandPrices` : prix des agrandissements.
- `Water.Boost` / `Water.Cooldown` : puissance de l'arrosoir.

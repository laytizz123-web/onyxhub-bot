# ONYX ARENA – jeu Roblox

Jeu d'arène ultra dynamique inspiré des hits du moment (type *deflect / dodge*) :
un ballon d'énergie fonce sur une cible, elle doit le **renvoyer au bon moment**,
le ballon accélère à chaque renvoi, et le **dernier survivant gagne**.

## Gameplay

| Action | PC | Manette | Mobile |
| --- | --- | --- | --- |
| Renvoyer le ballon | `F` ou clic gauche | `R2` | bouton RENVOI |
| Dash | `Q` ou `Maj gauche` | `L2` | bouton DASH |
| Pulse (ralentit le ballon) | `E` | `Y` | bouton PULSE |
| Double saut | `Espace` en l'air | `A` en l'air | bouton saut en l'air |

- **Ballon à guidage** : il vise toujours un joueur (surligné en rouge + étiquette CIBLE).
  Si tu es la cible, une bannière et une vignette rouge te préviennent. Quand le ballon est
  à portée la bannière passe en bleu : c'est le moment de renvoyer.
- **Vitesse croissante** : chaque renvoi accélère le ballon (couleur blanc → or → rouge).
- **Overdrive** : après 2 min 30 la vitesse de base est multipliée par 1,8 pour finir la manche.
- **Arène vivante** : piliers qui montent et descendent, 6 jump pads dorés, cubes néon,
  murs de verre, lobby flottant au-dessus de l'arène.
- **Mode entraînement automatique** tant qu'il n'y a qu'un seul joueur (le ballon ne
  t'élimine pas, il repart du centre). Parfait pour tester seul dans Studio.
- **Progression** : pièces (renvois, survie, victoire), victoires et série de victoires,
  sauvegardées en DataStore et affichées dans le leaderboard.

## Installation (2 façons)

### 1. Le plus simple : ouvrir le fichier de place

1. Télécharge `OnyxArena.rbxlx`.
2. Dans Roblox Studio : **Fichier → Ouvrir depuis un fichier** et choisis `OnyxArena.rbxlx`.
3. Clique sur **Jouer**. Tout (arène, lobby, éclairage, interface) est généré par script.

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
l'option **Activer l'accès aux services API par Studio** pour que la sauvegarde des pièces
fonctionne aussi en test Studio.

## Structure

```
src/
  ReplicatedStorage/Shared/
    Config.lua          Tous les réglages (vitesses, cooldowns, récompenses, tailles)
    Remotes.lua         RemoteEvents client <-> serveur
  ServerScriptService/Server/
    Main.server.lua     Point d'entrée serveur
    Modules/
      MapBuilder.lua    Génère l'arène, le lobby et l'éclairage
      BallController.lua Ballon : guidage, renvois, vitesse, overdrive
      RoundManager.lua  Boucle de manche, éliminations, récompenses
      DataService.lua   DataStore + leaderstats
      AbilityService.lua Validation des capacités (Pulse) et relais d'effets
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.lua     Point d'entrée client
    Modules/
      Input.lua         Contrôles, dash, double saut, jump pads
      HUD.lua           Interface complète (générée par script)
      Effects.lua       Ondes de choc, particules, sons, tremblement caméra
      State.lua         État partagé côté client
```

## Équilibrage rapide

Tout se règle dans `Config.lua` :

- `Ball.SpeedPerDeflect` / `Ball.MaxSpeed` : difficulté de la montée en vitesse.
- `Ball.DeflectRange` : fenêtre de renvoi (plus grand = plus facile).
- `Round.Duration` : délai avant l'Overdrive.
- `Abilities.*.Cooldown` : fréquence des capacités.
- `Rewards.*` : économie du jeu.

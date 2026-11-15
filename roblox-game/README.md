# ONYX BATTLEGROUNDS – jeu Roblox

Un **Battleground** : grande zone de combat en Free For All où chaque joueur choisit un
personnage, enchaîne des combos M1, bloque, dash, utilise 4 compétences, charge son
**Ultimate**, monte en niveau et débloque des cosmétiques.

## Boucle de jeu

Spawn (zone sûre) → Choisir un personnage (`C`) → Combattre dans la ville / l'arène →
Gagner XP, pièces, kills, victoires → Débloquer auras, effets de dash, titres → Recommencer

## Contrôles

| Action | PC | Manette | Mobile |
| --- | --- | --- | --- |
| Attaque de base (M1, combo 4 coups) | Clic gauche | `R2` | bouton M1 |
| Bloquer (maintenir) | `F` | `L2` | bouton BLOC |
| Dash (avant / arrière / gauche / droite selon le déplacement) | `Q` | `L1` | bouton DASH |
| Compétences 1 à 4 | `1` `2` `3` `4` | `X` `B` `A` `R1` | boutons à l'écran |
| Ultimate | `G` | `Y` | bouton ULT |
| Personnage | `C` | | bouton |
| Cosmétiques | `K` | | bouton |

## Système de combat

- **M1** : 4 coups enchaînés (droite, gauche, coup de pied, coup lourd). Le 4e coup
  repousse l'adversaire, brise sa garde et l'étourdit plus longtemps.
- **Blocage** : -70 % de dégâts sur les M1, -50 % sur les compétences. Le 4e coup du combo
  brise le blocage. On ne peut pas attaquer ni dasher en bloquant.
- **Dash** : déplacement rapide dans la direction du mouvement (1,6 s de recharge) avec
  traînée cosmétique.
- **Étourdissement / knockback / mise au sol** selon la puissance du coup.
- **Ultimate** : chaque dégât infligé ou subi remplit la barre. À 100 %, `G` active le mode
  Ultimate pendant 16 s : aura, lumière, ambiance sonore, dégâts x1,25 et **4 nouvelles
  compétences** par personnage.
- **Compétences** : 5 types génériques (corps à corps, ruée, projectile, zone, bonus) avec
  dégâts, recharge, animation procédurale, effets visuels et sonores définis dans `Config.lua`.

## Personnages

| | Vie | Vitesse | Style | Compétences | Ultimate |
| --- | --- | --- | --- | --- | --- |
| **Fighter** | 100 | 17 | équilibré | Uppercut, Rush Punch, Shockwave, Finisher | Meteor Fist, Blitz Rush, Earth Breaker, Omega Strike |
| **Volt** | 85 | 21 | rapide, mobilité | Spark Jab, Lightning Dash, Thunder Bolt, Overcharge | Chain Lightning, Volt Rush, Plasma Shot, Storm Cage |
| **Titan** | 145 | 14 | lent, dévastateur | Boulder Punch, Charge, Ground Slam, Titan Crush | Quake, Avalanche, Mountain Fist, Cataclysm |
| **Blaze** | 90 | 17 | distance, dégâts | Fire Punch, Flame Dash, Fire Blast, Inferno | Hellfire Fist, Phoenix Dash, Dragon Breath, Supernova |

## Map

- **Spawn** : zone sûre (aucun dégât, impossible d'attaquer), panneau de contrôles,
  **tableau de classement** (top victoires, global via OrderedDataStore + joueurs présents).
- **Arène** : plateforme centrale néon entourée de piliers lumineux.
- **Centre-ville** : immeubles avec toits accessibles (caisses en escalier), rues larges,
  lampadaires.
- **Zone calme** : parc avec 4 mannequins d'entraînement (600 PV, régénération,
  réapparition) pour tester les compétences, même seul.

## Progression

- **XP** : 2 par coup, 60 par kill, 120 par victoire. Niveau = courbe croissante.
- **Pièces** : 1 par coup, 40 par kill, 120 par victoire.
- **Victoire** : 3 éliminations d'affilée sans mourir.
- **Cosmétiques** (uniquement visuels) : 5 auras, 4 traînées de dash à acheter avec des
  pièces, 9 titres débloqués par niveau / kills / victoires. Affichés au-dessus de la tête.
- Tout est sauvegardé en DataStore (`OnyxBG_v1`).

## Installation

### 1. Le plus simple : ouvrir le fichier de place

1. Télécharge `OnyxBattlegrounds.rbxlx`.
2. Roblox Studio : **Fichier → Ouvrir depuis un fichier**.
3. **Jouer**. Map, mannequins et interface sont générés par script.

Test à plusieurs : **Test → Clients et serveurs**, 2 joueurs ou plus.

### 2. Avec Rojo

```bash
rojo serve default.project.json
```

Régénérer le fichier de place après modification :

```bash
node build-place.js
```

## Publication

Après **Fichier → Publier sur Roblox**, active *Paramètres du jeu → Sécurité → Accès aux
services API par Studio* pour que la sauvegarde et le classement global fonctionnent.

## Structure

```
src/
  ReplicatedStorage/Shared/
    Config.lua            Personnages, compétences, combat, progression, cosmétiques, map
    Remotes.lua           RemoteEvents
  ServerScriptService/Server/
    Main.server.lua
    Modules/
      MapBuilder.lua      Map complète + mannequins + zone sûre
      CombatService.lua   M1/combos, blocage, dash, compétences, dégâts, stun, knockback, ultimate
      CharacterService.lua Application de la classe, mort, crédit des kills
      ProgressionService.lua XP, niveaux, pièces, titres, cosmétiques, classement
      DataService.lua     DataStore + leaderstats + OrderedDataStore
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.lua
    Modules/
      Input.lua           Contrôles, dash local, orientation caméra, ruées
      Anim.lua            Animations procédurales (Motor6D) R15/R6, sans assets
      HUD.lua             Vie, ultimate, compétences, combo, stats, menus
      Effects.lua         Particules, ondes de choc, dégâts flottants, auras, traînées, sons
      State.lua
```

## Ajouter un personnage ou une compétence

Ajoute une entrée dans `Config.Characters` : 4 `skills` + 4 `ultSkills` avec un `type`
(`melee`, `rush`, `projectile`, `aoe`, `buff`), des dégâts, une recharge, une `pose`
(`jab`, `uppercut`, `heavy`, `rush`, `slam`, `cast`, `power`) et un `sound`
(`heavy`, `whoosh`, `slam`, `zap`, `fire`, `explosion`, `thunder`, `charge`).
Aucun autre fichier à modifier.

# Remplacer les décors par tes propres modèles

Le jeu cherche des modèles dans **ReplicatedStorage > Decor** (le dossier existe déjà dans `RelicRush.rbxlx`).
Un modèle placé là avec le **nom d'un emplacement** remplace automatiquement le décor généré, partout et dans tous les mondes.

## Marche à suivre
1. Trouve ou crée un modèle : Toolbox ou Creator Store, Poly Pizza, Kenney, Quaternius, Tripo, Blender…
2. Importe-le dans Studio : **Fichier > Importer en 3D**, ou insère-le depuis la Toolbox.
3. Glisse-le dans **ReplicatedStorage > Decor** et renomme-le, par exemple `Arbre`, `Fontaine` ou `Caisse`.
4. Lance le jeu : le modèle est mis à la bonne taille, posé au sol et orienté automatiquement.

## Règles
| Tu veux… | Nom à donner |
|---|---|
| Remplacer partout | `Arbre` |
| Plusieurs variantes tirées au hasard | `Arbre`, `Arbre2`, `Arbre3`… (jusqu'à 9) |
| Un modèle pour un seul monde | `Arbre_Forest`, `Caisse_Lava`, `Boss_Celestial`… |
| Agrandir / réduire | ajoute l'attribut `Taille` (nombre) : `0.5` = moitié, `1.5` = une fois et demie |
| Garder la taille d'origine | ajoute l'attribut `KeepScale` (booléen, coché) au modèle |

- Mondes : `Village`, `Forest`, `Cave`, `Desert`, `Frozen`, `Lava`, `Celestial`.
- Le modèle peut être un **Model** ou une **MeshPart** seule.
- **Sécurité** : tous les scripts contenus dans ces modèles sont supprimés au lancement. Les modèles de la Toolbox en contiennent parfois de malveillants.
- Les bâtiments de gameplay gardent leurs invites (E) et leurs panneaux. Seul l'aspect change.

## Liste des emplacements (taille cible en studs)
**Gameplay**
| Nom | Taille | Où |
|---|---|---|
| `Fontaine` | 16 haut | place du village |
| `Caisse` | 9 haut | caisse de reliques de chaque monde |
| `Boutique` | 17 haut | village |
| `Forge` | 12 haut | village |
| `Autel` | 16 haut | autel de renaissance |
| `TableauQuetes` | 10 haut | village |
| `Portail` | 22 haut | portails entre mondes |
| `Arene` | 68 large | arène de boss de chaque monde |
| `Grotte` | 50 large | grotte aux trésors (doit être creuse, car les trésors sont à l'intérieur) |
| `Boss` | 20 haut | boss (les morceaux s'envolent quand il est vaincu) |
| `Vase` | 4,6 haut | trésor |
| `Coffre` | 4 haut | trésor |
| `TresorGeant` | 4,5 haut | trésor |

**Nature** (taille de base, un peu variée selon l'endroit) :
| Nom | Taille |
|---|---|
| `Arbre` | 14 |
| `GrandArbre` | 21 |
| `Sapin` | 17 |
| `SapinNeige` | 17 |
| `Palmier` | 15 |
| `ArbreMagique` | 14 |
| `ArbreMort` | 11 |
| `Buisson` | 4 |
| `Fleurs` | 1,6 |
| `Rocher` | 3 |
| `Champignon` | 3,2 |
| `ChampignonMagique` | 9 |
| `Cactus` | 9 |
| `Cristal` | 9 |
| `CristalGlace` | 7 |
| `Obsidienne` | 8 |
| `Topiaire` | 10 |

**Constructions** :
| Nom | Taille |
|---|---|
| `Maison` | 16 |
| `Chalet` | 14 |
| `Tente` | 6 |
| `Echoppe` | 8,5 |
| `Kiosque` | 15 |
| `Moulin` | 26 |
| `Banc` | 4 |
| `Lanterne` | 7,5 |
| `Lampadaire` | 10 |
| `Statue` | 10 |
| `Parasol` | 8,5 |
| `Phare` | 40 |
| `BonhommeNeige` | 13 |
| `Igloo` | 9 |
| `Pyramide` | 24–36 |
| `Obelisque` | 20 |
| `Sphinx` | 18 |
| `Volcan` | 45 |
| `Chateau` | 70 de large |

## Important quand je t'envoie une nouvelle version
Tes modèles sont enregistrés dans **ton** fichier `.rbxlx`, pas dans le code.
Quand tu ouvres une nouvelle version que je t'envoie :
1. Ouvre les deux fichiers dans Studio.
2. Copie le dossier `Decor` de l'ancien (Ctrl+C).
3. Colle-le dans `ReplicatedStorage` du nouveau (Ctrl+V), en remplaçant le dossier vide.

Tu peux aussi faire un clic droit sur `Decor` > **Enregistrer dans un fichier** pour le garder de côté.

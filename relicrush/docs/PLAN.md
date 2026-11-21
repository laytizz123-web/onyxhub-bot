# RELIC RUSH — Architecture et plan de test par phase

## Boucle de jeu
Détruire des trésors → ramasser les pièces → ouvrir des caisses → obtenir des reliques → les équiper (elles flottent autour de toi) → plus de puissance → trésors plus gros, boss → nouveaux mondes → renaissance (bonus permanents).

## Organisation des fichiers
```
src/ReplicatedStorage/Shared/
  Config.lua        equilibrage complet (9 raretes, 7 mondes, 51 reliques, caisses, tresors...)
  Formulas.lua      puissance, couts, chances (partage client/serveur)
  RelicModel.lua    modeles 3D des reliques (33 formes, effets selon la rarete)
  Icons.lua         affichage des icones (planche fournie) ; IconData.lua = donnees generees
  Remotes.lua       Action, Sync, Notify, FX, Trade, Boss (RemoteEvents) + Query (RemoteFunction)
src/ServerScriptService/Server/
  Main.server.lua   demarrage de chaque service
  Modules/WorldBuilder   7 iles, village detaille, caisses, portails, arenes, batiments
  Modules/MapKit, MapZones  props et decors thematiques
  Modules/DataService    DataStore (tentatives, autosave, BindToClose), leaderstats, classements
  Modules/Actions        routeur des actions client (anti-spam)
  Modules/Targets        cibles et degats (serveur uniquement)
  Modules/TreasureService tresors + pieces a ramasser
  Modules/RelicService   caisses (tirage serveur), equipement, verrou, recyclage
  Modules/ProgressService ameliorations, boutique, renaissance, mondes, quotidien, quetes, parametres
  Modules/BossService    boss multijoueurs, onde de choc, recompenses
  Modules/TradeService   echanges securises
  Modules/QueryService   classements mondiaux
src/StarterPlayer/StarterPlayerScripts/Client/
  Modules/HUD, Window, PanelsA, PanelsB   HUD et les 12 interfaces + caisse
  Modules/RelicOrbit     reliques flottantes de tous les joueurs
  Modules/Effects        ouverture de caisse, pieces, degats, sons
  Modules/UI, RelicView, State
```
Sécurité : tout ce qui rapporte (dégâts, pièces, tirages, achats, échanges) est calculé et vérifié par le serveur. Le client n'envoie que des intentions.

## Phases : quoi vérifier en jeu
| Phase | Contenu | À vérifier dans Studio |
|---|---|---|
| 1 | Carte de départ, déplacement, HUD | Le village apparaît (place, fontaine, forêt, grotte, plage, boutique, forge, autel, caisse, portail, arène) ; 12 boutons et 3 compteurs |
| 2 | Trésors et pièces | Clic sur un vase : les dégâts s'affichent, la barre de vie descend, les pièces tombent puis s'envolent vers le compteur |
| 3 | Caisses, reliques, raretés | E sur la caisse : la fenêtre affiche les chances ; l'animation d'ouverture fonctionne ; la relique flotte autour de toi |
| 4 | Inventaire, index, équipement | Équiper/retirer, « Équiper les meilleures », verrouiller, recycler ; l'index montre les silhouettes manquantes |
| 5 | Améliorations | Forge : puissance, fortune, chance, vitesse, aimant, emplacements |
| 6 | Mondes et portails | Débloquer l'Enchanted Forest, voyager par le portail et par le menu |
| 7 | Boss | Le golem apparaît dans l'arène ; on le combat à plusieurs ; récompenses et relique du boss |
| 8 | Renaissance, quêtes, quotidien | Les bonus augmentent ; les quêtes progressent et se réclament ; le calendrier fonctionne |
| 9 | Échanges et classements | Avec 2 joueurs : demande, offres, double validation, compte à rebours, échange |
| 10 | Sauvegarde | Quitter puis revenir : tout est conservé |

## Pistes pour la suite
- Reliques à évolution (fusionner 5 identiques pour une version dorée).
- Événements de serveur (pluie de trésors, chance ×2 le week-end).
- Badges.
- Musique : `Config.MusicId`.
- Monétisation uniquement cosmétique ou de confort, comme la frappe automatique, déjà achetable en pièces.

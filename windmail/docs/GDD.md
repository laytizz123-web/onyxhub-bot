# WINDMAIL — Les Facteurs du Vent
*Document de conception (version 0.1 jouable)*

## 1. Le concept en une phrase
Tu es facteur dans un archipel balayé par le vent : tu récupères des colis à la poste, tu sautes des falaises avec ton planeur et tu livres chaque colis à la bonne boîte aux lettres, le plus vite et le plus proprement possible.

## 2. Pourquoi ça peut plaire à beaucoup de monde
- **Plaisir immédiat** : en 20 secondes on saute d'une falaise et on plane au-dessus de la mer. Voler est amusant même sans objectif.
- **Facile à comprendre** : prendre un colis, voler, livrer. Le ruban de vent et la flèche montrent toujours où aller.
- **Profondeur** : piquer pour accélérer et cabrer pour remonter, lire les colonnes de vent, enchaîner les anneaux, choisir l'ordre d'une tournée de 5 colis. La note S/A/B/C récompense la maîtrise.
- **Original** : ni pets, ni combat, ni clic. Le mouvement *est* le jeu, et la livraison lui donne un but.
- **Pour tous** : aucune violence ; le seul « échec » est de tomber à l'eau, et un bateau te ramène au quai.
- **Social naturellement** : voler ensemble donne un bonus de convoi, et la malle lourde se transporte mieux à deux.

## 3. Boucle de jeu, minute par minute
| Moment | Ce que vit le joueur |
|---|---|
| 0:00 | Apparition sur la place de Port-Brise. Une carte de tutoriel et une flèche indiquent le guichet de la Poste des Vents. |
| 0:15 | Il prend un colis. Une carte apparaît à droite, la boîte aux lettres cible s'illumine et un ruban de vent la relie au joueur. |
| 0:30 | Il saute du Tremplin et ouvre son planeur (Espace). Le champ de vision s'élargit et le vent siffle. |
| 1:00 | Il atterrit et livre. Un tampon S/A/B/C claque à l'écran, des confettis volent, les pièces et l'XP montent. |
| 2-5 min | Rang 2 : sacoche en cuir (2 colis). Colis fragiles : il faut atterrir en douceur. Il découvre les colonnes de vent pour remonter. |
| 5-15 min | Rang 3 : le Verger s'ouvre, premières traversées en mer en passant par les thermiques. Premier colis mystère et son timbre. |
| 15-30 min | Achat de l'Aile de mouette. Les tournées à plusieurs colis deviennent rentables. Premier événement (Ballon égaré). |
| Sessions suivantes | Nouvelles zones (rangs 6, 10, 15), planeurs plus rapides, quête des timbres secrets, cadeau quotidien, classement mondial. |

## 4. Systèmes principaux
**Planeur** (`Glider.lua`, côté client)
- Il s'ouvre en l'air avec Espace, Q ou le bouton « Planer » sur mobile. On le pilote à la caméra.
- Modèle d'énergie : piquer convertit l'altitude en vitesse, cabrer fait l'inverse. Le boost (Shift) puise dans une réserve d'élan qui se recharge au sol.
- **Colonnes de vent** : elles soulèvent les joueurs, en vol comme à pied, et servent d'ascenseurs naturels.
- **Anneaux de vent** : ils donnent de l'élan et de la vitesse.

**Colis et livraisons** (`ParcelService.lua`, côté serveur, autoritaire)

| Type | Rang | Particularité |
|---|---|---|
| Lettre | 1 | Simple |
| Fragile | 2 | Perd de l'intégrité à chaque choc et dans l'eau |
| Mystère | 3 | Contient un timbre de collection |
| Express | 4 | Chrono, à livrer avant la fin du délai |
| Malle lourde | 7 | On plane moins bien, sauf en convoi |

- La note dépend du temps écoulé comparé à un « temps par » calculé selon la distance.
- Récompense = base × distance × type × note × intégrité × convoi × événement × bonus de collection.
- Le **convoi** donne +30 % au livreur, et chaque ami à moins de 40 studs reçoit 20 % de la récompense.

**Timbres** (`StampService.lua`)
- 16 timbres répartis en 7 collections. Ils viennent des colis mystère, de cachettes secrètes ou des événements.
- Compléter une collection donne un bonus permanent : pièces, XP, ou la traînée « Aurore boréale ».

**Boutique** (`ShopService.lua`)
- 5 planeurs avec des statistiques différentes, 5 sacoches (1 à 5 colis) et des traînées cosmétiques.
- **Tout s'achète avec les pièces gagnées en jouant.**

**Événements aléatoires** (`EventService.lua`), toutes les 5 à 8 minutes :
- **Vent doré** : les livraisons rapportent ×2.
- **Ballon égaré** : un ballon postal survole l'archipel ; le premier qui l'attrape gagne un timbre légendaire.
- **Grande Tournée** : un objectif commun pour tout le serveur, et tous les participants sont récompensés.

**Cadeau quotidien** : une série de 7 jours, de 150 à 2 000 pièces.

**Sauvegarde** (`DataService.lua`)
- DataStore avec nouvelles tentatives, sauvegarde automatique toutes les 2 minutes, à la déconnexion et à la fermeture du serveur.
- Si le chargement échoue, rien n'est sauvegardé pour ne pas écraser les vraies données.
- Un classement mondial (OrderedDataStore) est affiché dans la poste.

## 5. Progression et économie
- **Rangs 1 à 40** : XP pour passer au rang suivant = 60 × rang^1,35. Titres de rang : Apprenti facteur, Facteur du port, Coursier des falaises, Messager céleste, Pilote des tempêtes, Capitaine des vents, Maître des vents.
- **Les zones s'ouvrent au rang** : l'exploration reste libre, seules les livraisons sont limitées. Les meilleurs planeurs permettent physiquement d'aller plus loin.
- **Revenus** : une livraison rapporte 15 à 60 pièces au début, et plusieurs centaines dans les zones lointaines avec une bonne note et une grosse sacoche.
- **Prix** : du premier planeur à 900 pièces jusqu'à l'Aile d'aurore à 65 000. Les prix sont pensés pour un nouvel objet toutes les 20 à 40 minutes de jeu.
- **Tout le réglage est dans `Config.lua`.**
- **Monétisation honnête (à ajouter plus tard)** : uniquement des cosmétiques (couleurs de planeur, traînées, tampons de note personnalisés) et un pass « facteur VIP » purement esthétique. Aucun avantage payant ; les meilleurs objets s'obtiennent en jouant.

## 6. La carte
| Zone | Rang | Ambiance | Éléments |
|---|---|---|---|
| Port-Brise | 1 | Village côtier sur une falaise de 62 m | Poste des Vents, 10 maisons, fontaine, Tremplin, phare, quai, 2 colonnes de vent |
| Le Verger | 3 | Île agricole basse | Vergers en rangées, moulin qui tourne, fermes, ruches, foin |
| Falaises Brumeuses | 6 | Haute île de 95 m dans la brume | Cercle de pierres, pins, maisons de pierre |
| Marché Céleste | 10 | Trois pitons de 110 m | Ponts de corde, étals colorés, lanternes |
| Pic des Tempêtes | 15 | Montagne de 160 m enneigée | Observatoire, refuges sur les replats, neige qui vole |

- **Routes du vent** : 6 thermiques en mer et 8 anneaux, à planifier pour traverser.
- **Secrets** :
  - une grotte derrière une cascade, sous Port-Brise ;
  - la galerie du phare, avec une échelle cachée à l'arrière ;
  - une épave sur un banc de sable ;
  - un îlot oublié avec une boîte aux lettres dorée, très loin à l'ouest.
- **Évolutivité** : chaque île est une fonction de `WorldBuilder.lua`. Ajouter une zone revient à ajouter une ligne dans `Config.Zones` et une fonction de construction.

## 7. Interface
Style : panneaux bleu nuit translucides, coins arrondis, police Gotham, accent bleu ciel et orange « postal ».
- **En haut à gauche** : badge de rang, titre et barre d'XP.
- **En haut à droite** : pièces (qui rebondissent quand elles augmentent) et nombre de livraisons.
- **À droite** : cartes des colis avec couleur du type, destinataire, zone, chrono, note visée en direct et barre d'intégrité.
- **En bas, au centre** : jauge de vol (vitesse et élan), indice « Colonne de vent », aides contextuelles.
- **En haut, au centre** : bandeau d'événement avec compte à rebours et barre d'objectif commun.
- **À gauche** : boutons Boutique, Album, Classement et Cadeau (avec une pastille quand il est prêt).
- **Écrans animés** : tampon de note (S/A/B/C), montée de rang, nouveau timbre, notifications.
- **Fenêtres** : boutique à onglets avec barres de statistiques, album par collection, classement du serveur. L'interface s'adapte aux petits écrans.
- **Guidage** : contour et étiquette sur les boîtes ciblées (le bouton « Livrer » n'apparaît que là), ruban de vent courbe, flèche en bord d'écran.
- **Tutoriel** : 4 étapes contextuelles pendant la première tournée.

## 8. Multijoueur
- Le bonus de convoi récompense le fait de voler ensemble, et le livreur partage ses gains.
- La malle lourde se transporte normalement seulement en convoi.
- La Grande Tournée est un objectif commun pour tout le serveur.
- Le Ballon égaré est une course amicale.
- Les ailes et traînées de chacun sont visibles par tous.
- Classement du serveur, classement mondial dans la poste, annonces publiques des exploits (timbres secrets, ballon).

## 9. Scripts et dossiers
```
windmail/
  build-place.js            construit Windmail.rbxlx depuis src/ (node build-place.js)
  default.project.json      projet Rojo (alternative au fichier .rbxlx)
  docs/GDD.md               ce document
  src/ReplicatedStorage/Shared/
    Config.lua              equilibrage : zones, colis, planeurs, sacoches, timbres, evenements
    Progress.lua            rangs, bonus de collection, format des nombres (client + serveur)
    Remotes.lua             RemoteEvents : Request, Sync, Notify, FX, Event, Parcels
  src/ServerScriptService/Server/
    Main.server.lua         demarrage de chaque service (isole par pcall)
    Modules/WorldBuilder    terrain, iles, batiments, boites aux lettres, vents, secrets, eclairage
    Modules/DataService     sauvegarde, leaderstats, classement mondial
    Modules/ParcelService   missions, livraisons, notes, convoi, chocs, sauvetage en mer
    Modules/StampService    timbres, collections
    Modules/ShopService     boutique, equipement, cadeau quotidien, etat de vol, trainees
    Modules/EventService    evenements aleatoires
    Modules/BoardService    panneau du classement mondial
  src/StarterPlayer/StarterPlayerScripts/Client/
    Main.client.lua         demarrage client
    Modules/Glider          vol, colonnes de vent, anneaux, ailes visibles
    Modules/Navigator       guidage vers la destination
    Modules/HUD             toute l'interface et les menus
    Modules/Effects         sons, camera, confettis, secousses
    Modules/UI, State       outils d'interface, etat local
```
Sécurité : le serveur décide de tout ce qui rapporte (missions, distances, temps, récompenses, achats). Le client ne fait que piloter son personnage et afficher.

## 10. Plan de développement
| Étape | Contenu | État |
|---|---|---|
| 1. Noyau | Vol, une île, poste, boîtes aux lettres, livraison, sauvegarde | ✅ v0.1 |
| 2. Boucle complète | Notes, types de colis, rangs, boutique, HUD | ✅ v0.1 |
| 3. Monde | 5 îles, thermiques, anneaux, secrets | ✅ v0.1 |
| 4. Social | Convoi, événements, classements | ✅ v0.1 |
| 5. Test et réglages | Tester en Studio, ajuster la vitesse de vol et les prix dans Config.lua, corriger | ⏳ à faire par toi |
| 6. Finition visuelle | Vrais modèles de planeur et de bâtiments (Blender ou Toolbox), sons sur mesure, icônes | ⏳ |
| 7. Lancement | Icône, miniatures, publication, badges (premier S, tous les timbres...) | ⏳ |
| 8. Mises à jour (toutes les 2 à 4 semaines) | Nouvelle île, nouveau type de colis (vivant : un chaton à livrer !), saison (neige, fête des lanternes), nouveaux timbres, défis hebdomadaires | ⏳ |

## 11. Idées de mises à jour (déjà compatibles avec l'architecture)
- **Défis quotidiens** : « 3 notes S », « livrer 5 colis fragiles intacts ».
- **Contre-la-montre** : des courses chronométrées entre deux îles avec un fantôme du record du serveur.
- **Courrier entre joueurs** : écrire une carte postale (texte filtré par Roblox) et l'envoyer à un ami.
- **Météo** : orages qui renforcent les vents, coucher de soleil qui rend les anneaux lumineux.

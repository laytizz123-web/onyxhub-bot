--[[
  DOSSIER DECOR : depose ici tes modeles 3D (Model ou MeshPart) pour remplacer les decors du jeu.
  Il suffit de donner au modele le NOM d'un emplacement ci-dessous, puis de lancer le jeu.

  Regles :
    - Variantes au hasard : Arbre, Arbre2, Arbre3 ... Arbre9
    - Version pour un seul monde : ajoute _Village, _Forest, _Cave, _Desert, _Frozen, _Lava ou _Celestial
      (ex. "Caisse_Lava", "Arbre_Forest"). Elle passe avant la version generale dans ce monde.
    - Taille automatique (hauteur indiquee). Pour garder la taille d'origine : attribut KeepScale = true.
    - Les scripts contenus dans les modeles sont supprimes automatiquement (securite).
    - Sans modele, le decor genere par le jeu reste en place.

  BATIMENTS ET GAMEPLAY (les boutons et panneaux restent fonctionnels)
    Fontaine (16)  Caisse (9)  Boutique (17)  Forge (12)  Autel (16)  TableauQuetes (10)
    Portail (22)  Arene (68 de large)  Grotte (66 de large, doit etre creuse : les tresors sont dedans)
    Boss (30)  Vase (4.6)  Coffre (4)  TresorGeant (4.5)

  NATURE ET PROPS
    Arbre (14)  GrandArbre (21)  Sapin (17)  SapinNeige (17)  Palmier (15)  ArbreMagique (14)  ArbreMort (11)
    Buisson (4)  Fleurs (1.6)  Rocher (3)  Champignon (3.2)  ChampignonMagique (9)  Cactus (9)
    Cristal (9)  CristalGlace (7)  Obsidienne (8)  Topiaire (10)

  CONSTRUCTIONS
    Maison (16)  Chalet (14)  Tente (6)  Echoppe (8.5)  Kiosque (15)  Moulin (26)  Banc (4)  Lanterne (7.5)
    Lampadaire (10)  Statue (10)  Parasol (8.5)  Phare (40)  BonhommeNeige (13)  Igloo (9)
    Pyramide (24-36)  Obelisque (20)  Sphinx (18)  Volcan (45)  Chateau (70 de large)
]]
return nil

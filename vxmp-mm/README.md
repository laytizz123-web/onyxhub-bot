# VXMP MM (LTC Middleman Bot)

Bot Discord indépendant : un ticket "middleman" où le bot garde les LTC le temps d'un échange.

## Installation (Windows)

1. Installe Node.js 18+ puis ouvre l'invite de commandes **dans ce dossier** (`cd vxmp-mm`).
2. `npm install`
3. `npm run new-seed` : copie la ligne `MM_SEED=...` et sauvegarde les 12 mots **hors ligne**.
4. Copie `.env.example` en `.env` et remplis-le (`DISCORD_TOKEN`, `CLIENT_ID`, `GUILD_ID`, `MM_SEED`).
5. `npm start`
6. Dans le salon voulu, tape `/panel` : le bouton **Open a middleman ticket** apparaît.

## Créer le bot Discord
https://discord.com/developers/applications → New Application → Bot → copie le token (`DISCORD_TOKEN`).
`CLIENT_ID` = Application ID. Invite le bot avec le scope `bot` + `applications.commands` et la permission **Administrator**
(il doit créer des salons et modifier leurs permissions).

## Déroulé d'un deal
1. Le ticket s'ouvre, la personne ajoute l'autre (@ ou ID).
2. Chacun choisit : envoie les LTC / reçoit les LTC.
3. Le sender entre le montant, le receiver confirme.
4. Le sender paie l'adresse du bot (une adresse par deal). Le bot annonce détection puis confirmation.
5. Le receiver livre, le sender clique **Release**.
6. Le receiver entre son adresse LTC, le bot envoie le montant moins les frais réseau.

Staff : **Call staff** gèle le deal ; ensuite dégeler, forcer le release ou rembourser le sender.

## Sécurité
- `MM_SEED` contrôle tous les fonds : jamais dans git, jamais partagé. Wallet "chaud" : garde peu d'argent dessus.
- `middleman.json` (état des deals) est local. Un ticket qui contient des fonds ne peut pas être fermé.
- Fais un premier deal de test à 0.001 LTC.

Option disponible :
-i <path_fichier_inventaire>

Si la variable environnement pve_pass n'existe pas et qu'elle n'est pas présente dans l'inventaire une saisie utilisateur sera demandé.
(pour l'export pensez à backslasher les symboles $)

Fonctions :
1. Afficher l'état de proxmox
2. Afficher toutes les VM (ID / Nom / Status )
3. Afficher seulement les VM de l'inventaire 
4. Afficher la liste des IP utilisées
5. Cloner la quantité de VM saisie dans l'inventaire
6. Détruire les VM de l'inventaire
7. Snapshot des VM de l'inventaire
8. Rollback des VM de l'inventaire
9. Liste des snapshots disponibles

Code couleur en Output : Vert en cas de création (clone/snap) / Jaune en cas de changement (rollback/destroy) / Rouge en cas d'erreur (exception)

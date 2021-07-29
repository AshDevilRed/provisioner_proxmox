# provisioner_proxmox
Scripts python et Shell qui permettent d'approvisioner un serveur Proxmox : (via les API)
- Création de VM
- Suppression de VM
- Snapshot
- Rollback d'un snapshot
- Status de l'hyperviseur
- Liste des VM (ID / Nom / Etat)
- Liste des VM de l'inventaire
- Liste des IP utilisées
- Liste des snapshot disponibles

## Python Script - auto_provisioner.py
Prérequis : 
- python3
- proxmoxer https://github.com/proxmoxer/proxmoxer

Step 1 :
```
- Créer un fichier d'inventaire (par défaut inventory.yml)
- Les variables du proxmox : ip / user / port / node 
- Les configurations voulu sur les VM : os / ressources / gateway / utilisateur
- Les groupes contenant dans chacun : Le premier ID / La première IP et le nombre de VM
```

Step 2 :
```
- Exporter le pass de proxmox
  export pve_pass="votre_pass"
- Pensez à bien backslasher les caractères spéciaux
```

## Bash Script 
Prérequis : 
- gridsite-clients
- curl
- jq


### auto_provisioner.sh

Suivre les mêmes étapes que pour le script Python !

### provisioner.sh

A la différence des deux autres script celui-ci demande une saisie utilisateur au lieu d'un fichier d'inventaire.



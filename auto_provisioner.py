#!/usr/bin/env python3
# pve_pass peut être exporter en variable environnement
# pensez à bien backslasher les char spéciaux $
# Prérequis : proxmoxer
# Un fichier inventory.yml doit être fournit en ini (le nom ou le path peut être changer ligne 18 ou via l'option -i
# Code couleur en Output : Vert en cas de création (clone/snap) / Jaune en cas de changement (rollback/destroy) / Rouge en cas d'erreur (exception)
# Copyright (C) 2021 Samuel Kervella

import os, sys, time, getopt
import re, mmap, ipaddress
import requests
from configparser import ConfigParser as ConfP
from proxmoxer import ProxmoxAPI as Prox
from shutil import copy2 as cp
import json, urllib
import pprint

# Chemin par défaut du fichier d'inventaire
inventory="inventory.yml"
conf = ConfP(allow_no_value=True)

# Récupération des arguments du script / Accepte seulement -i suivi d'un Path
try:
    options, remainder = getopt.getopt(sys.argv[1:], 'i:')
    for opt, arg in options:
        if opt in ('-i'):
            inventory=arg
except:
    print("Argument incorrect ! \nEx : [ -i inventory.yml ]")

# Permet de lire le fichier d'inventaire
conf.read(inventory)


# Variables de l'hyperviseur
pve_user=conf.get('proxmox','pve_user')
pve_host=conf.get('proxmox','pve_host')
pve_port=conf.get('proxmox','pve_port')
pve_node=conf.get('proxmox','pve_node')
pass_path=""
try:
    pve_ssh=conf.get('proxmox','pve_ssh')
except Exception as e:
    pass
try:
    pve_pass=os.environ["pve_pass"]
    pass_path="env"
except:
    try:
        if conf.get('proxmox','pve_pass') != "":
            pve_pass=conf.get('proxmox','pve_pass')
            pass_path="inv"
        else:
            print("Proxmox password : ")
            pve_pass=input()
            pass_path="input"
    except:
        print("Proxmox password :")
        pve_pass=input()
        pass_path="input"

ssh_pass=pve_pass # Dans notre cas proxmox à le même pass que le serveur

# Variables de configuration
memory_type="G"
size=conf.get('config','size')+memory_type
memory_size=conf.get('config','memory_size')
gateway=conf.get('config','gateway')
ciuser=conf.get('config','ciuser')
cipassword=conf.get('config','cipassword')
suivi=conf.get('config','suivi')
os_clone=conf.get('config','os_clone')
group_name=[]

# Tableau de couleurs
bold='\033[1;37m'
NC='\033[0;39m'
under='\033[4m'
NU='\033[24m'
yellow='\033[0;33m'
green='\033[0;32m'
red='\033[0;91m'

# Connexion à l'API de Proxmox
pve_user=pve_user + "@pam"
try:
    proxmox=Prox(pve_host, user=pve_user, password=pve_pass, verify_ssl=False)
except:
    if pass_path == "inv":
        print(f"{red}Le mot de passe Proxmox de l'inventaire est incorrect !{NC}")
    elif pass_path == "env":
        print(f"{red}Le mot de passe Proxmox exporté est incorrect !{NC}")
    else:
        print(f"{red}Le mot de passe Proxmox saisi est incorrect !{NC}")
    exit()

# Récupération de la clé SSH publique de notre machine
path=os.environ['HOME']+"/.ssh/id_rsa.pub"
cp(path,'id_rsa.pub')

# Fonction permettant la recherche des noms de groupes entre [] dans le fichier d'inventaire
def search():
    y=0
    for i, line in enumerate(open(inventory)):
        pattern=re.compile(r"\[([A-Za-z0-9_-]+)\]")
        for match in re.finditer(pattern, line):
            if y>=2:
                group_name.append(match.group().replace("[","").replace("]",""))
            y=y+1

# Affiche les différentes informations sur le node Proxmox
def show_proxmox_stats():
    json_data=proxmox.nodes(pve_node).status.get()
    pprint.pprint(json_data)
    
# Affiche les VM de notre inventaire (ID / Nom / Etat)
def show_vm():
    search()
    count_group=len(group_name)
    
    vmid_list=[]
    
    for c in range(count_group):
        count_vm=conf.get(group_name[c],'nb_vm')
        vm_id=conf.get(group_name[c],'vmid')
        for v in range(int(count_vm)):
            vmid_list.append(vm_id)
            vm_id=str(int(vm_id)+1)
   
    for node in proxmox.nodes.get():
        for vm in proxmox.nodes(node['node']).qemu.get():
            if vm['vmid'] in vmid_list:
                if vm['status'] == "running":
                    print(f"{bold}{vm['vmid']}{NC}. {vm['name']} => {green}{vm['status']}{NC}")
                elif vm['status'] == "stopped":
                    print(f"{bold}{vm['vmid']}{NC}. {vm['name']} => {yellow}{vm['status']}{NC}")
                else:
                    print(f"{bold}{vm['vmid']}{NC}. {vm['name']} => {red}{vm['status']}{NC}")

# Affiche toutes les VM du node (ID / Nom / Etat)
# ATTENTION : Ne pas utiliser si il y à trop de VM sur Proxmox
def show_all_vm():
    for node in proxmox.nodes.get():
        for vm in proxmox.nodes(node['node']).qemu.get():
            if vm['status'] == "running":
                print(f"{bold}{vm['vmid']}{NC}. {vm['name']} => {green}{vm['status']}{NC}")
            elif vm['status'] == "stopped":
                print(f"{bold}{vm['vmid']}{NC}. {vm['name']} => {yellow}{vm['status']}{NC}")
            else:
                print(f"{bold}{vm['vmid']}{NC}. {vm['name']} => {red}{vm['status']}{NC}")

# Créer des clones de l'OS choisi dans l'inventaire
def clone_vm():
    global os_clone
    print(f"{bold}OS : ",os_clone)
    if os_clone == "debian":
        os_clone="8000"
    elif os_clone == "centos":
        os_clone="8001"
    elif os_clone == "rhel":
        os_clone="8002"
    elif int(os_clone) in range(8000,10000): #Vous pouvez choisir un template par son numéro (entre 8000 et 10000)
        pass
    else:
        os_clone="8000"
    
    search()
    count_group=len(group_name)
    print("Nombre de groupes à créer : ",count_group)
    print("Définition de la quantité de ressources :\nDisque : ",size[:-1]," Go\nRAM : ", memory_size," Mo\n")

    for c in range(count_group):
        print(f"{bold}Nom du groupe : {under}",group_name[c],f"{NU}")

        count_vm=conf.get(group_name[c],'nb_vm')
        print("Nombre de VM du groupe : ",count_vm)
        
        vm_id=conf.get(group_name[c],'vmid')
        print("Premier ID du groupe : ",vm_id)
        
        ip=conf.get(group_name[c],'ip')
        print("Première IP du groupe : ",ip,"\n")
      
        # On récupère notre clé publique / URLencode / retouche car la fonction est pourrit (-3 char / remplacement du char "+" par "%20")
        sshk=open('id_rsa.pub','r')
        ssh_key=urllib.parse.quote_plus(sshk.read())
        ssh_key=ssh_key[:len(ssh_key)-3].replace("+","%20")
        sshk.close()
        
        ip_list=list_ip(1)

        for v in range(int(count_vm)):
           
            # Vérification de la validité de l'IP
            try:
                test=ipaddress.ip_address(ip)
            except:
                print(f"{red}Le format de l'adresse IP (",ip,f") est incorrect !\nArrêt du programme !{NC}")
                exit()

            # Vérifie si l'IP est déjà utilisé
            ip_use=0
            if ip in ip_list:
                print(f"{red}l'IP",ip,f"est déjà utilisé !\nClone",v+1,f"échoué !{NC}\n")
                ip_use=1

            name=group_name[c]+str(v)
            if ip_use == 0:
                try:
                    status=proxmox.nodes(pve_node).qemu(vm_id).status.current.get()
                    #pprint.pprint(status)
                    print(f"{red}La VM",vm_id,f"existe déjà !{NC}")
                except:
                    try:
                        proxmox.nodes(pve_node).qemu(os_clone).clone.create(newid=vm_id,name=name,target=pve_node,full=1)
                        print(f"{green}Clone ",vm_id,": ",name)
                        ipconf='ip='+ip+'/23,gw='+gateway
                        proxmox.nodes(pve_node).qemu(vm_id).config.create(ciuser=ciuser,cipassword=cipassword,memory=memory_size,ipconfig0=ipconf,sshkeys=ssh_key)
                        print("Fichier cloud-init du clone ",vm_id," configuré ...")
                        try:
                            proxmox.nodes(pve_node).qemu(vm_id).resize.set(disk='scsi0',size=size)
                        except:
                            proxmox.nodes(pve_node).qemu(vm_id).resize.set(disk='scsi0',size=size)
                        print("Modification de la quantité de ressources du clone ",vm_id," réussie ...")
                        proxmox.nodes(pve_node).qemu(vm_id).config.post(agent='enabled=1')
                        print("Activation de l'agent QEMU ...")
                        proxmox.nodes(pve_node).qemu(vm_id).status.start.post()
                        print(f"Lancement de la vm ",vm_id,f" nouvellement crée !{NC}")
                    except:
                        print(f"{red}Création de la VM ",vm_id,f" échouée ...{bold}")
                        exit()
                    if os_clone == "8002":
                        proxmox.nodes(pve_node).qemu(vm_id).put('config?delete=ide0') 
                        #ide0 ou ide2 en fonction du disque utilisé par cloud-init, dans notre cas RHEL utilise le disque ide0
                        print(f"{green}Désactivation du disque Cloud-init.{NC}")
                    else:
                        proxmox.nodes(pve_node).qemu(vm_id).put('config?delete=ide2')
                        print(f"{green}Désactivation du disque Cloud-init.{NC}")
                    print(ip)
                    print("")
            ip=str(ipaddress.ip_address(ip)+1)
            vm_id=int(vm_id)+1
        
        if ciuser == "": print("\nVous pouvez vous connecter à vos VM avec l'utilisateur ansible:ansible")

# Eteint et supprime les VM de l'inventaire 
def destroy_vm():
    search()
    count_group=len(group_name)
    print(f"{bold}Suppression de ",count_group," groupe(s) !")
   
    # Liste les VM à supprimer et demande une validation de l'utilisateur
    for c in range(count_group):
        print("\nNom du groupe : ",group_name[c])

        count_vm=conf.get(group_name[c],'nb_vm')
        print("Nombre de VM du groupe : ",count_vm,"\n")
        vm_id=conf.get(group_name[c],'vmid')

        for v in range(int(count_vm)):
            print(f"{yellow}ID :",int(vm_id),f"{bold}")
            vm_id=int(vm_id)+1

    print("\nEtes vous sûr ? : [N]/o ",end=f"{yellow}");sure=input();print(f"{bold}")
    
    if sure == "o" or sure == "oui" or sure == "Oui" or sure == "OUI":
        pass
    else:
        exit()

    # Suppression des VM
    for c in range(count_group):
        vm_id=conf.get(group_name[c],'vmid')

        count_vm=conf.get(group_name[c],'nb_vm')
        for v in range(int(count_vm)):
            try:
                proxmox.nodes(pve_node).qemu(vm_id).status.stop.post()
                time.sleep(2)
                proxmox.nodes(pve_node).qemu(vm_id).delete()
                print(f"{yellow}Destruction de la VM ",vm_id,f" réussie !{bold}")
            except:
                print(f"{red}Destruction de la VM ",vm_id,f" echouée ...{bold}")
            vm_id=int(vm_id)+1

# Création d'un snapshot sur toutes les VM de l'inventaire
def snapshot():
    search()
    count_group=len(group_name)
    
    print(f"{bold}Snapshot des VM de votre inventaire :")
    for c in range(count_group):
        print("\nNom du groupe :",group_name[c])

        count_vm=conf.get(group_name[c],'nb_vm')
        print("Nombre de VM du groupe :",count_vm,"\n")

        vm_id=conf.get(group_name[c],'vmid')
        for v in range(int(count_vm)):
            print(f"{yellow}ID :",int(vm_id),f"{bold}")
            vm_id=int(vm_id)+1
    
    print("\nVeuillez saisir le nom du snapshot : ",end=f"{yellow}");snapname=input();print(f"{bold}")

    for c in range(count_group):
        vm_id=conf.get(group_name[c],'vmid')

        count_vm=conf.get(group_name[c],'nb_vm')
        for v in range(int(count_vm)):
            try:
                proxmox.nodes(pve_node).qemu(vm_id).snapshot.create(snapname=snapname)
                print(f"{green}Snapshot de la VM",vm_id,f"réussi !{bold}")
            except:
                print(f"{green}Snapshot de la VM",vm_id,f"échoué ...{bold}")
            vm_id=int(vm_id)+1
    
    print("\nFin du snapshot",snapname,"!")

# Rollback de toutes les VM de l'inventaire vers un snapshot précédemment créé
def rollback():
    search()
    count_group=len(group_name)

    print(f"{bold}Rollback des VM de votre inventaire :")
    
    for c in range(count_group):
        print("\nNom du groupe :",group_name[c])

        count_vm=conf.get(group_name[c],'nb_vm')
        print("Nombre de VM du groupe :",count_vm,"\n")
       
        vm_id=conf.get(group_name[c],'vmid')
        for v in range(int(count_vm)):
            print(f"{yellow}ID :",int(vm_id),f"{bold}")
            vm_id=int(vm_id)+1
            

    print("\nVeuillez saisir le nom du snapshot à rollback : ",end=f"{yellow}");snapname=input();print(f"{bold}")
    
    print("Etes vous sûre ? : [N]/o ",end=f"{yellow}");sure=input();print(f"{bold}")
    
    if sure == "o" or sure == "oui" or sure == "Oui" or sure == "OUI":
        pass
    else:
        exit()

    for c in range(count_group):
        vm_id=conf.get(group_name[c],'vmid')

        count_vm=conf.get(group_name[c],'nb_vm')
        for v in range(int(count_vm)):
            try:
                proxmox.nodes(pve_node).qemu(vm_id).snapshot(snapname).rollback.post()
                print(f"{yellow}Rollback de la VM",vm_id,f"réussi !{bold}")
                time.sleep(2)
                proxmox.nodes(pve_node).qemu(vm_id).status.start.post()
                print(f"{yellow}Lancement de la VM",vm_id,f"réussi !{bold}")
            except:
                print(f"{red}Rollback de la VM",vm_id,f"échoué ...{bold}")
            vm_id=int(vm_id)+1
    
    print("\nFin du rollback vers le snapshot",snapname,"!")

def list_ip(test):
    search()
    count_group=len(group_name)

    ip_list=[]

    for node in proxmox.nodes.get():
        for vm in proxmox.nodes(node['node']).qemu.get():
            try:
                vm_ip=proxmox.nodes(node['node']).qemu(vm['vmid']).agent('network-get-interfaces').get()
                ip = vm_ip['result'][1]['ip-addresses'][0]['ip-address'] 
                ip_list.append(ip)
                if test == 0:
                    print(f"VM ({bold}",vm['vmid'],f"{NC}) :{yellow}",ip,f"{NC}")
            except:
                if test == 0:
                    print("No QEMU agent")
                ip=""
           
    return ip_list

if __name__ == "__main__":
    print(f"{bold}MENU :")
    print("Que souhaitez vous faire?")
    print(f'{under}1{NU}. Afficher l\'état de proxmox')
    print(f"{under}2{NU}. Afficher toutes les VM")
    print(f"{under}3{NU}. Afficher les VM de notre inventaire")
    print(f"{under}4{NU}. Liste des IP utilisées")
    print(f"{under}5{NU}. Cloner une ou plusieurs VM")
    print(f"{under}6{NU}. Supprimer une ou plusieurs VM")
    print(f"{under}7{NU}. Snapshot d'une ou plusieurs VM")
    print(f"{under}8{NU}. Rollback d'une ou plusieurs VM\n")

    print("Choix : ",end =f"{yellow}");choix=input();print(f"{NC}")

    if choix == "1":
        show_proxmox_stats()
    elif choix == "2":
        show_all_vm()
    elif choix == "3":
        show_vm()
    elif choix == "4":
        list_ip(0)
    elif choix == "5":
        clone_vm()
    elif choix == "6":
        destroy_vm()
    elif choix == "7":
        snapshot()
    elif choix == "8":
        rollback()

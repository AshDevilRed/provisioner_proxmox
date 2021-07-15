#/bin/bash
# 
# PREREQUIS : gridsite-clients curl jq
# 
# pve_pass peut être exporter en variable environnement
# pensez à bien backslasher les char spéciaux $

# Modification de l'user / de l'ip du proxmox / de son port / et du node sur le quel créer les VM
#pve_pass=""
pve_user="root"
pve_host=172.16.1.2
pve_port=8006
pve_node="proxmox2"
memory_type="G"

# Passerelle du réseau
gateway=172.16.0.1

# Identifiant de connexion aux VM nouvellement créer
ciuser="ansible"
cipassword="ansible"

# Tableau de couleurs
bold='\033[1;37m'
NC='\033[0;39m'
under='\033[4m'
yellow='\033[0;33m'
green='\033[0;32m'

# Demande de saisie du pass proxmox si la variable n'a pas été exporter
if [ -z $pve_pass ]
then
        read -sp 'Proxmox password : ' pve_pass
fi

# NE PAS TOUCHER | Fonction pour l'incrémentation des IP
nextip(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

# Vérification de la présences des paquets requis
printf "\n${NC}Vérification de la présence des paquets requis\n"
if [ $(apt list 2>/dev/null|grep gridsite-client|awk '{ print $NF }') != "[installé]" ]
then
	printf "${bold}Veuillez installer gridsite-clients curl et jq${NC}\n"
fi

# Modifier si jamais le mot de passe de proxmox et le mdp du serveur sont différent (identique dans notre cas)
export SSHPASS=$pve_pass

# Récupération de la clé publique de proxmox 
printf "Récupération de la clé publique de proxmox\n"
sshpass -e ssh root@$pve_host 'cat ~/.ssh/id_rsa.pub' > .id_rsa.pub && chmod 600 .id_rsa.pub
urlencode $(cat .id_rsa.pub) > .id_rsa_encod.pub && chmod 600 .id_rsa_encod.pub
pve_ssh_key=$(<.id_rsa_encod.pub)


# Récupération du cookie de session ainsi que le token de prévention contre les attaques CSRF
printf "Récupération du cookie et du token de session\n\n"
curl --silent https://$pve_host:$pve_port/api2/json/access/ticket -k -d "username=$pve_user@pam&password=$pve_pass" > .access_ticket && chmod 600 .access_ticket
# regex pour récuperer le cookie et l'écrire dans un fichier "cookie"
cat .access_ticket |jq --raw-output '.data.ticket' |sed 's/^/PVEAuthCookie=/' > cookie && chmod 600 cookie
# regex pour récuperer le token de prévention CSRF et l'écrire dans un fichier "csrfp"
cat .access_ticket |jq --raw-output '.data.CSRFPreventionToken' |sed 's/^/CSRFPreventionToken:/' > csrfp && chmod 600 csrfp

# Menu du script (Status de l'hyperviseur / Création de VM / Destruction de VM / Snapshot / Rollback)
printf "${bold}Que souhaitez vous faire ?${NC}\n${bold}1. ${NC}Afficher les ${bold}status${NC} de proxmox \n${bold}2. Cloner${NC} une VM \n${bold}3. Supprimer${NC} une ou plusieurs VM \n${bold}4. Snapshot${NC} d'une ou plusieurs VM\n${bold}5. Rollback${NC} d'une ou plusieurs VM\n"

while [[ $action != 1 ]] && [[ $action != 2  ]] && [[ $action != 3 ]] && [[ $action != 4 ]] && [[ $action != 5 ]]; do
	printf "Choix : ${yellow}"
        read action
	printf "${NC}"
done

if [ $action == "1" ]
then
	# Choix du node dans notre cas proxmox2
	printf "Quel node souaithez vous joindre : ${yellow}"
        read pve_node
	printf "${NC}"
	curl --silent -k --cookie "$(<cookie)" https://$pve_host:$pve_port/api2/json/nodes/$pve_node/status | jq '.'
elif [ $action == "2" ]
then
	printf "\nQuel type d'OS souhaitez vous déployer ? ([${under}debian${NC}]/centos/rhel)\n${yellow}"
	read os_clone
	printf "${NC}"


	# Le numéro correspond à l'ID du template sur proxmox	
	if [ -z $os_clone ]
	then
		os_clone="8000"
	elif [ $os_clone == "centos" ]
	then
		os_clone="8001"
	elif [ $os_clone == "rhel" ]
	then
		os_clone="8002"
	else
		os_clone="8000" #Debian par défaut
	fi

	printf "Combien de groupes de VM souhaitez-vous créer ? \n${yellow}"
	read count_group
	
	printf "${NC}Voulez vous définir la quantité de ressource ? (default: 32Go HDD + 2 Go RAM) (${under}N${NC}/o)\n${yellow}"
	read def_choice
	printf "${NC}"

	if [ -z $def_choice ]
	then
		size="32"
		memory_size="2048"
	elif [ "$def_choice" == "o" ] || [ "$def_choice" == "oui" ] || [ "$def_choice" == "Oui" ] || [ "$def_choice" == "OUI" ]
	then
		printf "Quelle quantité de stockage voulez vous leur attribuer ? \n${yellow}"
		read size
	
		printf "${NC}Quelle quantité de RAM voulez vous leur attribuer ? (2048 pour 2Go) \n${yellow}"
		read memory_size
		printf "${NC}"
	else
		size="32"
		memory_size="2048"
	fi

	for (( i=1; i<=$count_group; i++ ))
	do	
		printf "Nom des VM du groupe\n${yellow}"
		read group_name

		printf "${NC}Nombre de VM du groupe\n${yellow}"
        	read count_vm

		printf "${NC}Premier ID du groupe (vérifier que les $count_vm ID sont bien disponibles)\n${yellow}"
        	read vm_id
		
		printf "${NC}Première IP du groupe (vérifier que les $count_vm IP sont bien disponibles)\n${yellow}"
		read ip
		printf "${NC}"

		printf "\n"
		for (( c=1; c<=$count_vm; c++ ))
		do
			# Clone la VM demandé (debian/centos/rhel)
			curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" --data-binary $"newid=$vm_id&name=$group_name$c&target=$pve_node&full=1" $"https://$pve_host:$pve_port/api2/extjs/nodes/$pve_node/qemu/$os_clone/clone" -o /dev/null #| jq '.'
			printf "${green}Clone $c terminé ...${NC}\n"
			
			# Modifie le fichier cloud-init (ip/gw/user/password/ssh_key) + Quantité de RAM
			curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" --data-binary $"ciuser=$ciuser&cipassword=$cipassword&memory=$memory_size&ipconfig0=ip%3D$ip%2F24%2Cgw%3D$gateway" --data-urlencode $"sshkeys=$pve_ssh_key" $"https://$pve_host:$pve_port/api2/extjs/nodes/$pve_node/qemu/$vm_id/config" -o /dev/null #| jq '.'
			printf "${green}Fichier cloud-init du clone $c configuré ...${NC}\n"
			
			# Modifie la quantité de stockage alloué
			curl -i --silent -k -X $'PUT' -H $(<csrfp) --cookie "$(<cookie)" --data-binary $"disk=scsi0&size=$size$memory_type" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/resize" -o /dev/null #| jq '.'
			printf "${green}Modification de la quantité de ressources du clone $c réussie !${NC}\n"
			
			# Lancement de la VM (démarre l'installation de base)
			curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/extjs/nodes/$pve_node/qemu/$vm_id/status/start" -o /dev/null #| jq '.'
			printf "${green}Lancement de la VM $c nouvellement crée !${NC}\n\n"

			vm_id=$(($vm_id+1))
			ip=$(nextip $ip)
		done	
	done

elif [ $action == "3" ]
then
	printf "\nCombien de VM voulez vous supprimer ?\n${yellow}"
	read nb_vm
	printf "${NC}"
	
	if [ $nb_vm != "1" ]
	then	
		printf "Leurs ID se suivent-ils ? [${under}O${NC}/n] \n${yellow}"
		read suivi
		printf "${NC}"
	else
		suivi="n"
	fi

	if [ -z $suivi ] || [ "$suivi" == "oui" ] || [ "$suivi" == "o" ]
	then
		suivi="O"
	fi
	if [ "$suivi" == "O" ] || [ "$suivi" == "OUI" ] || [ "$suivi" == "Oui" ]
	then
		printf "Saisir l'ID de la première VM à supprimer\n${yellow}"
		read vm_id
		printf "${NC}Suppression de toutes les VM à partir de l'ID $vm_id jusqu'à $(($vm_id+$nb_vm-1))\n"
		vm_id_sure=$vm_id
		
		for (( c=1; c<=$nb_vm; c++ ))
		do
			printf "${yellow}ID : $vm_id_sure${NC}\n"
			vm_id_sure=$(($vm_id_sure+1))
			
		done
		# Demande de validation de suppresion avec la liste des ID
		printf "\nEtes vous sûr de votre choix ? [${under}N${NC}/o]\n${yellow}"
		read sure
		printf "${NC}"
		if [ $sure == "oui" ] || [ $sure == "o" ]
		then
			sure="O"
		fi


		if [ -z $sure ]
		then
			exit
		elif [ $sure == "O" ] || [ $sure == "OUI" ] || [ $sure == "Oui" ]
		then
			for (( c=1; c<=$nb_vm; c++ ))
			do
				# Boucle de suppression des VM qui se suivent
				curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/status/stop" -o /dev/null
                                sleep 3
				curl -i --silent -k -X $'DELETE' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id" -o /dev/null #| jq '.'
				printf "${green}Suppression de la VM $vm_id terminé !${NC}\n"
				vm_id=$(($vm_id+1))
			done
		else
			exit
		fi	

	elif [ $suivi == "n" ] || [ $suivi == "non" ] || [ $suivi == "N" ] || [ $suivi == "Non" ] || [ $suivi == "NON" ]
	then
		for (( c=1; c<=$nb_vm; c++ ))
		do
			printf "\nSaisir l'ID de la VM à supprimer : ${yellow}"
			read vm_id
			printf "${yellow}Suppression de la VM $vm_id${NC}\n"
			printf "Etes vous sûr de votre choix ? [${under}N${NC}/o]\n"
			read sure
			if [ $sure == "o" ] || [ $sure == "oui" ]
			then
				sure="O"
			fi
			
			if [ -z $sure ]
                	then
                        	exit
                	elif [ $sure == "O" ] || [ $sure == "OUI" ] || [ $sure == "Oui" ]
                	then
				# Suppression d'une VM par saisie utilisateur
				curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/status/stop" -o /dev/null
				sleep 3
				curl -i --silent -k -X $'DELETE' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id" -o /dev/null
				printf "${green}Suppression de la VM $vm_id terminé !${NC}\n"
			else
				exit
			fi
		done
	fi
elif [ $action == "4" ]
then
        printf "\nCombien de VM voulez vous snapshoter ?\n${yellow}"
        read nb_vm
        printf "${NC}"

        if [ $nb_vm != "1" ]
        then
                printf "Leurs ID se suivent-ils ? [${under}O${NC}/n] \n${yellow}"
                read suivi
                printf "${NC}"
        else
                suivi="n"
        fi

	printf "Saisir le nom du snapshot\n"
	read snap_name

        if [ -z $suivi ] || [ "$suivi" == "oui" ] || [ "$suivi" == "o" ]
        then
                suivi="O"
        fi
        if [ "$suivi" == "O" ] || [ "$suivi" == "OUI" ] || [ "$suivi" == "Oui" ]
        then
                printf "Saisir l'ID de la première VM à snapshoter\n${yellow}"
                read vm_id
                printf "${NC}Snapshot de toutes les VM à partir de l'ID $vm_id jusqu'à $(($vm_id+$nb_vm-1))\n"
                vm_id_sure=$vm_id

                for (( c=1; c<=$nb_vm; c++ ))
                do
                        printf "${yellow}ID : $vm_id_sure${NC}\n"
                        vm_id_sure=$(($vm_id_sure+1))

                done
                # Demande de validation de snapshot avec la liste des ID
                printf "\nEtes vous sûr de votre choix ? [${under}N${NC}/o]\n${yellow}"
                read sure
                printf "${NC}"
                if [ $sure == "oui" ] || [ $sure == "o" ]
                then
                        sure="O"
                fi


                if [ -z $sure ]
                then
                        exit
                elif [ $sure == "O" ] || [ $sure == "OUI" ] || [ $sure == "Oui" ]
                then
                        for (( c=1; c<=$nb_vm; c++ ))
                        do
                                # Boucle de snapshot des VM qui se suivent
                                curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" --data-binary $"snapname=$snap_name" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/snapshot" -o /dev/null #| jq '.'
                                printf "${green}Snapshot de la VM $vm_id terminé !${NC}\n"
                                vm_id=$(($vm_id+1))
                        done
                else
                        exit
                fi

        elif [ $suivi == "n" ] || [ $suivi == "non" ] || [ $suivi == "N" ] || [ $suivi == "Non" ] || [ $suivi == "NON" ]
        then
                for (( c=1; c<=$nb_vm; c++ ))
                do
                        printf "\nSaisir l'ID de la VM à snapshoter : ${yellow}"
                        read vm_id
                        printf "${yellow}Snapshot de la VM $vm_id${NC}\n"
                        printf "Etes vous sûr de votre choix ? [${under}N${NC}/o]\n"
                        read sure
                        if [ $sure == "o" ] || [ $sure == "oui" ]
                        then
                                sure="O"
                        fi

                        if [ -z $sure ]
                        then
                                exit
                        elif [ $sure == "O" ] || [ $sure == "OUI" ] || [ $sure == "Oui" ]
                        then
                                # Snapshot d'une VM par saisie utilisateur
                                curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" --data-binary $"snapname=$snap_name" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/snapshot" -o /dev/null #| jq '.'
                                printf "${green}Snapshot de la VM $vm_id terminé !${NC}\n"
                        else
                                exit
                        fi
                done
        fi
elif [ $action == "5" ]
then
        printf "\nCombien de VM voulez vous rollback ?\n${yellow}"
        read nb_vm
        printf "${NC}"

        if [ $nb_vm != "1" ]
        then
                printf "Leurs ID se suivent-ils ? [${under}O${NC}/n] \n${yellow}"
                read suivi
                printf "${NC}"
        else
                suivi="n"
        fi

	printf "Saisir le nom du snapshot à Rollback\n"
	read snap_name

        if [ -z $suivi ] || [ "$suivi" == "oui" ] || [ "$suivi" == "o" ]
        then
                suivi="O"
        fi
        if [ "$suivi" == "O" ] || [ "$suivi" == "OUI" ] || [ "$suivi" == "Oui" ]
        then
                printf "Saisir l'ID de la première VM à rollback\n${yellow}"
                read vm_id
                printf "${NC}rollback de toutes les VM à partir de l'ID $vm_id jusqu'à $(($vm_id+$nb_vm-1))\n"
                vm_id_sure=$vm_id

                for (( c=1; c<=$nb_vm; c++ ))
                do
                        printf "${yellow}ID : $vm_id_sure${NC}\n"
                        vm_id_sure=$(($vm_id_sure+1))

                done
                # Demande de validation du rollback avec la liste des ID
                printf "\nEtes vous sûr de votre choix ? [${under}N${NC}/o]\n${yellow}"
                read sure
                printf "${NC}"
                if [ $sure == "oui" ] || [ $sure == "o" ]
                then
                        sure="O"
                fi


                if [ -z $sure ]
                then
                        exit
                elif [ $sure == "O" ] || [ $sure == "OUI" ] || [ $sure == "Oui" ]
                then
                        for (( c=1; c<=$nb_vm; c++ ))
                        do
                                # Boucle de rollback des VM qui se suivent
                                curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/snapshot/$snap_name/rollback" -o /dev/null #| jq '.'
                                printf "${green}Rollback de la VM $vm_id terminé !${NC}\n"
								# Lancement de la VM
								sleep 3
								curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/extjs/nodes/$pve_node/qemu/$vm_id/status/start" -o /dev/null
                                vm_id=$(($vm_id+1))
                        done
                else
                        exit
                fi

        elif [ $suivi == "n" ] || [ $suivi == "non" ] || [ $suivi == "N" ] || [ $suivi == "Non" ] || [ $suivi == "NON" ]
        then
                for (( c=1; c<=$nb_vm; c++ ))
                do
                        printf "\nSaisir l'ID de la VM à rollback : ${yellow}"
                        read vm_id
                        printf "${yellow}rollback de la VM $vm_id${NC}\n"
                        printf "Etes vous sûr de votre choix ? [${under}N${NC}/o]\n"
                        read sure
                        if [ $sure == "o" ] || [ $sure == "oui" ]
                        then
                                sure="O"
                        fi

                        if [ -z $sure ]
                        then
                                exit
                        elif [ $sure == "O" ] || [ $sure == "OUI" ] || [ $sure == "Oui" ]
                        then
                                # rollback d'une VM par saisie utilisateur
                                curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/json/nodes/$pve_node/qemu/$vm_id/snapshot/$snap_name/rollback" -o /dev/null #| jq '.'
                                # Lancement de la VM
								sleep 3
								curl -i --silent -k -X $'POST' -H $(<csrfp) --cookie "$(<cookie)" $"https://$pve_host:$pve_port/api2/extjs/nodes/$pve_node/qemu/$vm_id/status/start" -o /dev/null
								printf "${green}Rollback de la VM $vm_id terminé !${NC}\n"
                        else
                                exit
                        fi
                done
        fi
fi

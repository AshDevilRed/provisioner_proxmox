#!/bin/bash
# Script permettant le partage des clé en passant par une machine autorisé 
# Utilisable dans le cas ou la connexion par mot de passe est interdite
# Les ip doivent se suivrent

name="ansible"
ip_1="172.16.1.159"
nb_vm_1=1
ip_2="172.16.1.152"
nb_vm_2=5

first_turn=1

# Fonction d'incrémentation d'IP
nextip(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

printf "Début de l'échange des clés ...\n"
# Boucle sur la liste 1
for y in {1..$nb_vm_1}
do
	ssh-keygen -f "/home/sam/.ssh/known_hosts" -R "$ip_1"
	# Création des clé publique et privé
	ssh $name@$ip_1 "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y >/dev/null 2>&1"
	# Copie sur la machine autorisé
	scp $name@$ip_1:/home/$name/.ssh/id_rsa.pub $HOME/id_rsa.pub >/dev/null 2>&1


	# Boucle sur la liste 2
	for (( i=1; i<=$nb_vm_2; i++ ))
	do
		# Copie et ajout dans la liste des clé autorisé sur l'ip de la liste 2
		scp $HOME/id_rsa.pub $name@$ip_2:/home/$name/id_rsa.pub >/dev/null 2>&1
		ssh $name@$ip_2 "cat /home/$name/id_rsa.pub >> /home/$name/.ssh/authorized_keys"
   	
		# Ajout de la clé IP 2 vers la machine IP 1
		if [ first_turn == 1 ]
		then
			ssh $name@$ip_2 "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y >/dev/null 2>&1"
			scp $name@$ip_2:/home/$name/.ssh/id_rsa.pub $HOME/id_rsa.pub >/dev/null 2>&1
		fi
		scp $HOME/id_rsa.pub $name@$ip_1:/home/$name/id_rsa.pub >/dev/null 2>&1
		ssh $name@$ip_1 "cat /home/$name/id_rsa.pub >> /home/$name/.ssh/authorized_keys"
		printf "IP cible : $ip_2\n"
		ip_2=$(nextip $ip_2)
		first_turn=0
	done
	
	printf "Echange des clés SSH sur la machine $ip_1 terminé !\n"
	ip_1=$(nextip $ip_1)
done

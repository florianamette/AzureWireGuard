#!/bin/bash

## Début du script

# Mise à jour et mise à niveau des paquets
apt-get update -y 
unattended-upgrades --verbose

# Activation du transfert IP
sed -i -e 's/#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sed -i -e 's/#net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sysctl -p

# Installation de WireGuard
add-apt-repository ppa:wireguard/wireguard -y 
apt-get update -y 
apt-get install linux-headers-$(uname -r) -y
apt-get install wireguard -y

# Création du répertoire pour les clés de sécurité
mkdir /home/$2/WireGuardSecurityKeys
umask 077
mkdir /home/$2/config/

# Génération des clés du serveur et de la clé pré-partagée
wg genkey | tee /home/$2/WireGuardSecurityKeys/server_private_key | wg pubkey > /home/$2/WireGuardSecurityKeys/server_public_key
wg genpsk > /home/$2/WireGuardSecurityKeys/preshared_key

# Génération des clés pour 100 clients
for i in $(seq 1 100)
do
    wg genkey | tee /home/$2/WireGuardSecurityKeys/client_${i}_private_key | wg pubkey > /home/$2/WireGuardSecurityKeys/client_${i}_public_key
done

# Lecture des clés générées
server_private_key=$(</home/$2/WireGuardSecurityKeys/server_private_key)
preshared_key=$(</home/$2/WireGuardSecurityKeys/preshared_key)
server_public_key=$(</home/$2/WireGuardSecurityKeys/server_public_key)

# Configuration du serveur WireGuard
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.13.13.1/24
SaveConfig = true
PrivateKey = $server_private_key
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# Ajout des clients dans la configuration du serveur
for i in $(seq 1 100)
do
    client_public_key=$(</home/$2/WireGuardSecurityKeys/client_${i}_public_key)

    echo "[Peer]
PublicKey = $client_public_key
PresharedKey = $preshared_key
AllowedIps = 10.0.10.$((100 + i))/16" >> /etc/wireguard/wg0.conf
done

# Création des fichiers de configuration pour chaque client
for i in $(seq 1 100)
do
    client_private_key=$(</home/$2/WireGuardSecurityKeys/client_${i}_private_key)

    cat > /home/$2/config/wg${i}.conf << EOF
[Interface]
PrivateKey = $client_private_key
Address = 10.0.10.$((100 + i))/24

[Peer]
PublicKey = $server_public_key
PresharedKey = $preshared_key
EndPoint = $1:51820
AllowedIps = 10.0.0.0/8
PersistentKeepAlive = 25
EOF

    chmod go+r /home/$2/wg0-client-${i}.conf
done


# Activation du service WireGuard
wg-quick up wg0
systemctl enable wg-quick@wg0

# Mise à niveau complète
apt-get full-upgrade -y

# Nettoyage
apt-get autoremove -y
apt-get clean

sleep 5
reboot


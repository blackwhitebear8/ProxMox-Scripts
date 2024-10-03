#!/bin/bash

# Log naar een bestand, inclusief foutmeldingen
exec > >(tee -a ./createvm.log) 2>&1

# Zorg dat het script met vier parameters wordt aangeroepen: VMID, STORAGE, VMNAME en SSH_KEYS_PATH
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <VMID> <STORAGE> <VMNAME> <SSH_KEYS_PATH>"
    exit 1
fi

echo "VMID: $VMID"
echo "STORAGE: $STORAGE"
echo "VMNAME: $VMNAME"
echo "SSH_KEYS_PATH: $SSH_KEYS_PATH"

# Variabelen op basis van ingevoerde parameters
VMID=$1
STORAGE=$2
VMNAME=$3
SSH_KEYS_PATH=$4

# Controleer of het SSH-key bestand bestaat
if [ ! -f "$SSH_KEYS_PATH" ]; then
    echo "Error: SSH keys file not found at $SSH_KEYS_PATH"
    exit 1
fi

# Vereiste packages installeren
sudo apt install libguestfs-tools -y

# Vernietig eventuele bestaande VM met dezelfde ID
qm destroy $VMID --destroy-unreferenced-disks 1 --purge 1

# Download de Debian cloud image
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2

# Pas de image aan met de vereiste tools en configuraties
virt-customize --install qemu-guest-agent,htop,curl,avahi-daemon,console-setup,cron,cifs-utils -a debian-12-generic-amd64.qcow2
virt-customize -a debian-12-generic-amd64.qcow2 --truncate /etc/machine-id --truncate /var/lib/dbus/machine-id

# Maak een nieuwe VM aan met de opgegeven parameters
qm create $VMID --name $VMNAME --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0,firewall=1 --agent 1

# Importeer de aangepaste image naar de opgegeven opslaglocatie
qm importdisk $VMID debian-12-generic-amd64.qcow2 $STORAGE

# Stel de schijven en andere VM-instellingen in
qm set $VMID --scsihw virtio-scsi-single --scsi0 $STORAGE:$VMID/vm-$VMID-disk-0.raw,discard=on,iothread=1,ssd=1,format=raw
qm set $VMID --ide0 $STORAGE:cloudinit,format=raw
qm set $VMID --ide2 none,media=cdrom
qm set $VMID --bios ovmf
qm set $VMID --machine q35 
qm set $VMID --tablet 0
qm set $VMID --serial0 socket

# Stel netwerkinstellingen en CPU-configuraties in
qm set $VMID --ipconfig0 ip=dhcp,ip6=auto
qm set $VMID --cpu cputype=host,flags="+md-clear;+spec-ctrl;+aes"

# Stel Cloud-Init instellingen in
qm set $VMID --ciuser gebruiker
qm set $VMID --ciupgrade 1

# Overige instellingen zoals automatische start en SSH-sleutels
qm set $VMID --onboot 1
qm set $VMID --sshkeys $SSH_KEYS_PATH
qm set $VMID --efidisk0 $STORAGE:0,format=raw,pre-enrolled-keys=1

# Stel de bootvolgorde in
qm set $VMID --boot order="scsi0;ide2;net0"

# Pas de grootte van de schijf aan naar 10GB
qm resize $VMID scsi0 10G

# Zet de VM om in een template
qm template $VMID

# Verwijder de gedownloade image
rm debian-12-generic-amd64.qcow2

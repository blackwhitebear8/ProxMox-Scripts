#!/bin/bash

# Log naar een bestand, inclusief foutmeldingen
exec > >(tee -a ./createvm.log) 2>&1

# Log de start van het script
echo "Script gestart op: $(date)"

while true; do
    read -p "Voer de VMID in (getal): " VMID
    if [[ "$VMID" =~ ^[0-9]+$ ]]; then
        # Controleer of de VM al bestaat direct na invoer
        if qm list | awk '{print $1}' | grep -q "^$VMID$"; then
            echo "Een VM of template met ID $VMID bestaat al."
            read -p "Wil je deze overschrijven? (j/n): " antwoord
            if [[ ! "$antwoord" =~ ^[jJ]$ ]]; then
                echo "Afgebroken door de gebruiker."
                exit 0
            fi

            # Indien bevestigd, verwijder de bestaande VM
            echo "Verwijderen van de bestaande VM met ID $VMID..."
            qm stop $VMID --skiplock  # Stop de VM als deze draait
            qm destroy $VMID --destroy-unreferenced-disks 1 --purge 1  # Verwijder de VM inclusief de schijven
            echo "De bestaande VM met ID $VMID is verwijderd."
            # Op dit punt willen we niet opnieuw om een VMID vragen, maar doorgaan met de rest van het script
            break
        else
            echo "Geen bestaande VM met ID $VMID gevonden."
            break  # Verlaat de loop als er geen bestaande VM is gevonden
        fi
    else
        echo "Ongeldige invoer. Voer een geldig getal in voor de VMID."
    fi
done

# Vraag de gebruiker om de VMID en valideer deze
#while true; do
#    read -p "Voer de VMID in (getal): " VMID
#    if [[ "$VMID" =~ ^[0-9]+$ ]]; then
#        break
#    else
#        echo "Ongeldige invoer. Voer een geldig getal in voor de VMID."
#    fi
#done

# Vraag de gebruiker om de opslag
read -p "Voer de opslag in (bijv. data-btrfs): " STORAGE

# Vraag de gebruiker om de naam van de VM
read -p "Voer de naam van de VM in: " VMNAME

# Vraag de gebruiker om het pad naar de SSH-sleutels en controleer of het bestand bestaat
while true; do
    read -p "Voer het pad naar de SSH-sleutels in: " SSH_KEYS_PATH
    if [ -f "$SSH_KEYS_PATH" ]; then
        echo "SSH-sleutels gevonden op: $SSH_KEYS_PATH"
        break  # Verlaat de loop als het bestand bestaat
    else
        echo "Error: SSH keys file not found at $SSH_KEYS_PATH. Probeer het opnieuw."
    fi
done

# Weergeven van de ingevoerde variabelen
echo "Gekozen instellingen:"
echo "VMID: $VMID"
echo "STORAGE: $STORAGE"
echo "VMNAME: $VMNAME"
echo "SSH_KEYS_PATH: $SSH_KEYS_PATH"

# Bevestigingsprompt
read -p "Klopt alles? (j/n): " bevestiging
if [[ ! "$bevestiging" =~ ^[jJ]$ ]]; then
    echo "Afgebroken door de gebruiker."
    exit 0
fi

echo "Voortzetten met de volgende instellingen..."

# Vereiste packages installeren
sudo apt install libguestfs-tools -y

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

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

# Keuze voor het downloaden van het besturingssysteem
while true; do
    echo "Kies het besturingssysteem dat je wilt downloaden:"
    echo "1) OS-LOOS"
    echo "2) Debian 12"
    echo "3) Ubuntu 22.04"
    echo "4) Ubuntu 24.04"
    echo "5) Almalinux 9"
    echo "6) Windows server 2025 EVAL GUI TODO"
    echo "7) Windows server 2025 EVAL TODO"
    read -p "Voer je keuze in (1 -7 ): " keuze

    case $keuze in
        1)
            IMAGE_URL=""
            IMAGE_NAME=""
            echo "OS-LOOS geselecteerd."
            break
            ;;
        2)
            IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
            IMAGE_NAME="debian-12-generic-amd64.qcow2"
            echo "Debian 12 geselecteerd."
            break
            ;;
        3)
            IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
            IMAGE_NAME="jammy-server-cloudimg-amd64.img"
            echo "Ubuntu 22.04 geselecteerd."
            break
            ;;
        4)
            IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
            IMAGE_NAME="noble-server-cloudimg-amd64.img"
            echo "Ubuntu 24.04 geselecteerd."
            break
            ;;
        5)
            IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
            IMAGE_NAME="AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
            echo "Almalinux 9 geselecteerd."
            break
            ;;
        6)
            IMAGE_URL=""
            IMAGE_NAME=""
            echo "Windows server 2025 EVAL GUI geselecteerd."
            break
            ;;
        7)
            IMAGE_URL=""
            IMAGE_NAME=""
            echo "Windows server 2025 EVAL geselecteerd."
            break
            ;;
        *)
            echo "Ongeldige keuze. Voer 1 - 7 in."
            ;;
    esac
done

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

# Vraag de gebruiker om de disk grootte en valideer dat het alleen cijfers zijn
while true; do
    read -p "Voer de gewenste disk grootte in GiB: " DISK_SIZE
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
        echo "Geldige disk grootte: ${DISK_SIZE} GiB"
        break  # Verlaat de loop als de invoer correct is
    else
        echo "Ongeldige invoer. Voer een geldig getal in voor de disk grootte (bijv. 10)."
    fi
done

# Functie om beschikbare opslaglocaties op te halen en te laten kiezen
function kies_storage() {
    echo "Beschikbare storage op de Proxmox server:"

    # Haal de beschikbare opslaglocaties op
    STORAGE_LIST=$(pvesm status | awk 'NR>1 {print $1}')  # Skip de eerste regel (header)

    # Controleer of er opslaglocaties beschikbaar zijn
    if [ -z "$STORAGE_LIST" ]; then
        echo "Geen opslaglocaties gevonden op de server."
        exit 1
    fi

    # Toon de beschikbare opslaglocaties en laat de gebruiker kiezen
    PS3="Kies de gewenste storage locatie: "
    select STORAGE in $STORAGE_LIST; do
        if [[ -n "$STORAGE" ]]; then
            echo "Je hebt gekozen voor opslaglocatie: $STORAGE"
            break
        else
            echo "Ongeldige keuze, probeer het opnieuw."
        fi
    done
}

# Roep de functie aan om de opslag te kiezen
kies_storage

# Weergeven van de ingevoerde variabelen
echo "Gekozen instellingen:"
echo "VMID: $VMID"
echo "STORAGE: $STORAGE"
echo "VMNAME: $VMNAME"
echo "DISK_SIZE: $DISK_SIZE"
echo "SSH_KEYS_PATH: $SSH_KEYS_PATH"
echo "Geselecteerd image: $IMAGE_URL"
echo "Op te slaan image naam: $IMAGE_NAME"

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
wget -O "$IMAGE_NAME" "$IMAGE_URL"

# Pas de image aan met de vereiste tools en configuraties
case $keuze in
    6|7)  # OS-LOOS
        ;;
    2|3|4)  # Debian en Ubuntu
        virt-customize --install qemu-guest-agent,htop,curl,avahi-daemon,console-setup,cron,cifs-utils -a "$IMAGE_NAME"
        virt-customize --run-command "systemctl enable qemu-guest-agent" -a "$IMAGE_NAME"
        virt-customize -a "$IMAGE_NAME" --truncate /etc/machine-id --truncate /var/lib/dbus/machine-id
        ;;
    5)  # RHEL
        virt-customize --install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -a "$IMAGE_NAME"
        virt-customize --install qemu-guest-agent,htop,curl,cifs-utils -a "$IMAGE_NAME"
        virt-customize --run-command "systemctl enable qemu-guest-agent" -a "$IMAGE_NAME"
        ;;
    6|7)  # Windows
        ;;
esac

# Maak een nieuwe VM aan met de opgegeven parameters
qm create $VMID --name $VMNAME --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0,firewall=1 --agent 1

# Importeer de aangepaste image naar de opgegeven opslaglocatie
case $keuze in
    0|6|7)  # OS-LOOS / Windows
        qm set $VMID --scsihw virtio-scsi-single 
        ;;
    2|3|4|5)  # Debian en Ubuntu en RHEL
        qm importdisk $VMID "$IMAGE_NAME" $STORAGE
        qm set $VMID --scsihw virtio-scsi-single --scsi0 $STORAGE:$VMID/vm-$VMID-disk-0.raw,discard=on,iothread=1,ssd=1,format=raw
        ;;
esac

# Stel de schijven en andere VM-instellingen in
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
case $keuze in
    0|6|7)  # OS-LOOS / WIndows
        qm set $VMID --boot order="ide2;net0"
        ;;
    1|2|3|4|5)  # Debian en Ubuntu en RHEL
        qm set $VMID --boot order="scsi0;ide2;net0"
        ;;
esac

# Pas de grootte van de schijf aan naar wat er opgegeven is
qm resize $VMID scsi0 "$DISK_SIZE"G

# Zet de VM om in een template
qm template $VMID

# Verwijder de gedownloade image
case $keuze in
    0|6|7)  # OS-LOOS / WIndows
        ;;
    1|2|3|4|5)  # Debian en Ubuntu en RHEL
        rm "$IMAGE_NAME"
        ;;
esac

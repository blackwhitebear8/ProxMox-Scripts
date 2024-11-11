#!/bin/bash

# Standaardduur in seconden (bijvoorbeeld 60 seconden)
DEFAULT_DURATION=60
DURATION=$DEFAULT_DURATION

# Aantal runs
DEFAULT_REPEATS=5
REPEATS=$DEFAULT_REPEATS

# Standaard slaaptijd tussen runs
DEFAULT_SLEEPTIME=60
SLEEPTIME=$DEFAULT_SLEEPTIME

# Uitvoer CSV-bestand
CSV_FILE="results.csv"

# Functie voor het verwijderen van het CSV-bestand
delete_csv() {
    if [ -f "$CSV_FILE" ]; then
        echo "Het CSV-bestand '$CSV_FILE' bestaat al en wordt verwijderd."
        rm "$CSV_FILE"
    fi
}

# Functie om argumenten te verwerken
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--delete)
            delete_csv
            shift
            ;;
        -t|--duration)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                DURATION=$2
                echo "Duur van de test ingesteld op $DURATION seconden."
                shift 2
            else
                echo "Fout: je moet een geldige numerieke waarde voor de duur opgeven."
                exit 1
            fi
            ;;
        -r|--repeats)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                REPEATS=$2
                echo "Aantal runs ingesteld op $REPEATS."
                shift 2
            else
                echo "Fout: je moet een geldige numerieke waarde voor runs opgeven."
                exit 1
            fi
            ;;
        -s|--sleep)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                SLEEPTIME=$2
                echo "slaaptijd ingesteld op $SLEEPTIME seconden."
                shift 2
            else
                echo "Fout: je moet een geldige numerieke waarde voor slaaptijd opgeven."
                exit 1
            fi
            ;;
        *)
            echo "Ongeldig argument: $1"
            exit 1
            ;;
    esac
done

# Maak het CSV-bestand aan met headers
echo "run,slaaptijd,timestamp,duration,read_bw_mbps,write_bw_mbps,read_iops,write_iops,avg_latency" > "$CSV_FILE"

# Variabelen voor het berekenen van gemiddelden
total_read_bw=0
total_write_bw=0
total_read_iops=0
total_write_iops=0
total_latency=0

# Loop voor meerdere tests
for ((i=1; i<=REPEATS; i++))
do
    echo "Test $i van de $REPEATS runs..."

    # FIO uitvoeren
    fio_output=$(fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=4k \
      --iodepth=64 --readwrite=randrw --rwmixread=75 --size=4G --filename=./fio.file \
      --lat_percentiles=1 --output-format=json --time_based --runtime=$DURATION --group_reporting)

    # Extract FIO metrics
    fio_read_iops=$(echo "$fio_output" | jq -r '.jobs[0].read.iops')
    fio_write_iops=$(echo "$fio_output" | jq -r '.jobs[0].write.iops')
    fio_read_bw_kbps=$(echo "$fio_output" | jq -r '.jobs[0].read.bw')
    fio_write_bw_kbps=$(echo "$fio_output" | jq -r '.jobs[0].write.bw')
    fio_read_bw_mbps=$(echo "scale=2; $fio_read_bw_kbps / 1024" | bc)
    fio_write_bw_mbps=$(echo "scale=2; $fio_write_bw_kbps / 1024" | bc)
     
    # Ioping uitvoeren
    ioping_output=$(ioping -c $DURATION ./)
    avg_latency=$(echo "$(echo "$ioping_output" | grep 'min/avg/max/mdev' | awk '{print $6}')")

    # Timestamp voor de CSV
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Variabelen omzetten naar 2 decimalen
    fio_read_iops=$(printf "%.2f" $fio_read_iops)
    fio_write_iops=$(printf "%.2f" $fio_write_iops)

    # Resultaten exporteren naar CSV
    echo "$i / $REPEATS,$SLEEPTIME seconden,$timestamp,$DURATION seconden,$fio_read_bw_mbps,$fio_write_bw_mbps,$fio_read_iops,$fio_write_iops,$avg_latency us" >> "$CSV_FILE"

    # Tel de waarden op voor gemiddelde berekening (zorg ervoor dat de waarden decimaal zijn)
    total_read_bw=$(echo "$total_read_bw + $fio_read_bw_mbps" | bc)
    total_write_bw=$(echo "$total_write_bw + $fio_write_bw_mbps" | bc)
    total_read_iops=$(echo "$total_read_iops + $fio_read_iops" | bc)
    total_write_iops=$(echo "$total_write_iops + $fio_write_iops" | bc)
    total_latency=$(echo "$total_latency + $avg_latency" | bc)

    # Opruimen
    rm -rf fio.file

    # Resultaten tonen
    echo "==== Instellingen ===="
    echo "Run: $i / $REPEATS"
    echo "Slaaptijd: $SLEEPTIME seconden"
    echo "Tijd: $DURATION seconden"
    echo "======================"

    echo "=== FIO Resultaten ==="
    echo "Read Bandwidth (MB/s): $fio_read_bw_mbps"
    echo "Write Bandwidth (MB/s): $fio_write_bw_mbps"
    echo "Read IOPS: $fio_read_iops"
    echo "Write IOPS: $fio_write_iops"
    echo "======================"

    echo "=== Ioping Resultaten ==="
    echo "Gemiddelde Latency: $avg_latency us"
    echo "========================="

        # Wacht 60 seconden voor de volgende test
    if [[ $i -lt $REPEATS ]]; then
        echo "Wacht $SLEEPTIME seconden voor de volgende test..."
        sleep $SLEEPTIME
    fi
done

# Alleen de gemiddelden berekenen als er 2 of meer herhalingen zijn
if [[ $REPEATS -ge 2 ]]; then
    # Bereken de gemiddelde waarden na alle runs
    avg_read_bw=$(echo "scale=2; $total_read_bw / $REPEATS" | bc)
    avg_write_bw=$(echo "scale=2; $total_write_bw / $REPEATS" | bc)
    avg_read_iops=$(echo "$total_read_iops / $REPEATS" | bc)
    avg_write_iops=$(echo "$total_write_iops / $REPEATS" | bc)
    avg_latency=$(echo "scale=2; $total_latency / $REPEATS" | bc)

    # Voeg de gemiddelde waarden toe aan het CSV-bestand
    echo "Gemiddelden,,,,$avg_read_bw,$avg_write_bw,$avg_read_iops,$avg_write_iops,$avg_latency us" >> "$CSV_FILE"
fi

echo "Alle tests zijn voltooid. Resultaten zijn opgeslagen in $CSV_FILE"

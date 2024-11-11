ProxMox Scripts

LET-OP: Dit script is allen getest op file based storage!
LET-OP: Windows is nog TODO!

createvm.sh:
Maakt templates op basis van inputs die tijdens het uitvoeren ingegegevn worden.

```chmod +x createvm.sh```

* je geeft de gewenste vmid op (als deze al bestaat vraagt hij of je hem wilt overschrijven).
* Dan krijg je een OS keuze list.
* Dan geef je de template een naam.
* dan geef je de gewenste gebruikersnaam op.
* Dan geef je de locatie op van de ssh keys die je wilt importeren bijv: /root/ssh.txt
* dan geef je de gewenste template disk grote op.
* Dan list hij de beschikbare storage waar je uit moet kiezen.
* Hierna vraagt hij of alle gegevens kloppen voor hij begint.

Disk test script met FIO en IOPING

```chmod +x disk-test.sh```
```./disk-test.sh -d -t 2 -r 2 -s 2```

* -d \ --delete = verwijder het resultaten csv bestand.
* -t \ --duration = test duur van het script in seconden
* -r \ --repeats = hoevaak je wilt testen
* -s \ --sleep = hoelang je wilt wachten tussen de tests

Je kan -r en -s weg laten om hem 1x te draaien.
Het script starten zonder argumenten is ook mogelijk. Dan zal hij met de standaard waarden de teste uitvoeren.
Deze standaardwaarden zijn: 5 runs van elk 60 seconden lang testen met een wachttijd van 60 seconden tussen elke run.

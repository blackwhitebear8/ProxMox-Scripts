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

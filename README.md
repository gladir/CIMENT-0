# CIMENT-0
Suite de commande écrit en Turbo Pascal/Free Pascal pour le ciment et le béton

## BETON

`BETON.PAS` : calculs de béton (volume, dosage, masse, rapport eau/ciment, résistance à la compression, formulation). Compatible Turbo Pascal 7 et Free Pascal, sans dépendance (unité `Dos` seulement, aucun fichier d'inclusion).

```
BETON -volume 5 4 0.15
BETON -dosage 350 -volume 3
BETON -masse 3 -densite 2400
BETON -rapport-ec 175 350
BETON -compression 600000 20000
BETON -melange SAMPLES\BETON\DALLE.TXT
BETON -rapport RESULTAT.TXT
BETON /?
```

Des exemples de fichiers de formulation sont dans `SAMPLES\BETON\`.

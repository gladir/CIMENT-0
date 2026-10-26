# CIMENT-0
Suite de commande écrit en Turbo Pascal/Free Pascal pour le ciment et le béton

<h2>Liste des fichiers</h3>

Voici la liste des différents fichiers proposés dans CIMENT-0 :

<table>
  <tr>
    <th>Nom</th>
    <th>Description</th>
  </tr>
  <tr>
    <td><b>BETON.PAS</b></td>
    <td>Cette commande permet de calculer le béton (volume, dosage, masse, rapport eau/ciment, résistance à la compression, formulation).</b>
  </tr>
  <tr>
	  <td><b>VCCTL.PAS</b></td>
	  <td>Cette commande permet de simuler, à la manière du logiciel VCCTL (Virtual Cement and Concrete Testing Laboratory), la microstructure 3D et l'hydratation d'une pâte de ciment (ciment Portland, cendres volantes, laitier, calcaire, fumée de silice) par automate cellulaire, puis d'estimer ses propriétés : degré d'hydratation, chaleur dégagée, retrait chimique, porosité, percolation, distribution des pores, modules élastiques, résistance à la compression, conductivité et diffusivité, zone de transition interfaciale.</td>
  </tr>
</table>

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

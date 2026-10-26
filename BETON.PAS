{ @author: Sylvain Maltais (support@gladir.com)
 @created: 2026
 @version: 1.00
 @website(https://www.gladir.com/ciment-0)
 @abstract(Target: Turbo Pascal 7, Free Pascal
 @description: Calculs de beton en ligne de commande }

Program BETON;

{ ======================================================================
  Compatible Turbo Pascal 7 et Free Pascal.
  Aucune dependance : seule l'unite Dos est utilisee (pour la date du
  rapport) et aucun fichier d'inclusion n'est utilise.
  Le source est volontairement en ASCII pur (sans accents) afin que les
  messages s'affichent correctement dans n'importe quelle page de code DOS.
  Hypotheses de calcul (methode des volumes absolus) :
    - masse volumique du ciment      3100 kg/m3
    - masse volumique des granulats  2650 kg/m3
    - air occlus                        2 % du volume
    - rapport eau/ciment par defaut  0.50
    - sable = 40 % du volume des granulats, gravier = 60 %
  ====================================================================== }

Uses Dos;

Const
 VERSION        = '1.0';
 D_CIMENT       = 3100.0;
   { kg/m3 }
 D_GRANULATS    = 2650.0;
   { kg/m3 }
 AIR            = 0.02;
     { m3 d'air occlus par m3 de beton }
 PART_SABLE     = 0.40;
     { part du sable dans le volume des granulats }
 EC_DEFAUT      = 0.50;
 DOSAGE_DEFAUT  = 350.0;
    { kg de ciment par m3 }
 DENSITE_DEFAUT = 2400.0;
   { kg/m3 }
 PERTE_DEFAUT   = 5.0;
      { % }
 SAC_DEFAUT     = 25.0;
     { kg }
 PSI_PAR_MPA    = 145.038;
 NB_CLASSES     = 14;
  { Classes de resistance : fck sur cylindre / fck sur cube (MPa) }
 ClCyl : Array[1..NB_CLASSES] Of Integer =
 (12, 16, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90);
 ClCube: Array[1..NB_CLASSES] Of Integer =
 (15, 20, 25, 30, 37, 45, 50, 55, 60, 67, 75, 85, 95, 105);

Type
  { Une valeur a 0 signifie "non precisee" : elle sera deduite. }
 TFormule = Record
  Nom: String;
  Volume, Ciment, Eau, Sable, Gravier, Perte, Sac: Real;
 End;

Var
 OptAide, OptVolume, OptDosage, OptMasse, OptDensite: Boolean;
 OptEC, OptComp, OptMelange, OptRapport: Boolean;
 VolN: Integer;
 Vol: Array[1..3] Of Real;
 Dosage, Masse, Densite, EauEC, CimentEC, Force, Surface: Real;
 FichierMelange, FichierRapport: String;
 Rapport: Text;
 RapportOuvert: Boolean;
 Fait: Boolean;
{ ---------------------------------------------------------------- }
{ Utilitaires                                                      }
{ ---------------------------------------------------------------- }

Function Majuscules(S: String): String;
Var
 I: Integer;
Begin
 For I := 1 To Length(S) Do S[I] := UpCase(S[I]);
 Majuscules := S;
End;

Function Epurer(S: String): String;Begin
 While (Length(S) > 0) And (S[1] <= ' ') Do Delete(S, 1, 1);
 While (Length(S) > 0) And (S[Length(S)] <= ' ') Do Delete(S, Length(S), 1);
 Epurer := S;
End;

Function PadR(S: String; N: Integer): String;Begin
 While Length(S) < N Do S := S + ' ';
 PadR := S;
End;

Function PadL(S: String; N: Integer): String;Begin
 While Length(S) < N Do S := ' ' + S;
 PadL := S;
End;

Function Fmt(X: Real; Dec: Integer): String;
Var
 S: String;
Begin
 Str(X:0:Dec, S);
 Fmt := S;
End;
{ Sans decimales si la valeur est entiere, sinon 2 decimales }

Function FmtSouple(X: Real): String;Begin
 If Abs(X - Round(X)) < 0.0005 Then FmtSouple := Fmt(X, 0)
                               Else FmtSouple := Fmt(X, 2);
End;

Function IntStr(N: LongInt): String;
Var
 S: String;
Begin
 Str(N, S);
 IntStr := S;
End;

Function Plafond(X: Real): LongInt;
Var
 N: LongInt;
Begin
 N := Trunc(X);
 If X - N > 0.000001 Then N := N + 1;
 Plafond := N;
End;
{ Accepte la virgule comme separateur decimal. Nombres positifs seulement. }

Function LireReel(S: String; Var R: Real): Boolean;
Var
 P, Code: Integer;
Begin
 LireReel := False;
 S := Epurer(S);
 If (Length(S) = 0) Or Not (S[1] In ['0'..'9', '.', ',']) Then Exit;
 P := Pos(',', S);
 If P > 0 Then S[P] := '.';
 Val(S, R, Code);
 LireReel := (Code = 0);
End;
{ Les chemins DOS (SAMPLES\BETON\X.TXT) restent utilisables sous Unix }
Function Chemin(S: String): String;
{$IFDEF UNIX}

 Var
  I: Integer;
 {$ENDIF}
Begin
 {$IFDEF UNIX}
  For I := 1 To Length(S) Do    If S[I] = '\' Then S[I] := '/';
 {$ENDIF}
 Chemin := S;
End;

Function Repeter(C: Char; N: Integer): String;
Var
 S: String;
Begin
 S := '';
 While Length(S) < N Do S := S + C;
 Repeter := S;
End;
{ ---------------------------------------------------------------- }
{ Sortie : ecran + fichier de rapport (-rapport)                   }
{ ---------------------------------------------------------------- }

Procedure Say(S: String);Begin
 WriteLn(S);
 If RapportOuvert Then WriteLn(Rapport, S);
End;

Procedure FinRapport;Begin
 If RapportOuvert Then Begin
  Close(Rapport);
  RapportOuvert := False;
 End;
End;

Procedure Echec(Msg: String; Code: Integer);Begin
 WriteLn('Erreur : ', Msg);
 FinRapport;
 Halt(Code);
End;
{ ---------------------------------------------------------------- }
{ Aide                                                             }
{ ---------------------------------------------------------------- }

Procedure Aide;Begin
 WriteLn('BETON ', VERSION, ' - Cette commande permet de calculer les caracteristiques de ',
         'b'+#130+'ton : volume, dosage, masse, rapport E/C, r'+#130+'sistance et formulation.');
 WriteLn;
 WriteLn('Syntaxe : BETON [parametres]');
 WriteLn;
 WriteLn('Parametres :');
 WriteLn('  -volume L l e     Volume d''une dalle : longueur x largeur x epaisseur (m)');
 WriteLn('  -volume V         Volume de beton connu, en m3 (une seule valeur)');
 WriteLn('  -dosage C         Dosage en ciment, en kg par m3 de beton (defaut : 350)');
 WriteLn('  -masse M          Masse de beton en tonnes; donne le volume correspondant');
 WriteLn('  -densite D        Masse volumique du beton en kg/m3 (defaut : 2400)');
 WriteLn('  -rapport-ec E C   Rapport eau/ciment : E = eau (litres), C = ciment (kg)');
 WriteLn('  -compression F S  Resistance en MPa : F = force (N), S = surface (mm2)');
 WriteLn('  -melange fichier  Lit une formulation (CLE=VALEUR) et calcule les quantites');
 WriteLn('  -rapport fichier  Enregistre les resultats dans un fichier texte');
 WriteLn('  /?  -h  --help    Affiche cette aide');
 WriteLn;
 WriteLn('Notes :');
 WriteLn('  - Les parametres se combinent; la virgule est acceptee comme decimale.');
 WriteLn('  - -volume calcule aussi les quantites de ciment, sable, gravier et eau.');
 WriteLn('  - -densite avec -volume donne la masse; avec -masse, il donne le volume.');
 WriteLn('  - -rapport seul enregistre la formulation de reference (1 m3 a 350 kg/m3).');
 WriteLn;
 WriteLn('Exemples :');
 WriteLn('  BETON -volume 5 4 0.15');
 WriteLn('      Dalle de 5 m x 4 m x 15 cm : volume et quantites de materiaux.');
 WriteLn('  BETON -dosage 350 -volume 3');
 WriteLn('      Materiaux pour 3 m3 de beton dose a 350 kg de ciment par m3.');
 WriteLn('  BETON -melange SAMPLES\BETON\DALLE.TXT -rapport RESULTAT.TXT');
 WriteLn('      Calcule la formulation du fichier et sauvegarde le resultat.');
End;
{ ---------------------------------------------------------------- }
{ Lecture des parametres                                           }
{ ---------------------------------------------------------------- }

Function ArgReel(Opt: String; Var I: Integer): Real;
Var
 R: Real;
Begin
 If I >= ParamCount Then    Echec('le parametre ' + Opt + ' attend une valeur de plus.',
 1);
 Inc(I);
 If Not LireReel(ParamStr(I), R) Then    Echec('valeur invalide pour ' + Opt + ' : "' +
 ParamStr(I) +
 '" (nombre positif attendu).', 1);
 If R <= 0 Then    Echec('la valeur de ' + Opt + ' doit etre superieure a zero.', 1);
 ArgReel := R;
End;

Function ArgTexte(Opt: String; Var I: Integer): String;Begin
 If I >= ParamCount Then    Echec('le parametre ' + Opt + ' attend un nom de fichier.', 1)
 ;
 Inc(I);
 ArgTexte := ParamStr(I);
End;

Procedure LireParametres;
Var
 I: Integer;
 A: String;
 R: Real;
Begin
 OptAide := False;    OptVolume := False;  OptDosage := False;
 OptMasse := False;   OptDensite := False; OptEC := False;
 OptComp := False;    OptMelange := False; OptRapport := False;
 VolN := 0;
 I := 1;
 While I <= ParamCount Do Begin
  A := Majuscules(ParamStr(I));
    { /option et --option sont acceptes comme -option }
  If (Length(A) > 1) And (A[1] = '/') Then A[1] := '-';
  If Copy(A, 1, 2) = '--' Then Delete(A, 1, 1);
  If (A = '-?') Or (A = '-H') Or (A = '-HELP') Then      OptAide := True Else
  If A = '-VOLUME' Then Begin
   OptVolume := True;
   VolN := 0;
   While (VolN < 3) And (I < ParamCount) And LireReel(ParamStr(I + 1), R) Do Begin
    Inc(I);
    Inc(VolN);
    If R <= 0 Then          Echec(
    'les dimensions de -volume doivent etre superieures a zero.', 1);
    Vol[VolN] := R;
   End;
   If (VolN <> 1) And (VolN <> 3) Then        Echec(
   '-volume attend 1 valeur (m3) ou 3 valeurs (longueur largeur epaisseur).', 1);
  End
  Else If A = '-DOSAGE' Then Begin
   Dosage := ArgReel('-dosage', I);
   OptDosage := True;
  End
  Else If A = '-MASSE' Then Begin
   Masse := ArgReel('-masse', I);
   OptMasse := True;
  End
  Else If A = '-DENSITE' Then Begin
   Densite := ArgReel('-densite', I);
   OptDensite := True;
  End
  Else If A = '-RAPPORT-EC' Then Begin
   EauEC := ArgReel('-rapport-ec', I);
   CimentEC := ArgReel('-rapport-ec', I);
   OptEC := True;
  End
  Else If A = '-COMPRESSION' Then Begin
   Force := ArgReel('-compression', I);
   Surface := ArgReel('-compression', I);
   OptComp := True;
  End
  Else If A = '-MELANGE' Then Begin
   FichierMelange := ArgTexte('-melange', I);
   OptMelange := True;
  End
  Else If A = '-RAPPORT' Then Begin
   FichierRapport := ArgTexte('-rapport', I);
   OptRapport := True;
  End
   Else
  Echec('parametre inconnu : "' + ParamStr(I) + '". Tapez BETON /? pour l''aide.', 1);
  Inc(I);
 End;
 If OptVolume And OptMasse Then    Echec(
 '-volume et -masse sont incompatibles (l''un donne l''autre).', 1);
 If OptDensite And Not (OptVolume Or OptMasse) Then    Echec(
 '-densite doit etre accompagne de -volume ou de -masse.', 1);
End;
{ ---------------------------------------------------------------- }
{ Rapport                                                          }
{ ---------------------------------------------------------------- }

Function Deux(N: Word): String;
Var
 S: String;
Begin
 Str(N, S);
 If Length(S) < 2 Then S := '0' + S;
 Deux := S;
End;

Procedure OuvrirRapport;
Var
 A, M, J, JS: Word;
Begin
 Assign(Rapport, Chemin(FichierRapport));
  {$I-}
 Rewrite(Rapport);
  {$I+}
 If IOResult <> 0 Then    Echec('impossible de creer le fichier "' + FichierRapport +
 '".', 2);
 RapportOuvert := True;
 GetDate(A, M, J, JS);
 WriteLn(Rapport, 'BETON ', VERSION, ' - Rapport de calcul du ',
 A, '-', Deux(M), '-', Deux(J));
 WriteLn(Rapport, Repeter('=', 60));
 WriteLn(Rapport);
End;
{ ---------------------------------------------------------------- }
{ Calculs                                                          }
{ ---------------------------------------------------------------- }

Procedure InitFormule(Var F: TFormule);Begin
 F.Nom := '';
 F.Volume := 0;
 F.Ciment := 0;
 F.Eau := 0;
 F.Sable := 0;
 F.Gravier := 0;
 F.Perte := PERTE_DEFAUT;
 F.Sac := SAC_DEFAUT;
End;
{ Deduit les composants non precises par la methode des volumes absolus }

Procedure Completer(Var F: TFormule);
Var
 Reste: Real;
Begin
 If F.Ciment <= 0 Then F.Ciment := DOSAGE_DEFAUT;
 If F.Eau <= 0 Then F.Eau := F.Ciment * EC_DEFAUT;
  { volume (m3) restant pour les granulats dans 1 m3 de beton }
 Reste := 1 - F.Ciment / D_CIMENT - F.Eau / 1000 - AIR;
 If (F.Sable > 0) And (F.Gravier > 0) Then    Exit;
 If F.Sable > 0 Then    Reste := Reste - F.Sable / D_GRANULATS Else
 If F.Gravier > 0 Then    Reste := Reste - F.Gravier / D_GRANULATS;
 If Reste <= 0 Then    Echec(
 'formulation impossible : ciment + eau + granulats depassent 1 m3 de beton.', 1);
 If F.Sable > 0 Then    F.Gravier := Reste * D_GRANULATS Else
 If F.Gravier > 0 Then    F.Sable := Reste * D_GRANULATS
  Else
 Begin
  F.Sable := Reste * D_GRANULATS * PART_SABLE;
  F.Gravier := Reste * D_GRANULATS * (1 - PART_SABLE);
 End;
End;

Procedure LigneMateriau(Nom, Unite: String; ParM3, V, Perte: Real);Begin
 Say('  ' + PadR(Nom, 9) +
 PadL(Fmt(ParM3, 1), 9) + ' ' + PadR(Unite, 3) +
 PadL(Fmt(ParM3 * V, 1), 11) + ' ' + PadR(Unite, 3) +
 PadL(Fmt(ParM3 * V * Perte, 1), 11) + ' ' + Unite);
End;

Procedure AfficherFormule(Var F: TFormule; AvecVolume: Boolean);
Var
 CoefPerte, MasseM3, VAbs, Ecart: Real;
Begin
 CoefPerte := 1 + F.Perte / 100;
 MasseM3 := F.Ciment + F.Eau + F.Sable + F.Gravier;
 VAbs := F.Ciment / D_CIMENT + F.Eau / 1000 + (F.Sable + F.Gravier) / D_GRANULATS + AIR;
 If F.Nom <> '' Then Say('Formulation          : ' + F.Nom);
 If AvecVolume Then Say('Volume de beton      : ' + Fmt(F.Volume, 3) + ' m3');
 Say('Dosage en ciment     : ' + FmtSouple(F.Ciment) + ' kg/m3');
 Say('Rapport eau/ciment   : ' + Fmt(F.Eau / F.Ciment, 2));
 Say('Perte prevue         : ' + FmtSouple(F.Perte) + ' %');
 If (F.Ciment < 150) Or (F.Ciment > 600) Then    Say(
 'Attention : dosage inhabituel (usage courant : 150 a 450 kg/m3).');
 Ecart := (VAbs - 1) * 100;
 If Abs(Ecart) > 5 Then    Say('Attention : la formulation occupe ' + Fmt(VAbs, 3) +
 ' m3 par m3 vise (ecart de ' +
 Fmt(Ecart, 1) + ' %); a reajuster.');
 Say('');
 Say('  ' + PadR('Materiau', 9) + PadL('Par m3', 9) + PadL('Total', 15) +
 PadL('Avec perte', 15));
 LigneMateriau('Ciment', 'kg', F.Ciment, F.Volume, CoefPerte);
 LigneMateriau('Sable', 'kg', F.Sable, F.Volume, CoefPerte);
 LigneMateriau('Gravier', 'kg', F.Gravier, F.Volume, CoefPerte);
 LigneMateriau('Eau', 'L', F.Eau, F.Volume, CoefPerte);
 Say('');
 Say('Sacs de ciment de ' + FmtSouple(F.Sac) + ' kg : ' +
 IntStr(Plafond(F.Ciment * F.Volume * CoefPerte / F.Sac)) + ' (avec perte)');
 Say('Masse volumique theorique : ' + Fmt(MasseM3, 0) + ' kg/m3');
 Say('Masse totale de beton     : ' + Fmt(MasseM3 * F.Volume / 1000, 3) +
 ' t (sans perte)');
End;
{ -volume, -dosage, -masse, -densite }

Procedure TraiterBeton;
Var
 V, D: Real;
 F: TFormule;
Begin
 V := 0;
 Say('=== Volume et quantites de beton ===');
 If OptVolume Then Begin
  If VolN = 3 Then Begin
   V := Vol[1] * Vol[2] * Vol[3];
   Say('Dalle : ' + FmtSouple(Vol[1]) + ' m x ' + FmtSouple(Vol[2]) + ' m x ' +
   FmtSouple(Vol[3]) + ' m');
   If Vol[3] > 1 Then        Say(
   'Attention : l''epaisseur s''exprime en metres (0.15 = 15 cm).');
  End
   Else
  V := Vol[1];
  Say('Volume de beton      : ' + Fmt(V, 3) + ' m3 (' + Fmt(V * 1000, 0) + ' L)');
  If OptDensite Then Begin
   Say('Masse volumique      : ' + FmtSouple(Densite) + ' kg/m3');
   Say('Masse de beton       : ' + Fmt(V * Densite, 0) + ' kg (' +
   Fmt(V * Densite / 1000, 3) + ' t)');
  End;
 End
 Else If OptMasse Then Begin
  If OptDensite Then D := Densite Else D := DENSITE_DEFAUT;
  V := Masse * 1000 / D;
  Say('Masse de beton       : ' + Fmt(Masse * 1000, 0) + ' kg (' + FmtSouple(Masse) +
  ' t)');
  If OptDensite Then      Say('Masse volumique      : ' + FmtSouple(D) + ' kg/m3')
   Else
  Say('Masse volumique      : ' + FmtSouple(D) + ' kg/m3 (valeur par defaut)');
  Say('Volume de beton      : ' + Fmt(V, 3) + ' m3 (' + Fmt(V * 1000, 0) + ' L)');
 End;
 If OptVolume Or OptDosage Then Begin
  If V <= 0 Then Begin
   V := 1;
   Say('Volume non precise : calcul pour 1 m3 de beton.');
  End;
  Say('');
  InitFormule(F);
  F.Volume := V;
  If OptDosage Then F.Ciment := Dosage Else F.Ciment := DOSAGE_DEFAUT;
  Completer(F);
  AfficherFormule(F, Not (OptVolume Or OptMasse));
 End;
End;
{ -rapport-ec }

Procedure TraiterRapportEC;
Var
 EC, Rc: Real;
Begin
 EC := EauEC / CimentEC;
 Say('=== Rapport eau/ciment ===');
 Say('Eau                  : ' + FmtSouple(EauEC) + ' L');
 Say('Ciment               : ' + FmtSouple(CimentEC) + ' kg');
 Say('Rapport E/C          : ' + Fmt(EC, 2));
 If EC < 0.40 Then    Say(
 'Evaluation           : tres faible - tres haute resistance, peu maniable (plastifiant conseille).')
 Else If EC <= 0.50 Then    Say(
 'Evaluation           : bon - beton resistant et durable.')
 Else If EC <= 0.60 Then    Say(
 'Evaluation           : courant - convient aux ouvrages ordinaires.')
  Else
 Say(
 'Evaluation           : eleve - resistance et durabilite reduites (maximum conseille : 0.60).');
 If EC < 2 Then Begin
    { Bolomey : Rc = G * Rciment * (C/E - 0.5), G = 0.5, ciment 42.5 MPa }
  Rc := 0.5 * 42.5 * (1 / EC - 0.5);
  Say('Resistance estimee   : environ ' + Fmt(Rc, 0) +
  ' MPa a 28 jours (Bolomey, ciment 42.5, indicatif).');
 End;
End;
{ -compression }

Procedure TraiterCompression;
Var
 MPa: Real;
 J, Classe: Integer;
Begin
 MPa := Force / Surface;   { N/mm2 = MPa }
 Say('=== Resistance a la compression ===');
 Say('Force de rupture     : ' + FmtSouple(Force) + ' N (' + Fmt(Force / 1000, 1) +
 ' kN)');
 Say('Surface              : ' + FmtSouple(Surface) + ' mm2 (' + Fmt(Surface / 100, 1) +
 ' cm2)');
 Say('Resistance           : ' + Fmt(MPa, 2) + ' MPa (' + Fmt(MPa * PSI_PAR_MPA, 0) +
 ' psi)');
 Classe := 0;
 For J := 1 To NB_CLASSES Do    If MPa >= ClCyl[J] Then Classe := J;
 If Classe = 0 Then    Say('Classe atteinte      : inferieure a C12/15')
  Else
 Say('Classe atteinte      : C' + IntStr(ClCyl[Classe]) + '/' + IntStr(ClCube[Classe]) +
 ' (eprouvette cylindrique, 28 jours)');
End;
{ ---------------------------------------------------------------- }
{ -melange : lecture d'un fichier de formulation                   }
{ ---------------------------------------------------------------- }

Procedure ErreurLigne(N: Integer; Msg: String);Begin
 Echec('fichier "' + FichierMelange + '", ligne ' + IntStr(N) + ' : ' + Msg, 2);
End;

Function ValeurFichier(N: Integer; Cle, Texte: String; ZeroOK: Boolean): Real;
Var
 R: Real;
Begin
 If Not LireReel(Texte, R) Then    ErreurLigne(N, Cle +
 ' attend un nombre positif (lu : "' + Texte + '").');
 If (R <= 0) And Not ZeroOK Then    ErreurLigne(N, Cle + ' doit etre superieur a zero.');
 ValeurFichier := R;
End;

Procedure LireFormule(Var F: TFormule);
Var
 T: Text;
 Ligne, Cle, Texte: String;
 N, P, NbDim: Integer;
 L, La, E: Real;
Begin
 InitFormule(F);
 L := 0; La := 0; E := 0;
 Assign(T, Chemin(FichierMelange));
  {$I-}
 Reset(T);
  {$I+}
 If IOResult <> 0 Then    Echec('impossible d''ouvrir le fichier "' + FichierMelange +
 '".', 2);
 N := 0;
 While Not Eof(T) Do Begin
  ReadLn(T, Ligne);
  Inc(N);
  Ligne := Epurer(Ligne);
  If (Ligne <> '') And (Ligne[1] <> ';') And (Ligne[1] <> '#') Then Begin
   P := Pos('=', Ligne);
   If P = 0 Then        ErreurLigne(N, 'format "CLE=VALEUR" attendu.');
   Cle := Majuscules(Epurer(Copy(Ligne, 1, P - 1)));
   Texte := Epurer(Copy(Ligne, P + 1, 255));
   If Cle = 'NOM' Then F.Nom := Texte Else
   If Cle = 'VOLUME' Then F.Volume := ValeurFichier(N, Cle, Texte, False) Else
   If Cle = 'LONGUEUR' Then L := ValeurFichier(N, Cle, Texte, False) Else
   If Cle = 'LARGEUR' Then La := ValeurFichier(N, Cle, Texte, False) Else
   If Cle = 'EPAISSEUR' Then E := ValeurFichier(N, Cle, Texte, False) Else
   If (Cle = 'CIMENT') Or (Cle = 'DOSAGE') Then        F.Ciment := ValeurFichier(N,
   Cle, Texte, False)
   Else If Cle = 'EAU' Then F.Eau := ValeurFichier(N, Cle, Texte, False) Else
   If Cle = 'SABLE' Then F.Sable := ValeurFichier(N, Cle, Texte, False) Else
   If Cle = 'GRAVIER' Then F.Gravier := ValeurFichier(N, Cle, Texte, False) Else
   If Cle = 'PERTE' Then F.Perte := ValeurFichier(N, Cle, Texte, True) Else
   If Cle = 'SAC' Then F.Sac := ValeurFichier(N, Cle, Texte, False)
    Else
   Say('Attention : ligne ' + IntStr(N) + ', cle inconnue "' + Cle + '" (ignoree).');
  End;
 End;
 Close(T);
 NbDim := 0;
 If L > 0 Then Inc(NbDim);
 If La > 0 Then Inc(NbDim);
 If E > 0 Then Inc(NbDim);
 If (F.Volume > 0) And (NbDim > 0) Then    Echec('fichier "' + FichierMelange +
 '" : VOLUME et LONGUEUR/LARGEUR/EPAISSEUR sont exclusifs.', 2);
 If NbDim = 3 Then    F.Volume := L * La * E Else
 If NbDim > 0 Then    Echec('fichier "' + FichierMelange +
 '" : LONGUEUR, LARGEUR et EPAISSEUR doivent etre donnes ensemble.', 2);
 If F.Volume <= 0 Then    Echec('fichier "' + FichierMelange +
 '" : VOLUME (ou LONGUEUR, LARGEUR et EPAISSEUR) est obligatoire.', 2);
End;

Procedure TraiterMelange;
Var
 F: TFormule;
Begin
 Say('=== Melange : ' + FichierMelange + ' ===');
 LireFormule(F);
 Completer(F);
 AfficherFormule(F, True);
End;
{ -rapport seul : formulation de reference }

Procedure TraiterReference;
Var
 F: TFormule;
Begin
 Say('=== Formulation de reference ===');
 Say('Aucun calcul demande : rapport de 1 m3 de beton a 350 kg/m3.');
 Say('');
 InitFormule(F);
 F.Volume := 1;
 F.Ciment := DOSAGE_DEFAUT;
 Completer(F);
 AfficherFormule(F, True);
End;

Procedure Separer;Begin
 If Fait Then Begin
  Say('');
  Say('');
 End;
 Fait := True;
End;
{ ---------------------------------------------------------------- }
{ Programme principal                                              }
{ ---------------------------------------------------------------- }

BEGIN
 RapportOuvert := False;
 Fait := False;
 LireParametres;
 If OptAide Or (ParamCount = 0) Then Begin
  Aide;
  Halt(0);
 End;
 If OptRapport Then OuvrirRapport;
 If OptVolume Or OptDosage Or OptMasse Or OptDensite Then Begin
  Separer;
  TraiterBeton;
 End;
 If OptEC Then Begin
  Separer;
  TraiterRapportEC;
 End;
 If OptComp Then Begin
  Separer;
  TraiterCompression;
 End;
 If OptMelange Then Begin
  Separer;
  TraiterMelange;
 End;
 If Not Fait Then TraiterReference;
 If OptRapport Then Begin
  FinRapport;
  WriteLn;
  WriteLn('Rapport enregistre dans : ', FichierRapport);
 End;
END.

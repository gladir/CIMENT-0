{ ======================================================================
  BETON.PAS - Calculs de beton en ligne de commande

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
program Beton;

uses Dos;

const
  VERSION        = '1.0';
  D_CIMENT       = 3100.0;   { kg/m3 }
  D_GRANULATS    = 2650.0;   { kg/m3 }
  AIR            = 0.02;     { m3 d'air occlus par m3 de beton }
  PART_SABLE     = 0.40;     { part du sable dans le volume des granulats }
  EC_DEFAUT      = 0.50;
  DOSAGE_DEFAUT  = 350.0;    { kg de ciment par m3 }
  DENSITE_DEFAUT = 2400.0;   { kg/m3 }
  PERTE_DEFAUT   = 5.0;      { % }
  SAC_DEFAUT     = 25.0;     { kg }
  PSI_PAR_MPA    = 145.038;
  NB_CLASSES     = 14;

  { Classes de resistance : fck sur cylindre / fck sur cube (MPa) }
  ClCyl : array[1..NB_CLASSES] of Integer =
    (12, 16, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90);
  ClCube: array[1..NB_CLASSES] of Integer =
    (15, 20, 25, 30, 37, 45, 50, 55, 60, 67, 75, 85, 95, 105);

type
  { Une valeur a 0 signifie "non precisee" : elle sera deduite. }
  TFormule = record
    Nom: String;
    Volume, Ciment, Eau, Sable, Gravier, Perte, Sac: Real;
  end;

var
  OptAide, OptVolume, OptDosage, OptMasse, OptDensite: Boolean;
  OptEC, OptComp, OptMelange, OptRapport: Boolean;
  VolN: Integer;
  Vol: array[1..3] of Real;
  Dosage, Masse, Densite, EauEC, CimentEC, Force, Surface: Real;
  FichierMelange, FichierRapport: String;
  Rapport: Text;
  RapportOuvert: Boolean;
  Fait: Boolean;

{ ---------------------------------------------------------------- }
{ Utilitaires                                                      }
{ ---------------------------------------------------------------- }

function Majuscules(S: String): String;
var I: Integer;
begin
  for I := 1 to Length(S) do S[I] := UpCase(S[I]);
  Majuscules := S;
end;

function Epurer(S: String): String;
begin
  while (Length(S) > 0) and (S[1] <= ' ') do Delete(S, 1, 1);
  while (Length(S) > 0) and (S[Length(S)] <= ' ') do Delete(S, Length(S), 1);
  Epurer := S;
end;

function PadR(S: String; N: Integer): String;
begin
  while Length(S) < N do S := S + ' ';
  PadR := S;
end;

function PadL(S: String; N: Integer): String;
begin
  while Length(S) < N do S := ' ' + S;
  PadL := S;
end;

function Fmt(X: Real; Dec: Integer): String;
var S: String;
begin
  Str(X:0:Dec, S);
  Fmt := S;
end;

{ Sans decimales si la valeur est entiere, sinon 2 decimales }
function FmtSouple(X: Real): String;
begin
  if Abs(X - Round(X)) < 0.0005 then FmtSouple := Fmt(X, 0)
  else FmtSouple := Fmt(X, 2);
end;

function IntStr(N: LongInt): String;
var S: String;
begin
  Str(N, S);
  IntStr := S;
end;

function Plafond(X: Real): LongInt;
var N: LongInt;
begin
  N := Trunc(X);
  if X - N > 0.000001 then N := N + 1;
  Plafond := N;
end;

{ Accepte la virgule comme separateur decimal. Nombres positifs seulement. }
function LireReel(S: String; var R: Real): Boolean;
var P, Code: Integer;
begin
  LireReel := False;
  S := Epurer(S);
  if (Length(S) = 0) or not (S[1] in ['0'..'9', '.', ',']) then Exit;
  P := Pos(',', S);
  if P > 0 then S[P] := '.';
  Val(S, R, Code);
  LireReel := (Code = 0);
end;

{ Les chemins DOS (SAMPLES\BETON\X.TXT) restent utilisables sous Unix }
function Chemin(S: String): String;
{$IFDEF UNIX}
var I: Integer;
{$ENDIF}
begin
{$IFDEF UNIX}
  for I := 1 to Length(S) do
    if S[I] = '\' then S[I] := '/';
{$ENDIF}
  Chemin := S;
end;

function Repeter(C: Char; N: Integer): String;
var S: String;
begin
  S := '';
  while Length(S) < N do S := S + C;
  Repeter := S;
end;

{ ---------------------------------------------------------------- }
{ Sortie : ecran + fichier de rapport (-rapport)                   }
{ ---------------------------------------------------------------- }

procedure Say(S: String);
begin
  WriteLn(S);
  if RapportOuvert then WriteLn(Rapport, S);
end;

procedure FinRapport;
begin
  if RapportOuvert then
  begin
    Close(Rapport);
    RapportOuvert := False;
  end;
end;

procedure Echec(Msg: String; Code: Integer);
begin
  WriteLn('Erreur : ', Msg);
  FinRapport;
  Halt(Code);
end;

{ ---------------------------------------------------------------- }
{ Aide                                                             }
{ ---------------------------------------------------------------- }

procedure Aide;
begin
  WriteLn('BETON ', VERSION, ' - Calculs de beton : volume, dosage, masse, rapport E/C,');
  WriteLn('resistance et formulation.');
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
end;

{ ---------------------------------------------------------------- }
{ Lecture des parametres                                           }
{ ---------------------------------------------------------------- }

function ArgReel(Opt: String; var I: Integer): Real;
var R: Real;
begin
  if I >= ParamCount then
    Echec('le parametre ' + Opt + ' attend une valeur de plus.', 1);
  Inc(I);
  if not LireReel(ParamStr(I), R) then
    Echec('valeur invalide pour ' + Opt + ' : "' + ParamStr(I) +
          '" (nombre positif attendu).', 1);
  if R <= 0 then
    Echec('la valeur de ' + Opt + ' doit etre superieure a zero.', 1);
  ArgReel := R;
end;

function ArgTexte(Opt: String; var I: Integer): String;
begin
  if I >= ParamCount then
    Echec('le parametre ' + Opt + ' attend un nom de fichier.', 1);
  Inc(I);
  ArgTexte := ParamStr(I);
end;

procedure LireParametres;
var
  I: Integer;
  A: String;
  R: Real;
begin
  OptAide := False;    OptVolume := False;  OptDosage := False;
  OptMasse := False;   OptDensite := False; OptEC := False;
  OptComp := False;    OptMelange := False; OptRapport := False;
  VolN := 0;

  I := 1;
  while I <= ParamCount do
  begin
    A := Majuscules(ParamStr(I));
    { /option et --option sont acceptes comme -option }
    if (Length(A) > 1) and (A[1] = '/') then A[1] := '-';
    if Copy(A, 1, 2) = '--' then Delete(A, 1, 1);

    if (A = '-?') or (A = '-H') or (A = '-HELP') then
      OptAide := True
    else if A = '-VOLUME' then
    begin
      OptVolume := True;
      VolN := 0;
      while (VolN < 3) and (I < ParamCount) and LireReel(ParamStr(I + 1), R) do
      begin
        Inc(I);
        Inc(VolN);
        if R <= 0 then
          Echec('les dimensions de -volume doivent etre superieures a zero.', 1);
        Vol[VolN] := R;
      end;
      if (VolN <> 1) and (VolN <> 3) then
        Echec('-volume attend 1 valeur (m3) ou 3 valeurs (longueur largeur epaisseur).', 1);
    end
    else if A = '-DOSAGE' then
    begin
      Dosage := ArgReel('-dosage', I);
      OptDosage := True;
    end
    else if A = '-MASSE' then
    begin
      Masse := ArgReel('-masse', I);
      OptMasse := True;
    end
    else if A = '-DENSITE' then
    begin
      Densite := ArgReel('-densite', I);
      OptDensite := True;
    end
    else if A = '-RAPPORT-EC' then
    begin
      EauEC := ArgReel('-rapport-ec', I);
      CimentEC := ArgReel('-rapport-ec', I);
      OptEC := True;
    end
    else if A = '-COMPRESSION' then
    begin
      Force := ArgReel('-compression', I);
      Surface := ArgReel('-compression', I);
      OptComp := True;
    end
    else if A = '-MELANGE' then
    begin
      FichierMelange := ArgTexte('-melange', I);
      OptMelange := True;
    end
    else if A = '-RAPPORT' then
    begin
      FichierRapport := ArgTexte('-rapport', I);
      OptRapport := True;
    end
    else
      Echec('parametre inconnu : "' + ParamStr(I) + '". Tapez BETON /? pour l''aide.', 1);
    Inc(I);
  end;

  if OptVolume and OptMasse then
    Echec('-volume et -masse sont incompatibles (l''un donne l''autre).', 1);
  if OptDensite and not (OptVolume or OptMasse) then
    Echec('-densite doit etre accompagne de -volume ou de -masse.', 1);
end;

{ ---------------------------------------------------------------- }
{ Rapport                                                          }
{ ---------------------------------------------------------------- }

function Deux(N: Word): String;
var S: String;
begin
  Str(N, S);
  if Length(S) < 2 then S := '0' + S;
  Deux := S;
end;

procedure OuvrirRapport;
var A, M, J, JS: Word;
begin
  Assign(Rapport, Chemin(FichierRapport));
  {$I-}
  Rewrite(Rapport);
  {$I+}
  if IOResult <> 0 then
    Echec('impossible de creer le fichier "' + FichierRapport + '".', 2);
  RapportOuvert := True;
  GetDate(A, M, J, JS);
  WriteLn(Rapport, 'BETON ', VERSION, ' - Rapport de calcul du ',
          A, '-', Deux(M), '-', Deux(J));
  WriteLn(Rapport, Repeter('=', 60));
  WriteLn(Rapport);
end;

{ ---------------------------------------------------------------- }
{ Calculs                                                          }
{ ---------------------------------------------------------------- }

procedure InitFormule(var F: TFormule);
begin
  F.Nom := '';
  F.Volume := 0;
  F.Ciment := 0;
  F.Eau := 0;
  F.Sable := 0;
  F.Gravier := 0;
  F.Perte := PERTE_DEFAUT;
  F.Sac := SAC_DEFAUT;
end;

{ Deduit les composants non precises par la methode des volumes absolus }
procedure Completer(var F: TFormule);
var Reste: Real;
begin
  if F.Ciment <= 0 then F.Ciment := DOSAGE_DEFAUT;
  if F.Eau <= 0 then F.Eau := F.Ciment * EC_DEFAUT;

  { volume (m3) restant pour les granulats dans 1 m3 de beton }
  Reste := 1 - F.Ciment / D_CIMENT - F.Eau / 1000 - AIR;

  if (F.Sable > 0) and (F.Gravier > 0) then
    Exit;
  if F.Sable > 0 then
    Reste := Reste - F.Sable / D_GRANULATS
  else if F.Gravier > 0 then
    Reste := Reste - F.Gravier / D_GRANULATS;
  if Reste <= 0 then
    Echec('formulation impossible : ciment + eau + granulats depassent 1 m3 de beton.', 1);

  if F.Sable > 0 then
    F.Gravier := Reste * D_GRANULATS
  else if F.Gravier > 0 then
    F.Sable := Reste * D_GRANULATS
  else
  begin
    F.Sable := Reste * D_GRANULATS * PART_SABLE;
    F.Gravier := Reste * D_GRANULATS * (1 - PART_SABLE);
  end;
end;

procedure LigneMateriau(Nom, Unite: String; ParM3, V, Perte: Real);
begin
  Say('  ' + PadR(Nom, 9) +
      PadL(Fmt(ParM3, 1), 9) + ' ' + PadR(Unite, 3) +
      PadL(Fmt(ParM3 * V, 1), 11) + ' ' + PadR(Unite, 3) +
      PadL(Fmt(ParM3 * V * Perte, 1), 11) + ' ' + Unite);
end;

procedure AfficherFormule(var F: TFormule; AvecVolume: Boolean);
var
  CoefPerte, MasseM3, VAbs, Ecart: Real;
begin
  CoefPerte := 1 + F.Perte / 100;
  MasseM3 := F.Ciment + F.Eau + F.Sable + F.Gravier;
  VAbs := F.Ciment / D_CIMENT + F.Eau / 1000 + (F.Sable + F.Gravier) / D_GRANULATS + AIR;

  if F.Nom <> '' then Say('Formulation          : ' + F.Nom);
  if AvecVolume then Say('Volume de beton      : ' + Fmt(F.Volume, 3) + ' m3');
  Say('Dosage en ciment     : ' + FmtSouple(F.Ciment) + ' kg/m3');
  Say('Rapport eau/ciment   : ' + Fmt(F.Eau / F.Ciment, 2));
  Say('Perte prevue         : ' + FmtSouple(F.Perte) + ' %');
  if (F.Ciment < 150) or (F.Ciment > 600) then
    Say('Attention : dosage inhabituel (usage courant : 150 a 450 kg/m3).');
  Ecart := (VAbs - 1) * 100;
  if Abs(Ecart) > 5 then
    Say('Attention : la formulation occupe ' + Fmt(VAbs, 3) + ' m3 par m3 vise (ecart de ' +
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
end;

{ -volume, -dosage, -masse, -densite }
procedure TraiterBeton;
var
  V, D: Real;
  F: TFormule;
begin
  V := 0;
  Say('=== Volume et quantites de beton ===');

  if OptVolume then
  begin
    if VolN = 3 then
    begin
      V := Vol[1] * Vol[2] * Vol[3];
      Say('Dalle : ' + FmtSouple(Vol[1]) + ' m x ' + FmtSouple(Vol[2]) + ' m x ' +
          FmtSouple(Vol[3]) + ' m');
      if Vol[3] > 1 then
        Say('Attention : l''epaisseur s''exprime en metres (0.15 = 15 cm).');
    end
    else
      V := Vol[1];
    Say('Volume de beton      : ' + Fmt(V, 3) + ' m3 (' + Fmt(V * 1000, 0) + ' L)');
    if OptDensite then
    begin
      Say('Masse volumique      : ' + FmtSouple(Densite) + ' kg/m3');
      Say('Masse de beton       : ' + Fmt(V * Densite, 0) + ' kg (' +
          Fmt(V * Densite / 1000, 3) + ' t)');
    end;
  end
  else if OptMasse then
  begin
    if OptDensite then D := Densite else D := DENSITE_DEFAUT;
    V := Masse * 1000 / D;
    Say('Masse de beton       : ' + Fmt(Masse * 1000, 0) + ' kg (' + FmtSouple(Masse) + ' t)');
    if OptDensite then
      Say('Masse volumique      : ' + FmtSouple(D) + ' kg/m3')
    else
      Say('Masse volumique      : ' + FmtSouple(D) + ' kg/m3 (valeur par defaut)');
    Say('Volume de beton      : ' + Fmt(V, 3) + ' m3 (' + Fmt(V * 1000, 0) + ' L)');
  end;

  if OptVolume or OptDosage then
  begin
    if V <= 0 then
    begin
      V := 1;
      Say('Volume non precise : calcul pour 1 m3 de beton.');
    end;
    Say('');
    InitFormule(F);
    F.Volume := V;
    if OptDosage then F.Ciment := Dosage else F.Ciment := DOSAGE_DEFAUT;
    Completer(F);
    AfficherFormule(F, not (OptVolume or OptMasse));
  end;
end;

{ -rapport-ec }
procedure TraiterRapportEC;
var EC, Rc: Real;
begin
  EC := EauEC / CimentEC;
  Say('=== Rapport eau/ciment ===');
  Say('Eau                  : ' + FmtSouple(EauEC) + ' L');
  Say('Ciment               : ' + FmtSouple(CimentEC) + ' kg');
  Say('Rapport E/C          : ' + Fmt(EC, 2));
  if EC < 0.40 then
    Say('Evaluation           : tres faible - tres haute resistance, peu maniable (plastifiant conseille).')
  else if EC <= 0.50 then
    Say('Evaluation           : bon - beton resistant et durable.')
  else if EC <= 0.60 then
    Say('Evaluation           : courant - convient aux ouvrages ordinaires.')
  else
    Say('Evaluation           : eleve - resistance et durabilite reduites (maximum conseille : 0.60).');
  if EC < 2 then
  begin
    { Bolomey : Rc = G * Rciment * (C/E - 0.5), G = 0.5, ciment 42.5 MPa }
    Rc := 0.5 * 42.5 * (1 / EC - 0.5);
    Say('Resistance estimee   : environ ' + Fmt(Rc, 0) +
        ' MPa a 28 jours (Bolomey, ciment 42.5, indicatif).');
  end;
end;

{ -compression }
procedure TraiterCompression;
var
  MPa: Real;
  J, Classe: Integer;
begin
  MPa := Force / Surface;   { N/mm2 = MPa }
  Say('=== Resistance a la compression ===');
  Say('Force de rupture     : ' + FmtSouple(Force) + ' N (' + Fmt(Force / 1000, 1) + ' kN)');
  Say('Surface              : ' + FmtSouple(Surface) + ' mm2 (' + Fmt(Surface / 100, 1) + ' cm2)');
  Say('Resistance           : ' + Fmt(MPa, 2) + ' MPa (' + Fmt(MPa * PSI_PAR_MPA, 0) + ' psi)');
  Classe := 0;
  for J := 1 to NB_CLASSES do
    if MPa >= ClCyl[J] then Classe := J;
  if Classe = 0 then
    Say('Classe atteinte      : inferieure a C12/15')
  else
    Say('Classe atteinte      : C' + IntStr(ClCyl[Classe]) + '/' + IntStr(ClCube[Classe]) +
        ' (eprouvette cylindrique, 28 jours)');
end;

{ ---------------------------------------------------------------- }
{ -melange : lecture d'un fichier de formulation                   }
{ ---------------------------------------------------------------- }

procedure ErreurLigne(N: Integer; Msg: String);
begin
  Echec('fichier "' + FichierMelange + '", ligne ' + IntStr(N) + ' : ' + Msg, 2);
end;

function ValeurFichier(N: Integer; Cle, Texte: String; ZeroOK: Boolean): Real;
var R: Real;
begin
  if not LireReel(Texte, R) then
    ErreurLigne(N, Cle + ' attend un nombre positif (lu : "' + Texte + '").');
  if (R <= 0) and not ZeroOK then
    ErreurLigne(N, Cle + ' doit etre superieur a zero.');
  ValeurFichier := R;
end;

procedure LireFormule(var F: TFormule);
var
  T: Text;
  Ligne, Cle, Texte: String;
  N, P, NbDim: Integer;
  L, La, E: Real;
begin
  InitFormule(F);
  L := 0; La := 0; E := 0;
  Assign(T, Chemin(FichierMelange));
  {$I-}
  Reset(T);
  {$I+}
  if IOResult <> 0 then
    Echec('impossible d''ouvrir le fichier "' + FichierMelange + '".', 2);

  N := 0;
  while not Eof(T) do
  begin
    ReadLn(T, Ligne);
    Inc(N);
    Ligne := Epurer(Ligne);
    if (Ligne <> '') and (Ligne[1] <> ';') and (Ligne[1] <> '#') then
    begin
      P := Pos('=', Ligne);
      if P = 0 then
        ErreurLigne(N, 'format "CLE=VALEUR" attendu.');
      Cle := Majuscules(Epurer(Copy(Ligne, 1, P - 1)));
      Texte := Epurer(Copy(Ligne, P + 1, 255));

      if Cle = 'NOM' then F.Nom := Texte
      else if Cle = 'VOLUME' then F.Volume := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'LONGUEUR' then L := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'LARGEUR' then La := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'EPAISSEUR' then E := ValeurFichier(N, Cle, Texte, False)
      else if (Cle = 'CIMENT') or (Cle = 'DOSAGE') then
        F.Ciment := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'EAU' then F.Eau := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'SABLE' then F.Sable := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'GRAVIER' then F.Gravier := ValeurFichier(N, Cle, Texte, False)
      else if Cle = 'PERTE' then F.Perte := ValeurFichier(N, Cle, Texte, True)
      else if Cle = 'SAC' then F.Sac := ValeurFichier(N, Cle, Texte, False)
      else
        Say('Attention : ligne ' + IntStr(N) + ', cle inconnue "' + Cle + '" (ignoree).');
    end;
  end;
  Close(T);

  NbDim := 0;
  if L > 0 then Inc(NbDim);
  if La > 0 then Inc(NbDim);
  if E > 0 then Inc(NbDim);
  if (F.Volume > 0) and (NbDim > 0) then
    Echec('fichier "' + FichierMelange +
          '" : VOLUME et LONGUEUR/LARGEUR/EPAISSEUR sont exclusifs.', 2);
  if NbDim = 3 then
    F.Volume := L * La * E
  else if NbDim > 0 then
    Echec('fichier "' + FichierMelange +
          '" : LONGUEUR, LARGEUR et EPAISSEUR doivent etre donnes ensemble.', 2);
  if F.Volume <= 0 then
    Echec('fichier "' + FichierMelange +
          '" : VOLUME (ou LONGUEUR, LARGEUR et EPAISSEUR) est obligatoire.', 2);
end;

procedure TraiterMelange;
var F: TFormule;
begin
  Say('=== Melange : ' + FichierMelange + ' ===');
  LireFormule(F);
  Completer(F);
  AfficherFormule(F, True);
end;

{ -rapport seul : formulation de reference }
procedure TraiterReference;
var F: TFormule;
begin
  Say('=== Formulation de reference ===');
  Say('Aucun calcul demande : rapport de 1 m3 de beton a 350 kg/m3.');
  Say('');
  InitFormule(F);
  F.Volume := 1;
  F.Ciment := DOSAGE_DEFAUT;
  Completer(F);
  AfficherFormule(F, True);
end;

procedure Separer;
begin
  if Fait then
  begin
    Say('');
    Say('');
  end;
  Fait := True;
end;

{ ---------------------------------------------------------------- }
{ Programme principal                                              }
{ ---------------------------------------------------------------- }

begin
  RapportOuvert := False;
  Fait := False;
  LireParametres;

  if OptAide or (ParamCount = 0) then
  begin
    Aide;
    Halt(0);
  end;

  if OptRapport then OuvrirRapport;

  if OptVolume or OptDosage or OptMasse or OptDensite then
  begin
    Separer;
    TraiterBeton;
  end;
  if OptEC then
  begin
    Separer;
    TraiterRapportEC;
  end;
  if OptComp then
  begin
    Separer;
    TraiterCompression;
  end;
  if OptMelange then
  begin
    Separer;
    TraiterMelange;
  end;
  if not Fait then TraiterReference;

  if OptRapport then
  begin
    FinRapport;
    WriteLn;
    WriteLn('Rapport enregistre dans : ', FichierRapport);
  end;
end.

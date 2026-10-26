{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @version: 1.00
  @website(https://www.gladir.com/ciment-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal
  @description: Clone de l'application CEMGEMS (CemGEMS : modelisation
                thermodynamique des materiaux cimentaires - hydratation,
                lixiviation, carbonatation, penetration de sels).

  CemGEMS calcule l'equilibre thermodynamique (minimisation de l'energie
  libre de Gibbs, moteur GEMS3K, bases Cemdata18 et PSI/Nagra) d'une
  recette cimentaire : ciment, ajouts cimentaires (cendres volantes,
  laitier, fumee de silice, calcaire, argile calcinee), eau, sels. Ce clone
  fournit un moteur de minimisation de Gibbs simplifie mais reel :

    - Systeme chimique reduit : H2O, H+, Ca, Si, Al, Fe, S, K, Na, Mg, C, Cl
    - Phase aqueuse : 33 especes, coefficients d'activite de Truesdell-Jones
      (Debye-Hueckel etendu), activite de l'eau, force ionique
    - Phases solides de type Cemdata18 : C-S-H (solution solide ideale a 4
      pole), portlandite, ettringite, monosulfate, mono- et hemicarbonate,
      sel de Friedel, stratlingite, hydrogrenats, hydrotalcite, brucite,
      gypse, calcite, gibbsite, silice amorphe, ferrihydrite
    - Resolution : methode de points interieurs (fonction barriere) puis
      polissage de Newton sur l'ensemble actif de phases
    - Cinetique d'hydratation : modele de Parrot-Killoh (C3S, C2S, C3A,
      C4AF), lois exponentielles pour les ajouts cimentaires
    - Processus : equilibre unique, hydratation, melange (balayage de
      recette), lixiviation, carbonatation, penetration de sels
    - Resultats : assemblage de phases (g et cm3 pour 100 g de liant),
      solution interstitielle (pH, force ionique, concentrations),
      porosite, chaleur, graphiques, exports CSV / BMP
    - Menus deroulants adaptes de CLONEDRAW\PAINT.PAS

  Ligne de commande :
    CEMGEMS [recette.CGM]
    CEMGEMS /B [recette.CGM] [sortie.CSV]   (mode lot : sans interface)

  Aucune dependance externe : tout le code est dans ce fichier. Les
  constantes thermodynamiques sont des valeurs indicatives inspirees de
  Cemdata18 ; ce programme est pedagogique et ne remplace pas GEMS.
}

Program CEMGEMS;

{$IFDEF FPC}
 {$MODE TP}
 {$Q-}
 {$R-}
{$ELSE}
 {$M 32768,0,655360}
{$ENDIF}

Uses {$IFDEF FPC}
      DOS,Crt,PtcGraph,PtcCrt,PtcMouse
     {$ELSE}
      DOS,Crt,Graph
     {$ENDIF};

{ --------------------------------------------------------------------- }
{ Constantes generales                                                  }
{ --------------------------------------------------------------------- }

Const
 PROG_TITLE      = 'CEMGEMS Clone 1.00';
 PROG_VERSION    = '1.00';

 MENUBAR_H       = 20;
 TOOLBAR_H       = 24;
 STATUS_H        = 18;

 NUM_MENUS       = 8;
 MAX_MENU_ITEMS  = 16;
 MENU_FILE       = 0;
 MENU_REC        = 1;
 MENU_PROC       = 2;
 MENU_RES        = 3;
 MENU_VIEW       = 4;
 MENU_DB         = 5;
 MENU_TOOLS      = 6;
 MENU_HELP       = 7;

 LN10            = 2.302585093;

{ --------------------------------------------------------------------- }
{ Utilitaires                                                           }
{ --------------------------------------------------------------------- }

Function UpStr(Const S: String): String;
Var I: Integer; R: String;
Begin
 R := S;
 For I := 1 To Length(R) Do
  If (R[I] >= 'a') And (R[I] <= 'z') Then R[I] := Chr(Ord(R[I]) - 32);
 UpStr := R;
End;

Function TrimStr(Const S: String): String;
Var A, B: Integer;
Begin
 A := 1; B := Length(S);
 While (A <= B) And (S[A] <= ' ') Do Inc(A);
 While (B >= A) And (S[B] <= ' ') Do Dec(B);
 TrimStr := Copy(S, A, B - A + 1);
End;

Function IStr(V: LongInt): String;
Var S: String;
Begin
 Str(V, S);
 IStr := S;
End;

Function RStr(V: Real; Dec: Integer): String;
Var S: String;
Begin
 If Abs(V) >= 1E9 Then Begin Str(V:0:0, S); RStr := S; Exit; End;
 Str(V:0:Dec, S);
 RStr := S;
End;

{ Nombre reel sans zeros inutiles }
Function RTrim(V: Real; Dec: Integer): String;
Var S: String;
Begin
 S := RStr(V, Dec);
 If Pos('.', S) > 0 Then Begin
  While (Length(S) > 1) And (S[Length(S)] = '0') Do Delete(S, Length(S), 1);
  If (Length(S) > 1) And (S[Length(S)] = '.') Then Delete(S, Length(S), 1);
 End;
 RTrim := S;
End;

Function PadR(Const S: String; W: Integer): String;
Var R: String;
Begin
 R := S;
 While Length(R) < W Do R := R + ' ';
 PadR := Copy(R, 1, W);
End;

Function PadL(Const S: String; W: Integer): String;
Var R: String;
Begin
 R := S;
 While Length(R) < W Do R := ' ' + R;
 PadL := R;
End;

Function ParseReal(Const S: String; Var V: Real): Boolean;
Var Code: Integer; R: Real; T: String; I: Integer;
Begin
 T := TrimStr(S);
 For I := 1 To Length(T) Do If T[I] = ',' Then T[I] := '.';
 If T = '' Then Begin ParseReal := False; Exit; End;
 Val(T, R, Code);
 If Code = 0 Then Begin V := R; ParseReal := True; End
 Else ParseReal := False;
End;

Function ExtractExt(Const FN: String): String;
Var I: Integer;
Begin
 I := Length(FN);
 While (I > 0) And (FN[I] <> '.') And (FN[I] <> '\') And (FN[I] <> '/') Do Dec(I);
 If (I > 0) And (FN[I] = '.') Then ExtractExt := UpStr(Copy(FN, I, 255))
 Else ExtractExt := '';
End;

Function ChangeExt(Const FN, Ext: String): String;
Var I: Integer;
Begin
 I := Length(FN);
 While (I > 0) And (FN[I] <> '.') And (FN[I] <> '\') And (FN[I] <> '/') Do Dec(I);
 If (I > 0) And (FN[I] = '.') Then ChangeExt := Copy(FN, 1, I - 1) + Ext
 Else ChangeExt := FN + Ext;
End;

Function BaseName(Const FN: String): String;
Var I: Integer;
Begin
 I := Length(FN);
 While (I > 0) And (FN[I] <> '\') And (FN[I] <> '/') Do Dec(I);
 BaseName := Copy(FN, I + 1, 255);
End;

Function FileOK(Const FN: String): Boolean;
Var F: File;
Begin
 {$I-}
 Assign(F, FN);
 Reset(F, 1);
 {$I+}
 If IOResult = 0 Then Begin
  Close(F);
  FileOK := True;
 End
 Else FileOK := False;
End;

Function RMin(A, B: Real): Real;
Begin
 If A < B Then RMin := A Else RMin := B;
End;

Function RMax(A, B: Real): Real;
Begin
 If A > B Then RMax := A Else RMax := B;
End;

Function IMin(A, B: LongInt): LongInt;
Begin
 If A < B Then IMin := A Else IMin := B;
End;

Function IMax(A, B: LongInt): LongInt;
Begin
 If A > B Then IMax := A Else IMax := B;
End;

{ exponentielle protegee contre le depassement (reels 6 octets de TP) }
Function SExp(X: Real): Real;
Begin
 If X > 80 Then SExp := Exp(80)
 Else If X < -80 Then SExp := 0
 Else SExp := Exp(X);
End;

Function Pw(X, Y: Real): Real;
Begin
 If X <= 0 Then Pw := 0 Else Pw := SExp(Y * Ln(X));
End;

{ Horloge en millisecondes depuis minuit }
Function NowMs: LongInt;
Var H, M, S, S100: Word;
Begin
 GetTime(H, M, S, S100);
 NowMs := LongInt(H) * 3600000 + LongInt(M) * 60000 +
          LongInt(S) * 1000 + LongInt(S100) * 10;
End;

{ --------------------------------------------------------------------- }
{ Base de donnees thermodynamique                                       }
{ --------------------------------------------------------------------- }

Const
 NM      = 12;     { composants : H2O H+ Ca Si Al Fe S K Na Mg C Cl }
 MAXSP   = 36;     { especes aqueuses }
 MAXEM   = 28;     { pole de solides }
 MAXPH   = 24;     { phases solides }
 MAXUN   = 36;     { inconnues du polissage }
 NPHASES = 20;

 C_W = 0;  C_H = 1;  C_CA = 2;  C_SI = 3;  C_AL = 4;  C_FE = 5;
 C_S = 6;  C_K = 7;  C_NA = 8;  C_MG = 9;  C_C = 10;  C_CL = 11;

 PH_CSH = 0;  PH_CH  = 1;  PH_AFT = 2;  PH_FAFT = 3; PH_MS  = 4;
 PH_MC  = 5;  PH_HC  = 6;  PH_FR  = 7;  PH_STR  = 8; PH_HG  = 9;
 PH_FHG = 10; PH_HT  = 11; PH_BRU = 12; PH_GYP  = 13; PH_HEM = 14;
 PH_ANH = 15; PH_CAL = 16; PH_AH3 = 17; PH_SIO2 = 18; PH_FH  = 19;

 R_GAS   = 8.314;
 MW_WATER = 18.015;
 N_WATER  = 55.508;        { mol d'eau par kg }

Type
 TVec = Array[0..NM-1] Of Real;

Var
 MName   : Array[0..NM-1] Of String[8];
 MMass   : TVec;
 MChg    : Array[0..NM-1] Of Integer;

 NSp     : Integer;
 SpName  : Array[0..MAXSP-1] Of String[12];
 SpZ     : Array[0..MAXSP-1] Of Integer;
 SpN     : Array[0..MAXSP-1] Of Byte;
 SpIdx   : Array[0..MAXSP-1, 0..2] Of Byte;
 SpNu    : Array[0..MAXSP-1, 0..2] Of Real;
 SpLK25  : Array[0..MAXSP-1] Of Real;
 SpDH    : Array[0..MAXSP-1] Of Real;
 SpLK    : Array[0..MAXSP-1] Of Real;      { ln K a la temperature }

 NEm     : Integer;
 NPh     : Integer;
 EmName  : Array[0..MAXEM-1] Of String[16];
 EmPh    : Array[0..MAXEM-1] Of Integer;
 EmNu    : Array[0..MAXEM-1, 0..NM-1] Of Real;
 EmLK25  : Array[0..MAXEM-1] Of Real;
 EmDH    : Array[0..MAXEM-1] Of Real;
 EmLK    : Array[0..MAXEM-1] Of Real;
 EmV     : Array[0..MAXEM-1] Of Real;      { cm3/mol }
 EmMW    : Array[0..MAXEM-1] Of Real;      { g/mol }
 PhName  : Array[0..MAXPH-1] Of String[16];
 PhFirst : Array[0..MAXPH-1] Of Integer;
 PhCount : Array[0..MAXPH-1] Of Integer;
 PhCls   : Array[0..MAXPH-1] Of Integer;

 DbTemp  : Real;
 MuStart : Real;
 NSpReal : Integer;                 { especes reelles ; les suivantes sont des sites fixes }
 AdsK, AdsNa : Real;                { fixation des alcalis sur le C-S-H (L/kg) }
 MCsh    : Real;                    { masse de C-S-H (kg pour 100 g de liant) }
 CsCa    : Real;                    { Ca/Si du C-S-H }
 DHA, DHB : Real;

Procedure DefSp(Const Nme: String; Z: Integer; LK, DH: Real;
                C1: Integer; N1: Real; C2: Integer; N2: Real; C3: Integer; N3: Real);
Var K: Integer;
Begin
 SpName[NSp] := Nme; SpZ[NSp] := Z; SpLK25[NSp] := LK * LN10; SpDH[NSp] := DH;
 K := 0;
 If C1 >= 0 Then Begin SpIdx[NSp, K] := C1; SpNu[NSp, K] := N1; Inc(K); End;
 If C2 >= 0 Then Begin SpIdx[NSp, K] := C2; SpNu[NSp, K] := N2; Inc(K); End;
 If C3 >= 0 Then Begin SpIdx[NSp, K] := C3; SpNu[NSp, K] := N3; Inc(K); End;
 SpN[NSp] := K;
 Inc(NSp);
End;

Procedure DefPh(Const Nme: String; Cls: Integer);
Begin
 PhName[NPh] := Nme; PhFirst[NPh] := NEm; PhCount[NPh] := 0; PhCls[NPh] := Cls;
 Inc(NPh);
End;

{ pole de phase : formule de dissolution (OH = nombre de OH-, H2O libere),
  logKsp sous la forme Cemdata (avec OH-), DH en kJ/mol (forme OH-) }
Procedure DefEm(Const Nme: String; Ca, Si, Al, Fe, S, K, Na, Mg, C, Cl, OH, H2O,
                LK, DH, V: Real);
Var I: Integer;
Begin
 EmName[NEm] := Nme; EmPh[NEm] := NPh - 1;
 For I := 0 To NM - 1 Do EmNu[NEm, I] := 0;
 EmNu[NEm, C_CA] := Ca; EmNu[NEm, C_SI] := Si; EmNu[NEm, C_AL] := Al;
 EmNu[NEm, C_FE] := Fe; EmNu[NEm, C_S] := S; EmNu[NEm, C_K] := K;
 EmNu[NEm, C_NA] := Na; EmNu[NEm, C_MG] := Mg; EmNu[NEm, C_C] := C;
 EmNu[NEm, C_CL] := Cl;
 EmNu[NEm, C_H] := -OH;
 EmNu[NEm, C_W] := OH + H2O;
 EmLK25[NEm] := (LK + 14.0 * OH) * LN10;
 EmDH[NEm] := DH - 55.8 * OH;
 EmMW[NEm] := 0;
 For I := 0 To NM - 1 Do EmMW[NEm] := EmMW[NEm] + EmNu[NEm, I] * MMass[I];
 If V > 0 Then EmV[NEm] := V Else EmV[NEm] := EmMW[NEm] / 2.25;
 Inc(PhCount[NPh - 1]);
 Inc(NEm);
End;

Procedure InitDatabase;
Var I: Integer;

 Procedure M(Ix: Integer; Const Nme: String; Mass: Real; Z: Integer);
 Begin MName[Ix] := Nme; MMass[Ix] := Mass; MChg[Ix] := Z; End;

 Procedure Mst(Ix: Integer);
 Begin DefSp(MName[Ix], MChg[Ix], 0, 0, Ix, 1, -1, 0, -1, 0); End;

Begin
 M(0, 'H2O', 18.015, 0);   M(1, 'H+', 1.008, 1);     M(2, 'Ca+2', 40.078, 2);
 M(3, 'H4SiO4', 96.113, 0); M(4, 'AlOH4-', 95.012, -1); M(5, 'FeOH4-', 123.873, -1);
 M(6, 'SO4-2', 96.06, -2);  M(7, 'K+', 39.098, 1);   M(8, 'Na+', 22.99, 1);
 M(9, 'Mg+2', 24.305, 2);   M(10, 'CO3-2', 60.009, -2); M(11, 'Cl-', 35.453, -1);
 NSp := 0; NEm := 0; NPh := 0;
 { especes : composants puis complexes }
 For I := 1 To NM - 1 Do Mst(I);
 DefSp('OH-', -1, -14.0, 55.8, C_W, 1, C_H, -1, -1, 0);
 DefSp('H3SiO4-', -1, -9.84, 0, C_SI, 1, C_H, -1, -1, 0);
 DefSp('H2SiO4-2', -2, -23.14, 0, C_SI, 1, C_H, -2, -1, 0);
 DefSp('CaOH+', 1, -12.78, 0, C_CA, 1, C_W, 1, C_H, -1);
 DefSp('CaSO4', 0, 2.36, 0, C_CA, 1, C_S, 1, -1, 0);
 DefSp('HCO3-', -1, 10.33, -14.7, C_C, 1, C_H, 1, -1, 0);
 DefSp('H2CO3', 0, 16.68, 0, C_C, 1, C_H, 2, -1, 0);
 DefSp('CaCO3', 0, 3.22, 0, C_CA, 1, C_C, 1, -1, 0);
 DefSp('CaHCO3+', 1, 11.44, 0, C_CA, 1, C_C, 1, C_H, 1);
 DefSp('CaH3SiO4+', 1, -8.64, 0, C_CA, 1, C_SI, 1, C_H, -1);
 DefSp('CaH2SiO4', 0, -18.54, 0, C_CA, 1, C_SI, 1, C_H, -2);
 DefSp('KOH', 0, -14.46, 0, C_K, 1, C_W, 1, C_H, -1);
 DefSp('KSO4-', -1, 0.85, 0, C_K, 1, C_S, 1, -1, 0);
 DefSp('NaOH', 0, -14.18, 0, C_NA, 1, C_W, 1, C_H, -1);
 DefSp('NaSO4-', -1, 0.7, 0, C_NA, 1, C_S, 1, -1, 0);
 DefSp('NaCO3-', -1, 1.27, 0, C_NA, 1, C_C, 1, -1, 0);
 DefSp('NaHCO3', 0, 10.08, 0, C_NA, 1, C_C, 1, C_H, 1);
 DefSp('MgOH+', 1, -11.44, 0, C_MG, 1, C_W, 1, C_H, -1);
 DefSp('MgSO4', 0, 2.37, 0, C_MG, 1, C_S, 1, -1, 0);
 DefSp('MgCO3', 0, 2.98, 0, C_MG, 1, C_C, 1, -1, 0);
 DefSp('MgHCO3+', 1, 11.4, 0, C_MG, 1, C_C, 1, C_H, 1);
 DefSp('HSO4-', -1, 1.98, 0, C_S, 1, C_H, 1, -1, 0);
 NSpReal := NSp;
 { sites fixes : echange K+ / H+ ou Na+ / H+ sur le C-S-H (neutres), Rd a pH 13,5 }
 DefSp('K+(ads)', 0, -13.5, 0, C_K, 1, C_H, -1, -1, 0);
 DefSp('Na+(ads)', 0, -13.5, 0, C_NA, 1, C_H, -1, -1, 0);
 AdsK := 0.4; AdsNa := 0.4; MCsh := 0; CsCa := 1.6;
 { phases solides : Ca Si Al Fe S K Na Mg C Cl OH H2O logK dH V }
 DefPh('C-S-H', 0);
 DefEm('TobH',  0.6667, 1,      0, 0, 0, 0, 0, 0, 0, 0, 1.3333, -1.1667, -9.22, 0, 55.4);
 DefEm('TobD',  0.8333, 1,      0, 0, 0, 0, 0, 0, 0, 0, 1.6667, -1.0,    -11.81, 0, 62.2);
 DefEm('JenH',  1.3333, 1,      0, 0, 0, 0, 0, 0, 0, 0, 2.6667, -1.1667, -15.52, 0, 77.3);
 DefEm('JenD',  1.5,    0.6667, 0, 0, 0, 0, 0, 0, 0, 0, 3.0,    -0.3333, -13.32, 0, 75.2);
 DefPh('Portlandite', 1);
 DefEm('Portlandite', 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, -5.19, -16.7, 33.06);
 DefPh('Ettringite', 2);
 DefEm('Ettringite', 6, 0, 2, 0, 3, 0, 0, 0, 0, 0, 4, 26, -44.9, 0, 707.0);
 DefPh('Fe-ettringite', 2);
 DefEm('Fe-ettringite', 6, 0, 0, 2, 3, 0, 0, 0, 0, 0, 4, 26, -44.0, 0, 717.0);
 DefPh('Monosulfate', 3);
 DefEm('Monosulfate', 4, 0, 2, 0, 1, 0, 0, 0, 0, 0, 4, 6, -29.26, 0, 309.0);
 DefPh('Monocarbonate', 3);
 DefEm('Monocarbonate', 4, 0, 2, 0, 0, 0, 0, 0, 1, 0, 4, 5, -31.47, 0, 262.0);
 DefPh('Hemicarbonate', 3);
 DefEm('Hemicarbonate', 4, 0, 2, 0, 0, 0, 0, 0, 0.5, 0, 5, 5.5, -29.13, 0, 285.0);
 DefPh('Sel de Friedel', 3);
 DefEm('Sel de Friedel', 4, 0, 2, 0, 0, 0, 0, 0, 0, 2, 4, 4, -27.1, 0, 272.0);
 DefPh('Stratlingite', 4);
 DefEm('Stratlingite', 2, 1, 2, 0, 0, 0, 0, 0, 0, 0, 2, 1, -23.86, 0, 216.0);
 DefPh('Hydrogrenat', 4);
 DefEm('Hydrogrenat', 3, 0, 2, 0, 0, 0, 0, 0, 0, 0, 4, 0, -20.84, 0, 150.0);
 DefPh('Hydrogrenat-Fe', 4);
 DefEm('Hydrogrenat-Fe', 3, 0, 0, 2, 0, 0, 0, 0, 0, 0, 4, 0, -26.3, 0, 156.0);
 DefPh('Hydrotalcite', 5);
 DefEm('Hydrotalcite', 0, 0, 2, 0, 0, 0, 0, 4, 0, 0, 6, 3, -49.7, 0, 220.0);
 DefPh('Brucite', 5);
 DefEm('Brucite', 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 2, 0, -11.16, 0, 24.63);
 DefPh('Gypse', 7);
 DefEm('Gypse', 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 2, -4.58, 0, 74.3);
 DefPh('Hemihydrate', 7);
 DefEm('Hemihydrate', 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0.5, -3.59, 0, 52.9);
 DefPh('Anhydrite', 7);
 DefEm('Anhydrite', 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, -4.36, 0, 45.94);
 DefPh('Calcite', 6);
 DefEm('Calcite', 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, -8.48, -10.6, 36.93);
 DefPh('Gibbsite AH3', 8);
 DefEm('Gibbsite AH3', 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0.7, 0, 32.0);
 DefPh('Silice amorphe', 8);
 DefEm('Silice amorphe', 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, -2, -2.71, 0, 29.0);
 DefPh('Ferrihydrite', 8);
 DefEm('Ferrihydrite', 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, -1, 0, -7.5, 0, 34.3);
 DbTemp := -999;
 MuStart := 0.3;
End;

{ constantes a la temperature (C) : van't Hoff, Debye-Hueckel }
Procedure SetTemperature(TC: Real);
Var I: Integer; F: Real;
Begin
 If Abs(TC - DbTemp) < 1E-6 Then Exit;
 DbTemp := TC;
 F := 1000.0 / R_GAS * (1.0 / (TC + 273.15) - 1.0 / 298.15);
 For I := 0 To NSp - 1 Do SpLK[I] := SpLK25[I] - SpDH[I] * F;
 For I := 0 To NEm - 1 Do EmLK[I] := EmLK25[I] - EmDH[I] * F;
 DHA := 0.4918 + 6.6E-4 * TC + 3.4E-6 * TC * TC;
 DHB := 0.3248 + 1.4E-4 * TC;
End;

{ verification de la neutralite des formules (utile au test) }
Function CheckDatabase: String;
Var I, K, C: Integer; Q: Real; Msg: String;
Begin
 Msg := '';
 For I := 0 To NSp - 1 Do Begin
  Q := 0;
  For K := 0 To SpN[I] - 1 Do Q := Q + SpNu[I, K] * MChg[SpIdx[I, K]];
  If Abs(Q - SpZ[I]) > 1E-6 Then Msg := Msg + ' esp:' + SpName[I];
 End;
 For I := 0 To NEm - 1 Do Begin
  Q := 0;
  For C := 0 To NM - 1 Do Q := Q + EmNu[I, C] * MChg[C];
  If Abs(Q) > 1E-3 Then Msg := Msg + ' sol:' + EmName[I];
 End;
 CheckDatabase := Msg;
End;

{ --------------------------------------------------------------------- }
{ Solveur d'equilibre (minimisation de Gibbs)                            }
{ --------------------------------------------------------------------- }

Var
 Tt      : TVec;                       { totaux de composants (mol) }
 Xs      : TVec;                       { ln a ; Xs[0] = ln a(H2O) }
 XsCold  : TVec;
 WKg     : Real;                       { eau libre (kg) }
 IonS    : Real;                       { force ionique }
 GamL    : Array[0..MAXSP-1] Of Real;  { ln gamma }
 Mol     : Array[0..MAXSP-1] Of Real;  { molalites }
 SIe     : Array[0..MAXEM-1] Of Real;
 PhS     : Array[0..MAXPH-1] Of Real;
 NEmol   : Array[0..MAXEM-1] Of Real;
 EmW     : Array[0..MAXEM-1] Of Real;
 PhU     : Array[0..MAXPH-1] Of Real;
 PhOm    : Array[0..MAXPH-1] Of Real;   { poids de la barriere par phase }
 NpP     : Array[0..MAXPH-1] Of Real;
 ActP    : Array[0..MAXPH-1] Of Boolean;
 DropCnt : Array[0..MAXPH-1] Of Integer;
 AqT     : TVec;                       { composants dissous (mol/kg d'eau) }
 AqW     : TVec;                       { composants en solution + fixes (mol) }
 SpWt    : Array[0..MAXSP-1] Of Real;  { poids des especes (kg d'eau ou de C-S-H) }
 ScC     : TVec;
 JM      : Array[0..MAXUN-1, 0..MAXUN] Of Real;
 ActE    : Array[0..MAXUN-1] Of Integer;
 NAct    : Integer;
 Vv      : Array[0..MAXEM-1] Of Real;
 Rv, Dv  : Array[0..MAXUN-1] Of Real;
 XsSv    : TVec;
 VvSv    : Array[0..MAXEM-1] Of Real;
 HaveWarm: Boolean;
 EqStatus: String[40];
 EqIter  : Integer;
 EqDry   : Boolean;

{ ln gamma des especes (Truesdell-Jones, b = 0.123, a = 3.31 A) }
Procedure UpdateGamma;
Var I: Integer; Sq, G: Real;
Begin
 Sq := Sqrt(IonS);
 For I := 0 To NSp - 1 Do Begin
  If SpZ[I] = 0 Then G := 0.1 * IonS
  Else G := -DHA * Sqr(SpZ[I]) * Sq / (1 + DHB * 3.31 * Sq) + 0.123 * IonS;
  GamL[I] := G * LN10;
 End;
End;

{ molalites des especes pour les ln a courants X ; faux si depassement }
Function EvalSpec(Const X: TVec): Boolean;
Var I, K: Integer; L: Real;
Begin
 EvalSpec := True;
 For I := 0 To NSp - 1 Do Begin
  L := SpLK[I] - GamL[I];
  For K := 0 To SpN[I] - 1 Do L := L + SpNu[I, K] * X[SpIdx[I, K]];
  If L > 40 Then Begin EvalSpec := False; L := 40; End;
  Mol[I] := SExp(L);
 End;
End;

{ indices de saturation des poles et des phases (log-somme-exp) }
Procedure EvalSI(Const X: TVec);
Var E, C: Integer; L: Real;
Begin
 For E := 0 To NEm - 1 Do Begin
  L := -EmLK[E];
  For C := 0 To NM - 1 Do
   If EmNu[E, C] <> 0 Then L := L + EmNu[E, C] * X[C];
  SIe[E] := L;
 End;
End;

Procedure EvalPhases;
Var P, E: Integer; Mx, S: Real;
Begin
 For P := 0 To NPh - 1 Do Begin
  If PhCount[P] = 1 Then PhS[P] := SIe[PhFirst[P]]
  Else Begin
   Mx := SIe[PhFirst[P]];
   For E := PhFirst[P] + 1 To PhFirst[P] + PhCount[P] - 1 Do
    If SIe[E] > Mx Then Mx := SIe[E];
   S := 0;
   For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do S := S + SExp(SIe[E] - Mx);
   PhS[P] := Mx + Ln(S);
  End;
 End;
End;

Function SolveN(N: Integer): Boolean;
Var I, J, K, P: Integer; Mx, F, Tmp: Real;
Begin
 SolveN := False;
 For K := 0 To N - 1 Do Begin
  P := K; Mx := Abs(JM[K, K]);
  For I := K + 1 To N - 1 Do
   If Abs(JM[I, K]) > Mx Then Begin Mx := Abs(JM[I, K]); P := I; End;
  If Mx < 1E-30 Then Exit;
  If P <> K Then
   For J := K To N Do Begin Tmp := JM[K, J]; JM[K, J] := JM[P, J]; JM[P, J] := Tmp; End;
  For I := K + 1 To N - 1 Do Begin
   F := JM[I, K] / JM[K, K];
   If F <> 0 Then
    For J := K To N Do JM[I, J] := JM[I, J] - F * JM[K, J];
  End;
 End;
 For I := N - 1 Downto 0 Do Begin
  Tmp := JM[I, N];
  For J := I + 1 To N - 1 Do Tmp := Tmp - JM[I, J] * JM[J, N];
  JM[I, N] := Tmp / JM[I, I];
 End;
 SolveN := True;
End;

{ fonction barriere (a maximiser) ; -1E30 si hors du domaine }
Function Psi(Const X: TVec; Mu: Real): Real;
Var C, I, P: Integer; S, Sm: Real;
Begin
 Psi := -1E30;
 If Not EvalSpec(X) Then Exit;
 EvalSI(X);
 EvalPhases;
 S := 0;
 For P := 0 To NPh - 1 Do Begin
  If PhS[P] >= -1E-13 Then Exit;
  S := S + Mu * PhOm[P] * Ln(-PhS[P]);
 End;
 Sm := 0;
 For I := 0 To NSp - 1 Do Sm := Sm + SpWt[I] * Mol[I];
 S := S - Sm;
 For C := 1 To NM - 1 Do S := S + Tt[C] * X[C];
 Psi := S;
End;

{ composants dans la phase aqueuse }
Procedure AqueousTotals;
Var I, K, C: Integer;
Begin
 For C := 0 To NM - 1 Do Begin AqT[C] := 0; AqW[C] := 0; End;
 For I := 0 To NSp - 1 Do
  For K := 0 To SpN[I] - 1 Do Begin
   AqW[SpIdx[I, K]] := AqW[SpIdx[I, K]] + SpWt[I] * SpNu[I, K] * Mol[I];
   If I < NSpReal Then AqT[SpIdx[I, K]] := AqT[SpIdx[I, K]] + SpNu[I, K] * Mol[I];
  End;
End;

{ echelles des residus }
Procedure ComputeScales;
Var I, K, C, E: Integer;
Begin
 For C := 1 To NM - 1 Do ScC[C] := Abs(Tt[C]) + 1E-9;
 For I := 0 To NSp - 1 Do
  For K := 0 To SpN[I] - 1 Do
   ScC[SpIdx[I, K]] := ScC[SpIdx[I, K]] + SpWt[I] * Abs(SpNu[I, K]) * Mol[I];
 For E := 0 To NEm - 1 Do
  For C := 1 To NM - 1 Do
   If EmNu[E, C] <> 0 Then ScC[C] := ScC[C] + Abs(EmNu[E, C]) * NEmol[E];
End;

{ une etape de Newton sur le probleme barriere ; renvoie le residu relatif max }
Function BarrierNewton(Mu: Real; Var Stalled: Boolean): Real;
Var
 C, K, I, E, P, A, B, N, Cnt: Integer;
 Np, U, Mx, Cv, G0, Alpha, P0, P1, DS, AMax, Conv, Dg: Real;
 Nb, F: TVec;
 X0: TVec;
 Sc: TVec;
Begin
 Stalled := False;
 If Not EvalSpec(Xs) Then Begin BarrierNewton := 1E30; Stalled := True; Exit; End;
 EvalSI(Xs); EvalPhases;
 For P := 0 To NPh - 1 Do Begin
  U := -PhS[P]; PhU[P] := U; Np := Mu * PhOm[P] / U; NpP[P] := Np;
  For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do Begin
   EmW[E] := SExp(SIe[E] - PhS[P]);
   NEmol[E] := Np * EmW[E];
  End;
 End;
 AqueousTotals;
 ComputeScales;
 Conv := 0;
 For C := 1 To NM - 1 Do Begin
  Cv := Tt[C] - AqW[C];
  For E := 0 To NEm - 1 Do Cv := Cv - EmNu[E, C] * NEmol[E];
  F[C] := Cv;
  If Abs(Cv) / ScC[C] > Conv Then Conv := Abs(Cv) / ScC[C];
 End;
 BarrierNewton := Conv;
 { matrice -Hessien }
 N := NM - 1;
 For A := 0 To N - 1 Do For B := 0 To N Do JM[A, B] := 0;
 For I := 0 To NSp - 1 Do
  For A := 0 To SpN[I] - 1 Do
   For B := 0 To SpN[I] - 1 Do
    If (SpIdx[I, A] > 0) And (SpIdx[I, B] > 0) Then
     JM[SpIdx[I, A] - 1, SpIdx[I, B] - 1] := JM[SpIdx[I, A] - 1, SpIdx[I, B] - 1] +
       SpWt[I] * SpNu[I, A] * SpNu[I, B] * Mol[I];
 For P := 0 To NPh - 1 Do Begin
  For C := 1 To NM - 1 Do Nb[C] := 0;
  For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do Begin
   For C := 1 To NM - 1 Do Begin
    If EmNu[E, C] <> 0 Then Begin
     Nb[C] := Nb[C] + EmW[E] * EmNu[E, C];
     If PhCount[P] > 1 Then
      For K := 1 To NM - 1 Do
       If EmNu[E, K] <> 0 Then
        JM[C - 1, K - 1] := JM[C - 1, K - 1] + NpP[P] * EmW[E] * EmNu[E, C] * EmNu[E, K];
    End;
   End;
  End;
  If PhCount[P] = 1 Then Begin
   E := PhFirst[P];
   For C := 1 To NM - 1 Do Nb[C] := EmNu[E, C];
   Dg := NpP[P] / PhU[P];
  End
  Else Dg := NpP[P] * (1.0 / PhU[P] - 1.0);
  For C := 1 To NM - 1 Do
   If Nb[C] <> 0 Then
    For K := 1 To NM - 1 Do
     If Nb[K] <> 0 Then
      JM[C - 1, K - 1] := JM[C - 1, K - 1] + Dg * Nb[C] * Nb[K];
 End;
 { mise a l'echelle diagonale }
 For C := 1 To NM - 1 Do Begin
  Sc[C] := JM[C - 1, C - 1];
  If Sc[C] < 1E-30 Then Sc[C] := 1;
  Sc[C] := 1.0 / Sqrt(Sc[C]);
 End;
 For A := 0 To N - 1 Do Begin
  For B := 0 To N - 1 Do JM[A, B] := JM[A, B] * Sc[A + 1] * Sc[B + 1];
  JM[A, N] := F[A + 1] * Sc[A + 1];
 End;
 If Not SolveN(N) Then Begin Stalled := True; Exit; End;
 Mx := 0;
 For A := 0 To N - 1 Do Begin
  Dv[A] := JM[A, N] * Sc[A + 1];
  If Abs(Dv[A]) > Mx Then Mx := Abs(Dv[A]);
 End;
 If Mx > 12 Then For A := 0 To N - 1 Do Dv[A] := Dv[A] * 12 / Mx;
 { limite lineaire de faisabilite }
 AMax := 1;
 For P := 0 To NPh - 1 Do Begin
  DS := 0;
  For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do
   For C := 1 To NM - 1 Do DS := DS + EmW[E] * EmNu[E, C] * Dv[C - 1];
  If DS > 1E-30 Then If 0.95 * PhU[P] / DS < AMax Then AMax := 0.95 * PhU[P] / DS;
 End;
 G0 := 0;
 For A := 0 To N - 1 Do G0 := G0 + F[A + 1] * Dv[A];
 X0 := Xs;
 P0 := Psi(X0, Mu);
 Alpha := AMax;
 Cnt := 0;
 While Cnt < 40 Do Begin
  For A := 0 To N - 1 Do Xs[A + 1] := X0[A + 1] + Alpha * Dv[A];
  P1 := Psi(Xs, Mu);
  If (P1 > -1E29) And (P1 >= P0 + 1E-4 * Alpha * G0 - 1E-12 * Abs(P0)) Then Break;
  Alpha := Alpha * 0.5;
  Inc(Cnt);
 End;
 If Cnt >= 40 Then Begin Xs := X0; Stalled := True; End;
End;

{ faisabilite stricte : tous les PhS < 0 ; sinon rapproche du point froid }
Procedure MakeFeasible;
Var Lam: Real; I, K: Integer; X: TVec; Ok: Boolean; Lams: Array[0..5] Of Real;
Begin
 Lams[0] := 0; Lams[1] := 0.02; Lams[2] := 0.06; Lams[3] := 0.2; Lams[4] := 0.5; Lams[5] := 1;
 X := Xs;
 For K := 0 To 5 Do Begin
  Lam := Lams[K];
  For I := 1 To NM - 1 Do Xs[I] := (1 - Lam) * X[I] + Lam * XsCold[I];
  EvalSI(Xs); EvalPhases;
  Ok := EvalSpec(Xs);
  For I := 0 To NPh - 1 Do If PhS[I] >= -1E-6 Then Ok := False;
  If Ok Then Exit;
 End;
End;

Procedure ColdStart;
Var I: Integer;
Begin
 XsCold[1] := Ln(1E-7);
 For I := 2 To NM - 1 Do XsCold[I] := Ln(1E-12);
 XsCold[C_AL] := Ln(1E-16);
 XsCold[C_FE] := Ln(1E-30);
 For I := 1 To NM - 1 Do Xs[I] := XsCold[I];
End;

{ ---- polissage : Newton sur l'ensemble actif ---- }

Procedure BuildAct;
Var P, E: Integer;
Begin
 NAct := 0;
 For P := 0 To NPh - 1 Do
  If ActP[P] Then
   For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do Begin
    ActE[NAct] := E; Inc(NAct);
   End;
End;

{ residu du systeme actif ; renvoie la somme des carres, remplit Rv }
Function PolRes: Real;
Var C, K, E, P: Integer; S, Cv: Real;
Begin
 PolRes := 1E30;
 If Not EvalSpec(Xs) Then Exit;
 EvalSI(Xs);
 For P := 0 To NPh - 1 Do NpP[P] := 0;
 For E := 0 To NEm - 1 Do NEmol[E] := 0;
 For K := 0 To NAct - 1 Do Begin
  E := ActE[K];
  NEmol[E] := SExp(Vv[E]);
  NpP[EmPh[E]] := NpP[EmPh[E]] + NEmol[E];
 End;
 AqueousTotals;
 S := 0;
 For C := 1 To NM - 1 Do Begin
  Cv := Tt[C] - AqW[C];
  For K := 0 To NAct - 1 Do Cv := Cv - EmNu[ActE[K], C] * NEmol[ActE[K]];
  Rv[C - 1] := Cv / ScC[C];
  S := S + Sqr(Rv[C - 1]);
 End;
 For K := 0 To NAct - 1 Do Begin
  E := ActE[K];
  Rv[NM - 1 + K] := Vv[E] - Ln(NpP[EmPh[E]]) - SIe[E];
  S := S + Sqr(Rv[NM - 1 + K]);
 End;
 PolRes := S;
End;

{ 0 = converge, 1 = singulier, 2 = pas de convergence }
Function PolishNewton: Integer;
Var It, N, C, K, I, A, B, R, E, F, Cnt: Integer;
    M0, M1, Alpha, Mx: Real;
Begin
 N := NM - 1 + NAct;
 PolishNewton := 2;
 M0 := PolRes;
 For It := 1 To 40 Do Begin
  If M0 < 1E-20 Then Begin PolishNewton := 0; Exit; End;
  For A := 0 To N - 1 Do For B := 0 To N Do JM[A, B] := 0;
  For I := 0 To NSp - 1 Do
   For A := 0 To SpN[I] - 1 Do
    For B := 0 To SpN[I] - 1 Do
     If (SpIdx[I, A] > 0) And (SpIdx[I, B] > 0) Then
      JM[SpIdx[I, A] - 1, SpIdx[I, B] - 1] := JM[SpIdx[I, A] - 1, SpIdx[I, B] - 1] -
        SpWt[I] * SpNu[I, A] * SpNu[I, B] * Mol[I] / ScC[SpIdx[I, A]];
  For K := 0 To NAct - 1 Do Begin
   E := ActE[K];
   For C := 1 To NM - 1 Do Begin
    JM[C - 1, NM - 1 + K] := -EmNu[E, C] * NEmol[E] / ScC[C];
    JM[NM - 1 + K, C - 1] := -EmNu[E, C];
   End;
   For R := 0 To NAct - 1 Do Begin
    F := ActE[R];
    If R = K Then JM[NM - 1 + K, NM - 1 + R] := 1;
    If EmPh[F] = EmPh[E] Then
     JM[NM - 1 + K, NM - 1 + R] := JM[NM - 1 + K, NM - 1 + R] - NEmol[F] / NpP[EmPh[E]];
   End;
  End;
  For A := 0 To N - 1 Do JM[A, N] := -Rv[A];
  If Not SolveN(N) Then Begin PolishNewton := 1; Exit; End;
  Mx := 0;
  For A := 0 To N - 1 Do Begin
   Dv[A] := JM[A, N];
   If Abs(Dv[A]) > Mx Then Mx := Abs(Dv[A]);
  End;
  If Mx > 6 Then For A := 0 To N - 1 Do Dv[A] := Dv[A] * 6 / Mx;
  XsSv := Xs;
  For K := 0 To NAct - 1 Do VvSv[ActE[K]] := Vv[ActE[K]];
  Alpha := 1; Cnt := 0;
  While Cnt < 30 Do Begin
   For A := 1 To NM - 1 Do Xs[A] := XsSv[A] + Alpha * Dv[A - 1];
   For K := 0 To NAct - 1 Do Vv[ActE[K]] := VvSv[ActE[K]] + Alpha * Dv[NM - 1 + K];
   M1 := PolRes;
   If M1 < M0 Then Break;
   Alpha := Alpha * 0.5;
   Inc(Cnt);
  End;
  If Cnt >= 30 Then Begin
   Xs := XsSv;
   For K := 0 To NAct - 1 Do Vv[ActE[K]] := VvSv[ActE[K]];
   M0 := PolRes;
   Exit;
  End;
  M0 := M1;
 End;
 If M0 < 1E-14 Then PolishNewton := 0;
End;

{ ligne nu-barre (composants 1..NM-1) d'une phase avec les poids courants }
Procedure PhaseRow(P: Integer; Var Rw: TVec);
Var E, C: Integer; W, N: Real;
Begin
 For C := 0 To NM - 1 Do Rw[C] := 0;
 N := 0;
 For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do N := N + NEmol[E];
 If N <= 0 Then N := 1;
 For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do Begin
  If PhCount[P] = 1 Then W := 1 Else W := NEmol[E] / N;
  For C := 1 To NM - 1 Do Rw[C] := Rw[C] + W * EmNu[E, C];
 End;
End;

{ test du ratio : phase a retirer quand P entre dans l'ensemble actif ;
  -1 si aucune, -2 si P n'est pas lineairement dependante des phases actives }
Function RatioLeave(P: Integer): Integer;
Var Q, R, C, NA, Who: Integer; Rows: Array[0..MAXPH-1] Of TVec; Idx: Array[0..MAXPH-1] Of Integer;
    Rp: TVec; Lam: Array[0..MAXPH-1] Of Real; S, Mx, Best, Rt: Real;
Begin
 RatioLeave := -2;
 NA := 0;
 For Q := 0 To NPh - 1 Do
  If ActP[Q] And (Q <> P) Then Begin Idx[NA] := Q; PhaseRow(Q, Rows[NA]); Inc(NA); End;
 If NA = 0 Then Exit;
 PhaseRow(P, Rp);
 For Q := 0 To NA - 1 Do Begin
  For R := 0 To NA - 1 Do Begin
   S := 0;
   For C := 1 To NM - 1 Do S := S + Rows[Q][C] * Rows[R][C];
   JM[Q, R] := S;
  End;
  JM[Q, Q] := JM[Q, Q] * (1 + 1E-12) + 1E-14;
  S := 0;
  For C := 1 To NM - 1 Do S := S + Rows[Q][C] * Rp[C];
  JM[Q, NA] := S;
 End;
 If Not SolveN(NA) Then Exit;
 For Q := 0 To NA - 1 Do Lam[Q] := JM[Q, NA];
 Mx := 0;
 For C := 1 To NM - 1 Do Begin
  S := Rp[C];
  For Q := 0 To NA - 1 Do S := S - Lam[Q] * Rows[Q][C];
  If Abs(S) > Mx Then Mx := Abs(S);
 End;
 If Mx > 1E-6 Then Exit;
 Who := -1; Best := 1E30;
 For Q := 0 To NA - 1 Do
  If Lam[Q] > 1E-9 Then Begin
   Rt := NpP[Idx[Q]] / Lam[Q];
   If Rt < Best Then Begin Best := Rt; Who := Idx[Q]; End;
  End;
 RatioLeave := Who;
End;

Function PolishAll(Mu: Real): Boolean;
Var Loop, P, E, Who, Lk, Swaps: Integer; Changed, Viol: Boolean; Mn, Mx: Real; R: Integer;
    XOk: TVec; VOk: Array[0..MAXEM-1] Of Real; AOk: Array[0..MAXPH-1] Of Boolean; NOk: Array[0..MAXPH-1] Of Real;
    LastAdd: Integer; HaveOk: Boolean;

 Procedure SaveOk;
 Var I: Integer;
 Begin
  XOk := Xs;
  For I := 0 To NEm - 1 Do VOk[I] := Vv[I];
  For I := 0 To NPh - 1 Do Begin AOk[I] := ActP[I]; NOk[I] := NpP[I]; End;
  HaveOk := True;
 End;

 Procedure RestoreOk;
 Var I: Integer;
 Begin
  Xs := XOk;
  For I := 0 To NEm - 1 Do Vv[I] := VOk[I];
  For I := 0 To NPh - 1 Do Begin ActP[I] := AOk[I]; NpP[I] := NOk[I]; End;
 End;

 Procedure InitPhase(Pp: Integer);
 Var Ee: Integer;
 Begin
  EvalSI(Xs); EvalPhases;
  ActP[Pp] := True;
  For Ee := PhFirst[Pp] To PhFirst[Pp] + PhCount[Pp] - 1 Do
   Vv[Ee] := Ln(1E-7) + SIe[Ee] - PhS[Pp];
 End;

Begin
 PolishAll := False;
 ComputeScales;
 For P := 0 To NPh - 1 Do Begin
  ActP[P] := NpP[P] > 5 * Mu * PhOm[P];
  DropCnt[P] := 0;
 End;
 For E := 0 To NEm - 1 Do Vv[E] := Ln(RMax(NEmol[E], 1E-30));
 LastAdd := -1; HaveOk := False; Swaps := 0;
 For Loop := 1 To 60 Do Begin
  BuildAct;
  If NM - 1 + NAct > MAXUN Then Exit;
  R := PolishNewton;
  If R <> 0 Then Begin
   If (LastAdd >= 0) And HaveOk Then Begin
    RestoreOk;
    Who := RatioLeave(LastAdd);
    If (Who >= 0) And (Swaps < 30) Then Begin
     Inc(Swaps);
     ActP[Who] := False;
     InitPhase(LastAdd);
     LastAdd := -1;
     Continue;
    End;
    ActP[LastAdd] := False; Inc(DropCnt[LastAdd]);
    LastAdd := -1;
    Continue;
   End;
   Who := -1; Mn := 1E30;
   For P := 0 To NPh - 1 Do
    If ActP[P] Then Begin
     If NpP[P] < Mn Then Begin Mn := NpP[P]; Who := P; End;
    End;
   If Who < 0 Then Exit;
   ActP[Who] := False; Inc(DropCnt[Who]);
   Continue;
  End;
  SaveOk;
  LastAdd := -1;
  Changed := False;
  Who := -1; Mn := 1E30;
  For P := 0 To NPh - 1 Do
   If ActP[P] And (NpP[P] < 1E-8) Then
    If NpP[P] < Mn Then Begin Mn := NpP[P]; Who := P; End;
  If Who >= 0 Then Begin
   ActP[Who] := False; DropCnt[Who] := 99; Changed := True;
  End;
  If Not Changed Then Begin
   EvalSI(Xs); EvalPhases;
   Who := -1; Mx := 1E-9;
   Viol := False;
   For P := 0 To NPh - 1 Do
    If Not ActP[P] And (PhS[P] > 1E-9) And (DropCnt[P] < 99) Then Begin
     Viol := True;
     Lk := DropCnt[P];
     If PhS[P] > Mx * Pw(1000, Lk) Then Begin Mx := PhS[P] / Pw(1000, Lk); Who := P; End;
    End;
   If Who >= 0 Then Begin
    InitPhase(Who);
    LastAdd := Who; Changed := True;
   End
   Else If Viol Then Begin PolishAll := False; Exit; End;
  End;
  If Not Changed Then Begin PolishAll := True; Exit; End;
 End;
End;

{ poids de barriere : quantite disponible du composant le plus rare de la phase }
Procedure SetBarrierWeights;
Var P, E, C: Integer; Om, V: Real;
Begin
 For P := 0 To NPh - 1 Do Begin
  Om := 1;
  For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do
   For C := 2 To NM - 1 Do
    If EmNu[E, C] > 0 Then Begin
     V := Tt[C] / EmNu[E, C];
     If V < Om Then Om := V;
    End;
  If Om < 1E-9 Then Om := 1E-9;
  PhOm[P] := Om;
 End;
End;

{ equilibre a W, gamma et a(H2O) fixes ; Cold = True : point de depart froid }
Function InnerSolve(Cold: Boolean): Boolean;
Var K, It, MaxIt: Integer; Mu, Conv, Tol: Real; Stalled, Last: Boolean;
Begin
 If Cold Then ColdStart Else MakeFeasible;
 EvalSI(Xs); EvalPhases;
 For K := 0 To NPh - 1 Do If PhS[K] >= 0 Then Begin ColdStart; Break; End;
 Mu := MuStart;
 Repeat
  Last := Mu < 4E-6;
  If Last Then Tol := 1E-6 Else Tol := 1E-3;
  If Last Then MaxIt := 100 Else MaxIt := 150;
  For It := 1 To MaxIt Do Begin
   Conv := BarrierNewton(Mu, Stalled);
   Inc(EqIter);
   If Conv < Tol Then Break;
   If Stalled Then Break;
  End;
  If Not Last Then Mu := Mu / 10;
 Until Last;
 { amplitudes finales de la barriere }
 Conv := BarrierNewton(Mu, Stalled);
 InnerSolve := True;
 If PolishAll(Mu) Then Begin
  EvalSpec(Xs); AqueousTotals;
 End
 Else Begin
  { repli : resultat de la barriere }
  EqStatus := 'approche';
  EvalSpec(Xs);
  EvalSI(Xs); EvalPhases;
  For K := 0 To NPh - 1 Do Begin
   NpP[K] := Mu * PhOm[K] / RMax(-PhS[K], 1E-30);
  End;
  AqueousTotals;
 End;
End;

{ poids des especes : eau libre pour les especes dissoutes, C-S-H pour les sites fixes }
Procedure UpdateWeights;
Var I: Integer; F: Real;
Begin
 For I := 0 To NSpReal - 1 Do SpWt[I] := WKg;
 F := SExp(-3.0 * (CsCa - 1.0));
 SpWt[NSpReal] := AdsK * MCsh * F;
 SpWt[NSpReal + 1] := AdsNa * MCsh * F;
End;

{ masse de C-S-H (kg pour 100 g de liant) a partir des amplitudes courantes }
Function CshKg: Real;
Var E: Integer; M: Real;
Begin
 M := 0;
 For E := PhFirst[PH_CSH] To PhFirst[PH_CSH] + PhCount[PH_CSH] - 1 Do M := M + NEmol[E] * EmMW[E];
 CshKg := M / 1000.0;
End;

{ rapport Ca/Si du C-S-H a partir des amplitudes courantes }
Function CshCaSi: Real;
Var E: Integer; Ca, Si: Real;
Begin
 Ca := 0; Si := 0;
 For E := PhFirst[PH_CSH] To PhFirst[PH_CSH] + PhCount[PH_CSH] - 1 Do Begin
  Ca := Ca + NEmol[E] * EmNu[E, C_CA];
  Si := Si + NEmol[E] * EmNu[E, C_SI];
 End;
 If Si > 1E-9 Then CshCaSi := Ca / Si Else CshCaSi := CsCa;
End;

{ equilibre complet (iteration externe : gamma, a(H2O), masse d'eau libre) }
Function Equilibrate(Const T: TVec; TC: Real; Warm: Boolean): Boolean;
Var Out, E, I, C: Integer; WNew, SmM, SumNuW, Cur, ISave, Dw, Di, Lnaw, Rl: Real; Cold, Conv: Boolean;
    Tol: Real;
Begin
 SetTemperature(TC);
 Tt := T;
 { traces pour les composants absents (oxydes neutres) }
 If Tt[C_CA] < 1E-8 Then Begin Tt[C_CA] := Tt[C_CA] + 1E-8; Tt[C_W] := Tt[C_W] + 1E-8; Tt[C_H] := Tt[C_H] - 2E-8; End;
 If Tt[C_SI] < 1E-8 Then Begin Tt[C_SI] := Tt[C_SI] + 1E-8; Tt[C_W] := Tt[C_W] - 2E-8; End;
 If Tt[C_AL] < 1E-8 Then Begin Tt[C_AL] := Tt[C_AL] + 1E-8; Tt[C_W] := Tt[C_W] - 2.5E-8; Tt[C_H] := Tt[C_H] + 1E-8; End;
 If Tt[C_FE] < 1E-8 Then Begin Tt[C_FE] := Tt[C_FE] + 1E-8; Tt[C_W] := Tt[C_W] - 2.5E-8; Tt[C_H] := Tt[C_H] + 1E-8; End;
 If Tt[C_S] < 1E-8 Then Begin Tt[C_S] := Tt[C_S] + 1E-8; Tt[C_W] := Tt[C_W] - 1E-8; Tt[C_H] := Tt[C_H] + 2E-8; End;
 If Tt[C_K] < 1E-8 Then Begin Tt[C_K] := Tt[C_K] + 1E-8; Tt[C_W] := Tt[C_W] + 0.5E-8; Tt[C_H] := Tt[C_H] - 1E-8; End;
 If Tt[C_NA] < 1E-8 Then Begin Tt[C_NA] := Tt[C_NA] + 1E-8; Tt[C_W] := Tt[C_W] + 0.5E-8; Tt[C_H] := Tt[C_H] - 1E-8; End;
 If Tt[C_MG] < 1E-8 Then Begin Tt[C_MG] := Tt[C_MG] + 1E-8; Tt[C_W] := Tt[C_W] + 1E-8; Tt[C_H] := Tt[C_H] - 2E-8; End;
 If Tt[C_C] < 1E-8 Then Begin Tt[C_C] := Tt[C_C] + 1E-8; Tt[C_W] := Tt[C_W] - 1E-8; Tt[C_H] := Tt[C_H] + 2E-8; End;
 If Tt[C_CL] < 1E-8 Then Begin Tt[C_CL] := Tt[C_CL] + 1E-8; Tt[C_H] := Tt[C_H] + 1E-8; End;
 SetBarrierWeights;
 EqStatus := 'ok'; EqIter := 0; EqDry := False;
 Cold := Not (Warm And HaveWarm);
 WKg := Tt[C_W] / N_WATER;
 If WKg < 1E-5 Then WKg := 1E-5;
 If Cold Then Begin IonS := 0.3; MCsh := 0; CsCa := 1.6; End;
 Lnaw := 0;
 Tol := 1E-7;
 Conv := False;
 For Out := 1 To 30 Do Begin
  UpdateGamma;
  UpdateWeights;
  Xs[C_W] := Lnaw;
  XsCold[C_W] := Lnaw;
  InnerSolve(Cold And (Out = 1));
  { nouvelle force ionique, a(H2O), eau libre }
  ISave := IonS;
  IonS := 0; SmM := 0;
  For I := 0 To NSpReal - 1 Do Begin
   IonS := IonS + 0.5 * Sqr(SpZ[I]) * Mol[I];
   SmM := SmM + Mol[I];
  End;
  SumNuW := 0;
  For I := 0 To NSpReal - 1 Do
   For C := 0 To SpN[I] - 1 Do
    If SpIdx[I, C] = C_W Then SumNuW := SumNuW + SpNu[I, C] * Mol[I];
  Cur := Tt[C_W];
  For E := 0 To NEm - 1 Do Cur := Cur - EmNu[E, C_W] * NEmol[E];
  WNew := Cur / (N_WATER + SumNuW);
  If WNew < 1E-6 Then Begin WNew := 1E-6; EqDry := True; End
  Else EqDry := False;
  Dw := Abs(WNew - WKg) / WKg;
  Di := Abs(IonS - ISave) + Abs(CshKg - MCsh) / (CshKg + 1E-4) + Abs(CshCaSi - CsCa) * 1E-2;
  Lnaw := -MW_WATER / 1000.0 * SmM;
  If (Dw < Tol) And (Di < 1E-6 + 1E-6 * IonS) And (Out > 1) Then Begin
   Conv := True;
   Break;
  End;
  Rl := 1.0;
  If Out > 5 Then Rl := 0.7;
  If Out > 12 Then Rl := 0.4;
  WKg := WKg + Rl * (WNew - WKg);
  MCsh := MCsh + Rl * (CshKg - MCsh);
  CsCa := CsCa + Rl * (CshCaSi - CsCa);
  IonS := ISave + Rl * (IonS - ISave);
 End;
 If Not Conv Then Begin
  { dernier equilibre avec les parametres retenus }
  UpdateGamma;
  UpdateWeights;
  Xs[C_W] := Lnaw;
  XsCold[C_W] := Lnaw;
  InnerSolve(False);
  If EqStatus = 'ok' Then EqStatus := 'approche';
 End;
 UpdateGamma;
 Xs[C_W] := Lnaw;
 HaveWarm := True;
 Equilibrate := True;
End;

{ --------------------------------------------------------------------- }
{ Recette : ciment, ajouts cimentaires, eau                             }
{ --------------------------------------------------------------------- }

Procedure ShowProgress(Const Msg: String; Pct: Integer); Forward;

Const
 NCP    = 14;           { phases du ciment }
 NSC    = 5;            { ajouts cimentaires }
 NOX    = 9;            { oxydes : CaO SiO2 Al2O3 Fe2O3 MgO SO3 K2O Na2O CO2 }
 NPK    = 4;            { phases cinetiques : C3S C2S C3A C4AF }
 MAXSTEP = 60;
 NITEM  = 96;           { colonnes de resultats }
 NKIN   = 330;

 { indices des phases du ciment }
 CP_C3S = 0; CP_C2S = 1; CP_C3A = 2; CP_C4AF = 3; CP_LIME = 4; CP_MGO = 5;
 CP_GYP = 6; CP_HEM = 7; CP_ANH = 8; CP_CAL = 9; CP_ARC = 10; CP_THE = 11;
 CP_K2O = 12; CP_NA2O = 13;

 { colonnes de resultats }
 RI_M   = 0;            { 20 phases (g / 100 g de liant) }
 RI_UM  = 20;           { 10 non reagis (g) : alite belite aluminate ferrite 5 ajouts autres }
 RI_V   = 30;           { 20 phases (cm3) }
 RI_UV  = 50;           { 10 non reagis (cm3) }
 RI_PH  = 60;
 RI_ION = 61;
 RI_WF  = 62;           { eau libre (g) }
 RI_EL  = 63;           { 10 elements dissous : Ca Si Al Fe S K Na Mg C Cl (mmol/kg) }
 RI_POR = 73;
 RI_VS  = 74;
 RI_VW  = 75;
 RI_VT  = 76;
 RI_COND = 77;
 RI_HEAT = 78;
 RI_AL  = 79;           { 4 + 5 degres de reaction }
 RI_CS  = 88;           { Ca/Si du C-S-H }
 RI_BW  = 89;           { eau liee (g) }

 PR_EQ = 0; PR_HYD = 1; PR_MIX = 2; PR_LEACH = 3; PR_CARB = 4; PR_SALT = 5;

 CPNames : Array[0..NCP-1] Of String[18] = (
  'Alite (C3S)', 'Belite (C2S)', 'Aluminate (C3A)', 'Ferrite (C4AF)',
  'Chaux libre', 'Periclase (MgO)', 'Gypse', 'Hemihydrate', 'Anhydrite',
  'Calcite', 'Arcanite K2SO4', 'Thenardite Na2SO4', 'K2O soluble', 'Na2O soluble');

 CPMass : Array[0..NCP-1] Of Real = (
  228.32, 172.24, 270.19, 485.96, 56.08, 40.30, 172.17, 145.15, 136.14,
  100.09, 174.26, 142.04, 94.20, 61.98);

 CPDens : Array[0..NCP-1] Of Real = (
  3.15, 3.28, 3.03, 3.73, 3.34, 3.58, 2.32, 2.74, 2.96, 2.71, 2.66, 2.66, 2.7, 2.7);

 CPHeat : Array[0..5] Of Real = (517, 262, 1672, 418, 1166, 842);

 { oxydes par mole de phase : CaO SiO2 Al2O3 Fe2O3 MgO SO3 K2O Na2O CO2 H2O }
 CPOx : Array[0..NCP-1, 0..9] Of Real = (
  (3, 1, 0, 0, 0, 0, 0, 0, 0, 0),
  (2, 1, 0, 0, 0, 0, 0, 0, 0, 0),
  (3, 0, 1, 0, 0, 0, 0, 0, 0, 0),
  (4, 0, 1, 1, 0, 0, 0, 0, 0, 0),
  (1, 0, 0, 0, 0, 0, 0, 0, 0, 0),
  (0, 0, 0, 0, 1, 0, 0, 0, 0, 0),
  (1, 0, 0, 0, 0, 1, 0, 0, 0, 2),
  (1, 0, 0, 0, 0, 1, 0, 0, 0, 0.5),
  (1, 0, 0, 0, 0, 1, 0, 0, 0, 0),
  (1, 0, 0, 0, 0, 0, 0, 0, 1, 0),
  (0, 0, 0, 0, 0, 1, 1, 0, 0, 0),
  (0, 0, 0, 0, 0, 1, 0, 1, 0, 0),
  (0, 0, 0, 0, 0, 0, 1, 0, 0, 0),
  (0, 0, 0, 0, 0, 0, 0, 1, 0, 0));

 OXMass : Array[0..NOX-1] Of Real = (
  56.077, 60.084, 101.961, 159.69, 40.304, 80.06, 94.196, 61.979, 44.01);

 OXNames : Array[0..NOX-1] Of String[6] = (
  'CaO', 'SiO2', 'Al2O3', 'Fe2O3', 'MgO', 'SO3', 'K2O', 'Na2O', 'CO2');

 SCNames : Array[0..NSC-1] Of String[18] = (
  'Cendres volantes', 'Laitier', 'Fumee de silice', 'Calcaire', 'Argile calcinee');

 PKNames : Array[0..NPK-1] Of String[16] = (
  'Alite C3S', 'Belite C2S', 'Aluminate C3A', 'Ferrite C4AF');

Type
 TAlph = Array[0..10] Of Real;
 TCement = Record
  Name : String[30];
  P    : Array[0..NCP-1] Of Real;      { % massiques du ciment }
 End;

 TScm = Record
  Name : String[30];
  Ox   : Array[0..NOX-1] Of Real;      { % massiques }
  Rho, AMax, Tau, Nexp, Ea : Real;
 End;

 TRow = Array[0..NITEM-1] Of Real;
 TResArr = Array[0..MAXSTEP-1] Of TRow;
 PResArr = ^TResArr;
 TSpcRow = Array[0..MAXSP-1] Of Real;
 TSpcArr = Array[0..MAXSTEP-1] Of TSpcRow;
 PSpcArr = ^TSpcArr;
 TKinT = Array[0..NKIN-1] Of Real;
 TKinA = Array[0..NKIN-1, 0..NPK-1] Of Real;
 PKinT = ^TKinT;
 PKinA = ^TKinA;

Var
 Cem     : TCement;
 Scm     : Array[0..NSC-1] Of TScm;
 SFrac   : Array[0..NSC-1] Of Real;      { % du liant }
 WB      : Real;                         { eau / liant }
 TempC   : Real;
 AgeD    : Real;                         { age (jours) }
 PK      : Array[0..NPK-1, 0..6] Of Real; { K1 N1 K2 K3 N3 H Ea(J/mol) }
 MgTau   : Real;
 { dialogue de processus }
 HydN    : Integer;
 HydT0, HydT1 : Real;
 MixVar  : Integer;
 MixV0, MixV1 : Real;
 MixN    : Integer;
 ExtVol  : Real;                         { g de solution externe par pas }
 ExtN    : Integer;
 ExtSalt : Array[0..6] Of Real;          { mmol/L : NaCl Na2SO4 MgSO4 MgCl2 CaCl2 Na2CO3 NaOH }
 CarbMax : Real;                         { g de CO2 pour 100 g de liant }
 CarbN   : Integer;

 { cinetique }
 KinT    : PKinT;
 KinA    : PKinA;
 KinN    : Integer;
 KinValid: Boolean;

 { resultats }
 Res     : PResArr;
 Spc     : PSpcArr;
 ResX    : Array[0..MAXSTEP-1] Of Real;
 ResStat : Array[0..MAXSTEP-1] Of Byte;     { 0 ok, 1 approche, 2 eau epuisee }
 NRes    : Integer;
 ResKind : Integer;
 ResXLab : String[40];
 ResTitle: String[60];
 ResLogX : Boolean;
 CurStep : Integer;
 UserAbort : Boolean;
 { etat des solides (processus de renouvellement) }
 UnrM    : Array[0..9] Of Real;
 UnrV    : Array[0..9] Of Real;
 AlphaCur: Array[0..8] Of Real;
 HeatCur : Real;
 Water0  : Real;
 AlphaScale : Real;                 { reduction des reactions si l'eau manque }

Procedure DefaultCement(K: Integer);
Const
 CD : Array[0..4, 0..13] Of Real = (
  (58, 14, 7.5, 9, 0.5, 1.5, 2.5, 1.2, 1.0, 3.0, 0.5, 0.05, 0.1, 0.05),
  (64, 10, 9, 8, 0.8, 1.2, 1.5, 1.0, 1.5, 0.5, 0.4, 0.05, 0.1, 0.05),
  (58, 18, 1.5, 14, 0.3, 1.4, 2.5, 0.5, 0.5, 0.8, 0.3, 0.05, 0.1, 0.05),
  (63, 20, 9, 0.7, 0.5, 0.5, 2.0, 1.0, 0.5, 1.0, 0.25, 0.05, 0.05, 0.05),
  (54, 17, 8, 9, 0.6, 1.8, 2.0, 1.0, 1.0, 1.5, 1.0, 0.2, 0.3, 0.1));
 CN : Array[0..4] Of String[30] = (
  'CEM I 42.5 N (type)', 'CEM I 52.5 R', 'CEM I 42.5 HS (C3A bas)',
  'Ciment blanc', 'CEM I 42.5 R alcalin');
Var I: Integer;
Begin
 If (K < 0) Or (K > 4) Then K := 0;
 Cem.Name := CN[K];
 For I := 0 To NCP - 1 Do Cem.P[I] := CD[K, I];
End;

Procedure DefaultScm(K, V: Integer);
Const
 SD : Array[0..5, 0..13] Of Real = (
  (5, 52, 25, 8, 1.5, 0.7, 1.9, 0.5, 0, 2.35, 0.45, 90, 0.5, 40),
  (41, 35, 12, 0.5, 8, 0.2, 0.5, 0.3, 0, 2.9, 0.8, 40, 0.7, 45),
  (0.4, 94, 0.5, 0.5, 0.6, 0, 1.0, 0.3, 0, 2.2, 1.0, 10, 0.6, 30),
  (53.8, 0, 0, 0, 0, 0, 0, 0, 42.2, 2.71, 1.0, 1, 1, 0),
  (0.5, 54, 40, 1, 0.2, 0, 0.5, 0.1, 0, 2.5, 0.9, 10, 0.7, 40),
  (25, 37, 18, 6, 5, 2.5, 0.5, 1.5, 0, 2.6, 0.7, 60, 0.5, 40));
 SN : Array[0..5] Of String[30] = (
  'Cendre volante (classe F)', 'Laitier granule', 'Fumee de silice',
  'Calcaire', 'Argile calcinee (MK)', 'Cendre volante (classe C)');
Var I, J: Integer;
Begin
 J := K;
 If V = 1 Then J := 5;
 Scm[K].Name := SN[J];
 For I := 0 To NOX - 1 Do Scm[K].Ox[I] := SD[J, I];
 Scm[K].Rho := SD[J, 9]; Scm[K].AMax := SD[J, 10]; Scm[K].Tau := SD[J, 11];
 Scm[K].Nexp := SD[J, 12]; Scm[K].Ea := SD[J, 13];
End;

Procedure DefaultAll;
Var I, J: Integer;
 Const PKD : Array[0..3, 0..6] Of Real = (
  (1.5, 0.7, 0.05, 1.1, 3.3, 1.8, 41570),
  (0.95, 0.5, 0.26, 0.5, 5.0, 1.35, 20670),
  (0.082, 0.87, 0.0, 0.04, 5.0, 1.6, 54000),
  (0.165, 3.7, 0.0, 0.12, 5.0, 1.85, 34000));
Begin
 DefaultCement(0);
 DefaultScm(0, 0); DefaultScm(1, 0); DefaultScm(2, 0); DefaultScm(3, 0); DefaultScm(4, 0);
 For I := 0 To NSC - 1 Do SFrac[I] := 0;
 WB := 0.40; TempC := 20; AgeD := 28;
 For I := 0 To NPK - 1 Do For J := 0 To 6 Do PK[I, J] := PKD[I, J];
 MgTau := 365;
 AdsK := 0.4; AdsNa := 0.4; MCsh := 0; CsCa := 1.6;
 HydN := 24; HydT0 := 0.05; HydT1 := 365;
 MixVar := 0; MixV0 := 0.25; MixV1 := 0.7; MixN := 12;
 ExtVol := 500; ExtN := 45;
 For I := 0 To 6 Do ExtSalt[I] := 0;
 CarbMax := 35; CarbN := 24;
 KinValid := False;
 AlphaScale := 1.0;
 NRes := 0; CurStep := 0;
End;

{ ajoute N moles d'oxyde Ox (0..8, 9 = H2O) au vecteur de composants }
Procedure AddOx(Var T: TVec; Ox: Integer; N: Real);
Begin
 Case Ox Of
  0: Begin T[C_CA] := T[C_CA] + N; T[C_W] := T[C_W] + N; T[C_H] := T[C_H] - 2 * N; End;
  1: Begin T[C_SI] := T[C_SI] + N; T[C_W] := T[C_W] - 2 * N; End;
  2: Begin T[C_AL] := T[C_AL] + 2 * N; T[C_W] := T[C_W] - 5 * N; T[C_H] := T[C_H] + 2 * N; End;
  3: Begin T[C_FE] := T[C_FE] + 2 * N; T[C_W] := T[C_W] - 5 * N; T[C_H] := T[C_H] + 2 * N; End;
  4: Begin T[C_MG] := T[C_MG] + N; T[C_W] := T[C_W] + N; T[C_H] := T[C_H] - 2 * N; End;
  5: Begin T[C_S] := T[C_S] + N; T[C_W] := T[C_W] - N; T[C_H] := T[C_H] + 2 * N; End;
  6: Begin T[C_K] := T[C_K] + 2 * N; T[C_W] := T[C_W] + N; T[C_H] := T[C_H] - 2 * N; End;
  7: Begin T[C_NA] := T[C_NA] + 2 * N; T[C_W] := T[C_W] + N; T[C_H] := T[C_H] - 2 * N; End;
  8: Begin T[C_C] := T[C_C] + N; T[C_W] := T[C_W] - N; T[C_H] := T[C_H] + 2 * N; End;
 Else T[C_W] := T[C_W] + N;
 End;
End;

Function CementFrac: Real;
Var I: Integer; S: Real;
Begin
 S := 0;
 For I := 0 To NSC - 1 Do S := S + SFrac[I];
 CementFrac := 100.0 - S;
End;

{ --------------------------------------------------------------------- }
{ Cinetique d'hydratation (Parrot-Killoh)                                }
{ --------------------------------------------------------------------- }

Function KTemp(Ea, TC: Real): Real;
Begin
 KTemp := SExp(-Ea / R_GAS * (1.0 / (TC + 273.15) - 1.0 / 293.15));
End;

Function PKRate(K: Integer; A, WC: Real): Real;
Var Om, L, R1, R2, R3, R, F, B: Real;
Begin
 Om := 1.0 - A;
 If Om < 1E-9 Then Begin PKRate := 0; Exit; End;
 If A < 1E-9 Then A := 1E-9;
 L := -Ln(Om);
 If L < 1E-9 Then L := 1E-9;
 R1 := PK[K, 0] / PK[K, 1] * Om * Pw(L, 1.0 - PK[K, 1]);
 R := R1;
 If PK[K, 2] > 0 Then Begin
  R2 := PK[K, 2] * Pw(Om, 2.0 / 3.0) / (1.0 - Pw(Om, 1.0 / 3.0));
  If R2 < R Then R := R2;
 End;
 R3 := PK[K, 3] * Pw(Om, PK[K, 4]);
 If R3 < R Then R := R3;
 If A > PK[K, 5] * WC Then Begin
  B := 1.0 + 3.333 * (PK[K, 5] * WC - A);
  If B <= 0 Then F := 0 Else F := Sqr(Sqr(B));
  R := R * F;
 End;
 PKRate := R;
End;

Procedure FreeKin;
Begin
 If KinT <> Nil Then FreeMem(KinT, SizeOf(TKinT));
 If KinA <> Nil Then FreeMem(KinA, SizeOf(TKinA));
 KinT := Nil; KinA := Nil;
End;

{ integre les degres de reaction des 4 phases du clinker jusqu'a 1E4 jours }
Procedure BuildKin(WBv, TC: Real);
Var
 K, J: Integer; T, Dt, TNext, WC, F: Real; A: Array[0..NPK-1] Of Real;
 KT: Array[0..NPK-1] Of Real; Step: Real;
Begin
 If KinT = Nil Then GetMem(KinT, SizeOf(TKinT));
 If KinA = Nil Then GetMem(KinA, SizeOf(TKinA));
 F := CementFrac / 100.0;
 If F < 0.01 Then F := 0.01;
 WC := WBv / F;
 For K := 0 To NPK - 1 Do Begin
  A[K] := 1E-6;
  KT[K] := KTemp(PK[K, 6], TC);
 End;
 T := 1E-3; J := 0;
 Step := Exp(Ln(10.0) / 40.0);
 TNext := T;
 KinN := 0;
 While (J < NKIN) And (T < 1.0E4) Do Begin
  KinT^[J] := T;
  For K := 0 To NPK - 1 Do KinA^[J, K] := A[K];
  Inc(J);
  TNext := T * Step;
  While T < TNext Do Begin
   Dt := 0.01 * T + 1E-5;
   If T + Dt > TNext Then Dt := TNext - T;
   For K := 0 To NPK - 1 Do Begin
    A[K] := A[K] + Dt * KT[K] * PKRate(K, A[K], WC);
    If A[K] > 0.999999 Then A[K] := 0.999999;
   End;
   T := T + Dt;
  End;
 End;
 KinN := J;
 KinValid := True;
End;

{ degres de reaction a l'age TD (jours) : 0..3 PK, 4 chaux, 5 MgO, puis 5 ajouts }
Procedure AlphaAt(TD: Real; Var Al: TAlph);
Var K, J: Integer; F, U: Real;
Begin
 If Not KinValid Then BuildKin(WB, TempC);
 If TD <= KinT^[0] Then Begin
  For K := 0 To NPK - 1 Do Al[K] := 0;
 End
 Else If TD >= KinT^[KinN - 1] Then Begin
  For K := 0 To NPK - 1 Do Al[K] := KinA^[KinN - 1, K];
 End
 Else Begin
  J := Trunc(Ln(TD / 1E-3) / Ln(10.0) * 40.0);
  If J < 0 Then J := 0;
  If J > KinN - 2 Then J := KinN - 2;
  While (J < KinN - 2) And (KinT^[J + 1] < TD) Do Inc(J);
  While (J > 0) And (KinT^[J] > TD) Do Dec(J);
  F := (Ln(TD) - Ln(KinT^[J])) / (Ln(KinT^[J + 1]) - Ln(KinT^[J]));
  For K := 0 To NPK - 1 Do Al[K] := KinA^[J, K] + F * (KinA^[J + 1, K] - KinA^[J, K]);
 End;
 Al[4] := 1.0;
 Al[5] := 1.0 - Exp(-TD / MgTau);
 For K := 0 To NSC - 1 Do Begin
  If Scm[K].Tau <= 0 Then Al[6 + K] := 1
  Else Begin
   U := TD * KTemp(Scm[K].Ea * 1000.0, TempC) / Scm[K].Tau;
   Al[6 + K] := Scm[K].AMax * (1.0 - SExp(-Pw(U, Scm[K].Nexp)));
  End;
  If K = 3 Then Al[6 + K] := 1.0;
 End;
End;

{ --------------------------------------------------------------------- }
{ Totaux de composants pour une recette a l'age TD                        }
{ --------------------------------------------------------------------- }

Procedure BuildTotals(TD: Real; Var T: TVec);
Var
 I, J, K: Integer; MC, MS, Mr, N, Sx: Real; Al: TAlph;
Begin
 AlphaAt(TD, Al);
 For K := 0 To NPK - 1 Do Al[K] := Al[K] * AlphaScale;
 For K := 0 To NSC - 1 Do If K <> 3 Then Al[6 + K] := Al[6 + K] * AlphaScale;
 For I := 0 To NM - 1 Do T[I] := 0;
 For I := 0 To 9 Do Begin UnrM[I] := 0; UnrV[I] := 0; End;
 MC := CementFrac;
 HeatCur := 0;
 Sx := 0;
 For K := 0 To NCP - 1 Do Begin
  Mr := MC * Cem.P[K] / 100.0;
  Sx := Sx + Mr;
  If K < 6 Then Begin
   N := Al[K] * Mr / CPMass[K];
   HeatCur := HeatCur + Al[K] * Mr * CPHeat[K] / 100.0;
  End
  Else N := Mr / CPMass[K];
  For J := 0 To 9 Do If CPOx[K, J] <> 0 Then AddOx(T, J, N * CPOx[K, J]);
  If K < 4 Then Begin
   UnrM[K] := (1.0 - Al[K]) * MC * Cem.P[K] / 100.0;
   UnrV[K] := UnrM[K] / CPDens[K];
  End
  Else If K < 6 Then Begin
   UnrM[9] := UnrM[9] + (1.0 - Al[K]) * MC * Cem.P[K] / 100.0;
   UnrV[9] := UnrV[9] + (1.0 - Al[K]) * MC * Cem.P[K] / 100.0 / CPDens[K];
  End;
 End;
 UnrM[9] := UnrM[9] + (MC - Sx);
 UnrV[9] := UnrV[9] + (MC - Sx) / 2.7;
 For K := 0 To NSC - 1 Do Begin
  MS := SFrac[K];
  Mr := 0;
  For J := 0 To NOX - 1 Do Begin
   Mr := Mr + Scm[K].Ox[J] / 100.0 * MS;
   N := Al[6 + K] * Scm[K].Ox[J] / 100.0 * MS / OXMass[J];
   If N <> 0 Then AddOx(T, J, N);
  End;
  UnrM[4 + K] := MS - Al[6 + K] * Mr;
  If UnrM[4 + K] < 0 Then UnrM[4 + K] := 0;
  If Scm[K].Rho > 0 Then UnrV[4 + K] := UnrM[4 + K] / Scm[K].Rho;
 End;
 AddOx(T, 9, WB * 100.0 / MW_WATER);
 Water0 := WB * 100.0;
 For I := 0 To 3 Do AlphaCur[I] := Al[I];
 For K := 0 To NSC - 1 Do AlphaCur[4 + K] := Al[6 + K];
End;

{ --------------------------------------------------------------------- }
{ Resultats                                                              }
{ --------------------------------------------------------------------- }

Procedure AllocResults;
Begin
 If Res = Nil Then GetMem(Res, SizeOf(TResArr));
 If Spc = Nil Then GetMem(Spc, SizeOf(TSpcArr));
End;

Function PhaseMass(P: Integer): Real;
Var E: Integer; S: Real;
Begin
 S := 0;
 For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do S := S + NEmol[E] * EmMW[E];
 PhaseMass := S;
End;

Function PhaseVol(P: Integer): Real;
Var E: Integer; S: Real;
Begin
 S := 0;
 For E := PhFirst[P] To PhFirst[P] + PhCount[P] - 1 Do S := S + NEmol[E] * EmV[E];
 PhaseVol := S;
End;

Function Conductivity: Real;
Const
 Lam : Array[0..11] Of Real = (349.8, 119.0, 0, 0, 50, 0, 160, 73.5, 50.1, 106, 138.6, 76.3);
Var I: Integer; S, L: Real;
Begin
 S := 0;
 For I := 0 To NSpReal - 1 Do Begin
  L := 0;
  If (SpN[I] = 1) And (SpNu[I, 0] = 1) And (Lam[SpIdx[I, 0]] > 0) Then L := Lam[SpIdx[I, 0]]
  Else If SpName[I] = 'OH-' Then L := 198
  Else If SpName[I] = 'HCO3-' Then L := 44.5
  Else If SpName[I] = 'H3SiO4-' Then L := 35
  Else If SpName[I] = 'CaOH+' Then L := 60
  Else If SpName[I] = 'KSO4-' Then L := 70
  Else If SpName[I] = 'NaSO4-' Then L := 60;
  S := S + L * Mol[I];
 End;
 Conductivity := 0.1 * S / (1.0 + 0.45 * Sqrt(IonS));
End;

{ remplit la ligne St des resultats a partir de l'equilibre courant }
Procedure FillRow(St: Integer; X: Real);
Var
 P, E, I, K: Integer; V, Vs, CaN, SiN: Real; Row: ^TRow;
Begin
 AllocResults;
 Row := @Res^[St];
 FillChar(Row^, SizeOf(TRow), 0);
 Vs := 0;
 For P := 0 To NPHASES - 1 Do Begin
  Row^[RI_M + P] := PhaseMass(P);
  V := PhaseVol(P);
  Row^[RI_V + P] := V;
  Vs := Vs + V;
 End;
 For I := 0 To 9 Do Begin
  Row^[RI_UM + I] := UnrM[I];
  Row^[RI_UV + I] := UnrV[I];
  Vs := Vs + UnrV[I];
 End;
 Row^[RI_PH] := -Xs[C_H] / LN10;
 Row^[RI_ION] := IonS;
 Row^[RI_WF] := WKg * 1000.0;
 For K := 0 To 9 Do Row^[RI_EL + K] := AqT[C_CA + K] * 1000.0;
 Row^[RI_VS] := Vs;
 Row^[RI_VW] := WKg * 1000.0;
 Row^[RI_VT] := Vs + WKg * 1000.0;
 If Row^[RI_VT] > 0 Then Row^[RI_POR] := 100.0 * Row^[RI_VW] / Row^[RI_VT];
 Row^[RI_COND] := Conductivity;
 Row^[RI_HEAT] := HeatCur;
 For I := 0 To 3 Do Row^[RI_AL + I] := AlphaCur[I];
 For I := 0 To NSC - 1 Do Row^[RI_AL + 4 + I] := AlphaCur[4 + I];
 CaN := 0; SiN := 0;
 For E := PhFirst[PH_CSH] To PhFirst[PH_CSH] + PhCount[PH_CSH] - 1 Do Begin
  CaN := CaN + NEmol[E] * EmNu[E, C_CA];
  SiN := SiN + NEmol[E] * EmNu[E, C_SI];
 End;
 If SiN > 1E-9 Then Row^[RI_CS] := CaN / SiN;
 Row^[RI_BW] := RMax(0, Water0 - WKg * 1000.0);
 For I := 0 To NSpReal - 1 Do Spc^[St][I] := Mol[I] * 1000.0;
 For I := NSpReal To NSp - 1 Do Spc^[St][I] := SpWt[I] * Mol[I] * 1000.0;
 ResX[St] := X;
 If EqDry Then ResStat[St] := 2
 Else If EqStatus <> 'ok' Then ResStat[St] := 1
 Else ResStat[St] := 0;
End;

{ --------------------------------------------------------------------- }
{ Processus                                                              }
{ --------------------------------------------------------------------- }

Procedure SolidsOf(Var S: TVec);
Var C, E: Integer;
Begin
 For C := 0 To NM - 1 Do Begin
  S[C] := 0;
  For E := 0 To NEm - 1 Do S[C] := S[C] + EmNu[E, C] * NEmol[E];
 End;
End;

Procedure ResetResults(Kind: Integer; Const Title, XLab: String; LogX: Boolean);
Begin
 AllocResults;
 NRes := 0; CurStep := 0; ResKind := Kind; ResTitle := Title; ResXLab := XLab;
 ResLogX := LogX;
 UserAbort := False;
End;

Procedure EquilibriumAt(TD: Real; St: Integer; X: Real; Warm: Boolean);
Var T: TVec; It: Integer; Lim: Boolean;
Begin
 AlphaScale := 1.0; Lim := False;
 For It := 1 To 40 Do Begin
  BuildTotals(TD, T);
  Equilibrate(T, TempC, Warm);
  If (Not EqDry) And (WKg * 1000.0 >= 1.0) Then Break;
  AlphaScale := AlphaScale * 0.9;
  Lim := True;
 End;
 FillRow(St, X);
 If Lim Then ResStat[St] := 3;
 AlphaScale := 1.0;
End;

Procedure RunEquilibrium;
Begin
 ResetResults(PR_EQ, 'Equilibre a ' + RTrim(AgeD, 1) + ' jours', 'Age (j)', False);
 KinValid := False;
 HaveWarm := False;
 EquilibriumAt(AgeD, 0, AgeD, False);
 NRes := 1;
End;

Procedure RunHydration;
Var I: Integer; T: Real;
Begin
 ResetResults(PR_HYD, 'Hydratation : ' + Cem.Name, 'Age (jours)', True);
 If HydN > MAXSTEP Then HydN := MAXSTEP;
 If HydN < 2 Then HydN := 2;
 KinValid := False;
 HaveWarm := False;
 For I := 0 To HydN - 1 Do Begin
  T := HydT0 * Exp(Ln(HydT1 / HydT0) * I / (HydN - 1));
  ShowProgress('Hydratation t = ' + RTrim(T, 2) + ' j', (I * 100) Div HydN);
  If UserAbort Then Break;
  EquilibriumAt(T, I, T, True);
  NRes := I + 1;
 End;
 ShowProgress('Hydratation terminee', 100);
End;

{ balayage de recette : 0 E/L, 1..5 fraction de l'ajout (%) }
Procedure RunMix;
Var I: Integer; V: Real; SaveWB: Real; SaveF: Array[0..NSC-1] Of Real; K: Integer;
 Lab: String;
Begin
 SaveWB := WB;
 For K := 0 To NSC - 1 Do SaveF[K] := SFrac[K];
 If MixVar = 0 Then Lab := 'Eau / liant' Else Lab := SCNames[MixVar - 1] + ' (%)';
 ResetResults(PR_MIX, 'Melange : balayage ' + Lab, Lab, False);
 If MixN > MAXSTEP Then MixN := MAXSTEP;
 If MixN < 2 Then MixN := 2;
 HaveWarm := False;
 For I := 0 To MixN - 1 Do Begin
  V := MixV0 + (MixV1 - MixV0) * I / (MixN - 1);
  ShowProgress('Melange ' + Lab + ' = ' + RTrim(V, 3), (I * 100) Div MixN);
  If UserAbort Then Break;
  If MixVar = 0 Then WB := V Else SFrac[MixVar - 1] := V;
  KinValid := False;
  EquilibriumAt(AgeD, I, V, True);
  NRes := I + 1;
 End;
 WB := SaveWB;
 For K := 0 To NSC - 1 Do SFrac[K] := SaveF[K];
 KinValid := False;
 ShowProgress('Balayage termine', 100);
End;

{ solution externe : ajoute DM grammes d'eau et les sels a T }
Procedure AddExternal(Var T: TVec; DM: Real);
Var L: Real;
Begin
 L := DM / 1000.0;      { litres (= kg) }
 T[C_W] := T[C_W] + DM / MW_WATER;
 T[C_NA] := T[C_NA] + L * (ExtSalt[0] + 2 * ExtSalt[1] + 2 * ExtSalt[5] + ExtSalt[6]) / 1000.0;
 T[C_CL] := T[C_CL] + L * (ExtSalt[0] + 2 * ExtSalt[3] + 2 * ExtSalt[4]) / 1000.0;
 T[C_S] := T[C_S] + L * (ExtSalt[1] + ExtSalt[2]) / 1000.0;
 T[C_MG] := T[C_MG] + L * (ExtSalt[2] + ExtSalt[3]) / 1000.0;
 T[C_CA] := T[C_CA] + L * ExtSalt[4] / 1000.0;
 T[C_C] := T[C_C] + L * ExtSalt[5] / 1000.0;
 { NaOH : Na+ + OH- = Na+ + H2O - H+ }
 T[C_W] := T[C_W] + L * ExtSalt[6] / 1000.0;
 T[C_H] := T[C_H] - L * ExtSalt[6] / 1000.0;
End;

{ renouvellement de la solution interstitielle (lixiviation, sels) }
Procedure RunRenewal(Kind: Integer);
Var I: Integer; T, S: TVec; Cum: Real; Lab: String;
Begin
 If Kind = PR_LEACH Then Lab := 'Lixiviation' Else Lab := 'Penetration de sels';
 ResetResults(Kind, Lab + ' : ' + Cem.Name, 'Solution ajoutee (g/100 g liant)', False);
 If ExtN > MAXSTEP - 1 Then ExtN := MAXSTEP - 1;
 KinValid := False;
 HaveWarm := False;
 EquilibriumAt(AgeD, 0, 0, False);
 NRes := 1;
 Cum := 0;
 For I := 1 To ExtN Do Begin
  ShowProgress(Lab + ' pas ' + IStr(I), (I * 100) Div ExtN);
  If UserAbort Then Break;
  SolidsOf(S);
  T := S;
  AddExternal(T, ExtVol);
  Cum := Cum + ExtVol;
  Equilibrate(T, TempC, True);
  FillRow(I, Cum);
  NRes := I + 1;
 End;
 ShowProgress(Lab + ' terminee', 100);
End;

Procedure RunCarbonation;
Var I: Integer; T, T0: TVec; Cum, D: Real;
Begin
 ResetResults(PR_CARB, 'Carbonatation : ' + Cem.Name, 'CO2 ajoute (g/100 g liant)', False);
 If CarbN > MAXSTEP - 1 Then CarbN := MAXSTEP - 1;
 KinValid := False;
 HaveWarm := False;
 BuildTotals(AgeD, T0);
 Equilibrate(T0, TempC, False);
 FillRow(0, 0);
 NRes := 1;
 D := CarbMax / CarbN / 44.01;
 For I := 1 To CarbN Do Begin
  ShowProgress('Carbonatation pas ' + IStr(I), (I * 100) Div CarbN);
  If UserAbort Then Break;
  T := T0;
  AddOx(T, 8, D * I);
  Cum := D * I * 44.01;
  Equilibrate(T, TempC, True);
  FillRow(I, Cum);
  NRes := I + 1;
 End;
 ShowProgress('Carbonatation terminee', 100);
End;

{ --------------------------------------------------------------------- }
{ Interface : types et variables globales                                }
{ --------------------------------------------------------------------- }

Const
 MAX_ROWS = 26;

Type
 TMenuItem = Record
  Caption   : String[34];
  Shortcut  : String[12];
  Enabled   : Boolean;
  Checked   : Boolean;
  Separator : Boolean;
 End;

 TMenu = Record
  Title     : String[16];
  Items     : Array[0..MAX_MENU_ITEMS-1] Of TMenuItem;
  ItemCount : Byte;
  X, Y, Width : Integer;
 End;

Var
 StatusMsg  : String;
 NeedRedraw : Boolean;
 ProjName   : String;
 Modified   : Boolean;
 BatchMode  : Boolean;
 Running    : Boolean;
 ProgPct    : Integer;
 LastShowT  : LongInt;

{ --------------------------------------------------------------------- }
{ Gestion de la souris                                                  }
{ --------------------------------------------------------------------- }

Var
 MouseX, MouseY, MouseButtons : Integer;
 OldMouseX, OldMouseY, OldMouseButtons : Integer;
 MouseAvailable : Boolean;

{$IFNDEF FPC}
Procedure InitMouseDriver;
Var Regs: Registers;
Begin
 Regs.AX := $0000;
 Intr($33, Regs);
 MouseAvailable := Regs.AX = $FFFF;
End;

Procedure ShowMouseCursor;
Var Regs: Registers;
Begin
 If Not MouseAvailable Then Exit;
 Regs.AX := $0001;
 Intr($33, Regs);
End;

Procedure HideMouseCursor;
Var Regs: Registers;
Begin
 If Not MouseAvailable Then Exit;
 Regs.AX := $0002;
 Intr($33, Regs);
End;

Procedure GetMouseLocal(Var X, Y, Buttons: Integer);
Var Regs: Registers;
Begin
 If Not MouseAvailable Then Begin
  X := 0; Y := 0; Buttons := 0;
  Exit;
 End;
 Regs.AX := $0003;
 Intr($33, Regs);
 X := Regs.CX;
 Y := Regs.DX;
 Buttons := Regs.BX;
End;
{$ELSE}
Procedure InitMouseDriver;
Begin
 PtcMouse.InitMouse;
 MouseAvailable := True;
End;

Procedure ShowMouseCursor;
Begin
 PtcMouse.ShowMouse;
End;

Procedure HideMouseCursor;
Begin
 PtcMouse.HideMouse;
End;

Procedure GetMouseLocal(Var X, Y, Buttons: Integer);
Var LX, LY, LB: LongInt;
Begin
 PtcMouse.GetMouseState(LX, LY, LB);
 X := LX; Y := LY; Buttons := LB;
End;
{$ENDIF}

Var
 ScreenWidth, ScreenHeight : Integer;
 Menus       : Array[0..NUM_MENUS-1] Of TMenu;
 MenuBarHeight : Integer;
 MenuActive  : Boolean;
 ActiveMenu, ActiveMenuItem : Integer;

Function PtInRect(MX, MY, X1, Y1, X2, Y2: Integer): Boolean;
Begin
 PtInRect := (MX >= X1) And (MX <= X2) And (MY >= Y1) And (MY <= Y2);
End;

Procedure Bevel(X1, Y1, X2, Y2: Integer; Down: Boolean);
Begin
 If Down Then SetColor(DarkGray) Else SetColor(White);
 Line(X1, Y1, X2 - 1, Y1); Line(X1, Y1, X1, Y2 - 1);
 If Down Then SetColor(White) Else SetColor(DarkGray);
 Line(X2, Y1, X2, Y2); Line(X1, Y2, X2, Y2);
End;

Procedure DrawButton(X1, Y1, X2, Y2: Integer; Const Caption: String;
                     Focused: Boolean);
Var TX, TY: Integer;
Begin
 SetFillStyle(SolidFill, LightGray);
 Bar(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1);
 SetColor(White);
 Line(X1, Y1, X2, Y1);
 Line(X1, Y1, X1, Y2);
 SetColor(DarkGray);
 Line(X1 + 1, Y2 - 1, X2 - 1, Y2 - 1);
 Line(X2 - 1, Y1 + 1, X2 - 1, Y2 - 1);
 SetColor(Black);
 Line(X1, Y2, X2, Y2);
 Line(X2, Y1, X2, Y2);
 SetTextStyle(DefaultFont, HorizDir, 1);
 TX := (X1 + X2 - TextWidth(Caption)) Div 2;
 TY := (Y1 + Y2 - TextHeight(Caption)) Div 2;
 SetColor(Black);
 OutTextXY(TX, TY, Caption);
 If Focused Then Begin
  SetColor(Black);
  Rectangle(X1 + 3, Y1 + 3, X2 - 3, Y2 - 3);
 End;
End;

Procedure DrawDialogBox(X1, Y1, X2, Y2: Integer; Const Title: String);
Begin
 SetFillStyle(SolidFill, LightGray);
 Bar(X1, Y1, X2, Y2);
 SetColor(White);
 Rectangle(X1, Y1, X2, Y2);
 SetColor(DarkGray);
 Rectangle(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1);
 SetFillStyle(SolidFill, Blue);
 Bar(X1 + 2, Y1 + 2, X2 - 2, Y1 + 16);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetColor(White);
 OutTextXY(X1 + 6, Y1 + 5, Title);
 SetColor(Black);
End;

{ --------------------------------------------------------------------- }
{ Barre de menus                                                        }
{ --------------------------------------------------------------------- }

Procedure LayoutMenuBar;
Var I, X, W : Integer;
Begin
 X := 6;
 For I := 0 To NUM_MENUS - 1 Do Begin
  W := 8 * Length(Menus[I].Title);
  Menus[I].X := X;
  Menus[I].Y := 0;
  X := X + W + 14;
 End;
 MenuBarHeight := MENUBAR_H;
End;

Procedure DrawMenuBar;
Var
 I, W : Integer;
Begin
 LayoutMenuBar;
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetFillStyle(SolidFill, LightGray);
 Bar(0, 0, ScreenWidth - 1, MenuBarHeight - 1);
 SetColor(DarkGray);
 Line(0, MenuBarHeight - 1, ScreenWidth - 1, MenuBarHeight - 1);
 For I := 0 To NUM_MENUS - 1 Do Begin
  W := 8 * Length(Menus[I].Title);
  If MenuActive And (ActiveMenu = I) Then Begin
   SetFillStyle(SolidFill, Blue);
   Bar(Menus[I].X - 3, Menus[I].Y + 2, Menus[I].X + W + 3, Menus[I].Y + MENUBAR_H - 3);
   SetColor(White);
  End
  Else SetColor(Black);
  OutTextXY(Menus[I].X, Menus[I].Y + 6, Menus[I].Title);
 End;
End;

Procedure DrawMenuPopup(MenuIdx: Integer);
Var
 I, ItemHeight, X, Y, W, H, Wmax, WSc : Integer;
 Cap, Sc : String;
Begin
 If (MenuIdx < 0) Or (MenuIdx >= NUM_MENUS) Then Exit;
 SetTextStyle(DefaultFont, HorizDir, 1);
 ItemHeight := 16;
 Wmax := 0;
 For I := 0 To Menus[MenuIdx].ItemCount - 1 Do Begin
  Cap := Menus[MenuIdx].Items[I].Caption;
  Sc  := Menus[MenuIdx].Items[I].Shortcut;
  W := TextWidth(Cap) + 30 + TextWidth(Sc) + 12;
  If W > Wmax Then Wmax := W;
 End;
 If Wmax < 180 Then Wmax := 180;
 Menus[MenuIdx].Width := Wmax;
 X := Menus[MenuIdx].X - 3;
 Y := Menus[MenuIdx].Y + MENUBAR_H;
 W := Wmax;
 H := Menus[MenuIdx].ItemCount * ItemHeight + 4;
 If X + W >= ScreenWidth Then X := ScreenWidth - W - 2;
 SetFillStyle(SolidFill, LightGray);
 Bar(X, Y, X + W, Y + H);
 SetColor(White);
 Line(X, Y, X + W, Y); Line(X, Y, X, Y + H);
 SetColor(DarkGray);
 Line(X + W, Y, X + W, Y + H); Line(X, Y + H, X + W, Y + H);
 SetColor(Black);
 Line(X + W + 1, Y + 1, X + W + 1, Y + H + 1);
 Line(X + 1, Y + H + 1, X + W + 1, Y + H + 1);
 For I := 0 To Menus[MenuIdx].ItemCount - 1 Do Begin
  If Menus[MenuIdx].Items[I].Separator Then Begin
   SetColor(DarkGray);
   Line(X + 4, Y + 2 + I * ItemHeight + ItemHeight Div 2,
        X + W - 4, Y + 2 + I * ItemHeight + ItemHeight Div 2);
  End
  Else Begin
   If ActiveMenuItem = I Then Begin
    SetFillStyle(SolidFill, Blue);
    Bar(X + 2, Y + 2 + I * ItemHeight, X + W - 2, Y + 2 + (I + 1) * ItemHeight);
    SetColor(White);
   End
   Else Begin
    If Menus[MenuIdx].Items[I].Enabled Then SetColor(Black)
    Else SetColor(DarkGray);
   End;
   If Menus[MenuIdx].Items[I].Checked Then
    OutTextXY(X + 5, Y + 4 + I * ItemHeight, #251);
   OutTextXY(X + 22, Y + 4 + I * ItemHeight, Menus[MenuIdx].Items[I].Caption);
   Sc := Menus[MenuIdx].Items[I].Shortcut;
   If Sc <> '' Then Begin
    WSc := TextWidth(Sc);
    OutTextXY(X + W - WSc - 8, Y + 4 + I * ItemHeight, Sc);
   End;
  End;
 End;
End;

Function MenuBarHitTest(Mx, My: Integer): Integer;
Var I, X1, X2: Integer;
Begin
 MenuBarHitTest := -1;
 If My >= MenuBarHeight Then Exit;
 For I := 0 To NUM_MENUS - 1 Do Begin
  X1 := Menus[I].X - 3;
  X2 := Menus[I].X + 8 * Length(Menus[I].Title) + 3;
  If (Mx >= X1) And (Mx <= X2) Then Begin
   MenuBarHitTest := I; Exit;
  End;
 End;
End;

Function MenuItemHitTest(Mx, My, MenuIdx: Integer): Integer;
Var Idx, Top, Bot, X, W: Integer;
Begin
 MenuItemHitTest := -1;
 If (MenuIdx < 0) Or (MenuIdx >= NUM_MENUS) Then Exit;
 Top := Menus[MenuIdx].Y + MENUBAR_H;
 Bot := Top + Menus[MenuIdx].ItemCount * 16 + 4;
 X := Menus[MenuIdx].X - 3;
 W := Menus[MenuIdx].Width;
 If X + W >= ScreenWidth Then X := ScreenWidth - W - 2;
 If (Mx < X) Or (Mx > X + W) Or (My < Top) Or (My > Bot) Then Exit;
 Idx := (My - Top - 2) Div 16;
 If (Idx < 0) Or (Idx >= Menus[MenuIdx].ItemCount) Then Exit;
 MenuItemHitTest := Idx;
End;

Procedure MenuNextItem(Step: Integer);
Var N, I: Integer;
Begin
 If (ActiveMenu < 0) Or (ActiveMenu >= NUM_MENUS) Then Exit;
 N := Menus[ActiveMenu].ItemCount;
 If N <= 0 Then Exit;
 If ActiveMenuItem < 0 Then Begin
  If Step > 0 Then ActiveMenuItem := -1 Else ActiveMenuItem := N;
 End;
 For I := 1 To N Do Begin
  ActiveMenuItem := ActiveMenuItem + Step;
  If ActiveMenuItem < 0 Then ActiveMenuItem := N - 1;
  If ActiveMenuItem >= N Then ActiveMenuItem := 0;
  If Not Menus[ActiveMenu].Items[ActiveMenuItem].Separator Then Exit;
 End;
End;

{ --------------------------------------------------------------------- }
{ Boites de dialogue                                                   }
{ --------------------------------------------------------------------- }

Const
 MAX_TL = 200;

Var
 DlgOldLeft : Boolean;
 DlgHappened : Boolean;
 TLines     : Array[0..MAX_TL - 1] Of String[72];
 NTL        : Integer;

Procedure DlgBegin;
Var K: Char;
Begin
 While KeyPressed Do Begin
  K := ReadKey;
  If K = #0 Then If KeyPressed Then K := ReadKey;
 End;
 GetMouseLocal(MouseX, MouseY, MouseButtons);
 DlgOldLeft := (MouseButtons And 1) <> 0;
End;

{ Interroge clavier et souris. Key : 0=rien, 1..255=ASCII, 256+code=touche etendue }
Function DlgPoll(Var Key, MX, MY: Integer; Var Click: Boolean): Boolean;
Var K: Char; L: Boolean;
Begin
 Key := 0; Click := False;
 If KeyPressed Then Begin
  K := ReadKey;
  If K = #0 Then Begin
   If KeyPressed Then Begin K := ReadKey; Key := 256 + Ord(K); End;
  End
  Else Key := Ord(K);
 End;
 GetMouseLocal(MouseX, MouseY, MouseButtons);
 MX := MouseX; MY := MouseY;
 L := (MouseButtons And 1) <> 0;
 Click := L And Not DlgOldLeft;
 DlgOldLeft := L;
 DlgPoll := (Key <> 0) Or Click;
End;

Procedure DlgEnd;
Begin
 DlgHappened := True;
 OldMouseButtons := MouseButtons;
 OldMouseX := MouseX; OldMouseY := MouseY;
 NeedRedraw := True;
End;

Function WordLine(Const S: String; N: Integer): String;
{ N-ieme segment (base 1) d'une chaine separee par '|' }
Var I, K, St: Integer;
Begin
 K := 1; St := 1;
 For I := 1 To Length(S) + 1 Do Begin
  If (I > Length(S)) Or (S[I] = '|') Then Begin
   If K = N Then Begin WordLine := Copy(S, St, I - St); Exit; End;
   Inc(K); St := I + 1;
  End;
 End;
 WordLine := '';
End;

Function CountLines(Const S: String): Integer;
Var I, N: Integer;
Begin
 N := 1;
 For I := 1 To Length(S) Do If S[I] = '|' Then Inc(N);
 CountLines := N;
End;

Procedure ShowMessage(Const Title, Msg: String);
Const BW = 70; BH = 22;
Var
 X1, Y1, X2, Y2, BX1, BY1, BX2, BY2, W, H, I, NL, Key, MX, MY : Integer;
 Click, Done : Boolean;
Begin
 NL := CountLines(Msg);
 W := TextWidth(Title) + 40;
 For I := 1 To NL Do
  If TextWidth(WordLine(Msg, I)) + 40 > W Then W := TextWidth(WordLine(Msg, I)) + 40;
 If W < 240 Then W := 240;
 If W > ScreenWidth - 20 Then W := ScreenWidth - 20;
 H := 70 + NL * 12;
 X1 := (ScreenWidth - W) Div 2; Y1 := (ScreenHeight - H) Div 2;
 X2 := X1 + W; Y2 := Y1 + H;
 BX1 := (X1 + X2 - BW) Div 2; BY1 := Y2 - BH - 8;
 BX2 := BX1 + BW; BY2 := BY1 + BH;
 HideMouseCursor;
 DrawDialogBox(X1, Y1, X2, Y2, Title);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetColor(Black);
 For I := 1 To NL Do OutTextXY(X1 + 20, Y1 + 28 + (I - 1) * 12, WordLine(Msg, I));
 DrawButton(BX1, BY1, BX2, BY2, 'OK', True);
 ShowMouseCursor;
 DlgBegin;
 Done := False;
 While Not Done Do Begin
  If DlgPoll(Key, MX, MY, Click) Then Begin
   If (Key = 13) Or (Key = 27) Or (Key = 32) Then Done := True;
   If Click And PtInRect(MX, MY, BX1, BY1, BX2, BY2) Then Done := True;
  End;
  Delay(10);
 End;
 DlgEnd;
End;

Function ConfirmBox(Const Title, Msg: String): Boolean;
Const BW = 70; BH = 22;
Var
 X1, Y1, X2, Y2, W, H, I, NL, Key, MX, MY, BY1, BY2, B1X, B2X : Integer;
 Click, Done, Res : Boolean;
Begin
 NL := CountLines(Msg);
 W := TextWidth(Title) + 40;
 For I := 1 To NL Do
  If TextWidth(WordLine(Msg, I)) + 40 > W Then W := TextWidth(WordLine(Msg, I)) + 40;
 If W < 260 Then W := 260;
 If W > ScreenWidth - 20 Then W := ScreenWidth - 20;
 H := 70 + NL * 12;
 X1 := (ScreenWidth - W) Div 2; Y1 := (ScreenHeight - H) Div 2;
 X2 := X1 + W; Y2 := Y1 + H;
 BY1 := Y2 - BH - 8; BY2 := BY1 + BH;
 B1X := (X1 + X2) Div 2 - BW - 8; B2X := (X1 + X2) Div 2 + 8;
 HideMouseCursor;
 DrawDialogBox(X1, Y1, X2, Y2, Title);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetColor(Black);
 For I := 1 To NL Do OutTextXY(X1 + 20, Y1 + 28 + (I - 1) * 12, WordLine(Msg, I));
 DrawButton(B1X, BY1, B1X + BW, BY2, 'Oui', True);
 DrawButton(B2X, BY1, B2X + BW, BY2, 'Non', False);
 ShowMouseCursor;
 DlgBegin;
 Done := False; Res := False;
 While Not Done Do Begin
  If DlgPoll(Key, MX, MY, Click) Then Begin
   If (Key = 13) Or (Key = Ord('o')) Or (Key = Ord('O')) Then Begin Res := True; Done := True; End;
   If (Key = 27) Or (Key = Ord('n')) Or (Key = Ord('N')) Then Begin Res := False; Done := True; End;
   If Click And PtInRect(MX, MY, B1X, BY1, B1X + BW, BY2) Then Begin Res := True; Done := True; End;
   If Click And PtInRect(MX, MY, B2X, BY1, B2X + BW, BY2) Then Begin Res := False; Done := True; End;
  End;
  Delay(10);
 End;
 DlgEnd;
 ConfirmBox := Res;
End;

Function InputString(Const Title, Prompt: String; Var Value: String): Boolean;
Const BW = 80; BH = 22;
Var
 X1, Y1, X2, Y2, W, BBY1, BBY2, BOk1, BOk2, BCa1, BCa2, Key, MX, MY : Integer;
 Click, Done, OK, First : Boolean;
Begin
 W := 460;
 If W > ScreenWidth - 10 Then W := ScreenWidth - 10;
 X1 := (ScreenWidth - W) Div 2; Y1 := (ScreenHeight - 140) Div 2;
 X2 := X1 + W; Y2 := Y1 + 140;
 BBY1 := Y2 - BH - 10; BBY2 := BBY1 + BH;
 BOk1 := X1 + W Div 2 - BW - 10; BOk2 := BOk1 + BW;
 BCa1 := X1 + W Div 2 + 10; BCa2 := BCa1 + BW;
 HideMouseCursor;
 DrawDialogBox(X1, Y1, X2, Y2, Title);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetColor(Black);
 OutTextXY(X1 + 15, Y1 + 30, Copy(Prompt, 1, (W - 30) Div 8));
 DrawButton(BOk1, BBY1, BOk2, BBY2, 'OK', False);
 DrawButton(BCa1, BBY1, BCa2, BBY2, 'Annuler', False);
 ShowMouseCursor;
 DlgBegin;
 Done := False; OK := False; First := True;
 While Not Done Do Begin
  HideMouseCursor;
  SetFillStyle(SolidFill, White);
  Bar(X1 + 15, Y1 + 50, X2 - 15, Y1 + 70);
  SetColor(Black);
  Rectangle(X1 + 14, Y1 + 49, X2 - 14, Y1 + 71);
  If Length(Value) > (W - 50) Div 8 Then
   OutTextXY(X1 + 18, Y1 + 56, Copy(Value, Length(Value) - (W - 50) Div 8 + 1, 255) + '_')
  Else OutTextXY(X1 + 18, Y1 + 56, Value + '_');
  ShowMouseCursor;
  Repeat
   If DlgPoll(Key, MX, MY, Click) Then Break;
   Delay(10);
  Until False;
  If Click Then Begin
   If PtInRect(MX, MY, BOk1, BBY1, BOk2, BBY2) Then Begin Done := True; OK := True; End
   Else If PtInRect(MX, MY, BCa1, BBY1, BCa2, BBY2) Then Begin Done := True; OK := False; End;
  End;
  If Key = 13 Then Begin Done := True; OK := True; End
  Else If Key = 27 Then Begin Done := True; OK := False; End
  Else If Key = 8 Then Begin
   If Length(Value) > 0 Then Delete(Value, Length(Value), 1);
   First := False;
  End
  Else If (Key >= 32) And (Key < 256) And (Length(Value) < 250) Then Begin
   If First Then Value := '';
   First := False;
   Value := Value + Chr(Key);
  End
  Else If Key > 0 Then First := False;
 End;
 DlgEnd;
 InputString := OK;
End;

{ Liste / visionneuse de texte dans TLines[0..NTL-1] ; renvoie l'indice choisi }
Function ListDialog(Const Title: String; Selectable: Boolean): Integer;
Const BW = 80; BH = 22; LH = 12;
Var
 X1, Y1, X2, Y2, LX1, LY1, LX2, LY2, MaxLn, Top, Sel, I, Y : Integer;
 B1X, B2X, BY1, BY2, Key, MX, MY, Row : Integer;
 Click, Done, Redraw : Boolean;
 Res : Integer;
 LastT : LongInt;
 LastRow : Integer;
Begin
 X1 := 40; Y1 := 24; X2 := ScreenWidth - 40; Y2 := ScreenHeight - 24;
 LX1 := X1 + 8; LY1 := Y1 + 24; LX2 := X2 - 24; LY2 := Y2 - 40;
 MaxLn := (LY2 - LY1 - 4) Div LH;
 BY1 := Y2 - BH - 8; BY2 := BY1 + BH;
 B1X := X2 - 2 * (BW + 10); B2X := X2 - (BW + 10);
 Top := 0; Sel := 0; Res := -1; Done := False; Redraw := True;
 LastT := 0; LastRow := -2;
 HideMouseCursor;
 DrawDialogBox(X1, Y1, X2, Y2, Title);
 If Selectable Then Begin
  DrawButton(B1X, BY1, B1X + BW, BY2, 'OK', True);
  DrawButton(B2X, BY1, B2X + BW, BY2, 'Annuler', False);
 End
 Else DrawButton(B2X, BY1, B2X + BW, BY2, 'Fermer', True);
 DrawButton(LX2 + 2, LY1, LX2 + 18, LY1 + 16, '^', False);
 DrawButton(LX2 + 2, LY2 - 16, LX2 + 18, LY2, 'v', False);
 ShowMouseCursor;
 DlgBegin;
 While Not Done Do Begin
  If Redraw Then Begin
   HideMouseCursor;
   SetFillStyle(SolidFill, White);
   Bar(LX1, LY1, LX2, LY2);
   SetColor(Black);
   Rectangle(LX1, LY1, LX2, LY2);
   SetTextStyle(DefaultFont, HorizDir, 1);
   For I := 0 To MaxLn - 1 Do Begin
    If Top + I >= NTL Then Break;
    Y := LY1 + 3 + I * LH;
    If Selectable And (Top + I = Sel) Then Begin
     SetFillStyle(SolidFill, Blue);
     Bar(LX1 + 1, Y - 1, LX2 - 1, Y + LH - 2);
     SetColor(White);
    End
    Else SetColor(Black);
    OutTextXY(LX1 + 4, Y, TLines[Top + I]);
   End;
   ShowMouseCursor;
   Redraw := False;
  End;
  If DlgPoll(Key, MX, MY, Click) Then Begin
   Case Key Of
    256 + 72: Begin If Selectable Then Begin If Sel > 0 Then Dec(Sel); If Sel < Top Then Top := Sel; End Else If Top > 0 Then Dec(Top); Redraw := True; End;
    256 + 80: Begin If Selectable Then Begin If Sel < NTL - 1 Then Inc(Sel); If Sel >= Top + MaxLn Then Top := Sel - MaxLn + 1; End Else If Top < NTL - MaxLn Then Inc(Top); Redraw := True; End;
    256 + 73: Begin Dec(Top, MaxLn); If Top < 0 Then Top := 0; If Selectable Then Sel := Top; Redraw := True; End;
    256 + 81: Begin
     Inc(Top, MaxLn); If Top > NTL - MaxLn Then Top := NTL - MaxLn; If Top < 0 Then Top := 0;
     If Selectable Then Sel := Top; Redraw := True;
    End;
    256 + 71: Begin Top := 0; Sel := 0; Redraw := True; End;
    256 + 79: Begin
     Sel := NTL - 1; Top := NTL - MaxLn; If Top < 0 Then Top := 0; Redraw := True;
    End;
    13: Begin If Selectable Then Res := Sel Else Res := 0; Done := True; End;
    27: Begin Res := -1; Done := True; End;
   End;
   If Click Then Begin
    If PtInRect(MX, MY, B2X, BY1, B2X + BW, BY2) Then Begin Res := -1; Done := True; End
    Else If Selectable And PtInRect(MX, MY, B1X, BY1, B1X + BW, BY2) Then Begin Res := Sel; Done := True; End
    Else If PtInRect(MX, MY, LX2 + 2, LY1, LX2 + 18, LY1 + 16) Then Begin If Top > 0 Then Dec(Top, 3); If Top < 0 Then Top := 0; Redraw := True; End
    Else If PtInRect(MX, MY, LX2 + 2, LY2 - 16, LX2 + 18, LY2) Then Begin
     If Top < NTL - MaxLn Then Inc(Top, 3); If Top > NTL - MaxLn Then Top := NTL - MaxLn; If Top < 0 Then Top := 0; Redraw := True;
    End
    Else If Selectable And PtInRect(MX, MY, LX1, LY1, LX2, LY2) Then Begin
     Row := Top + (MY - LY1 - 3) Div LH;
     If (Row >= 0) And (Row < NTL) Then Begin
      If (Row = LastRow) And (NowMs - LastT < 600) And (NowMs >= LastT) Then Begin
       Res := Row; Done := True;
      End;
      Sel := Row; LastRow := Row; LastT := NowMs;
      Redraw := True;
     End;
    End;
   End;
  End;
  Delay(10);
 End;
 DlgEnd;
 ListDialog := Res;
End;

{ --------------------------------------------------------------------- }
{ Boite d'ouverture de fichier                                          }
{ --------------------------------------------------------------------- }

Const
 FD_MAX_FILES = 160;

Type
 TFDEntry = Record
  Name  : String[14];
  IsDir : Boolean;
 End;

Var
 FDFiles : Array[0..FD_MAX_FILES - 1] Of TFDEntry;
 FDCount, FDTop, FDSel : Integer;
 FDMask, FDFileName : String;

Procedure FD_ScanMask(Const Mask: String);
Var Sr: SearchRec;
Begin
 FindFirst(Mask, AnyFile, Sr);
 While (DosError = 0) And (FDCount < FD_MAX_FILES) Do Begin
  If ((Sr.Attr And Directory) = 0) Then Begin
   FDFiles[FDCount].Name := Sr.Name;
   FDFiles[FDCount].IsDir := False;
   Inc(FDCount);
  End;
  FindNext(Sr);
 End;
 {$IFDEF FPC}FindClose(Sr);{$ENDIF}
End;

Procedure FD_ScanDir(Const Mask: String);
Var
 Sr : SearchRec;
 Tmp : TFDEntry;
 I, J, P : Integer;
 M : String;
Begin
 FDCount := 0;
 FindFirst('*', Directory, Sr);
 While (DosError = 0) And (FDCount < FD_MAX_FILES) Do Begin
  If ((Sr.Attr And Directory) <> 0) And (Sr.Name <> '.') Then Begin
   FDFiles[FDCount].Name := Sr.Name;
   FDFiles[FDCount].IsDir := True;
   Inc(FDCount);
  End;
  FindNext(Sr);
 End;
 {$IFDEF FPC}FindClose(Sr);{$ENDIF}
 M := Mask;
 Repeat
  P := Pos(';', M);
  If P > 0 Then Begin FD_ScanMask(Copy(M, 1, P - 1)); Delete(M, 1, P); End
  Else Begin FD_ScanMask(M); M := ''; End;
 Until M = '';
 For I := 1 To FDCount - 1 Do Begin
  Tmp := FDFiles[I];
  J := I - 1;
  While (J >= 0) And
        ((FDFiles[J].IsDir < Tmp.IsDir) Or
         ((FDFiles[J].IsDir = Tmp.IsDir) And (UpStr(FDFiles[J].Name) > UpStr(Tmp.Name)))) Do Begin
   FDFiles[J + 1] := FDFiles[J];
   Dec(J);
  End;
  FDFiles[J + 1] := Tmp;
 End;
End;

Procedure FD_DrawList(X1, Y1, X2, Y2: Integer);
Var I, Y, MaxLn : Integer; S : String;
Begin
 SetFillStyle(SolidFill, White);
 Bar(X1, Y1, X2, Y2);
 SetColor(Black);
 Rectangle(X1, Y1, X2, Y2);
 SetTextStyle(DefaultFont, HorizDir, 1);
 MaxLn := (Y2 - Y1 - 2) Div 10;
 For I := 0 To MaxLn - 1 Do Begin
  If FDTop + I >= FDCount Then Break;
  Y := Y1 + 2 + I * 10;
  If FDTop + I = FDSel Then Begin
   SetFillStyle(SolidFill, Blue);
   Bar(X1 + 1, Y, X2 - 1, Y + 9);
   SetColor(White);
  End
  Else SetColor(Black);
  If FDFiles[FDTop + I].IsDir Then S := '[' + FDFiles[FDTop + I].Name + ']'
  Else S := FDFiles[FDTop + I].Name;
  OutTextXY(X1 + 4, Y + 1, S);
 End;
End;

Function FileOpenDialog(Const Title: String; Var FileName: String;
                        Const InitialMask: String): Boolean;
Const BW = 80; BH = 22;
Var
 X1, Y1, X2, Y2, LX1, LY1, LX2, LY2, BOu1, BAn1, BBY1, BBY2, MaxLn : Integer;
 Key, MX, MY, SimK : Integer;
 Click, Done, Result : Boolean;
 OldDir, CurDir : String;
 NewMask : String;
 LastT : LongInt;
 LastRow, Row : Integer;
Begin
 FileOpenDialog := False;
 GetDir(0, OldDir);
 FDMask := InitialMask;
 FD_ScanDir(FDMask);
 FDTop := 0; FDSel := 0;
 X1 := 50; Y1 := 40; X2 := ScreenWidth - 50; Y2 := ScreenHeight - 40;
 LX1 := X1 + 10; LY1 := Y1 + 50; LX2 := X2 - 10; LY2 := Y2 - 90;
 MaxLn := (LY2 - LY1 - 2) Div 10;
 BBY1 := Y2 - BH - 8; BBY2 := BBY1 + BH;
 BOu1 := X2 - 2 * (BW + 8) - 10;
 BAn1 := X2 - (BW + 8) - 10;
 HideMouseCursor;
 DrawDialogBox(X1, Y1, X2, Y2, Title);
 GetDir(0, CurDir);
 SetColor(Black);
 OutTextXY(X1 + 10, Y1 + 22, 'Dossier : ' + Copy(CurDir, 1, 52));
 OutTextXY(X1 + 10, Y1 + 35, 'Masque : ' + FDMask + '   (Tab = changer le masque)');
 OutTextXY(X1 + 10, Y2 - 80, 'Fichier:');
 DrawButton(BOu1, BBY1, BOu1 + BW, BBY2, 'Ouvrir', True);
 DrawButton(BAn1, BBY1, BAn1 + BW, BBY2, 'Annuler', False);
 ShowMouseCursor;
 Done := False; Result := False; FDFileName := '';
 LastT := 0; LastRow := -2;
 DlgBegin;
 While Not Done Do Begin
  HideMouseCursor;
  SetFillStyle(SolidFill, White);
  Bar(X1 + 80, Y2 - 83, X2 - 10, Y2 - 70);
  SetColor(Black);
  Rectangle(X1 + 80, Y2 - 84, X2 - 9, Y2 - 69);
  OutTextXY(X1 + 84, Y2 - 81, FDFileName + '_');
  FD_DrawList(LX1, LY1, LX2, LY2);
  ShowMouseCursor;
  SimK := 0;
  Repeat
   If DlgPoll(Key, MX, MY, Click) Then Begin
    If Click Then Begin
     If PtInRect(MX, MY, BOu1, BBY1, BOu1 + BW, BBY2) Then SimK := 13
     Else If PtInRect(MX, MY, BAn1, BBY1, BAn1 + BW, BBY2) Then SimK := 27
     Else If PtInRect(MX, MY, LX1, LY1, LX2, LY2) Then Begin
      Row := FDTop + (MY - LY1 - 2) Div 10;
      If (Row >= 0) And (Row < FDCount) Then Begin
       If (Row = LastRow) And (NowMs - LastT < 600) And (NowMs >= LastT) Then SimK := 13;
       FDSel := Row; LastRow := Row; LastT := NowMs;
       FDFileName := '';
      End;
     End;
    End;
    If SimK = 0 Then SimK := Key;
    If SimK = 0 Then SimK := -1;
    Break;
   End;
   Delay(10);
  Until False;
  Case SimK Of
   -1: ;
   256 + 72: Begin If FDSel > 0 Then Dec(FDSel); If FDSel < FDTop Then FDTop := FDSel; End;
   256 + 80: Begin
    If FDSel < FDCount - 1 Then Inc(FDSel);
    If FDSel >= FDTop + MaxLn Then FDTop := FDSel - MaxLn + 1;
   End;
   256 + 73: Begin Dec(FDSel, MaxLn); If FDSel < 0 Then FDSel := 0; FDTop := FDSel; End;
   256 + 81: Begin
    Inc(FDSel, MaxLn); If FDSel >= FDCount Then FDSel := FDCount - 1;
    FDTop := FDSel - MaxLn + 1; If FDTop < 0 Then FDTop := 0;
   End;
   256 + 71: Begin FDSel := 0; FDTop := 0; End;
   256 + 79: Begin
    FDSel := FDCount - 1; FDTop := FDSel - MaxLn + 1; If FDTop < 0 Then FDTop := 0;
   End;
   13: Begin
    If FDFileName <> '' Then Begin
     FileName := FDFileName; Result := True; Done := True;
    End
    Else If (FDSel >= 0) And (FDSel < FDCount) Then Begin
     If FDFiles[FDSel].IsDir Then Begin
      {$I-}ChDir(FDFiles[FDSel].Name);{$I+}
      If IOResult <> 0 Then ;
      FD_ScanDir(FDMask);
      FDTop := 0; FDSel := 0;
      GetDir(0, CurDir);
      HideMouseCursor;
      SetFillStyle(SolidFill, LightGray);
      Bar(X1 + 10, Y1 + 20, X2 - 5, Y1 + 31);
      SetColor(Black);
      OutTextXY(X1 + 10, Y1 + 22, 'Dossier : ' + Copy(CurDir, 1, 52));
      ShowMouseCursor;
     End
     Else Begin
      FileName := FDFiles[FDSel].Name; Result := True; Done := True;
     End;
    End;
   End;
   27: Begin Result := False; Done := True; End;
   9: Begin
    NewMask := FDMask;
    If InputString('Masque', 'Entrer le masque (ex: *.CGM):', NewMask) Then Begin
     FDMask := NewMask; FD_ScanDir(FDMask); FDTop := 0; FDSel := 0;
    End;
    HideMouseCursor;
    DrawDialogBox(X1, Y1, X2, Y2, Title);
    SetColor(Black);
    OutTextXY(X1 + 10, Y1 + 22, 'Dossier : ' + Copy(CurDir, 1, 52));
    OutTextXY(X1 + 10, Y1 + 35, 'Masque : ' + FDMask + '   (Tab = changer le masque)');
    OutTextXY(X1 + 10, Y2 - 80, 'Fichier:');
    DrawButton(BOu1, BBY1, BOu1 + BW, BBY2, 'Ouvrir', True);
    DrawButton(BAn1, BBY1, BAn1 + BW, BBY2, 'Annuler', False);
    ShowMouseCursor;
   End;
   8: Begin If Length(FDFileName) > 0 Then Delete(FDFileName, Length(FDFileName), 1); End;
  Else
   If (SimK >= 32) And (SimK < 256) And (Length(FDFileName) < 60) Then
    FDFileName := FDFileName + Chr(SimK);
  End;
 End;
 If Not Result Then ChDir(OldDir);
 DlgEnd;
 FileOpenDialog := Result;
End;

Function FileSaveDialog(Const Title: String; Var FileName: String): Boolean;
Var Cur: String;
Begin
 Cur := FileName;
 If InputString(Title, 'Nom du fichier :', Cur) And (Cur <> '') Then Begin
  FileName := Cur;
  FileSaveDialog := True;
 End
 Else FileSaveDialog := False;
End;


{ --------------------------------------------------------------------- }
{ Boite de parametres generique                                         }
{ --------------------------------------------------------------------- }

Var
 PN     : Integer;
 PLabel : Array[0..MAX_ROWS-1] Of String[44];
 PVal   : Array[0..MAX_ROWS-1] Of Real;
 PMin   : Array[0..MAX_ROWS-1] Of Real;
 PMax   : Array[0..MAX_ROWS-1] Of Real;
 PKind  : Array[0..MAX_ROWS-1] Of Byte;   { 0 reel, 1 entier, 2 choix, 3 oui/non, 4 titre, 5 texte }
 PDec   : Array[0..MAX_ROWS-1] Of Byte;
 PEnum  : Array[0..MAX_ROWS-1] Of String[200];

Procedure PReset;
Begin
 PN := 0;
End;

Procedure PAdd(Const L: String; K: Byte; V, Mn, Mx: Real; Dc: Byte; Const E: String);
Begin
 If PN >= MAX_ROWS Then Exit;
 PLabel[PN] := L; PKind[PN] := K; PVal[PN] := V; PMin[PN] := Mn; PMax[PN] := Mx;
 PDec[PN] := Dc; PEnum[PN] := E;
 Inc(PN);
End;

Procedure PAddR(Const L: String; V, Mn, Mx: Real; Dc: Integer);
Begin PAdd(L, 0, V, Mn, Mx, Dc, ''); End;

Procedure PAddI(Const L: String; V, Mn, Mx: LongInt);
Begin PAdd(L, 1, V, Mn, Mx, 0, ''); End;

Procedure PAddE(Const L: String; V: Integer; Const E: String);
Begin PAdd(L, 2, V, 0, 0, 0, E); End;

Procedure PAddB(Const L: String; V: Boolean);
Begin If V Then PAdd(L, 3, 1, 0, 1, 0, '') Else PAdd(L, 3, 0, 0, 1, 0, ''); End;

Procedure PAddH(Const L: String);
Begin PAdd(L, 4, 0, 0, 0, 0, ''); End;

Procedure PAddT(Const L, Txt: String);
Begin PAdd(L, 5, 0, 0, 0, 0, Txt); End;

Function PValStr(I: Integer): String;
Begin
 Case PKind[I] Of
  0: PValStr := RTrim(PVal[I], PDec[I]);
  1: PValStr := IStr(Round(PVal[I]));
  2: PValStr := WordLine(PEnum[I], Round(PVal[I]) + 1);
  3: If PVal[I] > 0.5 Then PValStr := 'Oui' Else PValStr := 'Non';
  5: PValStr := PEnum[I];
 Else PValStr := '';
 End;
End;

Function PBool(I: Integer): Boolean;
Begin PBool := PVal[I] > 0.5; End;

Function PInt(I: Integer): LongInt;
Begin PInt := Round(PVal[I]); End;

Procedure PEdit(I: Integer);
Var S: String; V: Real;
Begin
 Case PKind[I] Of
  0, 1: Begin
   S := PValStr(I);
   If InputString(PLabel[I], 'Nouvelle valeur (' + RTrim(PMin[I], 4) + ' a ' + RTrim(PMax[I], 4) + ') :', S) Then Begin
    If ParseReal(S, V) Then Begin
     If (PMax[I] > PMin[I]) And ((V < PMin[I]) Or (V > PMax[I])) Then
      ShowMessage('Valeur refusee', 'La valeur doit etre comprise entre|' + RTrim(PMin[I], 4) + ' et ' + RTrim(PMax[I], 4))
     Else Begin
      If PKind[I] = 1 Then V := Round(V);
      PVal[I] := V;
     End;
    End
    Else ShowMessage('Valeur refusee', 'Ce n''est pas un nombre valide.');
   End;
  End;
  2: Begin
   PVal[I] := PVal[I] + 1;
   If PVal[I] > CountLines(PEnum[I]) - 1 Then PVal[I] := 0;
  End;
  3: If PVal[I] > 0.5 Then PVal[I] := 0 Else PVal[I] := 1;
 End;
End;

Function ParamDialog(Const Title, Hint: String): Boolean;
Const BW = 90; BH = 22; RH = 16;
Var
 X1, Y1, X2, Y2, RY, I, Sel, Top, Vis, Key, MX, MY, BOk1, BCa1, BBY1, BBY2, Row, LabW : Integer;
 Click, Done, Res, Redraw : Boolean;
 LastT : LongInt; LastRow : Integer;

 Procedure NextSel(Step: Integer);
 Var K: Integer;
 Begin
  K := Sel;
  Repeat
   K := K + Step;
   If (K < 0) Or (K >= PN) Then Exit;
  Until PKind[K] < 4;
  Sel := K;
  If Sel < Top Then Top := Sel;
  If Sel >= Top + Vis Then Top := Sel - Vis + 1;
 End;

Begin
 X1 := 50; Y1 := 26; X2 := ScreenWidth - 50; Y2 := ScreenHeight - 26;
 RY := Y1 + 24;
 Vis := (Y2 - Y1 - 24 - 52) Div RH;
 BBY2 := Y2 - 8; BBY1 := BBY2 - BH;
 BOk1 := X2 - 2 * (BW + 10); BCa1 := X2 - (BW + 10);
 LabW := 0;
 For I := 0 To PN - 1 Do If 8 * Length(PLabel[I]) + 28 > LabW Then LabW := 8 * Length(PLabel[I]) + 28;
 If LabW < 170 Then LabW := 170;
 If LabW > 360 Then LabW := 360;
 Sel := 0; Top := 0; Done := False; Res := False; Redraw := True;
 LastT := 0; LastRow := -1;
 If (PN > 0) And (PKind[0] >= 4) Then NextSel(1);
 DlgBegin;
 While Not Done Do Begin
  If Redraw Then Begin
   HideMouseCursor;
   DrawDialogBox(X1, Y1, X2, Y2, Title);
   SetTextStyle(DefaultFont, HorizDir, 1);
   For I := 0 To Vis - 1 Do Begin
    Row := Top + I;
    If Row >= PN Then Break;
    If PKind[Row] = 4 Then Begin
     SetColor(Blue);
     OutTextXY(X1 + 10, RY + I * RH + 4, PLabel[Row]);
     SetColor(DarkGray);
     Line(X1 + 10, RY + I * RH + RH - 2, X2 - 10, RY + I * RH + RH - 2);
    End
    Else Begin
     If Row = Sel Then Begin
      SetFillStyle(SolidFill, Blue);
      Bar(X1 + 6, RY + I * RH, X2 - 6, RY + I * RH + RH - 2);
      SetColor(White);
     End
     Else SetColor(Black);
     OutTextXY(X1 + 12, RY + I * RH + 4, PLabel[Row]);
     If PKind[Row] < 4 Then Begin
      If Row <> Sel Then Begin
       SetFillStyle(SolidFill, White);
       Bar(X1 + LabW, RY + I * RH, X2 - 12, RY + I * RH + RH - 3);
       SetColor(Black);
      End;
      OutTextXY(X1 + LabW + 4, RY + I * RH + 4, Copy(PValStr(Row), 1, (X2 - X1 - LabW - 20) Div 8));
     End
     Else Begin
      SetColor(Black);
      If Row = Sel Then SetColor(White);
      OutTextXY(X1 + LabW + 4, RY + I * RH + 4, Copy(PValStr(Row), 1, (X2 - X1 - LabW - 20) Div 8));
     End;
    End;
   End;
   SetColor(DarkGray);
   If Hint <> '' Then OutTextXY(X1 + 10, BBY1 - 14, Copy(Hint, 1, (X2 - X1 - 20) Div 8));
   If PN > Vis Then OutTextXY(X1 + 10, BBY1 + 6, 'Haut/bas : defiler (' + IStr(Sel + 1) + '/' + IStr(PN) + ')')
   Else OutTextXY(X1 + 10, BBY1 + 6, 'Entree : modifier  Tab : OK  Echap : annuler');
   DrawButton(BOk1, BBY1, BOk1 + BW, BBY2, 'OK', True);
   DrawButton(BCa1, BBY1, BCa1 + BW, BBY2, 'Annuler', False);
   ShowMouseCursor;
   Redraw := False;
  End;
  If DlgPoll(Key, MX, MY, Click) Then Begin
   Case Key Of
    256 + 72: Begin NextSel(-1); Redraw := True; End;
    256 + 80: Begin NextSel(1); Redraw := True; End;
    256 + 73: Begin For I := 1 To Vis Do NextSel(-1); Redraw := True; End;
    256 + 81: Begin For I := 1 To Vis Do NextSel(1); Redraw := True; End;
    256 + 75: If (Sel < PN) And (PKind[Sel] = 2) Then Begin
     PVal[Sel] := PVal[Sel] - 1;
     If PVal[Sel] < 0 Then PVal[Sel] := CountLines(PEnum[Sel]) - 1;
     Redraw := True;
    End;
    256 + 77: If (Sel < PN) And ((PKind[Sel] = 2) Or (PKind[Sel] = 3)) Then Begin PEdit(Sel); Redraw := True; End;
    32: If (Sel < PN) And ((PKind[Sel] = 2) Or (PKind[Sel] = 3)) Then Begin PEdit(Sel); Redraw := True; End;
    13: Begin
     If (Sel < PN) And ((PKind[Sel] = 0) Or (PKind[Sel] = 1)) Then Begin PEdit(Sel); Redraw := True; End
     Else If (Sel < PN) And ((PKind[Sel] = 2) Or (PKind[Sel] = 3)) Then Begin PEdit(Sel); Redraw := True; End
     Else Begin Res := True; Done := True; End;
    End;
    27: Begin Res := False; Done := True; End;
    9: Begin Res := True; Done := True; End;
   End;
   If Click Then Begin
    If PtInRect(MX, MY, BOk1, BBY1, BOk1 + BW, BBY2) Then Begin Res := True; Done := True; End
    Else If PtInRect(MX, MY, BCa1, BBY1, BCa1 + BW, BBY2) Then Begin Res := False; Done := True; End
    Else If PtInRect(MX, MY, X1 + 6, RY, X2 - 6, RY + Vis * RH) Then Begin
     Row := Top + (MY - RY) Div RH;
     If (Row >= 0) And (Row < PN) And (PKind[Row] < 4) Then Begin
      Sel := Row;
      If (PKind[Row] >= 2) And (PKind[Row] <= 3) And (MX >= X1 + LabW) Then PEdit(Row)
      Else If (Row = LastRow) And (NowMs - LastT < 600) And (NowMs >= LastT) Then PEdit(Row);
      LastRow := Row; LastT := NowMs;
      Redraw := True;
     End;
    End;
   End;
  End;
  Delay(10);
 End;
 DlgEnd;
 ParamDialog := Res;
End;

{ --------------------------------------------------------------------- }
{ Lignes de texte et visionneuse                                        }
{ --------------------------------------------------------------------- }

Procedure TClear;
Begin
 NTL := 0;
End;

Procedure TAdd(Const S: String);
Begin
 If NTL < MAX_TL Then Begin
  TLines[NTL] := Copy(S, 1, 72);
  Inc(NTL);
 End;
End;

Procedure TView(Const Title: String);
Var R: Integer;
Begin
 R := ListDialog(Title, False);
End;

Const
 MAXSER = 12;
 MAXPT  = 60;
 SerColors : Array[0..MAXSER-1] Of Byte = (9, 4, 2, 5, 6, 1, 12, 10, 13, 3, 14, 8);

Var
 ChNS    : Integer;
 ChN     : Array[0..MAXSER-1] Of Integer;
 ChX, ChY : Array[0..MAXSER-1, 0..MAXPT-1] Of Real;
 ChName  : Array[0..MAXSER-1] Of String[32];
 ChMark  : Array[0..MAXSER-1] Of Boolean;
 ChTitle, ChXL, ChYL : String[64];
 ChLogX  : Boolean;
 ChFixY0 : Boolean;
 ChLogMin : Real;

Procedure ChartReset(Const T, XL, YL: String; LogX: Boolean);
Var I: Integer;
Begin
 ChNS := 0; ChTitle := T; ChXL := XL; ChYL := YL; ChLogX := LogX;
 ChFixY0 := True;
 If LogX Then ChLogMin := 0.1 Else ChLogMin := 0;
 For I := 0 To MAXSER - 1 Do Begin ChN[I] := 0; ChMark[I] := False; ChName[I] := ''; End;
End;

Function ChartAddSeries(Const Name: String; Mark: Boolean): Integer;
Begin
 If ChNS >= MAXSER Then Begin ChartAddSeries := MAXSER - 1; Exit; End;
 ChName[ChNS] := Name; ChMark[ChNS] := Mark; ChN[ChNS] := 0;
 ChartAddSeries := ChNS;
 Inc(ChNS);
End;

Procedure ChartPoint(S: Integer; X, Y: Real);
Begin
 If (S < 0) Or (S >= MAXSER) Or (ChN[S] >= MAXPT) Then Exit;
 If ChLogX And (X < ChLogMin) Then Exit;
 ChX[S, ChN[S]] := X; ChY[S, ChN[S]] := Y;
 Inc(ChN[S]);
End;

Procedure NiceRange(Lo, Hi: Real; Var NLo, NHi, Step: Real);
Var Raw, Mag, R: Real;
Begin
 If Hi - Lo < 1E-12 Then Begin Hi := Lo + 1; End;
 Raw := (Hi - Lo) / 6;
 Mag := 1;
 While Raw >= 10 * Mag Do Mag := Mag * 10;
 While Raw < Mag Do Mag := Mag / 10;
 R := Raw / Mag;
 If R < 1.5 Then Step := Mag
 Else If R < 3 Then Step := 2 * Mag
 Else If R < 7 Then Step := 5 * Mag
 Else Step := 10 * Mag;
 NLo := Int(Lo / Step) * Step;
 If NLo > Lo + 1E-12 Then NLo := NLo - Step;
 NHi := Int(Hi / Step) * Step;
 If NHi < Hi - 1E-12 Then NHi := NHi + Step;
End;

Procedure ChartExport;
Var F: Text; FN: String; S, I: Integer;
Begin
 FN := 'GRAPHE.CSV';
 If Not InputString('Exporter le graphique', 'Nom du fichier CSV :', FN) Then Exit;
 If FN = '' Then Exit;
 {$I-}
 Assign(F, FN); Rewrite(F);
 {$I+}
 If IOResult <> 0 Then Begin ShowMessage('Erreur', 'Impossible d''ecrire ' + FN); Exit; End;
 WriteLn(F, ChTitle);
 For S := 0 To ChNS - 1 Do Begin
  WriteLn(F, ChName[S]);
  WriteLn(F, ChXL, ';', ChYL);
  For I := 0 To ChN[S] - 1 Do WriteLn(F, ChX[S, I]:0:6, ';', ChY[S, I]:0:6);
 End;
 Close(F);
End;

Procedure ChartDialog;
Const BW = 90; BH = 22;
Var
 X1, Y1, X2, Y2, PX1, PY1, PX2, PY2, BBY1, BBY2, BOk1, BCs1 : Integer;
 S, I, Key, MX, MY, OldMX, OldMY, XP, YP, XP0, YP0 : Integer;
 XLo, XHi, YLo, YHi, XSt, YSt, V, XMin, XMax, YMin, YMax : Real;
 Click, Done, Any : Boolean;
 BestD, D : Real; BS, BI : Integer; Info : String;

 Function SXp(V: Real): Integer;
 Begin
  If ChLogX Then Begin
   If V <= 0 Then V := XLo;
   SXp := PX1 + Round((Ln(V) - Ln(XLo)) / (Ln(XHi) - Ln(XLo)) * (PX2 - PX1));
  End
  Else SXp := PX1 + Round((V - XLo) / (XHi - XLo) * (PX2 - PX1));
 End;

 Function SYp(V: Real): Integer;
 Begin
  SYp := PY2 - Round((V - YLo) / (YHi - YLo) * (PY2 - PY1));
 End;

Begin
 X1 := 24; Y1 := 16; X2 := ScreenWidth - 24; Y2 := ScreenHeight - 16;
 PX1 := X1 + 62; PX2 := X2 - 18; PY1 := Y1 + 40; PY2 := Y2 - 118;
 BBY2 := Y2 - 8; BBY1 := BBY2 - BH;
 BOk1 := X2 - BW - 12; BCs1 := BOk1 - BW - 10;
 { bornes }
 Any := False; XMin := 1E30; XMax := -1E30; YMin := 1E30; YMax := -1E30;
 For S := 0 To ChNS - 1 Do
  For I := 0 To ChN[S] - 1 Do Begin
   Any := True;
   If ChLogX And (ChX[S, I] <= 0) Then Continue;
   If ChX[S, I] < XMin Then XMin := ChX[S, I];
   If ChX[S, I] > XMax Then XMax := ChX[S, I];
   If ChY[S, I] < YMin Then YMin := ChY[S, I];
   If ChY[S, I] > YMax Then YMax := ChY[S, I];
  End;
 If Not Any Then Begin XMin := 0; XMax := 1; YMin := 0; YMax := 1; End;
 If ChFixY0 And (YMin > 0) Then YMin := 0;
 If YMax <= YMin Then YMax := YMin + 1;
 NiceRange(YMin, YMax, YLo, YHi, YSt);
 If ChLogX Then Begin
  XLo := 1; While XLo > XMin Do XLo := XLo / 10;
  While XLo * 10 <= XMin Do XLo := XLo * 10;
  XHi := XLo;
  While XHi < XMax Do XHi := XHi * 10;
  If XHi <= XLo Then XHi := XLo * 10;
  XSt := 10;
 End
 Else Begin
  If XMax <= XMin Then XMax := XMin + 1;
  NiceRange(XMin, XMax, XLo, XHi, XSt);
 End;
 HideMouseCursor;
 DrawDialogBox(X1, Y1, X2, Y2, ChTitle);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetFillStyle(SolidFill, White);
 Bar(PX1, PY1, PX2, PY2);
 { grille et graduations }
 SetColor(Black);
 V := YLo;
 While V <= YHi + YSt * 0.001 Do Begin
  YP := SYp(V);
  SetColor(LightGray); Line(PX1, YP, PX2, YP);
  SetColor(Black); Line(PX1 - 3, YP, PX1, YP);
  OutTextXY(PX1 - 6 - 8 * Length(RTrim(V, 3)), YP - 3, RTrim(V, 3));
  V := V + YSt;
 End;
 If ChLogX Then Begin
  V := XLo;
  While V <= XHi * 1.001 Do Begin
   XP := SXp(V);
   SetColor(LightGray); Line(XP, PY1, XP, PY2);
   SetColor(Black); Line(XP, PY2, XP, PY2 + 3);
   OutTextXY(XP - 4 * Length(RTrim(V, 3)), PY2 + 6, RTrim(V, 3));
   V := V * 10;
  End;
 End
 Else Begin
  V := XLo;
  While V <= XHi + XSt * 0.001 Do Begin
   XP := SXp(V);
   SetColor(LightGray); Line(XP, PY1, XP, PY2);
   SetColor(Black); Line(XP, PY2, XP, PY2 + 3);
   OutTextXY(XP - 4 * Length(RTrim(V, 3)), PY2 + 6, RTrim(V, 3));
   V := V + XSt;
  End;
 End;
 SetColor(Black);
 Rectangle(PX1, PY1, PX2, PY2);
 OutTextXY((PX1 + PX2) Div 2 - 4 * Length(ChXL), PY2 + 20, ChXL);
 OutTextXY(PX1 - 54, PY1 - 14, ChYL);
 { courbes }
 SetViewPort(PX1 + 1, PY1 + 1, PX2 - 1, PY2 - 1, True);
 XP0 := 0; YP0 := 0;
 For S := 0 To ChNS - 1 Do Begin
  SetColor(SerColors[S]);
  For I := 0 To ChN[S] - 1 Do Begin
   XP := SXp(ChX[S, I]) - PX1 - 1; YP := SYp(ChY[S, I]) - PY1 - 1;
   If ChMark[S] Then Begin
    Rectangle(XP - 2, YP - 2, XP + 2, YP + 2);
   End
   Else If I > 0 Then
    Line(XP0, YP0, XP, YP);
   XP0 := XP; YP0 := YP;
  End;
 End;
 SetViewPort(0, 0, ScreenWidth - 1, ScreenHeight - 1, True);
 { legende }
 For S := 0 To ChNS - 1 Do Begin
  SetFillStyle(SolidFill, SerColors[S]);
  Bar(X1 + 14 + (S Mod 3) * 196, PY2 + 30 + (S Div 3) * 12, X1 + 26 + (S Mod 3) * 196, PY2 + 36 + (S Div 3) * 12);
  SetColor(Black);
  OutTextXY(X1 + 32 + (S Mod 3) * 196, PY2 + 30 + (S Div 3) * 12, Copy(ChName[S], 1, 21));
 End;
 DrawButton(BCs1, BBY1, BCs1 + BW, BBY2, 'Exporter CSV', False);
 DrawButton(BOk1, BBY1, BOk1 + BW, BBY2, 'Fermer', True);
 ShowMouseCursor;
 DlgBegin;
 Done := False; OldMX := -1; OldMY := -1; Info := '';
 While Not Done Do Begin
  If DlgPoll(Key, MX, MY, Click) Then Begin
   If (Key = 13) Or (Key = 27) Or (Key = 32) Then Done := True;
   If Click Then Begin
    If PtInRect(MX, MY, BOk1, BBY1, BOk1 + BW, BBY2) Then Done := True
    Else If PtInRect(MX, MY, BCs1, BBY1, BCs1 + BW, BBY2) Then Begin
     ChartExport;
     HideMouseCursor;
     SetFillStyle(SolidFill, LightGray);
     Bar(0, 0, ScreenWidth - 1, ScreenHeight - 1);
     ShowMouseCursor;
     Done := True;
    End;
   End;
  End;
  If (MX <> OldMX) Or (MY <> OldMY) Then Begin
   OldMX := MX; OldMY := MY;
   If PtInRect(MX, MY, PX1, PY1, PX2, PY2) Then Begin
    BestD := 1E30; BS := -1; BI := -1;
    For S := 0 To ChNS - 1 Do
     For I := 0 To ChN[S] - 1 Do Begin
      D := Sqr(SXp(ChX[S, I]) - MX) + Sqr(SYp(ChY[S, I]) - MY);
      If D < BestD Then Begin BestD := D; BS := S; BI := I; End;
     End;
    If (BS >= 0) And (BestD < 900) Then
     Info := ChName[BS] + ' : ' + RTrim(ChX[BS, BI], 4) + ' ; ' + RTrim(ChY[BS, BI], 4)
    Else Info := '';
   End
   Else Info := '';
   HideMouseCursor;
   SetFillStyle(SolidFill, LightGray);
   Bar(X1 + 14, BBY1 + 2, BCs1 - 8, BBY2);
   SetColor(Blue);
   OutTextXY(X1 + 14, BBY1 + 6, Copy(Info, 1, (BCs1 - X1 - 30) Div 8));
   ShowMouseCursor;
  End;
  Delay(10);
 End;
 DlgEnd;
End;
{ --------------------------------------------------------------------- }
{ Noms, classes et couleurs des phases                                   }
{ --------------------------------------------------------------------- }

Const
 NIT = 30;                 { phases (20) + non reagis (10) }
 ClsCol : Array[0..11] Of Byte = (10, 12, 9, 3, 5, 6, 15, 14, 13, 8, 7, 1);
 UnrNames : Array[0..9] Of String[16] = (
  'Alite nr', 'Belite nr', 'Aluminate nr', 'Ferrite nr', 'Cendres nr',
  'Laitier nr', 'Fumee nr', 'Calcaire nr', 'Argile cal. nr', 'Autres inertes');

 VX0 = 214;
 VY0 = 48;
 VX1 = 635;
 VY1 = 292;
 LPX = 4;
 LPW = 204;

 TB_FORM = 1;  TB_CEM = 2;   TB_EQ = 3;    TB_HYD = 4;   TB_MIX = 5;
 TB_LEA = 6;   TB_CARB = 7;  TB_SALT = 8;  TB_PHA = 10;  TB_SOL = 11;
 TB_AREA = 9; TB_GRA = 12;  TB_UNIT = 13; TB_PREV = 14; TB_NEXT = 15; TB_HELP = 16;
 MAX_TB = 18;

Var
 MassMode  : Boolean;               { empilement en masse (True) ou volume }
 NTB       : Integer;
 TBId      : Array[0..MAX_TB-1] Of Integer;
 TBX1, TBX2 : Array[0..MAX_TB-1] Of Integer;
 TBCap     : Array[0..MAX_TB-1] Of String[6];
 TBHint    : Array[0..MAX_TB-1] Of String[60];
 ProcSel   : Integer;               { dernier processus lance }
 StackX0, StackX1, StackY0, StackY1 : Integer;
 NBar      : Integer;

Function ItemName(I: Integer): String;
Begin
 If I < NPHASES Then ItemName := PhName[I]
 Else ItemName := UnrNames[I - NPHASES];
End;

Function ItemClass(I: Integer): Integer;
Begin
 If I < NPHASES Then ItemClass := PhCls[I]
 Else If I < NPHASES + 4 Then ItemClass := 9
 Else If I < NPHASES + 9 Then ItemClass := 10
 Else ItemClass := 9;
End;

{ valeur d'un element (masse ou volume) a l'etape St }
Function ItemVal(St, I: Integer; Mass: Boolean): Real;
Begin
 If Res = Nil Then Begin ItemVal := 0; Exit; End;
 If I < NPHASES Then Begin
  If Mass Then ItemVal := Res^[St][RI_M + I] Else ItemVal := Res^[St][RI_V + I];
 End
 Else Begin
  If Mass Then ItemVal := Res^[St][RI_UM + I - NPHASES]
  Else ItemVal := Res^[St][RI_UV + I - NPHASES];
 End;
End;

{ --------------------------------------------------------------------- }
{ Barre d'outils                                                         }
{ --------------------------------------------------------------------- }

Procedure AddTB(Id: Integer; Const Cap, Hint: String; Var X: Integer);
Var W: Integer;
Begin
 W := 8 * Length(Cap) + 8;
 If W < 22 Then W := 22;
 TBId[NTB] := Id; TBCap[NTB] := Cap; TBHint[NTB] := Hint;
 TBX1[NTB] := X; TBX2[NTB] := X + W - 1;
 X := X + W + 1;
 Inc(NTB);
End;

Procedure InitToolbar;
Var X: Integer;
Begin
 NTB := 0; X := 3;
 AddTB(TB_FORM, 'Form.', 'Formulation : eau/liant, temperature, age, ajouts', X);
 AddTB(TB_CEM, 'Cim.', 'Composition du ciment', X);
 X := X + 5;
 AddTB(TB_EQ, 'Equil', 'Equilibre thermodynamique a l''age donne', X);
 AddTB(TB_HYD, 'Hydr', 'Hydratation : equilibre en fonction du temps', X);
 AddTB(TB_MIX, 'Mel', 'Melange : balayage de la recette', X);
 AddTB(TB_LEA, 'Lix', 'Lixiviation par de l''eau pure', X);
 AddTB(TB_CARB, 'Carb', 'Carbonatation (ajout de CO2)', X);
 AddTB(TB_SALT, 'Sels', 'Penetration de sels (solution externe)', X);
 X := X + 5;
 AddTB(TB_AREA, 'Aires', 'Aires empilees des phases (F8)', X);
 AddTB(TB_PHA, 'Phas', 'Assemblage de phases de l''etape courante', X);
 AddTB(TB_SOL, 'Soln', 'Solution interstitielle de l''etape courante', X);
 AddTB(TB_GRA, 'Graph', 'Graphiques des resultats', X);
 AddTB(TB_UNIT, 'g/cm3', 'Empilement en masse ou en volume', X);
 X := X + 5;
 AddTB(TB_PREV, '<', 'Etape precedente (fleche gauche)', X);
 AddTB(TB_NEXT, '>', 'Etape suivante (fleche droite)', X);
 AddTB(TB_HELP, '?', 'Aide', X);
End;

Function ToolbarHit(MX, MY: Integer): Integer;
Var I: Integer;
Begin
 ToolbarHit := -1;
 If (MY < MENUBAR_H) Or (MY >= MENUBAR_H + TOOLBAR_H) Then Exit;
 For I := 0 To NTB - 1 Do
  If (MX >= TBX1[I]) And (MX <= TBX2[I]) Then Begin ToolbarHit := I; Exit; End;
End;

Function TBEnabled(Id: Integer): Boolean;
Begin
 Case Id Of
  TB_AREA, TB_PHA, TB_SOL, TB_GRA, TB_UNIT, TB_PREV, TB_NEXT: TBEnabled := NRes > 0;
 Else TBEnabled := True;
 End;
End;

Procedure DrawToolbar;
Var I, Y1, Y2: Integer; Pr: Boolean;
Begin
 Y1 := MENUBAR_H; Y2 := MENUBAR_H + TOOLBAR_H - 1;
 SetFillStyle(SolidFill, LightGray);
 Bar(0, Y1, ScreenWidth - 1, Y2);
 SetColor(DarkGray);
 Line(0, Y2, ScreenWidth - 1, Y2);
 SetTextStyle(DefaultFont, HorizDir, 1);
 For I := 0 To NTB - 1 Do Begin
  Pr := (TBId[I] = TB_UNIT) And Not MassMode;
  If Pr Then SetFillStyle(SolidFill, LightCyan) Else SetFillStyle(SolidFill, LightGray);
  Bar(TBX1[I], Y1 + 2, TBX2[I], Y2 - 2);
  Bevel(TBX1[I], Y1 + 2, TBX2[I], Y2 - 2, Pr);
  If TBEnabled(TBId[I]) Then SetColor(Black) Else SetColor(DarkGray);
  OutTextXY(TBX1[I] + 4, Y1 + 8, TBCap[I]);
 End;
End;

{ --------------------------------------------------------------------- }
{ Graphique principal : assemblage de phases empile                       }
{ --------------------------------------------------------------------- }

Function ProcName(K: Integer): String;
Begin
 Case K Of
  PR_EQ: ProcName := 'Equilibre';
  PR_HYD: ProcName := 'Hydratation';
  PR_MIX: ProcName := 'Melange';
  PR_LEACH: ProcName := 'Lixiviation';
  PR_CARB: ProcName := 'Carbonatation';
  PR_SALT: ProcName := 'Sels';
 Else ProcName := '';
 End;
End;

{ l'eau libre n'est pas tracee quand la solution est renouvelee a chaque pas }
Function WaterShown: Boolean;
Begin
 WaterShown := (ResKind <> PR_LEACH) And (ResKind <> PR_SALT);
End;

Function BarX(I: Integer): Integer;
Begin
 If NBar <= 1 Then BarX := StackX0
 Else BarX := StackX0 + (I * (StackX1 - StackX0 + 1)) Div NBar;
End;

Procedure DrawStack;
Var
 I, K, C, X1, X2, Y, YA, YB: Integer; Tot, Mx, YLo, YHi, YSt, Acc: Real;
 Cl : Array[0..11] Of Real;
 S, Lab: String;

 Function YP(Vv: Real): Integer;
 Begin
  YP := StackY1 - Round((Vv - YLo) / (YHi - YLo) * (StackY1 - StackY0));
 End;

Begin
 SetFillStyle(SolidFill, White);
 Bar(VX0, VY0, VX1, VY1);
 Bevel(VX0 - 1, VY0 - 1, VX1 + 1, VY1 + 1, True);
 SetTextStyle(DefaultFont, HorizDir, 1);
 If NRes < 1 Then Begin
  SetColor(Blue);
  OutTextXY(VX0 + 14, VY0 + 14, 'CEMGEMS - modelisation thermodynamique');
  OutTextXY(VX0 + 14, VY0 + 26, 'des materiaux cimentaires (clone)');
  SetColor(DarkGray);
  Line(VX0 + 14, VY0 + 40, VX1 - 14, VY0 + 40);
  SetColor(Black);
  OutTextXY(VX0 + 14, VY0 + 54, 'Marche a suivre :');
  OutTextXY(VX0 + 14, VY0 + 70, ' 1. Recette > Formulation, Ciment, Ajouts');
  OutTextXY(VX0 + 14, VY0 + 82, ' 2. Processus > Hydratation (F6) ou Equilibre');
  OutTextXY(VX0 + 14, VY0 + 94, '    (F5), Lixiviation, Carbonatation, Sels');
  OutTextXY(VX0 + 14, VY0 + 106, ' 3. Resultats > Phases, Solution, Graphiques');
  SetColor(DarkGray);
  OutTextXY(VX0 + 14, VY0 + 130, 'Raccourcis :');
  OutTextXY(VX0 + 14, VY0 + 142, ' F2 formulation  F5 equilibre  F6 hydratation');
  OutTextXY(VX0 + 14, VY0 + 154, ' F3 phases  F4 solution  F7 graphiques');
  OutTextXY(VX0 + 14, VY0 + 166, ' Gauche/Droite  etape precedente / suivante');
  OutTextXY(VX0 + 14, VY0 + 178, ' F10 menus   F1 aide   Alt+X quitter');
  SetColor(Blue);
  OutTextXY(VX0 + 14, VY1 - 22, 'Moteur : minimisation de l''energie libre de');
  OutTextXY(VX0 + 14, VY1 - 12, 'Gibbs (points interieurs), base type Cemdata18');
  Exit;
 End;
 NBar := NRes;
 StackX0 := VX0 + 50; StackX1 := VX1 - 8;
 StackY0 := VY0 + 22; StackY1 := VY1 - 28;
 { hauteurs }
 Mx := 0;
 For I := 0 To NRes - 1 Do Begin
  Tot := 0;
  For K := 0 To NIT - 1 Do Tot := Tot + ItemVal(I, K, MassMode);
  If WaterShown Then Begin
   If MassMode Then Tot := Tot + Res^[I][RI_WF] Else Tot := Tot + Res^[I][RI_VW];
  End;
  If Tot > Mx Then Mx := Tot;
 End;
 If Mx <= 0 Then Mx := 1;
 NiceRange(0, Mx, YLo, YHi, YSt);
 If YHi <= YLo Then YHi := YLo + 1;
 SetColor(Black);
 If MassMode Then Lab := 'g / 100 g' Else Lab := 'cm3 / 100 g';
 OutTextXY(VX0 + 6, VY0 + 5, Copy(ResTitle, 1, 36) + ' - ' + Lab);
 { echelle verticale }
 Acc := YLo;
 While Acc <= YHi + YSt * 0.001 Do Begin
  Y := YP(Acc);
  SetColor(LightGray); Line(StackX0, Y, StackX1, Y);
  SetColor(Black); Line(StackX0 - 3, Y, StackX0, Y);
  S := RTrim(Acc, 2);
  OutTextXY(StackX0 - 6 - 8 * Length(S), Y - 3, S);
  Acc := Acc + YSt;
 End;
 { barres }
 For I := 0 To NRes - 1 Do Begin
  X1 := BarX(I);
  If NBar <= 1 Then X2 := StackX1 Else X2 := BarX(I + 1) - 2;
  If X2 < X1 Then X2 := X1;
  For C := 0 To 11 Do Cl[C] := 0;
  For K := 0 To NIT - 1 Do Cl[ItemClass(K)] := Cl[ItemClass(K)] + ItemVal(I, K, MassMode);
  If Not WaterShown Then Cl[11] := 0
  Else If MassMode Then Cl[11] := Res^[I][RI_WF] Else Cl[11] := Res^[I][RI_VW];
  Acc := 0;
  For C := 0 To 11 Do Begin
   If Cl[C] > 0 Then Begin
    YA := YP(Acc + Cl[C]); YB := YP(Acc);
    If YB - YA >= 1 Then Begin
     SetFillStyle(SolidFill, ClsCol[C]);
     Bar(X1, YA, X2, YB - 1);
    End;
    Acc := Acc + Cl[C];
   End;
  End;
  If I = CurStep Then Begin
   SetColor(Black);
   Rectangle(X1 - 1, YP(Acc) - 1, X2 + 1, StackY1 + 1);
   SetColor(Red);
   Line(X1, StackY1 + 5, X2, StackY1 + 5);
  End;
 End;
 SetColor(Black);
 Rectangle(StackX0, StackY0, StackX1, StackY1);
 { echelle horizontale }
 S := RTrim(ResX[0], 3);
 OutTextXY(StackX0, StackY1 + 8, S);
 If NRes > 2 Then Begin
  S := RTrim(ResX[NRes Div 2], 3);
  OutTextXY((StackX0 + StackX1) Div 2 - 4 * Length(S), StackY1 + 8, S);
 End;
 If NRes > 1 Then Begin
  S := RTrim(ResX[NRes - 1], 3);
  OutTextXY(StackX1 - 8 * Length(S), StackY1 + 8, S);
 End;
 SetColor(Blue);
 S := Copy(ResXLab, 1, 30);
 OutTextXY((StackX0 + StackX1) Div 2 - 4 * Length(S), StackY1 + 18, S);
End;

{ --------------------------------------------------------------------- }
{ Panneau de gauche : recette et solution interstitielle                 }
{ --------------------------------------------------------------------- }

Procedure DrawLeftPanel;
Var Y, I: Integer; Cp: Real; Row: ^TRow;

 Procedure PLn(Const A, B: String);
 Begin
  SetColor(DarkGray); OutTextXY(LPX + 6, Y, A);
  SetColor(Black); OutTextXY(LPX + 6 + 8 * 12, Y, Copy(B, 1, 12));
  Y := Y + 10;
 End;

 Procedure Title(Const T: String);
 Begin
  SetFillStyle(SolidFill, Blue);
  Bar(LPX, Y, LPX + LPW - 2, Y + 11);
  SetColor(White);
  OutTextXY(LPX + 4, Y + 2, T);
  Y := Y + 15;
 End;

Begin
 SetFillStyle(SolidFill, White);
 Bar(LPX, VY0, LPX + LPW - 2, ScreenHeight - STATUS_H - 8);
 Bevel(LPX - 1, VY0 - 1, LPX + LPW - 1, ScreenHeight - STATUS_H - 7, True);
 SetTextStyle(DefaultFont, HorizDir, 1);
 Y := VY0;
 Title('Recette');
 PLn('Ciment', Copy(Cem.Name, 1, 12));
 Cp := CementFrac;
 PLn('  part', RStr(Cp, 1) + ' %');
 For I := 0 To NSC - 1 Do
  If SFrac[I] > 0 Then PLn(Copy(SCNames[I], 1, 10), RStr(SFrac[I], 1) + ' %');
 PLn('Eau/liant', RStr(WB, 3));
 PLn('Temperature', RStr(TempC, 1) + ' C');
 PLn('Age', RTrim(AgeD, 1) + ' j');
 Y := Y + 3;
 Title('Processus');
 If NRes > 0 Then Begin
  PLn('Type', ProcName(ResKind));
  PLn('Etapes', IStr(NRes));
  If CurStep >= NRes Then CurStep := NRes - 1;
  PLn('Etape', IStr(CurStep + 1) + ' / ' + IStr(NRes));
  PLn('x', RTrim(ResX[CurStep], 3));
  If ResStat[CurStep] = 1 Then PLn('Etat', 'approche')
  Else If ResStat[CurStep] = 2 Then PLn('Etat', 'eau epuisee')
  Else If ResStat[CurStep] = 3 Then PLn('Etat', 'eau limite')
  Else PLn('Etat', 'converge');
  Y := Y + 3;
  Title('Solution interstitielle');
  Row := @Res^[CurStep];
  PLn('pH', RStr(Row^[RI_PH], 2));
  PLn('Force ion.', RStr(Row^[RI_ION], 3) + ' M');
  PLn('Eau libre', RStr(Row^[RI_WF], 1) + ' g');
  PLn('Porosite', RStr(Row^[RI_POR], 1) + ' %');
  PLn('Conduct.', RStr(Row^[RI_COND], 2) + ' S/m');
  PLn('Ca (mM)', RStr(Row^[RI_EL + 0], 2));
  PLn('Si (mM)', RStr(Row^[RI_EL + 1], 3));
  PLn('Al (mM)', RStr(Row^[RI_EL + 2], 3));
  PLn('S (mM)', RStr(Row^[RI_EL + 4], 2));
  PLn('K (mM)', RStr(Row^[RI_EL + 5], 1));
  PLn('Na (mM)', RStr(Row^[RI_EL + 6], 1));
  PLn('C (mM)', RStr(Row^[RI_EL + 8], 3));
  PLn('Cl (mM)', RStr(Row^[RI_EL + 9], 1));
  If Row^[RI_CS] > 0 Then PLn('Ca/Si CSH', RStr(Row^[RI_CS], 2));
  If ResKind = PR_HYD Then PLn('Chaleur', RStr(Row^[RI_HEAT], 0) + ' J/g');
 End
 Else Begin
  SetColor(DarkGray);
  OutTextXY(LPX + 6, Y, 'Aucun resultat.'); Y := Y + 10;
  OutTextXY(LPX + 6, Y, 'Lancer un processus.');
 End;
End;

{ --------------------------------------------------------------------- }
{ Liste des phases de l'etape courante                                   }
{ --------------------------------------------------------------------- }

Procedure DrawPhaseList;
Var X0, Y0, K, C, N, Col, Row: Integer; V: Real; S: String;
Begin
 X0 := VX0; Y0 := VY1 + 6;
 SetFillStyle(SolidFill, White);
 Bar(VX0, Y0, VX1, ScreenHeight - STATUS_H - 8);
 Bevel(VX0 - 1, Y0 - 1, VX1 + 1, ScreenHeight - STATUS_H - 7, True);
 SetFillStyle(SolidFill, Blue);
 Bar(VX0, Y0, VX1, Y0 + 11);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetColor(White);
 If NRes < 1 Then Begin
  OutTextXY(VX0 + 4, Y0 + 2, 'Assemblage de phases');
  Exit;
 End;
 If MassMode Then S := 'g/100 g liant' Else S := 'cm3/100 g liant';
 OutTextXY(VX0 + 4, Y0 + 2, 'Assemblage de phases (' + S + ') - etape ' + IStr(CurStep + 1));
 N := 0;
 For K := 0 To NIT - 1 Do Begin
  V := ItemVal(CurStep, K, MassMode);
  If V >= 0.005 Then Begin
   Col := N Div 14; Row := N Mod 14;
   If Col < 2 Then Begin
    C := ItemClass(K);
    SetFillStyle(SolidFill, ClsCol[C]);
    Bar(X0 + 4 + Col * 210, Y0 + 15 + Row * 10, X0 + 12 + Col * 210, Y0 + 22 + Row * 10);
    SetColor(Black);
    Rectangle(X0 + 4 + Col * 210, Y0 + 15 + Row * 10, X0 + 12 + Col * 210, Y0 + 22 + Row * 10);
    OutTextXY(X0 + 16 + Col * 210, Y0 + 15 + Row * 10, PadR(ItemName(K), 16));
    OutTextXY(X0 + 16 + Col * 210 + 8 * 16, Y0 + 15 + Row * 10, PadL(RStr(V, 2), 7));
   End;
   Inc(N);
  End;
 End;
End;

{ --------------------------------------------------------------------- }
{ Barre d'etat                                                           }
{ --------------------------------------------------------------------- }

Procedure DrawStatusBar;
Var Y, W, MaxC: Integer; S, PN: String;
Begin
 Y := ScreenHeight - STATUS_H;
 SetFillStyle(SolidFill, LightGray);
 Bar(0, Y, ScreenWidth - 1, ScreenHeight - 1);
 SetColor(DarkGray);
 Line(0, Y, ScreenWidth - 1, Y);
 SetTextStyle(DefaultFont, HorizDir, 1);
 SetColor(Black);
 PN := BaseName(ProjName);
 If PN = '' Then PN := '(sans nom)';
 If Modified Then PN := PN + ' *';
 S := StatusMsg;
 If ProgPct >= 0 Then MaxC := (ScreenWidth - 170) Div 8
 Else MaxC := (ScreenWidth - 8 * Length(PN) - 24) Div 8;
 OutTextXY(6, Y + 5, Copy(S, 1, MaxC));
 If ProgPct >= 0 Then Begin
  W := 150;
  SetFillStyle(SolidFill, White);
  Bar(ScreenWidth - W - 8, Y + 4, ScreenWidth - 8, Y + STATUS_H - 4);
  SetFillStyle(SolidFill, Blue);
  If ProgPct > 100 Then ProgPct := 100;
  Bar(ScreenWidth - W - 8, Y + 4, ScreenWidth - W - 8 + (W * ProgPct) Div 100, Y + STATUS_H - 4);
  SetColor(Black);
  Rectangle(ScreenWidth - W - 8, Y + 4, ScreenWidth - 8, Y + STATUS_H - 4);
 End
 Else Begin
  SetColor(Blue);
  OutTextXY(ScreenWidth - 8 * Length(PN) - 8, Y + 5, PN);
 End;
End;

Procedure ShowProgress(Const Msg: String; Pct: Integer);
Var K: Char; T: LongInt;
Begin
 If BatchMode Then Exit;
 If KeyPressed Then Begin
  K := ReadKey;
  If K = #27 Then UserAbort := True
  Else If K = #0 Then If KeyPressed Then K := ReadKey;
 End;
 T := NowMs;
 If (Pct < 100) And (Abs(T - LastShowT) < 60) Then Exit;
 LastShowT := T;
 StatusMsg := Msg;
 ProgPct := Pct;
 HideMouseCursor;
 DrawStatusBar;
 ShowMouseCursor;
End;

Procedure RedrawAll;
Begin
 HideMouseCursor;
 SetFillStyle(SolidFill, LightGray);
 Bar(0, MENUBAR_H + TOOLBAR_H, ScreenWidth - 1, ScreenHeight - 1);
 DrawLeftPanel;
 DrawStack;
 DrawPhaseList;
 DrawToolbar;
 DrawStatusBar;
 DrawMenuBar;
 If MenuActive Then DrawMenuPopup(ActiveMenu);
 ShowMouseCursor;
 NeedRedraw := False;
End;

{ --------------------------------------------------------------------- }
{ Dialogues : recette                                                    }
{ --------------------------------------------------------------------- }

Procedure CementDialog;
Var I, Sel: Integer; Sum: Real; Done: Boolean;
Begin
 Done := False;
 While Not Done Do Begin
  Sum := 0;
  For I := 0 To NCP - 1 Do Sum := Sum + Cem.P[I];
  PReset;
  PAddE('Modele de la bibliotheque', 0, '(valeurs actuelles)|CEM I 42.5 N (type)|CEM I 52.5 R|' +
        'CEM I 42.5 HS (C3A bas)|Ciment blanc|CEM I 42.5 R alcalin');
  PAddH('Composition (% massique)');
  For I := 0 To NCP - 1 Do PAddR(CPNames[I], Cem.P[I], 0, 100, 2);
  PAddT('Somme (reste = inerte)', RStr(Sum, 2) + ' %');
  If Not ParamDialog('Recette : ciment - ' + Cem.Name, 'Choisir un modele puis OK pour le charger') Then Exit;
  Sel := PInt(0);
  If Sel > 0 Then Begin
   DefaultCement(Sel - 1);
   StatusMsg := 'Ciment charge : ' + Cem.Name;
   Modified := True; KinValid := False;
  End
  Else Begin
   Sum := 0;
   For I := 0 To NCP - 1 Do Begin Cem.P[I] := PVal[2 + I]; Sum := Sum + Cem.P[I]; End;
   If Sum > 100 Then
    For I := 0 To NCP - 1 Do Cem.P[I] := Cem.P[I] * 100 / Sum;
   Cem.Name := 'Ciment personnalise';
   Modified := True; KinValid := False;
   Done := True;
  End;
 End;
End;

Procedure ScmDialog(K: Integer);
Var Sel, J: Integer; Done: Boolean; S: Real; Enm: String;
Begin
 Done := False;
 While Not Done Do Begin
  S := 0;
  For J := 0 To NOX - 1 Do S := S + Scm[K].Ox[J];
  PReset;
  If K = 0 Then Enm := '(valeurs actuelles)|Cendre volante classe F|Cendre volante classe C'
  Else Enm := '(valeurs actuelles)|Modele standard';
  PAddE('Modele de la bibliotheque', 0, Enm);
  PAddH('Composition (% massique)');
  For J := 0 To NOX - 1 Do PAddR(OXNames[J], Scm[K].Ox[J], 0, 100, 2);
  PAddH('Reaction');
  PAddR('Masse volumique (g/cm3)', Scm[K].Rho, 1, 5, 3);
  PAddR('Degre de reaction maximal', Scm[K].AMax, 0, 1, 2);
  PAddR('Temps caracteristique (j)', Scm[K].Tau, 0.1, 5000, 1);
  PAddR('Exposant n (loi exponentielle)', Scm[K].Nexp, 0.1, 3, 2);
  PAddR('Energie d''activation (kJ/mol)', Scm[K].Ea, 0, 100, 1);
  PAddT('Somme des oxydes', RStr(S, 2) + ' %');
  If Not ParamDialog('Recette : ' + SCNames[K] + ' - ' + Scm[K].Name,
                     'alpha(t) = amax (1 - exp(-(t / tau)^n))') Then Exit;
  Sel := PInt(0);
  If Sel > 0 Then Begin
   DefaultScm(K, Sel - 1);
   Modified := True; KinValid := False;
  End
  Else Begin
   For J := 0 To NOX - 1 Do Scm[K].Ox[J] := PVal[2 + J];
   Scm[K].Rho := PVal[12]; Scm[K].AMax := PVal[13]; Scm[K].Tau := PVal[14];
   Scm[K].Nexp := PVal[15]; Scm[K].Ea := PVal[16];
   Modified := True; KinValid := False;
   Done := True;
  End;
 End;
End;

Procedure FormDialog;
Var I: Integer; S: Real;
Begin
 PReset;
 PAddR('Rapport eau / liant (E/L)', WB, 0.15, 3, 3);
 PAddR('Temperature (C)', TempC, 0, 80, 1);
 PAddR('Age du materiau (jours)', AgeD, 0.01, 10000, 2);
 PAddH('Ajouts cimentaires (% massique du liant)');
 For I := 0 To NSC - 1 Do PAddR(SCNames[I], SFrac[I], 0, 95, 1);
 PAddH('Fixation des alcalis (Rd a Ca/Si = 1, pH 13,5, L/kg)');
 PAddR('Potassium', AdsK, 0, 5, 3);
 PAddR('Sodium', AdsNa, 0, 5, 3);
 If ParamDialog('Recette : formulation', 'Le reste du liant est du ciment') Then Begin
  WB := PVal[0]; TempC := PVal[1]; AgeD := PVal[2];
  S := 0;
  For I := 0 To NSC - 1 Do S := S + PVal[4 + I];
  If S > 95 Then Begin
   ShowMessage('Formulation', 'Les ajouts ne peuvent pas depasser 95 %.|Valeurs inchangees.');
   Exit;
  End;
  For I := 0 To NSC - 1 Do SFrac[I] := PVal[4 + I];
  AdsK := PVal[10]; AdsNa := PVal[11];
  Modified := True; KinValid := False;
  StatusMsg := 'Formulation mise a jour';
 End;
End;

Procedure PKDialog;
Var Sel, J: Integer;
Begin
 TClear;
 For J := 0 To NPK - 1 Do TAdd(PKNames[J]);
 TAdd('Periclase (MgO) : temps caracteristique');
 Sel := ListDialog('Cinetique de Parrot-Killoh', True);
 If Sel < 0 Then Exit;
 If Sel = NPK Then Begin
  PReset;
  PAddR('Temps caracteristique de MgO (j)', MgTau, 1, 10000, 1);
  If ParamDialog('Periclase', 'alpha = 1 - exp(-t / tau)') Then Begin
   MgTau := PVal[0]; Modified := True; KinValid := False;
  End;
  Exit;
 End;
 PReset;
 PAddR('K1 (nucleation-croissance, 1/j)', PK[Sel, 0], 0.001, 10, 4);
 PAddR('N1', PK[Sel, 1], 0.1, 5, 3);
 PAddR('K2 (diffusion, 0 = inactif)', PK[Sel, 2], 0, 5, 4);
 PAddR('K3 (epaisseur de gel, 1/j)', PK[Sel, 3], 0.0001, 10, 4);
 PAddR('N3', PK[Sel, 4], 0.5, 10, 2);
 PAddR('H (eau / ciment de reaction totale)', PK[Sel, 5], 0.5, 3, 2);
 PAddR('Ea (kJ/mol)', PK[Sel, 6] / 1000.0, 0, 100, 2);
 If ParamDialog('Parrot-Killoh : ' + PKNames[Sel],
                'R = min(R1 nucleation, R2 diffusion, R3 gel) x f(E/C) x Arrhenius') Then Begin
  PK[Sel, 0] := PVal[0]; PK[Sel, 1] := PVal[1]; PK[Sel, 2] := PVal[2];
  PK[Sel, 3] := PVal[3]; PK[Sel, 4] := PVal[4]; PK[Sel, 5] := PVal[5];
  PK[Sel, 6] := PVal[6] * 1000.0;
  Modified := True; KinValid := False;
 End;
End;

{ --------------------------------------------------------------------- }
{ Lancement des processus                                                 }
{ --------------------------------------------------------------------- }

Procedure AfterRun;
Begin
 ProgPct := -1;
 If NRes > 0 Then CurStep := NRes - 1 Else CurStep := 0;
 If UserAbort Then StatusMsg := 'Calcul interrompu apres ' + IStr(NRes) + ' etapes'
 Else StatusMsg := ProcName(ResKind) + ' : ' + IStr(NRes) + ' etape(s) calculee(s)';
 NeedRedraw := True;
End;

Procedure DoEquilibrium;
Begin
 ProcSel := PR_EQ;
 StatusMsg := 'Calcul de l''equilibre...';
 RunEquilibrium;
 AfterRun;
End;

Procedure DoHydration;
Begin
 PReset;
 PAddI('Nombre d''etapes', HydN, 2, MAXSTEP);
 PAddR('Age initial (jours)', HydT0, 0.01, 100, 2);
 PAddR('Age final (jours)', HydT1, 0.1, 10000, 1);
 If Not ParamDialog('Processus : hydratation', 'Equilibre a chaque age (Parrot-Killoh)') Then Exit;
 HydN := PInt(0); HydT0 := PVal[1]; HydT1 := PVal[2];
 If HydT1 <= HydT0 * 1.5 Then HydT1 := HydT0 * 2;
 ProcSel := PR_HYD;
 RunHydration;
 AfterRun;
End;

Procedure DoMix;
Var Enm: String; I: Integer;
Begin
 Enm := 'Rapport eau / liant';
 For I := 0 To NSC - 1 Do Enm := Enm + '|' + SCNames[I] + ' (%)';
 PReset;
 PAddE('Variable balayee', MixVar, Enm);
 PAddR('Valeur initiale', MixV0, 0, 95, 3);
 PAddR('Valeur finale', MixV1, 0, 95, 3);
 PAddI('Nombre d''etapes', MixN, 2, MAXSTEP);
 If Not ParamDialog('Processus : melange (balayage)', 'Equilibre a l''age de la formulation') Then Exit;
 MixVar := PInt(0); MixV0 := PVal[1]; MixV1 := PVal[2]; MixN := PInt(3);
 If (MixVar = 0) And ((MixV0 < 0.15) Or (MixV1 < 0.15)) Then Begin
  ShowMessage('Melange', 'Le rapport eau / liant doit etre >= 0,15.'); Exit;
 End;
 ProcSel := PR_MIX;
 RunMix;
 AfterRun;
End;

Procedure DoRenewal(Kind: Integer);
Var I: Integer; Sv: Array[0..6] Of Real;
Begin
 PReset;
 PAddR('Solution ajoutee par etape (g/100 g liant)', ExtVol, 10, 5000, 0);
 PAddI('Nombre d''etapes', ExtN, 2, MAXSTEP - 1);
 If Kind = PR_SALT Then Begin
  PAddH('Solution externe (mmol/L)');
  PAddR('NaCl', ExtSalt[0], 0, 5000, 1);
  PAddR('Na2SO4', ExtSalt[1], 0, 2000, 1);
  PAddR('MgSO4', ExtSalt[2], 0, 2000, 1);
  PAddR('MgCl2', ExtSalt[3], 0, 2000, 1);
  PAddR('CaCl2', ExtSalt[4], 0, 2000, 1);
  PAddR('Na2CO3', ExtSalt[5], 0, 2000, 1);
  PAddR('NaOH', ExtSalt[6], 0, 5000, 1);
  If Not ParamDialog('Processus : penetration de sels', 'Renouvellement par une solution saline') Then Exit;
 End
 Else If Not ParamDialog('Processus : lixiviation', 'Renouvellement de la solution par de l''eau pure') Then Exit;
 ExtVol := PVal[0]; ExtN := PInt(1);
 For I := 0 To 6 Do Sv[I] := ExtSalt[I];
 If Kind = PR_SALT Then Begin
  For I := 0 To 6 Do ExtSalt[I] := PVal[3 + I];
  For I := 0 To 6 Do Sv[I] := ExtSalt[I];
 End
 Else For I := 0 To 6 Do ExtSalt[I] := 0;
 ProcSel := Kind;
 RunRenewal(Kind);
 For I := 0 To 6 Do ExtSalt[I] := Sv[I];
 AfterRun;
End;

Procedure DoCarbonation;
Begin
 PReset;
 PAddR('CO2 total ajoute (g / 100 g liant)', CarbMax, 1, 100, 1);
 PAddI('Nombre d''etapes', CarbN, 2, MAXSTEP - 1);
 If Not ParamDialog('Processus : carbonatation', 'Ajout progressif de CO2 au systeme ferme') Then Exit;
 CarbMax := PVal[0]; CarbN := PInt(1);
 ProcSel := PR_CARB;
 RunCarbonation;
 AfterRun;
End;

Procedure RunSelected;
Begin
 Case ProcSel Of
  PR_EQ: DoEquilibrium;
  PR_MIX: DoMix;
  PR_LEACH, PR_SALT: DoRenewal(ProcSel);
  PR_CARB: DoCarbonation;
 Else DoHydration;
 End;
End;

{ --------------------------------------------------------------------- }
{ Tableaux                                                                }
{ --------------------------------------------------------------------- }

Function NeedResults: Boolean;
Begin
 NeedResults := NRes > 0;
 If NRes <= 0 Then ShowMessage('Resultats', 'Aucun resultat : lancer d''abord un processus|(menu Processus).');
End;

Procedure ShowPhaseTable;
Var K: Integer; V, M, Vt, Mt: Real; Row: ^TRow; S: String;
Begin
 If Not NeedResults Then Exit;
 Row := @Res^[CurStep];
 TClear;
 TAdd(ProcName(ResKind) + ' : etape ' + IStr(CurStep + 1) + ' / ' + IStr(NRes) + '   x = ' + RTrim(ResX[CurStep], 3));
 TAdd('(quantites pour 100 g de liant anhydre)');
 TAdd('');
 TAdd('Phase                   Masse (g)  Volume (cm3)  Vol. (%)');
 TAdd('--------------------------------------------------------');
 Vt := Row^[RI_VT]; Mt := 0;
 For K := 0 To NIT - 1 Do Begin
  M := ItemVal(CurStep, K, True); V := ItemVal(CurStep, K, False);
  If (M >= 0.0005) Or (V >= 0.0005) Then Begin
   Mt := Mt + M;
   If Vt > 0 Then S := RStr(100.0 * V / Vt, 2) Else S := '0';
   TAdd(PadR(ItemName(K), 22) + PadL(RStr(M, 3), 10) + PadL(RStr(V, 3), 13) + PadL(S, 10));
  End;
 End;
 TAdd('--------------------------------------------------------');
 TAdd(PadR('Eau libre (solution)', 22) + PadL(RStr(Row^[RI_WF], 3), 10) + PadL(RStr(Row^[RI_VW], 3), 13) +
      PadL(RStr(100.0 * Row^[RI_VW] / RMax(Vt, 1E-9), 2), 10));
 TAdd(PadR('Volume total', 22) + PadL('', 10) + PadL(RStr(Vt, 3), 13));
 TAdd('');
 TAdd('Porosite (eau libre)    : ' + RStr(Row^[RI_POR], 2) + ' %');
 If Row^[RI_CS] > 0 Then TAdd('Ca/Si du C-S-H         : ' + RStr(Row^[RI_CS], 3));
 If ResKind = PR_HYD Then Begin
  TAdd('Chaleur du clinker      : ' + RStr(Row^[RI_HEAT], 1) + ' J/g de liant');
  TAdd('Degres de reaction      : C3S ' + RStr(Row^[RI_AL], 2) + '  C2S ' + RStr(Row^[RI_AL + 1], 2) +
       '  C3A ' + RStr(Row^[RI_AL + 2], 2) + '  C4AF ' + RStr(Row^[RI_AL + 3], 2));
 End;
 TView('Assemblage de phases');
End;

Procedure ShowSolution;
Var I, K: Integer; Row: ^TRow; V: Real;
Begin
 If Not NeedResults Then Exit;
 Row := @Res^[CurStep];
 TClear;
 TAdd('Solution interstitielle - etape ' + IStr(CurStep + 1) + ' / ' + IStr(NRes) + '   x = ' + RTrim(ResX[CurStep], 3));
 TAdd('');
 TAdd('pH                         ' + RStr(Row^[RI_PH], 3));
 TAdd('Force ionique              ' + RStr(Row^[RI_ION], 4) + ' mol/kg');
 TAdd('Eau libre                  ' + RStr(Row^[RI_WF], 3) + ' g / 100 g de liant');
 TAdd('Conductivite estimee       ' + RStr(Row^[RI_COND], 3) + ' S/m');
 TAdd('');
 TAdd('Concentrations totales (mmol/kg d''eau)');
 TAdd('------------------------------------------');
 For K := 0 To 9 Do
  TAdd(PadR(MName[C_CA + K], 10) + PadL(RStr(Row^[RI_EL + K], 5), 14));
 TAdd('');
 TAdd('Especes aqueuses (mmol/kg d''eau)');
 TAdd('------------------------------------------');
 For I := 0 To NSpReal - 1 Do Begin
  V := Spc^[CurStep][I];
  If V >= 0.00001 Then TAdd(PadR(SpName[I], 12) + PadL(RStr(V, 6), 16));
 End;
 TAdd('');
 TAdd('Alcalis fixes sur le C-S-H (mmol / 100 g de liant)');
 TAdd('------------------------------------------');
 TAdd(PadR('K+', 12) + PadL(RStr(Spc^[CurStep][NSpReal], 4), 16));
 TAdd(PadR('Na+', 12) + PadL(RStr(Spc^[CurStep][NSpReal + 1], 4), 16));
 TView('Solution interstitielle');
End;

Procedure ShowStepsTable;
Var I: Integer; Row: ^TRow;
Begin
 If Not NeedResults Then Exit;
 TClear;
 TAdd(ResTitle);
 TAdd('');
 TAdd('  x         pH    I(M)   Por%  CSH    CH    AFt   AFm   Cal   Eau');
 TAdd('---------------------------------------------------------------------');
 For I := 0 To NRes - 1 Do Begin
  Row := @Res^[I];
  TAdd(PadL(RTrim(ResX[I], 2), 8) + PadL(RStr(Row^[RI_PH], 2), 7) + PadL(RStr(Row^[RI_ION], 3), 7) +
       PadL(RStr(Row^[RI_POR], 1), 6) + PadL(RStr(Row^[RI_M + PH_CSH], 1), 6) +
       PadL(RStr(Row^[RI_M + PH_CH], 1), 6) +
       PadL(RStr(Row^[RI_M + PH_AFT] + Row^[RI_M + PH_FAFT], 1), 6) +
       PadL(RStr(Row^[RI_M + PH_MS] + Row^[RI_M + PH_MC] + Row^[RI_M + PH_HC] + Row^[RI_M + PH_FR], 1), 6) +
       PadL(RStr(Row^[RI_M + PH_CAL], 1), 6) + PadL(RStr(Row^[RI_WF], 1), 6));
 End;
 TAdd('');
 TAdd('Masses en g pour 100 g de liant ; AFm = mono/hemicarbonate, monosulfate, Friedel.');
 TView('Tableau des etapes');
End;

Procedure ShowOxides;
Var J, K, I: Integer; Ct, St: Array[0..NOX-1] Of Real; MC, Mr: Real;
Begin
 For J := 0 To NOX - 1 Do Begin Ct[J] := 0; St[J] := 0; End;
 MC := CementFrac;
 For K := 0 To NCP - 1 Do Begin
  Mr := MC * Cem.P[K] / 100.0;
  For J := 0 To NOX - 1 Do Ct[J] := Ct[J] + Mr / CPMass[K] * CPOx[K, J] * OXMass[J];
 End;
 For I := 0 To NSC - 1 Do
  For J := 0 To NOX - 1 Do St[J] := St[J] + Scm[I].Ox[J] / 100.0 * SFrac[I];
 TClear;
 TAdd('Bilan d''oxydes de la recette (g pour 100 g de liant anhydre)');
 TAdd('');
 TAdd('Oxyde     Ciment    Ajouts     Total');
 TAdd('---------------------------------------');
 For J := 0 To NOX - 1 Do
  TAdd(PadR(OXNames[J], 8) + PadL(RStr(Ct[J], 2), 9) + PadL(RStr(St[J], 2), 10) + PadL(RStr(Ct[J] + St[J], 2), 10));
 TAdd('');
 TAdd('Eau : ' + RStr(WB * 100, 1) + ' g   (E/L = ' + RStr(WB, 3) + ')');
 TAdd('Ciment : ' + Cem.Name + ' (' + RStr(MC, 1) + ' %)');
 TAdd('');
 TAdd('K2O + Na2O dans le ciment : seuls les alcalis facilement solubles');
 TAdd('(sulfates alcalins, K2O et Na2O libres) sont pris en compte.');
 TView('Bilan d''oxydes');
End;

Procedure ShowPhaseDB;
Var E: Integer;
Begin
 TClear;
 TAdd('Phases solides (25 C, forme Cemdata : Ca2+, OH-, H4SiO4, Al(OH)4-...)');
 TAdd('');
 TAdd('Pole                  logKsp   M (g/mol)  V (cm3/mol)');
 TAdd('-----------------------------------------------------');
 For E := 0 To NEm - 1 Do
  TAdd(PadR(EmName[E], 18) + PadL(RStr(EmLK25[E] / LN10 + 14.0 * EmNu[E, C_H], 2), 9) +
       PadL(RStr(EmMW[E], 1), 11) + PadL(RStr(EmV[E], 1), 12));
 TAdd('');
 TAdd('Le C-S-H est une solution solide ideale de quatre poles (type CSHQ).');
 TView('Base de donnees : phases');
End;

Procedure ShowSpeciesDB;
Var I: Integer;
Begin
 TClear;
 TAdd('Composants : ' + MName[0] + ' ' + MName[1] + ' ' + MName[2] + ' ' + MName[3] + ' ' + MName[4]);
 TAdd('             ' + MName[5] + ' ' + MName[6] + ' ' + MName[7] + ' ' + MName[8] + ' ' + MName[9] + ' ' +
      MName[10] + ' ' + MName[11]);
 TAdd('');
 TAdd('Especes aqueuses (formation a partir des composants, 25 C)');
 TAdd('Espece        Charge   logK');
 TAdd('--------------------------------');
 For I := 0 To NSp - 1 Do
  TAdd(PadR(SpName[I], 14) + PadL(IStr(SpZ[I]), 4) + PadL(RStr(SpLK25[I] / LN10, 2), 10));
 TAdd('');
 TAdd('Activites : Truesdell-Jones (a = 3,31 A, b = 0,123), a(H2O) par la');
 TAdd('molalite totale, especes neutres : log gamma = 0,1 I.');
 TView('Base de donnees : especes aqueuses');
End;

{ --------------------------------------------------------------------- }
{ Graphiques                                                              }
{ --------------------------------------------------------------------- }

Procedure GraphItems(Mass: Boolean);
Var I, K, S, B: Integer; Mx: Array[0..NIT-1] Of Real; Used: Array[0..NIT-1] Of Boolean; Best: Real;
Begin
 If Mass Then
  ChartReset('Assemblage de phases', ResXLab, 'g pour 100 g de liant', ResLogX)
 Else ChartReset('Assemblage de phases', ResXLab, 'cm3 pour 100 g de liant', ResLogX);
 If ResLogX Then ChLogMin := 0.001;
 For K := 0 To NIT - 1 Do Begin
  Mx[K] := 0; Used[K] := False;
  For I := 0 To NRes - 1 Do If ItemVal(I, K, Mass) > Mx[K] Then Mx[K] := ItemVal(I, K, Mass);
 End;
 For S := 0 To MAXSER - 1 Do Begin
  Best := 0.005; B := -1;
  For K := 0 To NIT - 1 Do If (Not Used[K]) And (Mx[K] > Best) Then Begin Best := Mx[K]; B := K; End;
  If B < 0 Then Break;
  Used[B] := True;
  K := ChartAddSeries(ItemName(B), NRes < 4);
  For I := 0 To NRes - 1 Do ChartPoint(K, ResX[I], ItemVal(I, B, Mass));
 End;
End;

Procedure GraphColumns(Const T, YL: String; First, Cnt: Integer; Const Names: String; Scale: Real);
Var I, K, S: Integer; Mx: Real;
Begin
 ChartReset(T, ResXLab, YL, ResLogX);
 If ResLogX Then ChLogMin := 0.001;
 For K := 0 To Cnt - 1 Do Begin
  Mx := 0;
  For I := 0 To NRes - 1 Do If Abs(Res^[I][First + K]) * Scale > Mx Then Mx := Abs(Res^[I][First + K]) * Scale;
  If (Mx > 1E-6) And (ChNS < MAXSER) Then Begin
   S := ChartAddSeries(WordLine(Names, K + 1), NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][First + K] * Scale);
  End;
 End;
End;

{ --------------------------------------------------------------------- }
{ Aires empilees par phase (type GEMS-Guis)                              }
{ --------------------------------------------------------------------- }

Const
 ItemCol : Array[0..NIT-1] Of Byte = (
  10, 9, 12, 4, 11, 3, 1, 5, 13, 13, 5, 6, 6, 14, 14, 14, 15, 2, 2, 4,
  8, 2, 1, 6, 7, 3, 8, 15, 13, 7);
 StkOrder : Array[0..NIT-1] Of Byte = (
  22, 23, 21, 20, 24, 25, 26, 27, 28, 29,
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19);

Procedure StackedAreaDialog;
Const BW = 124; BH = 22;
Var
 X1, Y1, X2, Y2, PX1, PY1, PX2, PY2, BBY1, BBY2, B1, B2, B3, LX: Integer;
 N, Key, MX, MY: Integer;
 Done, Click, Areas, Redo: Boolean;
 Lst: Array[0..NIT] Of Integer;
 Mxv, Tot, V, Bot, YLo, YHi, YSt, XLo, XHi, XLoD, XHiD, F, Lv, Ac, T: Real;
 SegI: Array[0..639] Of Integer;
 SegF: Array[0..639] Of Real;
 BestA: Array[0..NIT] Of Integer;
 BestY: Array[0..NIT] Of Integer;
 S, Nm: String;
 Mass: Boolean;

 Function ValAt(It, I0: Integer; Fr: Real): Real;
 Var V0, V1: Real;
 Begin
  If It = NIT Then Begin
   If Mass Then V0 := Res^[I0][RI_WF] Else V0 := Res^[I0][RI_VW];
  End
  Else V0 := ItemVal(I0, It, Mass);
  V1 := V0;
  If (Fr <> 0) And (I0 + 1 < NRes) Then Begin
   If It = NIT Then Begin
    If Mass Then V1 := Res^[I0 + 1][RI_WF] Else V1 := Res^[I0 + 1][RI_VW];
   End
   Else V1 := ItemVal(I0 + 1, It, Mass);
  End;
  ValAt := V0 + Fr * (V1 - V0);
 End;

 Function XPix(Xv: Real): Integer;
 Begin
  If ResLogX Then Begin
   If Xv <= 0 Then Xv := XLo;
   XPix := PX1 + Round((Ln(Xv) - Ln(XLo)) / (Ln(XHi) - Ln(XLo)) * (PX2 - PX1));
  End
  Else XPix := PX1 + Round((Xv - XLo) / (XHi - XLo) * (PX2 - PX1));
 End;

 Function YP(Vv: Real): Integer;
 Begin
  YP := PY2 - Round((Vv - YLo) / (YHi - YLo) * (PY2 - PY1));
 End;

 Procedure Draw;
 Var Q, It, Sg, Tcol, I, K, C, Px, X, Y, YA, YB, LegY: Integer; Vx: Real;
 Begin
  HideMouseCursor;
  DrawDialogBox(X1, Y1, X2, Y2, 'Aires empilees : ' + Copy(ResTitle, 1, 40));
  SetTextStyle(DefaultFont, HorizDir, 1);
  SetFillStyle(SolidFill, White);
  Bar(PX1, PY1, PX2, PY2);
  { phases presentes }
  N := 0;
  For Q := 0 To NIT - 1 Do Begin
   It := StkOrder[Q];
   Mxv := 0;
   For I := 0 To NRes - 1 Do If ItemVal(I, It, Mass) > Mxv Then Mxv := ItemVal(I, It, Mass);
   If Mxv >= 0.005 Then Begin Lst[N] := It; Inc(N); End;
  End;
  If WaterShown Then Begin Lst[N] := NIT; Inc(N); End;
  { echelles }
  Mxv := 0;
  For I := 0 To NRes - 1 Do Begin
   Tot := 0;
   For Q := 0 To N - 1 Do Tot := Tot + ValAt(Lst[Q], I, 0);
   If Tot > Mxv Then Mxv := Tot;
  End;
  If Mxv <= 0 Then Mxv := 1;
  NiceRange(0, Mxv * 1.02, YLo, YHi, YSt);
  XLo := ResX[0]; XHi := ResX[0];
  For I := 0 To NRes - 1 Do Begin
   If ResX[I] < XLo Then XLo := ResX[I];
   If ResX[I] > XHi Then XHi := ResX[I];
  End;
  XLoD := XLo; XHiD := XHi;
  If ResLogX Then Begin
   If XLo <= 0 Then XLo := 0.01;
   XLo := Exp(Ln(10.0) * Int(Ln(XLo) / Ln(10.0) + 0.0001 - 1 + 1));
   If XLo > ResX[0] * 1.0001 Then XLo := XLo / 10;
   T := XLo;
   While T < XHi * 0.9999 Do T := T * 10;
   XHi := T;
   If XHi <= XLo Then XHi := XLo * 10;
  End
  Else If XHi <= XLo Then XHi := XLo + 1;
  { colonnes }
  For Px := PX1 To PX2 Do Begin
   If ResLogX Then Vx := Exp(Ln(XLo) + (Ln(XHi) - Ln(XLo)) * (Px - PX1) / (PX2 - PX1))
   Else Vx := XLo + (XHi - XLo) * (Px - PX1) / (PX2 - PX1);
   SegI[Px] := -1; SegF[Px] := 0;
   If NRes = 1 Then Begin SegI[Px] := 0; SegF[Px] := 0; End
   Else For I := 0 To NRes - 2 Do
    If ((Vx >= ResX[I]) And (Vx <= ResX[I + 1])) Or ((Vx <= ResX[I]) And (Vx >= ResX[I + 1])) Then Begin
     SegI[Px] := I;
     If ResX[I + 1] = ResX[I] Then SegF[Px] := 0
     Else If ResLogX And (ResX[I] > 0) And (ResX[I + 1] > 0) Then
      SegF[Px] := (Ln(Vx) - Ln(ResX[I])) / (Ln(ResX[I + 1]) - Ln(ResX[I]))
     Else SegF[Px] := (Vx - ResX[I]) / (ResX[I + 1] - ResX[I]);
     Break;
    End;
  End;
  For Q := 0 To N Do Begin BestA[Q] := 0; BestY[Q] := 0; End;
  { remplissage }
  For Px := PX1 To PX2 Do Begin
   Sg := SegI[Px];
   If Sg >= 0 Then Begin
    Bot := 0;
    For Q := 0 To N - 1 Do Begin
     It := Lst[Q];
     If NRes = 1 Then Begin
      If It = NIT Then Begin If Mass Then V := Res^[0][RI_WF] Else V := Res^[0][RI_VW]; End
      Else V := ItemVal(0, It, Mass);
     End
     Else V := ValAt(It, Sg, SegF[Px]);
     YA := YP(Bot + V); YB := YP(Bot);
     If YB - YA >= 1 Then Begin
      If Areas Then Begin
       If It = NIT Then SetColor(LightCyan) Else SetColor(ItemCol[It]);
       Line(Px, YB, Px, YA);
      End;
      SetColor(Black);
      PutPixel(Px, YA, Black);
      If YB - YA > BestA[Q] Then Begin BestA[Q] := YB - YA; BestY[Q] := Px; End;
     End;
     Bot := Bot + V;
    End;
   End;
  End;
  { etiquettes dans les aires }
  If Areas Then
   For Q := 0 To N - 1 Do
    If BestA[Q] >= 10 Then Begin
     It := Lst[Q];
     If It = NIT Then Nm := 'Eau libre' Else Nm := ItemName(It);
     Px := BestY[Q];
     { milieu vertical de la couche a cette colonne }
     Sg := SegI[Px]; Bot := 0;
     For C := 0 To Q - 1 Do Begin
      If NRes = 1 Then Begin
       If Lst[C] = NIT Then Begin If Mass Then V := Res^[0][RI_WF] Else V := Res^[0][RI_VW]; End
       Else V := ItemVal(0, Lst[C], Mass);
      End
      Else V := ValAt(Lst[C], Sg, SegF[Px]);
      Bot := Bot + V;
     End;
     If NRes = 1 Then Begin
      If It = NIT Then Begin If Mass Then V := Res^[0][RI_WF] Else V := Res^[0][RI_VW]; End
      Else V := ItemVal(0, It, Mass);
     End
     Else V := ValAt(It, Sg, SegF[Px]);
     Y := (YP(Bot) + YP(Bot + V)) Div 2 - 3;
     X := Px - 4 * Length(Nm);
     If X + 8 * Length(Nm) > XPix(XHiD) - 2 Then X := XPix(XHiD) - 2 - 8 * Length(Nm);
     If X < XPix(XLoD) + 2 Then X := XPix(XLoD) + 2;
     If It = NIT Then Tcol := Black
     Else If ItemCol[It] In [0, 1, 2, 4, 5, 6, 8] Then Tcol := White
     Else Tcol := Black;
     SetColor(Tcol);
     OutTextXY(X, Y, Nm);
    End;
  { cadre et graduations }
  SetColor(Black);
  Rectangle(PX1, PY1, PX2, PY2);
  T := YLo;
  While T <= YHi + YSt * 0.001 Do Begin
   Y := YP(T);
   Line(PX1 - 3, Y, PX1, Y);
   S := RTrim(T, 2);
   OutTextXY(PX1 - 6 - 8 * Length(S), Y - 3, S);
   T := T + YSt;
  End;
  If ResLogX Then Begin
   T := XLo;
   While T <= XHi * 1.0001 Do Begin
    Px := XPix(T);
    Line(Px, PY2, Px, PY2 + 4);
    S := RTrim(T, 3);
    OutTextXY(Px - 4 * Length(S), PY2 + 7, S);
    For K := 2 To 9 Do
     If T * K < XHi * 1.0001 Then Line(XPix(T * K), PY2, XPix(T * K), PY2 + 2);
    T := T * 10;
   End;
  End
  Else Begin
   NiceRange(XLo, XHi, Ac, Lv, F);
   T := Ac;
   While T <= XHi + F * 0.001 Do Begin
    If T >= XLo - F * 0.001 Then Begin
     Px := XPix(T);
     Line(Px, PY2, Px, PY2 + 4);
     S := RTrim(T, 3);
     OutTextXY(Px - 4 * Length(S), PY2 + 7, S);
    End;
    T := T + F;
   End;
  End;
  S := ResXLab;
  OutTextXY((PX1 + PX2) Div 2 - 4 * Length(S), PY2 + 20, S);
  If Mass Then S := 'Masse [ g pour 100 g de liant ]' Else S := 'Volume [ cm3 pour 100 g de liant ]';
  SetColor(Blue);
  OutTextXY(PX1, PY1 - 12, S);
  { legende (de haut en bas) }
  LegY := PY1;
  For Q := N - 1 Downto 0 Do Begin
   It := Lst[Q];
   If It = NIT Then Begin SetFillStyle(SolidFill, LightCyan); Nm := 'Eau libre'; End
   Else Begin SetFillStyle(SolidFill, ItemCol[It]); Nm := ItemName(It); End;
   If LegY < PY2 - 2 Then Begin
    Bar(LX, LegY, LX + 10, LegY + 7);
    SetColor(Black);
    Rectangle(LX, LegY, LX + 10, LegY + 7);
    OutTextXY(LX + 14, LegY, Copy(Nm, 1, 17));
   End;
   LegY := LegY + 10;
  End;
  DrawButton(B1, BBY1, B1 + BW, BBY2, 'Masse/Volume', False);
  DrawButton(B2, BBY1, B2 + BW, BBY2, 'Aires/Contours', False);
  DrawButton(B3, BBY1, B3 + BW, BBY2, 'Fermer', True);
  ShowMouseCursor;
 End;

Begin
 X1 := 4; Y1 := 4; X2 := ScreenWidth - 5; Y2 := ScreenHeight - 5;
 PX1 := X1 + 44; PX2 := X2 - 160; PY1 := Y1 + 40; PY2 := Y2 - 60;
 LX := PX2 + 10;
 BBY2 := Y2 - 8; BBY1 := BBY2 - BH;
 B3 := X2 - BW - 10; B2 := B3 - BW - 8; B1 := B2 - BW - 8;
 Mass := MassMode; Areas := True;
 DlgBegin;
 Done := False; Redo := True;
 While Not Done Do Begin
  If Redo Then Begin Draw; Redo := False; End;
  If DlgPoll(Key, MX, MY, Click) Then Begin
   If (Key = 13) Or (Key = 27) Or (Key = 32) Then Done := True;
   If (Key = Ord('m')) Or (Key = Ord('M')) Then Begin Mass := Not Mass; Redo := True; End;
   If (Key = Ord('a')) Or (Key = Ord('A')) Then Begin Areas := Not Areas; Redo := True; End;
   If Click Then Begin
    If PtInRect(MX, MY, B3, BBY1, B3 + BW, BBY2) Then Done := True
    Else If PtInRect(MX, MY, B1, BBY1, B1 + BW, BBY2) Then Begin Mass := Not Mass; Redo := True; End
    Else If PtInRect(MX, MY, B2, BBY1, B2 + BW, BBY2) Then Begin Areas := Not Areas; Redo := True; End;
   End;
  End;
  Delay(10);
 End;
 DlgEnd;
End;

Procedure GraphMenu;
Var Sel, I, S: Integer;
Begin
 If Not NeedResults Then Exit;
 TClear;
 TAdd('Aires empilees des phases (volume ou masse)');
 TAdd('Phases solides : masse (g / 100 g de liant)');
 TAdd('Phases solides : volume (cm3 / 100 g de liant)');
 TAdd('pH de la solution interstitielle');
 TAdd('Force ionique (mol/kg)');
 TAdd('Concentrations dissoutes (mmol/kg)');
 TAdd('Porosite (%) et eau libre (g)');
 TAdd('Degres de reaction');
 TAdd('Chaleur d''hydratation (J/g)');
 TAdd('Conductivite estimee (S/m)');
 TAdd('Rapport Ca/Si du C-S-H');
 Sel := ListDialog('Graphiques', True);
 If Sel < 0 Then Exit;
 If Sel = 0 Then Begin StackedAreaDialog; Exit; End;
 Dec(Sel);
 Case Sel Of
  0: GraphItems(True);
  1: GraphItems(False);
  2: Begin
   ChartReset('pH de la solution interstitielle', ResXLab, 'pH', ResLogX);
   If ResLogX Then ChLogMin := 0.001;
   ChFixY0 := False;
   S := ChartAddSeries('pH', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_PH]);
  End;
  3: Begin
   ChartReset('Force ionique', ResXLab, 'mol/kg', ResLogX);
   If ResLogX Then ChLogMin := 0.001;
   S := ChartAddSeries('I', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_ION]);
  End;
  4: GraphColumns('Concentrations dissoutes', 'mmol/kg d''eau', RI_EL, 10,
                  'Ca|Si|Al|Fe|S|K|Na|Mg|C|Cl', 1.0);
  5: Begin
   ChartReset('Porosite et eau libre', ResXLab, '% et g/100 g', ResLogX);
   If ResLogX Then ChLogMin := 0.001;
   S := ChartAddSeries('Porosite (%)', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_POR]);
   S := ChartAddSeries('Eau libre (g)', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_WF]);
   S := ChartAddSeries('Eau liee (g)', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_BW]);
  End;
  6: GraphColumns('Degres de reaction', 'alpha', RI_AL, 9,
                  'C3S|C2S|C3A|C4AF|Cendres|Laitier|Fumee|Calcaire|Argile cal.', 1.0);
  7: Begin
   ChartReset('Chaleur d''hydratation du clinker', ResXLab, 'J/g de liant', ResLogX);
   If ResLogX Then ChLogMin := 0.001;
   S := ChartAddSeries('Chaleur', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_HEAT]);
  End;
  8: Begin
   ChartReset('Conductivite de la solution', ResXLab, 'S/m', ResLogX);
   If ResLogX Then ChLogMin := 0.001;
   S := ChartAddSeries('Conductivite', NRes < 4);
   For I := 0 To NRes - 1 Do ChartPoint(S, ResX[I], Res^[I][RI_COND]);
  End;
 Else Begin
  ChartReset('Rapport Ca/Si du C-S-H', ResXLab, 'Ca/Si', ResLogX);
  If ResLogX Then ChLogMin := 0.001;
  ChFixY0 := False;
  S := ChartAddSeries('Ca/Si', NRes < 4);
  For I := 0 To NRes - 1 Do If Res^[I][RI_CS] > 0 Then ChartPoint(S, ResX[I], Res^[I][RI_CS]);
 End;
 End;
 If ChNS = 0 Then Begin ShowMessage('Graphique', 'Aucune donnee a tracer.'); Exit; End;
 ChartDialog;
End;

{ --------------------------------------------------------------------- }
{ Outils : Bogue, auto-test                                               }
{ --------------------------------------------------------------------- }

Procedure BogueDialog;
Var C, S, A, F, M, SO3, FL, K2, N2, C3S, C2S, C3A, C4F, Arc, Rem: Real;
Begin
 PReset;
 PAddR('CaO (%)', 64.5, 0, 100, 2);
 PAddR('SiO2 (%)', 21.0, 0, 100, 2);
 PAddR('Al2O3 (%)', 5.2, 0, 100, 2);
 PAddR('Fe2O3 (%)', 3.0, 0, 100, 2);
 PAddR('MgO (%)', 1.8, 0, 100, 2);
 PAddR('SO3 (%)', 3.0, 0, 100, 2);
 PAddR('CaO libre (%)', 0.8, 0, 100, 2);
 PAddR('K2O (%)', 0.7, 0, 100, 2);
 PAddR('Na2O (%)', 0.2, 0, 100, 2);
 If Not ParamDialog('Calculateur de Bogue', 'Analyse d''oxydes du ciment -> phases du clinker') Then Exit;
 C := PVal[0] - PVal[6]; S := PVal[1]; A := PVal[2]; F := PVal[3]; M := PVal[4];
 SO3 := PVal[5]; FL := PVal[6]; K2 := PVal[7]; N2 := PVal[8];
 If (F > 0) And (A / F < 0.64) Then Begin
  C3A := 0; C4F := 2.1 * A + 1.702 * F;
  C3S := 4.071 * C - 7.6 * S - 4.479 * A - 2.859 * F - 2.852 * SO3;
 End
 Else Begin
  C3S := 4.071 * C - 7.6 * S - 6.718 * A - 1.43 * F - 2.852 * SO3;
  C3A := 2.65 * A - 1.692 * F;
  C4F := 3.043 * F;
 End;
 C2S := 2.867 * S - 0.7544 * C3S;
 If C3S < 0 Then C3S := 0;
 If C2S < 0 Then C2S := 0;
 If C3A < 0 Then C3A := 0;
 TClear;
 TAdd('Phases du clinker (formules de Bogue, % massique)');
 TAdd('');
 TAdd('Alite C3S        ' + PadL(RStr(C3S, 2), 8));
 TAdd('Belite C2S       ' + PadL(RStr(C2S, 2), 8));
 TAdd('Aluminate C3A    ' + PadL(RStr(C3A, 2), 8));
 TAdd('Ferrite C4AF     ' + PadL(RStr(C4F, 2), 8));
 TAdd('Chaux libre      ' + PadL(RStr(FL, 2), 8));
 TAdd('Periclase MgO    ' + PadL(RStr(M, 2), 8));
 TAdd('Somme            ' + PadL(RStr(C3S + C2S + C3A + C4F + FL + M, 2), 8));
 TAdd('');
 TAdd('Les sulfates (SO3) sont repartis entre gypse, hemihydrate, anhydrite et');
 TAdd('arcanite ; les alcalis restants sont consideres comme solubles.');
 TView('Calculateur de Bogue');
 If ConfirmBox('Calculateur de Bogue', 'Appliquer ces phases au ciment courant ?') Then Begin
  Cem.P[CP_C3S] := C3S; Cem.P[CP_C2S] := C2S; Cem.P[CP_C3A] := C3A; Cem.P[CP_C4AF] := C4F;
  Cem.P[CP_LIME] := FL; Cem.P[CP_MGO] := M;
  Arc := 0.5 * K2 * 174.26 / 94.2;
  If Arc * 80.06 / 174.26 > SO3 Then Arc := SO3 * 174.26 / 80.06;
  Cem.P[CP_ARC] := Arc;
  Rem := SO3 - Arc * 80.06 / 174.26;
  If Rem < 0 Then Rem := 0;
  Cem.P[CP_GYP] := Rem / 3.0 * 172.17 / 80.06;
  Cem.P[CP_HEM] := Rem / 3.0 * 145.15 / 80.06;
  Cem.P[CP_ANH] := Rem / 3.0 * 136.14 / 80.06;
  Cem.P[CP_CAL] := 0;
  Cem.P[CP_THE] := 0.5 * N2 * 142.04 / 61.98;
  Cem.P[CP_K2O] := 0.5 * K2;
  Cem.P[CP_NA2O] := 0.5 * N2;
  Cem.Name := 'Ciment (Bogue)';
  Modified := True; KinValid := False;
 End;
End;

Procedure SelfTest;
Var T: TVec; Msg: String; K: Integer;
Begin
 Msg := CheckDatabase;
 For K := 0 To NM - 1 Do T[K] := 0;
 AddOx(T, 0, 0.0135);
 AddOx(T, 9, 100.0 / MW_WATER);
 HaveWarm := False;
 Equilibrate(T, 25, False);
 TClear;
 TAdd('Auto-test du moteur thermodynamique (25 C)');
 TAdd('');
 If Msg = '' Then TAdd('Base de donnees : formules neutres, OK')
 Else TAdd('Base de donnees : anomalies :' + Msg);
 TAdd('');
 TAdd('Portlandite dans 100 g d''eau pure :');
 TAdd('  pH                  ' + RStr(-Xs[C_H] / LN10, 3) + '   (attendu env. 12,4 - 12,5)');
 TAdd('  Ca total            ' + RStr(AqT[C_CA] * 1000, 2) + ' mmol/kg   (attendu env. 20 - 22)');
 TAdd('  Force ionique       ' + RStr(IonS, 4) + ' mol/kg');
 TAdd('  Etat du solveur     ' + EqStatus + ', ' + IStr(EqIter) + ' iterations');
 TView('Verification de la base de donnees');
End;

{ --------------------------------------------------------------------- }
{ Fichiers : recette, exports                                             }
{ --------------------------------------------------------------------- }

Var IOErr: Boolean;

Procedure ErrBox(Const Title, Msg: String);
Begin
 If BatchMode Then WriteLn(Title, ' : ', Msg) Else ShowMessage(Title, Msg);
End;

Procedure IOR(Var F: Text; Wrt: Boolean; Const Key: String; Var V: Real);
Var L: String; P: Integer; R: Real;
Begin
 If Wrt Then WriteLn(F, Key, '=', V:0:8)
 Else Begin
  If Eof(F) Then Begin IOErr := True; Exit; End;
  ReadLn(F, L);
  P := Pos('=', L);
  If (P = 0) Or Not ParseReal(Copy(L, P + 1, 255), R) Then IOErr := True Else V := R;
 End;
End;

Procedure IOI(Var F: Text; Wrt: Boolean; Const Key: String; Var V: Integer);
Var R: Real;
Begin
 R := V;
 IOR(F, Wrt, Key, R);
 If Not Wrt Then V := Round(R);
End;

Procedure IOS(Var F: Text; Wrt: Boolean; Const Key: String; Var V: String);
Var L: String; P: Integer;
Begin
 If Wrt Then WriteLn(F, Key, '=', V)
 Else Begin
  If Eof(F) Then Begin IOErr := True; Exit; End;
  ReadLn(F, L);
  P := Pos('=', L);
  If P = 0 Then IOErr := True Else V := Copy(L, P + 1, 255);
 End;
End;

Procedure RecipeIO(Var F: Text; Wrt: Boolean);
Var I, J: Integer; NMs: String;
Begin
 NMs := Cem.Name;
 IOS(F, Wrt, 'ciment.nom', NMs); Cem.Name := Copy(NMs, 1, 30);
 For I := 0 To NCP - 1 Do IOR(F, Wrt, 'ciment.phase' + IStr(I), Cem.P[I]);
 For I := 0 To NSC - 1 Do Begin
  NMs := Scm[I].Name;
  IOS(F, Wrt, 'ajout' + IStr(I) + '.nom', NMs); Scm[I].Name := Copy(NMs, 1, 30);
  For J := 0 To NOX - 1 Do IOR(F, Wrt, 'ajout' + IStr(I) + '.' + OXNames[J], Scm[I].Ox[J]);
  IOR(F, Wrt, 'ajout' + IStr(I) + '.rho', Scm[I].Rho);
  IOR(F, Wrt, 'ajout' + IStr(I) + '.amax', Scm[I].AMax);
  IOR(F, Wrt, 'ajout' + IStr(I) + '.tau', Scm[I].Tau);
  IOR(F, Wrt, 'ajout' + IStr(I) + '.n', Scm[I].Nexp);
  IOR(F, Wrt, 'ajout' + IStr(I) + '.ea', Scm[I].Ea);
  IOR(F, Wrt, 'liant.ajout' + IStr(I), SFrac[I]);
 End;
 IOR(F, Wrt, 'melange.el', WB);
 IOR(F, Wrt, 'melange.temperature', TempC);
 IOR(F, Wrt, 'melange.age', AgeD);
 For I := 0 To NPK - 1 Do For J := 0 To 6 Do IOR(F, Wrt, 'pk' + IStr(I) + '.' + IStr(J), PK[I, J]);
 IOR(F, Wrt, 'pk.mgtau', MgTau);
 IOI(F, Wrt, 'proc.type', ProcSel);
 IOI(F, Wrt, 'hydr.n', HydN); IOR(F, Wrt, 'hydr.t0', HydT0); IOR(F, Wrt, 'hydr.t1', HydT1);
 IOI(F, Wrt, 'mel.var', MixVar); IOR(F, Wrt, 'mel.v0', MixV0); IOR(F, Wrt, 'mel.v1', MixV1);
 IOI(F, Wrt, 'mel.n', MixN);
 IOR(F, Wrt, 'ext.vol', ExtVol); IOI(F, Wrt, 'ext.n', ExtN);
 For I := 0 To 6 Do IOR(F, Wrt, 'ext.sel' + IStr(I), ExtSalt[I]);
 IOR(F, Wrt, 'carb.co2', CarbMax); IOI(F, Wrt, 'carb.n', CarbN);
 IOR(F, Wrt, 'ads.k', AdsK); IOR(F, Wrt, 'ads.na', AdsNa);
End;

Function SaveRecipe(Const FN: String): Boolean;
Var F: Text;
Begin
 SaveRecipe := False;
 {$I-}
 Assign(F, FN); Rewrite(F);
 {$I+}
 If IOResult <> 0 Then Begin ShowMessage('Erreur', 'Impossible d''ecrire ' + FN); Exit; End;
 WriteLn(F, 'CEMGEMS-RECETTE ', PROG_VERSION);
 IOErr := False;
 RecipeIO(F, True);
 Close(F);
 ProjName := FN; Modified := False;
 StatusMsg := 'Recette enregistree : ' + FN;
 SaveRecipe := True;
End;

Function LoadRecipe(Const FN: String; Quiet: Boolean): Boolean;
Var F: Text; L: String;
Begin
 LoadRecipe := False;
 {$I-}
 Assign(F, FN); Reset(F);
 {$I+}
 If IOResult <> 0 Then Begin
  If Not Quiet Then ErrBox('Erreur', 'Impossible de lire ' + FN);
  Exit;
 End;
 ReadLn(F, L);
 If Copy(L, 1, 15) <> 'CEMGEMS-RECETTE' Then Begin
  Close(F);
  If Not Quiet Then ShowMessage('Erreur', 'Ce fichier n''est pas une recette CEMGEMS.');
  Exit;
 End;
 IOErr := False;
 RecipeIO(F, False);
 Close(F);
 If (IOErr) And Not Quiet Then ShowMessage('Recette', 'Fichier incomplet : certaines valeurs sont inchangees.');
 If HydN > MAXSTEP Then HydN := MAXSTEP;
 If MixN > MAXSTEP Then MixN := MAXSTEP;
 If ExtN > MAXSTEP - 1 Then ExtN := MAXSTEP - 1;
 If CarbN > MAXSTEP - 1 Then CarbN := MAXSTEP - 1;
 If (ProcSel < 0) Or (ProcSel > PR_SALT) Then ProcSel := PR_HYD;
 KinValid := False;
 NRes := 0; CurStep := 0;
 ProjName := FN; Modified := False;
 StatusMsg := 'Recette chargee : ' + FN;
 LoadRecipe := True;
End;

Procedure ExportResultsCSV(Const FN: String);
Var F: Text; I, K: Integer; Row: ^TRow; S: String;
Begin
 If NRes < 1 Then Begin ErrBox('Resultats', 'Aucun resultat a exporter.'); Exit; End;
 {$I-}
 Assign(F, FN); Rewrite(F);
 {$I+}
 If IOResult <> 0 Then Begin ErrBox('Erreur', 'Impossible d''ecrire ' + FN); Exit; End;
 S := 'x;pH;force_ionique;eau_libre_g;porosite_pct;volume_total_cm3;chaleur_J_g;Ca_SiCSH';
 For K := 0 To NIT - 1 Do S := S + ';' + ItemName(K) + '_g';
 For K := 0 To 9 Do S := S + ';' + MName[C_CA + K] + '_mmol_kg';
 WriteLn(F, S);
 For I := 0 To NRes - 1 Do Begin
  Row := @Res^[I];
  Write(F, ResX[I]:0:5, ';', Row^[RI_PH]:0:4, ';', Row^[RI_ION]:0:5, ';', Row^[RI_WF]:0:4, ';',
        Row^[RI_POR]:0:3, ';', Row^[RI_VT]:0:3, ';', Row^[RI_HEAT]:0:2, ';', Row^[RI_CS]:0:3);
  For K := 0 To NIT - 1 Do Write(F, ';', ItemVal(I, K, True):0:4);
  For K := 0 To 9 Do Write(F, ';', Row^[RI_EL + K]:0:5);
  WriteLn(F);
 End;
 Close(F);
 StatusMsg := 'Resultats exportes : ' + FN;
End;

Const
 VgaRGB : Array[0..15, 0..2] Of Byte = (
  (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170),
  (170, 85, 0), (170, 170, 170), (85, 85, 85), (85, 85, 255), (85, 255, 85),
  (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255));

{ exporte la zone du graphique principal en BMP 24 bits }
Procedure ExportChartBMP(Const FN: String);
Var
 F: File; W, H, RowBytes, X, Y: Integer; Row: Array[0..1299] Of Byte;
 Hd: Array[0..53] Of Byte; Sz: LongInt; C: Word;
 Procedure PutL(Off: Integer; V: LongInt);
 Begin Hd[Off] := V And 255; Hd[Off + 1] := (V Shr 8) And 255; Hd[Off + 2] := (V Shr 16) And 255; Hd[Off + 3] := (V Shr 24) And 255; End;
Begin
 W := VX1 - VX0 + 1; H := VY1 - VY0 + 1;
 RowBytes := ((W * 3 + 3) Div 4) * 4;
 {$I-}
 Assign(F, FN); Rewrite(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin ShowMessage('Erreur', 'Impossible d''ecrire ' + FN); Exit; End;
 FillChar(Hd, SizeOf(Hd), 0);
 Hd[0] := Ord('B'); Hd[1] := Ord('M');
 Sz := 54 + LongInt(RowBytes) * H;
 PutL(2, Sz); PutL(10, 54); PutL(14, 40); PutL(18, W); PutL(22, H);
 Hd[26] := 1; Hd[28] := 24; PutL(34, LongInt(RowBytes) * H);
 BlockWrite(F, Hd, 54);
 HideMouseCursor;
 For Y := VY1 Downto VY0 Do Begin
  FillChar(Row, SizeOf(Row), 0);
  For X := 0 To W - 1 Do Begin
   C := GetPixel(VX0 + X, Y) And 15;
   Row[X * 3] := VgaRGB[C, 2]; Row[X * 3 + 1] := VgaRGB[C, 1]; Row[X * 3 + 2] := VgaRGB[C, 0];
  End;
  BlockWrite(F, Row, RowBytes);
 End;
 ShowMouseCursor;
 Close(F);
 StatusMsg := 'Graphique exporte : ' + FN;
End;

{ --------------------------------------------------------------------- }
{ Aide                                                                    }
{ --------------------------------------------------------------------- }

Procedure ShowHelp;
Begin
 TClear;
 TAdd('CEMGEMS Clone - modelisation thermodynamique des materiaux cimentaires');
 TAdd('');
 TAdd('Marche a suivre');
 TAdd(' 1. Recette : choisir le ciment, les ajouts cimentaires (cendres volantes,');
 TAdd('    laitier, fumee de silice, calcaire, argile calcinee), le rapport');
 TAdd('    eau/liant, la temperature et l''age.');
 TAdd(' 2. Processus : lancer un calcul. Chaque etape est un equilibre complet');
 TAdd('    (minimisation de l''energie libre de Gibbs, 12 composants).');
 TAdd(' 3. Resultats : assemblage de phases, solution interstitielle, graphiques.');
 TAdd('');
 TAdd('Processus');
 TAdd(' Equilibre     un seul equilibre a l''age donne (alpha de Parrot-Killoh).');
 TAdd(' Hydratation   equilibre a des ages croissants ; degres de reaction du');
 TAdd('                clinker (Parrot-Killoh) et des ajouts (lois exponentielles).');
 TAdd(' Melange       balayage de E/L ou du taux d''un ajout.');
 TAdd(' Lixiviation   la solution est renouvelee par de l''eau pure a chaque pas :');
 TAdd('                dissolution des alcalis, de la portlandite puis du C-S-H.');
 TAdd(' Carbonatation du CO2 est ajoute au systeme ferme : portlandite, C-S-H,');
 TAdd('                AFm sont carbonates (calcite, gel de silice, gibbsite).');
 TAdd(' Sels          renouvellement par une solution saline (NaCl, Na2SO4, MgSO4,');
 TAdd('                MgCl2, CaCl2, Na2CO3, NaOH) : sel de Friedel, ettringite, gypse.');
 TAdd('');
 TAdd('Modele');
 TAdd(' Composants : H2O, H+, Ca, Si, Al, Fe, S, K, Na, Mg, C, Cl. Phase aqueuse');
 TAdd(' de 33 especes avec coefficients d''activite de Truesdell-Jones. Phases');
 TAdd(' solides : C-S-H (solution solide a 4 poles), portlandite, ettringite,');
 TAdd(' monosulfate, mono/hemicarbonate, sel de Friedel, stratlingite, hydrogrenats,');
 TAdd(' hydrotalcite, brucite, gypse, calcite, gibbsite, silice, ferrihydrite.');
 TAdd(' Les constantes sont des valeurs indicatives inspirees de Cemdata18 ; le');
 TAdd(' C-S-H est calibre sur sa courbe de solubilite. Les alcalis sont fixes sur');
 TAdd(' le C-S-H par un coefficient de distribution Rd = Rd1 exp(-3 (Ca/Si - 1)).');
 TAdd(' Modele pedagogique : ne remplace pas GEMS.');
 TAdd('');
 TAdd('Raccourcis');
 TAdd(' F1 aide  F2 formulation  F3 phases  F4 solution  F5 equilibre');
 TAdd(' F6 hydratation  F7 graphiques  F10 menus  Gauche/Droite etape');
 TAdd(' Ctrl+N nouvelle  Ctrl+O ouvrir  Ctrl+S enregistrer  Alt+X quitter');
 TAdd(' Echap interrompt un calcul en cours');
 TAdd('');
 TAdd('Mode lot : CEMGEMS /B [recette.CGM] [sortie.CSV]');
 TView('Aide de CEMGEMS');
End;

Procedure ShowAbout;
Begin
 ShowMessage('A propos de CEMGEMS', 'CEMGEMS Clone ' + PROG_VERSION + '|Clone de CemGEMS (cemgems.org)|' +
   'Modelisation thermodynamique des ciments|Sylvain Maltais - www.gladir.com/ciment-0');
End;

{ --------------------------------------------------------------------- }
{ Definition des menus                                                   }
{ --------------------------------------------------------------------- }

Procedure ZeroMenu(Var M: TMenu);
Var I: Integer;
Begin
 For I := 0 To MAX_MENU_ITEMS - 1 Do Begin
  M.Items[I].Caption := '';
  M.Items[I].Shortcut := '';
  M.Items[I].Enabled := True;
  M.Items[I].Checked := False;
  M.Items[I].Separator := False;
 End;
End;

Procedure MI(Var Mn: TMenu; Idx: Integer; Const Cap, Sc: String);
Begin
 Mn.Items[Idx].Caption := Cap;
 Mn.Items[Idx].Shortcut := Sc;
End;

Procedure MS(Var Mn: TMenu; Idx: Integer);
Begin
 Mn.Items[Idx].Separator := True;
End;

Procedure InitMenus;
Var I: Integer;
Begin
 { Fichier }
 ZeroMenu(Menus[MENU_FILE]);
 Menus[MENU_FILE].Title := 'Fichier';
 Menus[MENU_FILE].ItemCount := 9;
 MI(Menus[MENU_FILE], 0, 'Nouvelle recette', 'Ctrl+N');
 MI(Menus[MENU_FILE], 1, 'Ouvrir une recette...', 'Ctrl+O');
 MI(Menus[MENU_FILE], 2, 'Enregistrer la recette', 'Ctrl+S');
 MI(Menus[MENU_FILE], 3, 'Enregistrer sous...', '');
 MS(Menus[MENU_FILE], 4);
 MI(Menus[MENU_FILE], 5, 'Exporter les resultats (CSV)...', '');
 MI(Menus[MENU_FILE], 6, 'Exporter le graphique (BMP)...', '');
 MS(Menus[MENU_FILE], 7);
 MI(Menus[MENU_FILE], 8, 'Quitter', 'Alt+X');
 { Recette }
 ZeroMenu(Menus[MENU_REC]);
 Menus[MENU_REC].Title := 'Recette';
 Menus[MENU_REC].ItemCount := 11;
 MI(Menus[MENU_REC], 0, 'Formulation (E/L, T, age)...', 'F2');
 MI(Menus[MENU_REC], 1, 'Ciment...', '');
 For I := 0 To NSC - 1 Do MI(Menus[MENU_REC], 2 + I, SCNames[I] + '...', '');
 MS(Menus[MENU_REC], 7);
 MI(Menus[MENU_REC], 8, 'Cinetique de reaction...', '');
 MS(Menus[MENU_REC], 9);
 MI(Menus[MENU_REC], 10, 'Bilan d''oxydes de la recette', '');
 { Processus }
 ZeroMenu(Menus[MENU_PROC]);
 Menus[MENU_PROC].Title := 'Processus';
 Menus[MENU_PROC].ItemCount := 6;
 MI(Menus[MENU_PROC], 0, 'Equilibre a l''age donne', 'F5');
 MI(Menus[MENU_PROC], 1, 'Hydratation...', 'F6');
 MI(Menus[MENU_PROC], 2, 'Melange (balayage)...', '');
 MI(Menus[MENU_PROC], 3, 'Lixiviation...', '');
 MI(Menus[MENU_PROC], 4, 'Carbonatation...', '');
 MI(Menus[MENU_PROC], 5, 'Penetration de sels...', '');
 { Resultats }
 ZeroMenu(Menus[MENU_RES]);
 Menus[MENU_RES].Title := 'Resultats';
 Menus[MENU_RES].ItemCount := 6;
 MI(Menus[MENU_RES], 0, 'Assemblage de phases', 'F3');
 MI(Menus[MENU_RES], 1, 'Solution interstitielle', 'F4');
 MI(Menus[MENU_RES], 2, 'Tableau des etapes', '');
 MS(Menus[MENU_RES], 3);
 MI(Menus[MENU_RES], 4, 'Graphiques...', 'F7');
 MI(Menus[MENU_RES], 5, 'Aires empilees des phases', 'F8');
 { Vue }
 ZeroMenu(Menus[MENU_VIEW]);
 Menus[MENU_VIEW].Title := 'Vue';
 Menus[MENU_VIEW].ItemCount := 7;
 MI(Menus[MENU_VIEW], 0, 'Etape suivante', 'Droite');
 MI(Menus[MENU_VIEW], 1, 'Etape precedente', 'Gauche');
 MI(Menus[MENU_VIEW], 2, 'Premiere etape', 'Debut');
 MI(Menus[MENU_VIEW], 3, 'Derniere etape', 'Fin');
 MS(Menus[MENU_VIEW], 4);
 MI(Menus[MENU_VIEW], 5, 'Empilement en masse (g)', '');
 MI(Menus[MENU_VIEW], 6, 'Empilement en volume (cm3)', '');
 { Base de donnees }
 ZeroMenu(Menus[MENU_DB]);
 Menus[MENU_DB].Title := 'Base donnees';
 Menus[MENU_DB].ItemCount := 2;
 MI(Menus[MENU_DB], 0, 'Phases solides', '');
 MI(Menus[MENU_DB], 1, 'Especes aqueuses', '');
 { Outils }
 ZeroMenu(Menus[MENU_TOOLS]);
 Menus[MENU_TOOLS].Title := 'Outils';
 Menus[MENU_TOOLS].ItemCount := 3;
 MI(Menus[MENU_TOOLS], 0, 'Calculateur de Bogue...', '');
 MI(Menus[MENU_TOOLS], 1, 'Valeurs par defaut', '');
 MI(Menus[MENU_TOOLS], 2, 'Verification du moteur', '');
 { Aide }
 ZeroMenu(Menus[MENU_HELP]);
 Menus[MENU_HELP].Title := 'Aide';
 Menus[MENU_HELP].ItemCount := 3;
 MI(Menus[MENU_HELP], 0, 'Aide', 'F1');
 MI(Menus[MENU_HELP], 1, 'Mode lot (ligne de commande)', '');
 MI(Menus[MENU_HELP], 2, 'A propos de CEMGEMS', '');
End;

Procedure UpdateMenuChecks;
Var I: Integer;
Begin
 Menus[MENU_VIEW].Items[5].Checked := MassMode;
 Menus[MENU_VIEW].Items[6].Checked := Not MassMode;
 For I := 0 To 3 Do Menus[MENU_VIEW].Items[I].Enabled := NRes > 0;
 For I := 0 To 2 Do Menus[MENU_RES].Items[I].Enabled := NRes > 0;
 Menus[MENU_RES].Items[4].Enabled := NRes > 0;
 Menus[MENU_RES].Items[5].Enabled := NRes > 0;
 Menus[MENU_FILE].Items[5].Enabled := NRes > 0;
 Menus[MENU_FILE].Items[6].Enabled := NRes > 0;
End;

{ --------------------------------------------------------------------- }
{ Commandes                                                              }
{ --------------------------------------------------------------------- }

Function ConfirmDiscard: Boolean;
Begin
 ConfirmDiscard := True;
 If Modified Then
  ConfirmDiscard := ConfirmBox('Recette modifiee', 'Les modifications non enregistrees seront|perdues. Continuer ?');
End;

Procedure DoNew;
Begin
 If Not ConfirmDiscard Then Exit;
 DefaultAll;
 ProjName := ''; Modified := False; ProcSel := PR_HYD;
 StatusMsg := 'Nouvelle recette';
 NeedRedraw := True;
End;

Procedure DoOpen;
Var FN: String;
Begin
 If Not ConfirmDiscard Then Exit;
 FN := '';
 If FileOpenDialog('Ouvrir une recette', FN, '*.CGM') Then
  If LoadRecipe(FN, False) Then ;
 NeedRedraw := True;
End;

Procedure DoSaveAs;
Var FN: String;
Begin
 FN := ProjName;
 If FN = '' Then FN := 'RECETTE.CGM';
 If FileSaveDialog('Enregistrer la recette', FN) Then Begin
  If ExtractExt(FN) = '' Then FN := FN + '.CGM';
  If SaveRecipe(FN) Then ;
 End;
End;

Procedure DoSave;
Begin
 If ProjName = '' Then DoSaveAs
 Else If SaveRecipe(ProjName) Then ;
End;

Procedure DoExportCSV;
Var FN: String;
Begin
 If NRes < 1 Then Exit;
 FN := 'RESULTAT.CSV';
 If FileSaveDialog('Exporter les resultats (CSV)', FN) Then Begin
  If ExtractExt(FN) = '' Then FN := FN + '.CSV';
  ExportResultsCSV(FN);
 End;
End;

Procedure DoExportBMP;
Var FN: String;
Begin
 If NRes < 1 Then Exit;
 FN := 'GRAPHE.BMP';
 If FileSaveDialog('Exporter le graphique (BMP)', FN) Then Begin
  If ExtractExt(FN) = '' Then FN := FN + '.BMP';
  ExportChartBMP(FN);
 End;
End;

Procedure StepTo(N: Integer);
Begin
 If NRes < 1 Then Exit;
 If N < 0 Then N := 0;
 If N > NRes - 1 Then N := NRes - 1;
 CurStep := N;
 NeedRedraw := True;
End;

Procedure ToggleUnit;
Begin
 MassMode := Not MassMode;
 NeedRedraw := True;
End;

Procedure DispatchMenu(M, I: Integer);
Begin
 UpdateMenuChecks;
 RedrawAll;
 NeedRedraw := True;
 Case M Of
  MENU_FILE: Case I Of
   0: DoNew;
   1: DoOpen;
   2: DoSave;
   3: DoSaveAs;
   5: DoExportCSV;
   6: DoExportBMP;
   8: If ConfirmDiscard Then Running := False;
  End;
  MENU_REC: Case I Of
   0: FormDialog;
   1: CementDialog;
   2, 3, 4, 5, 6: ScmDialog(I - 2);
   8: PKDialog;
   10: ShowOxides;
  End;
  MENU_PROC: Case I Of
   0: DoEquilibrium;
   1: DoHydration;
   2: DoMix;
   3: DoRenewal(PR_LEACH);
   4: DoCarbonation;
   5: DoRenewal(PR_SALT);
  End;
  MENU_RES: Case I Of
   0: ShowPhaseTable;
   1: ShowSolution;
   2: ShowStepsTable;
   4: GraphMenu;
   5: StackedAreaDialog;
  End;
  MENU_VIEW: Case I Of
   0: StepTo(CurStep + 1);
   1: StepTo(CurStep - 1);
   2: StepTo(0);
   3: StepTo(NRes - 1);
   5: Begin MassMode := True; NeedRedraw := True; End;
   6: Begin MassMode := False; NeedRedraw := True; End;
  End;
  MENU_DB: Case I Of
   0: ShowPhaseDB;
   1: ShowSpeciesDB;
  End;
  MENU_TOOLS: Case I Of
   0: BogueDialog;
   1: If ConfirmBox('Valeurs par defaut', 'Restaurer tous les parametres par defaut ?|(les resultats sont effaces)') Then Begin
     DefaultAll; ProcSel := PR_HYD; Modified := True;
    End;
   2: SelfTest;
  End;
  MENU_HELP: Case I Of
   0: ShowHelp;
   1: Begin
    TClear;
    TAdd('Mode lot (sans interface) :');
    TAdd('');
    TAdd('   CEMGEMS /B [recette.CGM] [sortie.CSV]');
    TAdd('');
    TAdd('Charge la recette (ou les valeurs par defaut), execute le dernier');
    TAdd('processus enregistre dans la recette (hydratation par defaut) et');
    TAdd('ecrit les resultats au format CSV.');
    TView('Mode lot');
   End;
   2: ShowAbout;
  End;
 End;
End;

Procedure DoToolbar(Id: Integer);
Begin
 Case Id Of
  TB_FORM: FormDialog;
  TB_CEM: CementDialog;
  TB_EQ: DoEquilibrium;
  TB_HYD: DoHydration;
  TB_MIX: DoMix;
  TB_LEA: DoRenewal(PR_LEACH);
  TB_CARB: DoCarbonation;
  TB_SALT: DoRenewal(PR_SALT);
  TB_PHA: ShowPhaseTable;
  TB_SOL: ShowSolution;
  TB_GRA: GraphMenu;
  TB_AREA: StackedAreaDialog;
  TB_UNIT: ToggleUnit;
  TB_PREV: StepTo(CurStep - 1);
  TB_NEXT: StepTo(CurStep + 1);
  TB_HELP: ShowHelp;
 End;
End;

{ --------------------------------------------------------------------- }
{ Clavier et souris                                                      }
{ --------------------------------------------------------------------- }

Procedure HandleKey;
Var K: Char; MZ, MN: Integer;
Begin
 K := ReadKey;
 If K = #0 Then Begin
  K := ReadKey;
  If MenuActive Then Begin
   Case K Of
    #75: Begin
     Dec(ActiveMenu); If ActiveMenu < 0 Then ActiveMenu := NUM_MENUS - 1;
     ActiveMenuItem := 0; MenuNextItem(0); If ActiveMenuItem < 0 Then ActiveMenuItem := 0;
    End;
    #77: Begin
     Inc(ActiveMenu); If ActiveMenu >= NUM_MENUS Then ActiveMenu := 0;
     ActiveMenuItem := 0; MenuNextItem(0); If ActiveMenuItem < 0 Then ActiveMenuItem := 0;
    End;
    #72: MenuNextItem(-1);
    #80: MenuNextItem(1);
    #68, #67: Begin MenuActive := False; ActiveMenu := -1; End;
   End;
   NeedRedraw := True;
   Exit;
  End;
  Case K Of
   #59: ShowHelp;
   #60: FormDialog;
   #61: ShowPhaseTable;
   #62: ShowSolution;
   #63: DoEquilibrium;
   #64: DoHydration;
   #65: GraphMenu;
   #66: If NRes > 0 Then StackedAreaDialog;
   #68: Begin MenuActive := True; ActiveMenu := 0; ActiveMenuItem := 0; MenuNextItem(0); End;
   #45: Begin If ConfirmDiscard Then Running := False; End;
   #75, #73: StepTo(CurStep - 1);
   #77, #81: StepTo(CurStep + 1);
   #71: StepTo(0);
   #79: StepTo(NRes - 1);
  End;
  NeedRedraw := True;
  Exit;
 End;
 If MenuActive Then Begin
  Case K Of
   #27: Begin MenuActive := False; ActiveMenu := -1; End;
   #13: Begin
    If (ActiveMenuItem >= 0) And Not Menus[ActiveMenu].Items[ActiveMenuItem].Separator Then Begin
     MZ := ActiveMenu; MN := ActiveMenuItem;
     MenuActive := False; ActiveMenu := -1;
     DispatchMenu(MZ, MN);
    End;
   End;
  End;
  NeedRedraw := True;
  Exit;
 End;
 Case K Of
  #14: DoNew;
  #15: DoOpen;
  #19: DoSave;
  #17: Begin If ConfirmDiscard Then Running := False; End;
  ' ': ToggleUnit;
 End;
 NeedRedraw := True;
End;

Procedure HoverInfo;
Var I, X1, X2: Integer;
Begin
 If (NRes < 1) Or MenuActive Then Exit;
 If (MouseX < StackX0) Or (MouseX > StackX1) Or (MouseY < VY0) Or (MouseY > VY1) Then Exit;
 For I := 0 To NBar - 1 Do Begin
  X1 := BarX(I);
  If NBar <= 1 Then X2 := StackX1 Else X2 := BarX(I + 1) - 2;
  If (MouseX >= X1) And (MouseX <= X2 + 1) Then Begin
   StatusMsg := 'Etape ' + IStr(I + 1) + ' : x = ' + RTrim(ResX[I], 3) + '   pH ' + RStr(Res^[I][RI_PH], 2) +
                '   (clic : selectionner)';
   HideMouseCursor; DrawStatusBar; ShowMouseCursor;
   Exit;
  End;
 End;
End;

Procedure ClickChart;
Var I, X1, X2: Integer;
Begin
 If NRes < 1 Then Exit;
 For I := 0 To NBar - 1 Do Begin
  X1 := BarX(I);
  If NBar <= 1 Then X2 := StackX1 Else X2 := BarX(I + 1) - 2;
  If (MouseX >= X1) And (MouseX <= X2 + 1) Then Begin StepTo(I); Exit; End;
 End;
End;

Procedure HandleMouse;
Var
 Hit, ItemHit, T, MZ : Integer;
 LeftDown, OldLeft, Moved : Boolean;
Begin
 GetMouseLocal(MouseX, MouseY, MouseButtons);
 LeftDown := (MouseButtons And 1) <> 0;
 OldLeft := (OldMouseButtons And 1) <> 0;
 Moved := (MouseX <> OldMouseX) Or (MouseY <> OldMouseY);
 DlgHappened := False;
 If MenuActive And Moved Then Begin
  Hit := MenuBarHitTest(MouseX, MouseY);
  If (Hit >= 0) And (Hit <> ActiveMenu) Then Begin
   ActiveMenu := Hit; ActiveMenuItem := -1; NeedRedraw := True;
  End
  Else Begin
   ItemHit := MenuItemHitTest(MouseX, MouseY, ActiveMenu);
   If (ItemHit >= 0) And (ItemHit <> ActiveMenuItem) And
      (Not Menus[ActiveMenu].Items[ItemHit].Separator) Then Begin
    ActiveMenuItem := ItemHit; NeedRedraw := True;
   End;
  End;
 End;
 If Moved And Not MenuActive Then Begin
  T := ToolbarHit(MouseX, MouseY);
  If T >= 0 Then Begin
   If StatusMsg <> TBHint[T] Then Begin StatusMsg := TBHint[T]; HideMouseCursor; DrawStatusBar; ShowMouseCursor; End;
  End
  Else HoverInfo;
 End;
 If LeftDown And Not OldLeft Then Begin
  Hit := MenuBarHitTest(MouseX, MouseY);
  If Hit >= 0 Then Begin
   If MenuActive And (ActiveMenu = Hit) Then Begin MenuActive := False; ActiveMenu := -1; End
   Else Begin MenuActive := True; ActiveMenu := Hit; ActiveMenuItem := -1; UpdateMenuChecks; End;
   NeedRedraw := True;
  End
  Else If MenuActive Then Begin
   ItemHit := MenuItemHitTest(MouseX, MouseY, ActiveMenu);
   If (ItemHit >= 0) And Not Menus[ActiveMenu].Items[ItemHit].Separator Then Begin
    MZ := ActiveMenu;
    MenuActive := False; ActiveMenu := -1;
    DispatchMenu(MZ, ItemHit);
   End
   Else If ItemHit < 0 Then Begin MenuActive := False; ActiveMenu := -1; End;
   NeedRedraw := True;
  End
  Else If (MouseY >= MENUBAR_H) And (MouseY < MENUBAR_H + TOOLBAR_H) Then Begin
   T := ToolbarHit(MouseX, MouseY);
   If (T >= 0) And TBEnabled(TBId[T]) Then DoToolbar(TBId[T]);
  End
  Else If (MouseX >= VX0) And (MouseX <= VX1) And (MouseY >= VY0) And (MouseY <= VY1) Then ClickChart;
 End;
 If Not DlgHappened Then OldMouseButtons := MouseButtons;
 OldMouseX := MouseX; OldMouseY := MouseY;
End;

{ --------------------------------------------------------------------- }
{ Mode lot                                                               }
{ --------------------------------------------------------------------- }

Procedure BatchRun;
Var Prj, Outf: String;
Begin
 BatchMode := True;
 Prj := ''; Outf := 'CEMGEMS.CSV';
 If ParamCount >= 2 Then Prj := ParamStr(2);
 If ParamCount >= 3 Then Outf := ParamStr(3);
 If (Prj <> '') And (UpStr(ExtractExt(Prj)) = '.CSV') Then Begin Outf := Prj; Prj := ''; End;
 If Prj <> '' Then Begin
  If Not FileOK(Prj) Then Begin WriteLn('Recette introuvable : ', Prj); Halt(1); End;
  If Not LoadRecipe(Prj, True) Then Begin WriteLn('Recette invalide : ', Prj); Halt(1); End;
  If ParamCount < 3 Then Outf := ChangeExt(Prj, '.CSV');
 End;
 WriteLn('CEMGEMS - mode lot');
 WriteLn('Ciment : ', Cem.Name, '  E/L = ', WB:0:3, '  T = ', TempC:0:1, ' C  age = ', AgeD:0:1, ' j');
 Case ProcSel Of
  PR_EQ: RunEquilibrium;
  PR_MIX: RunMix;
  PR_LEACH, PR_SALT: RunRenewal(ProcSel);
  PR_CARB: RunCarbonation;
 Else RunHydration;
 End;
 WriteLn('Processus : ', ProcName(ResKind), ', ', NRes, ' etape(s)');
 If NRes > 0 Then
  WriteLn('Dernier equilibre : pH = ', Res^[NRes - 1][RI_PH]:0:2, '  porosite = ', Res^[NRes - 1][RI_POR]:0:1, ' %');
 ExportResultsCSV(Outf);
 WriteLn('Resultats : ', Outf);
End;

{ --------------------------------------------------------------------- }
{ Initialisation et boucle principale                                    }
{ --------------------------------------------------------------------- }

Procedure InitializeGraphics;
Var
 Driver, Mode : Integer;
 ErrCode : Integer;
Begin
 {$IFDEF FPC}
  Driver := VGA;
  Mode := VGAHi;
 {$ELSE}
  Driver := Detect;
  Mode := VGAHi;
 {$ENDIF}
 InitGraph(Driver, Mode, '');
 ErrCode := GraphResult;
 If ErrCode = grOk Then Begin
  SetColor(White);
  SetLineStyle(0, 0, 1);
 End
 Else Begin
  WriteLn('Erreur graphique : ', GraphErrorMsg(ErrCode));
  Halt;
 End;
 ScreenWidth := GetMaxX + 1;
 ScreenHeight := GetMaxY + 1;
End;

Procedure InitializeAll;
Begin
 InitMenus;
 InitToolbar;
 LayoutMenuBar;
 MenuActive := False; ActiveMenu := -1; ActiveMenuItem := -1;
 OldMouseButtons := 0; OldMouseX := -1; OldMouseY := -1;
 ProgPct := -1;
 InitMouseDriver;
 Running := True;
 NeedRedraw := True;
End;

Procedure MainLoop;
Begin
 RedrawAll;
 While Running Do Begin
  If KeyPressed Then HandleKey;
  HandleMouse;
  If MenuActive Then UpdateMenuChecks;
  If NeedRedraw Then RedrawAll;
  Delay(8);
 End;
End;

{ ===================================================================== }
{ Programme principal                                                   }
{ ===================================================================== }

BEGIN
 Res := Nil; Spc := Nil; KinT := Nil; KinA := Nil;
 InitDatabase;
 MassMode := False; ProcSel := PR_HYD;
 StatusMsg := ''; ProjName := ''; Modified := False; BatchMode := False;
 NeedRedraw := True; ProgPct := -1; LastShowT := 0;
 DefaultAll;
 AllocResults;
 If (ParamStr(1) = '/?') Or (ParamStr(1) = '--help') Or (ParamStr(1) = '-h') Then Begin
  WriteLn('CEMGEMS - Cette commande permet de modeliser l''equilibre thermodynamique des ciments.');
  WriteLn;
  WriteLn('Syntaxe : CEMGEMS [recette.CGM]');
  WriteLn('          CEMGEMS /B [recette.CGM] [sortie.CSV]');
  WriteLn;
  WriteLn(' recette.CGM  Recette a ouvrir');
  WriteLn(' /B           Mode lot : calcule le processus de la recette et ecrit le CSV');
  Halt;
 End;
 If (UpStr(ParamStr(1)) = '/B') Or (UpStr(ParamStr(1)) = '-B') Then Begin
  BatchRun;
  Halt;
 End;
 InitializeGraphics;
 InitializeAll;
 SetViewPort(0, 0, ScreenWidth - 1, ScreenHeight - 1, True);
 If ParamCount >= 1 Then Begin
  If FileOK(ParamStr(1)) Then Begin
   If LoadRecipe(ParamStr(1), False) Then ;
  End
  Else StatusMsg := 'Fichier introuvable : ' + ParamStr(1);
 End;
 Modified := False;
 MainLoop;
 CloseGraph;
END.

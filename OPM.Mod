(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)


MODULE OPM;

(* Machine dependent constants needed before code generation *)
(* Host interface *)
(* RC, NM, pjm, prk 16.05.97 *)

	IMPORT
		FileDir, Fonts, Texts, Oberon, Files, SYSTEM;

	CONST (* i386 *)

		(* basic type sizes *)
		ByteSize* = 1;	(* SYSTEM.BYTE *)
		CharSize* = 1;	(* CHAR *)
		BoolSize* = 1;	(* BOOLEAN *)
		SetSize* = 4;	(* SET *)
		SIntSize* = 1;	(* SHORTINT *)
		IntSize* = 2;	(* INTEGER *)
		LIntSize* = 4;	(* LONGINT *)
		RealSize* = 4;	(* REAL *)
		LRealSize* = 8;	(* LONGREAL *)
		ProcSize* = 4;	(* PROCEDURE type *)
		PointerSize* = 4;	(* POINTER type *)

		(* value of constant NIL *)
		nilval* = 0;
		
		(* target machine minimum values of basic types expressed in host machine format: *)
		MinSInt* = -80H;
		MinInt* = -8000H;
		MinLInt* =  80000000H;	(* i386: -2147483648*)
		MinRealPat = 0FF7FFFFFH;	(* most  negative, 32-bit pattern *)
		MinLRealPatL = 0FFFFFFFFH;	(* most  negative, lower 32-bit pattern *)
		MinLRealPatH = 0FFEFFFFFH;	(* most  negative, higher 32-bit pattern *)
		
		(* target machine maximum values of basic types expressed in host machine format: *)
		MaxSInt* = 7FH;
		MaxInt* = 7FFFH;
		MaxLInt* = 7FFFFFFFH;	(* i386: 2147483647*)
		MaxSet* = 31;	(* must be >= 15, else the bootstraped compiler cannot run (IN-tests) *)
		MaxRealPat = 7F7FFFFFH;	(* most positive, 32-bit pattern *)
		MaxLRealPatL = 0FFFFFFFFH;	(* most positive, lower 32-bit pattern *)
		MaxLRealPatH = 7FEFFFFFH;		(* most positive, higher 32-bit pattern *)
		
		(* maximal index value for array declaration: *)
		MaxIndex* = MaxLInt;

		(* maximal bound value for array declaration: *)
		MinBound* = MinInt;  MaxBound* = MaxInt-1;

		(* parametrization of numeric scanner: *)
		MaxHDig* = 8;	(* maximal hexadecimal longint length *)
		MaxRExp* = 38;	(* maximal real exponent *)
		MaxLExp* = 308;	(* maximal longreal exponent *)
		
		(* inclusive range of parameter of standard procedure HALT: *)
		MinHaltNr* = 20;

		MaxHaltNr* = MAX(LONGINT);


		(* inclusive range of register number of procedures SYSTEM.GETREG and SYSTEM.PUTREG: *)
		MinRegNr* = 0;	(* interpretation is left to the back-end, e.g. for i386: *)
		MaxRegNr* = 7;	(* F0-F7 if second parameter is REAL or LONGREAL, R0-R7 else *)
		
		(* maximal value of flag used to mark interface structures: *)
		MaxSysFlag* = 0;	(* i386: only 0 is valid, not used *)
		
		(* maximal condition value of parameter of SYSTEM.CC: *)
		MaxCC* = -1;	(* not implemented interpretation is left to the back-end *)
		
		(* initialization of linkadr field in ObjDesc, must be different from any valid link address: *)
		LANotAlloc* = -1;
		
		(* initialization of constant address, must be different from any valid constant address: *)
		ConstNotAlloc* = -1;	(* i386: only strings are allocated *)
		
		(* initialization of tdadr field in StrDesc, must be different from any valid address: *)
		TDAdrUndef* = -1;
		
		(* maximal number of cases in a case statement: *)
		MaxCases* = 128;
		
		(* maximal range of a case statement (higher label - lower label ~ jump table size): *)
		MaxCaseRange* = 512;

		(* whether hidden pointer fields have to be nevertheless exported: *)
		ExpHdPtrFld* = TRUE;

		(* whether hidden procedure fields have to be nevertheless exported (may be used for System.Free): *)
		ExpHdProcFld* = FALSE;
		
		(* whether hidden bound procedures have to be nevertheless exported: *)
		ExpHdTProc* = FALSE;

		(* whether addresses of formal parameters are exported: *)
		ExpParAdr* = FALSE;

		(* whether addresses or entry numbers are exported for global variables: *)
		ExpVarAdr* = FALSE;


		allowProcesses* = FALSE;

		(* whether field leaf of pointer variable p has to be set to FALSE, when NEW(p) or SYSTEM.NEW(p, n) is used: *)

		NEWusingAdr* = TRUE;

		
		(* special character (< " ") returned by procedure Get, if end of text reached *)
		Eot* = 0X;
		SetLen = MAX(SET)+1;
		NumErrors = (912+SetLen) DIV SetLen * SetLen;

	VAR
		MinReal*, MaxReal*: REAL;
		MinLReal*, MaxLReal*: LONGREAL;
		noerr*: BOOLEAN;	(* no error found until now *)
		curpos*, errpos*: LONGINT;	(* character and error position in source file *)
		breakpc*: LONGINT;	(* set by OPV.Init *)
		breakpos*: LONGINT;	(* set by Mark *)
		errors: ARRAY NumErrors DIV SetLen OF SET;
		outputPath*: ARRAY 32 OF CHAR;		
		options*: SET; portable*: BOOLEAN;
		errName*: ARRAY 32 OF CHAR;
		first: BOOLEAN;

	CONST

	OFext = ".Obj";  SFext = ".Sym";


	OFversion = 36X;


		SFtag = 0F7X;	(* symbol file tag *)
		OFtag = 0F8X;	(* object file tag *)


	TYPE
		FileName = ARRAY 32 OF CHAR;
		
	VAR
		LRealPat: RECORD L, H: LONGINT END ;
		lastpos, pat: LONGINT;	(* last position error in source file *)
		refpatch: LONGINT;	(* OM: last position error in source file *)
		inR: Texts.Reader;
		Log: Texts.Text;
		W: Texts.Writer;
		oldSymF, newSymF, ObjF, RefF, ModF: Files.Rider;
		RefFile, ObjFile, ModFile, oldSymFile, newSymFile: Files.File;
		nopath: ARRAY 2 OF CHAR;
(*	SymFile	OM		now
		oldSF		-			oldSymF
		newSF	  SymF	  newSymF
		ObjF		 ObjF	  ObjF
		RefF		  RefF	   RefF
		-			   ModF	 ModF
		oldSFile	-			oldSymFile
		newSFile  SymFile  newSymFile
		ObjFile	  ObjFile  ObjFile
		RefFile	  RefFile    RefFile
		-			   ModFile  ModFile
*)
	PROCEDURE Init*(opt: SET; source: Texts.Reader; log: Texts.Text);
		CONST portblOpt = 17;
		VAR i: SHORTINT;
	BEGIN inR := source; Log := log; options := opt; portable := portblOpt IN opt;
		noerr := TRUE; curpos := Texts.Pos(inR); errpos := curpos; lastpos := curpos-10;
		FOR i := 0 TO NumErrors DIV SetLen - 1 DO errors[i] := {} END;
		Oberon.Collect
	END Init;
	
		PROCEDURE Close*; (* jm *)
		BEGIN
			Files.Set(oldSymF, NIL, 0); Files.Set(newSymF, NIL, 0); Files.Set(ObjF, NIL, 0); Files.Set(RefF, NIL, 0);
			oldSymFile := NIL; newSymFile := NIL; ObjFile := NIL;  RefFile := NIL;
		END Close;
		
	PROCEDURE Get*(VAR ch: CHAR);	(* read next character from source text, Eot if no more *)
	BEGIN
		(* System3 get: skip embedded objects *)
		REPEAT
			Texts.Read(inR, ch); INC(curpos)
		UNTIL inR.eot OR ((inR.lib # NIL) & (inR.lib IS Fonts.Font))
	END Get;
	
	PROCEDURE MakeFileName(VAR path, modName, fileName: ARRAY OF CHAR; ext: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN	i:=0; ch:=path[0];
		WHILE	ch#0X	DO	fileName[i]:=ch; INC(i); ch:=path[i]	END;
		IF (i # 0) & (path[i-1] # FileDir.PathChar) & (FileDir.PathChar # 0X) THEN fileName[i] := FileDir.PathChar; INC(i) END;
		j:=0; ch:=modName[0];
		WHILE	ch#0X	DO	fileName[i]:=ch; INC(i); INC(j); ch:=modName[j]	END;
		j := -1; REPEAT	INC(j); fileName[i] := ext[j]; INC(i)	UNTIL ext[j] = 0X
	END MakeFileName;


	PROCEDURE NewKey*(): LONGINT;
		VAR time, date: LONGINT;
	BEGIN Oberon.GetClock(time, date); RETURN (time MOD 20000H) * (date MOD 4000H)
	END NewKey;

	

	
	(* ----- auxiliaries ----- *)

	PROCEDURE WString(VAR R: Files.Rider; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN	i:=0; ch:=s[i];
		IF	ch=0X	THEN	Files.Write(R, 0X); RETURN	END;
		WHILE	(ch#0X) & (ch<7FX)	DO	INC(i); ch:=s[i]	END;
		IF	i>1	THEN	Files.WriteBytes(R, s, i-1)	END;
		IF	ch=0X	THEN	Files.Write(R, CHR(ORD(s[i-1])+80H))
		ELSE	
			IF	i>0	THEN	Files.Write(R, s[i-1])	END;
			Files.Write(R, 7FX); REPEAT	Files.Write(R, ch); INC(i); ch:=s[i]	UNTIL ch=0X;
			Files.Write(R, 0X)
		END
	END WString;

	(* ------------------------- Log Output ------------------------- *)
	
	PROCEDURE LogW*(ch: CHAR);
	BEGIN
		Texts.Write(W, ch); Texts.Append(Log, W.buf)
	END LogW;
	
	PROCEDURE LogWStr*(s: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, s); Texts.Append(Log, W.buf)
	END LogWStr;
	
	PROCEDURE LogWNum*(i, len: LONGINT);
	BEGIN
		Texts.WriteInt(W, i, len); Texts.Append(Log, W.buf)
	END LogWNum;

	PROCEDURE LogWHex*(i: LONGINT);
	BEGIN	Texts.WriteHex(W, i); Texts.Write(W, "H"); Texts.Append(Log, W.buf)
	END LogWHex;

	PROCEDURE LogWLn*;
	BEGIN
		Texts.WriteLn(W); Texts.Append(Log, W.buf)
	END LogWLn;
	
	PROCEDURE ErrorMsg(n: INTEGER);
	VAR s: Texts.Scanner; ch: CHAR;  e: ARRAY 127 OF CHAR;  i: SHORTINT;

	BEGIN
		IF (n >= NumErrors) OR ~((n MOD SetLen) IN errors[n DIV SetLen]) THEN
			IF (n < NumErrors) THEN INCL(errors[n DIV SetLen], n MOD SetLen) END;

			Oberon.OpenScanner(s, "OP2.Errors");

			IF s.class # Texts.Inval THEN
				REPEAT Texts.Scan(s) UNTIL s.eot OR (s.class = Texts.Int) & (s.i = 0);
				WHILE ~s.eot & ((s.class # Texts.Int) OR (s.i # n)) DO Texts.Scan(s) END;
				IF ~s.eot THEN Texts.Read(s, ch);  Texts.Write(W, 9X);  i := 0;
					WHILE ~s.eot & (ch # 0DX) DO e[i] := ch; INC(i); Texts.Read(s, ch) END;
					e[i] := 0X;  LogWStr(e)
				END
			ELSE
				IF first THEN

					LogWStr("Oberon.Text - OP2.Errors not found");  LogWLn;

					first := FALSE
				END
			END
		END
	END ErrorMsg;
	
	PROCEDURE Mark*(n: INTEGER; pos: LONGINT);
		CONST warning = 12;
	BEGIN
		IF n >= 0 THEN
			noerr := FALSE;
			IF (pos < lastpos) OR (lastpos + 9 < pos) OR (n>=450) & (n<=460) OR (n=155) THEN lastpos := pos;
				LogWLn; LogW(9X); LogW(9X);
				IF (n<450) OR (n>460) THEN
					LogWStr("pos"); LogWNum(pos, 7);
					IF n = 255 THEN LogWStr("  pc "); LogWHex(breakpc); breakpos := pos
					ELSIF n = 254 THEN LogWStr("  pc not found")
					ELSE LogWStr("  err"); LogWNum(n, 4);
						ErrorMsg(n)

					END
				ELSE LogWStr(errName);
					IF	n=450	THEN	LogWStr(" is no longer visible")
					ELSIF	n=451	THEN	LogWStr(" is new")
					ELSIF	n=452	THEN	LogWStr(" is redefined")
					END
				END
			END
		ELSIF warning IN options THEN
			LogWLn; LogW(9X); LogW(9X); LogWStr("pos"); LogWNum(pos, 7); LogWStr("  warning"); LogWNum(-n, 4);
			ErrorMsg(-n)
		END
	END Mark;
	
	PROCEDURE err*(n: INTEGER);
	BEGIN Mark(n, errpos)
	END err;

	(* ------------------------- Read Symbol File ------------------------- *)


	PROCEDURE SymRCh*(VAR ch: CHAR);
	BEGIN Files.Read(oldSymF, ch)
	END SymRCh;

	PROCEDURE SymRTag*(VAR k: INTEGER);
		VAR ch: CHAR;
	BEGIN Files.Read(oldSymF, ch); k := ORD(ch)
	END SymRTag;
	
	PROCEDURE SymRInt*(VAR k: LONGINT);
		VAR i: INTEGER;
	BEGIN Files.ReadInt(oldSymF, i); k := i
	END SymRInt;

	PROCEDURE SymRLInt*(VAR k: LONGINT);
	BEGIN Files.ReadLInt(oldSymF, k)
	END SymRLInt;
	
	PROCEDURE SymRSet*(VAR s: SET);
	BEGIN Files.ReadSet(oldSymF, s)
	END SymRSet;

	PROCEDURE SymRReal*(VAR r: REAL);
	BEGIN Files.ReadReal(oldSymF, r)
	END SymRReal;
	
	PROCEDURE SymRLReal*(VAR lr: LONGREAL);
	BEGIN Files.ReadLReal(oldSymF, lr)
	END SymRLReal;
	
	PROCEDURE CloseOldSym*;
	(* called only if OldSym previously returned done = TRUE *)
	END CloseOldSym;

	PROCEDURE OldSym*(VAR modName: ARRAY OF CHAR; self: BOOLEAN; VAR done: BOOLEAN);
	(* open file in read mode *)
		VAR ch: CHAR; fileName: FileName;
	BEGIN 
		MakeFileName(nopath, modName, fileName, SFext);
		oldSymFile := Files.Old(fileName); done := oldSymFile # NIL;
		IF done THEN
			Files.Set(oldSymF, oldSymFile, 0); SymRCh(ch);
			IF ch # SFtag THEN err(151);  (*not a symbol file*)
				CloseOldSym; done := FALSE
			END
		ELSIF ~self THEN err(152)   (*sym file not found*)
		END
	END OldSym;
	
	PROCEDURE eofSF*(): BOOLEAN;
	(* = TRUE if end of old file reached *)
	BEGIN RETURN oldSymF.eof
	END eofSF;

	
	(* ------------------------- Write Symbol File ------------------------- *)
	
	PROCEDURE SymW*(b: CHAR);
	BEGIN	Files.Write(newSymF, b)
	END SymW;

	PROCEDURE SymWCh*(ch: CHAR);
	BEGIN Files.Write(newSymF, ch)
	END SymWCh;

	PROCEDURE SymWTag*(k: INTEGER);
	BEGIN Files.Write(newSymF, CHR(k))
	END SymWTag;

	PROCEDURE SymWInt*(k: LONGINT);
	BEGIN Files.WriteInt(newSymF, SHORT(k))
	END SymWInt;

	PROCEDURE SymWLInt*(k: LONGINT);
	BEGIN Files.WriteLInt(newSymF, k)
	END SymWLInt;

	PROCEDURE SymWNum*(i: LONGINT);
	BEGIN	Files.WriteNum(newSymF, i)
	END SymWNum;

	PROCEDURE SymWPos*():LONGINT;
	BEGIN RETURN Files.Pos(newSymF)+Files.Pos(ModF);
	END SymWPos;

	PROCEDURE SymWMod*(VAR name: ARRAY OF CHAR);
	BEGIN  WString(ModF, name)
	END SymWMod;


	PROCEDURE SymWSet*(s: SET);
	BEGIN Files.WriteSet(newSymF, s)
	END SymWSet;


	PROCEDURE SymWReal*(r: REAL);
	BEGIN Files.WriteReal(newSymF, r)
	END SymWReal;
	
	PROCEDURE SymWLReal*(lr: LONGREAL);
	BEGIN Files.WriteLReal(newSymF, lr)
	END SymWLReal;
	
	PROCEDURE SymWString*(VAR s: ARRAY OF CHAR);
	BEGIN	WString(newSymF, s)
	END SymWString;


	PROCEDURE RegisterNewSym*(VAR modName: ARRAY OF CHAR);
	(* delete possibly already existing file with same name, register new created file *)
	BEGIN Files.Register(newSymFile)
	END RegisterNewSym;
	
	PROCEDURE DeleteNewSym*;
	(* delete new created file, don't touch possibly already existing file with same name *)
	END DeleteNewSym;

	PROCEDURE NewSym*(VAR modName: ARRAY OF CHAR; VAR done: BOOLEAN);
	(* open new file in write mode, don't touch possibly already existing file with same name *)
		VAR fileName: FileName;
	BEGIN 
		MakeFileName(outputPath, modName, fileName, SFext);
		newSymFile := Files.New(fileName); done := newSymFile # NIL;
		IF done THEN Files.Set(newSymF, newSymFile, 0);
			SymWCh(SFtag)
		ELSE err(153)
		END
	END NewSym;

	PROCEDURE EqualSym*(VAR oldkey: LONGINT): BOOLEAN;
	(* compare old and new Symbol File, close old file, return TRUE if equal *)
		VAR ch0, ch1: CHAR; equal: BOOLEAN;
	BEGIN
		Files.Set(oldSymF, oldSymFile, 2); Files.ReadLInt(oldSymF, oldkey); Files.Set(newSymF, newSymFile, 6);
		REPEAT Files.Read(oldSymF, ch0); Files.Read(newSymF, ch1)
		UNTIL (ch0 # ch1) OR newSymF.eof;
		equal := oldSymF.eof & newSymF.eof; CloseOldSym;
		RETURN equal
	END EqualSym;


	(* ------------------------- Write Reference & Object Files ------------------------- *)

	PROCEDURE RefW*(ch: CHAR);
	BEGIN Files.Write(RefF, ch)
	END RefW;

	PROCEDURE RefWNum* (i: LONGINT);
	BEGIN
		Files.WriteNum (RefF, i)
	END RefWNum;

(* no longer used
	PROCEDURE RefWInt*(i: INTEGER);
	BEGIN Files.WriteInt(RefF, i)
	END RefWInt;

	PROCEDURE RefWLInt*(i: LONGINT);
	BEGIN Files.WriteLInt(RefF, i)
	END RefWLInt;
*)

	PROCEDURE ObjW*(ch: CHAR);
	BEGIN Files.Write(ObjF, ch)
	END ObjW;

	PROCEDURE ObjWInt*(i: INTEGER);
	BEGIN Files.WriteInt(ObjF, i)
		(* Files.WriteBytes(ObjF, i, 2)	*)		(* Was OM, but is equivalent on little-endian machines *)
	END ObjWInt;

	PROCEDURE ObjWLInt*(i: LONGINT);
	BEGIN Files.WriteLInt(ObjF, i)
		(* Files.WriteBytes(ObjF, i, 4)	*)		(* Was OM, but is equivalent on little-endian machines *)
	END ObjWLInt;

	PROCEDURE ObjWBytes*(VAR bytes: ARRAY OF SYSTEM.BYTE; n: LONGINT);
	BEGIN Files.WriteBytes(ObjF, bytes, n)
	END ObjWBytes;

	PROCEDURE ObjWNum*(i: LONGINT);
	BEGIN	Files.WriteNum(ObjF, i)
	END ObjWNum;

	PROCEDURE ObjWString*(VAR s: ARRAY OF CHAR);			(* OM only *)
	BEGIN	WString(ObjF, s)
	END ObjWString;

	PROCEDURE ObjAllocInt*(): LONGINT;			(* OM only *)
		VAR pos: LONGINT;
	BEGIN	pos:=Files.Pos(ObjF); Files.WriteInt(ObjF, SYSTEM.VAL(INTEGER, 0));
		RETURN pos;
	END ObjAllocInt;

	PROCEDURE ObjFillInt*(pos: LONGINT; int: INTEGER);			(* OM only *)
		VAR savepos: LONGINT;
	BEGIN	savepos:=Files.Pos(ObjF);
		Files.Set(ObjF, ObjFile, pos); Files.WriteBytes(ObjF, int, 2);
		Files.Set(ObjF, ObjFile, savepos);
	END ObjFillInt;


	PROCEDURE OpenRefObj*(VAR modName: ARRAY OF CHAR);
		VAR FName: ARRAY 32 OF CHAR;
	BEGIN
		RefFile := Files.New(""); Files.Set(RefF, RefFile, 0);
		MakeFileName(outputPath, modName, FName, OFext);
		ObjFile := Files.New(FName);
		IF ObjFile # NIL THEN
			Files.Set(ObjF, ObjFile, 0);
			ObjW(OFtag); ObjW(OFversion); ObjWInt(0); ObjWInt(0)
		ELSE err(153)
		END
	END OpenRefObj;

	PROCEDURE CloseRefObj*;
		VAR refpos: LONGINT; ch: CHAR; ref: Files.Rider;
	BEGIN (*ref block*)
		refpos := Files.Pos(ObjF); 
		Files.Set(ref, RefFile, 0); Files.Read(ref, ch);
		WHILE ~ref.eof DO ObjW(ch); Files.Read(ref, ch) END ;
		Files.Set(ObjF, ObjFile, 2); ObjWLInt(Files.Length(RefFile));
		Files.Register(ObjFile)
	END CloseRefObj;


BEGIN
	pat := MinRealPat; SYSTEM.MOVE(SYSTEM.ADR(pat), SYSTEM.ADR(MinReal), 4);	(*i386: -3.40282346E38*)
	pat := MaxRealPat; SYSTEM.MOVE(SYSTEM.ADR(pat), SYSTEM.ADR(MaxReal), 4);	(*i386: 3.40282346E38*)
	LRealPat.L := MinLRealPatL; LRealPat.H := MinLRealPatH;
	SYSTEM.MOVE(SYSTEM.ADR(LRealPat), SYSTEM.ADR(MinLReal), 8);	(*i386: -1.7976931348623157D308*)
	LRealPat.L := MaxLRealPatL; LRealPat.H := MaxLRealPatH;
	SYSTEM.MOVE(SYSTEM.ADR(LRealPat), SYSTEM.ADR(MaxLReal), 8);	(*i386: 1.7976931348623157D308*)
	Texts.OpenWriter(W); Log := Oberon.Log;
	outputPath := "";
	first := TRUE

END OPM.


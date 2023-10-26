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


MODULE Compiler;

(* RC, NM, jm, rml, pjm, prk 16.07.97 *)

	IMPORT
		Modules, Kernel, Files, Objects, Display, Texts, Oberon,


		OPP, OPB, OPV, OPT, OPS, OPC, OPL, OPO, OPM;

	
	CONST
		ShowCommand = "OPdump.ShowProg";
		ShowTableCommand = "OPdump.ShowTable";
		
		(* compiler options: *)
		inxchk = 0;	(* index check on *)
		ovflchk = 1;	(* overflow check on *)
		typchk = 3;	(* type check on *)
		ptrinit = 5;	(* pointer initialization *)
		assert = 6;	(* assert evaluation *)
		findpc = 7;	(* find text position of breakpc *)
		systemchk = 8;	(* prevent compilation of modules that import SYSTEM *) (* jm *)
		nofiles = 9;	(* don't create any files (dVdW) *)
		extsf = 11;	(* e - generation of extended symbol file allowed *)
		warning = 12;	(* w - display warnings *)
		update = 13;	(* u - compile only if necessary *)
		portable = 17;	(* P/N - portable/native *)
		prefix = 18;	(* X - retain filename prefix on .Sym & .Obj file (Native) *)
		oberon2 = 19; 	(* 2 - compile oberon-2 programs *)


		newsf = 4;	(* generation of new symbol file allowed *)
		DefOpt = {inxchk, typchk, ptrinit, assert};


		noarrinit = 14;

	VAR
		prog*: OPT.Node;
		ModName*: ARRAY 32 OF CHAR;


		dpath: ARRAY 32 OF CHAR;




		S: Texts.Scanner;
		W: Texts.Writer;


	PROCEDURE SignOn;
	BEGIN

		Texts.WriteString(W, "Oberon Portable Compiler / nw, rc, nm, tk, prk"); Texts.WriteLn(W);
		Texts.WriteString(W, OPP.SignOnMessage); Texts.WriteLn(W); 
		Texts.Append(Oberon.Log, W.buf)
	END SignOn;
				

	PROCEDURE Loaded(name: ARRAY OF CHAR): BOOLEAN;
	VAR m: Modules.Module;
	BEGIN
	
		m := Kernel.modules;
		WHILE m # NIL DO
			IF m.name = name THEN RETURN TRUE END;
			m := m.next
		END;
	
		RETURN FALSE
	END Loaded;

	
	(* Returns the frame that is at X, Y on the display. u, v contain the relative coordinates inside this frame *)
	PROCEDURE ThisFrame(X, Y: INTEGER; VAR F: Display.Frame);
	VAR M: Display.LocateMsg;
	BEGIN M.X := X; M.Y := Y; M.F := NIL; M.loc := NIL; Display.Broadcast(M); F := M.loc
	END ThisFrame;
	
	(* Get the marked text *)
	PROCEDURE GetText(VAR par: Display.Frame): Texts.Text;
	VAR M: Objects.LinkMsg; t: Texts.Text;
	BEGIN
		t := NIL;
		ThisFrame(Oberon.Pointer.X+1, Oberon.Pointer.Y+1, par);
		IF par # NIL THEN
			M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; par.handle(par, M);
			IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN t := M.obj(Texts.Text) END
		END;
		RETURN t
	END GetText;

	PROCEDURE Module*(source: Texts.Reader; options: ARRAY OF CHAR; breakpc: LONGINT;
										log: Texts.Text; VAR error: BOOLEAN);
		VAR key: LONGINT; opt: SET; ch: CHAR; extSF, newSF: BOOLEAN;
			p: OPT.Node; modName: OPS.Name;
			res, i: INTEGER;
			command: ARRAY 32 OF CHAR;
	BEGIN

		opt := DefOpt; i := 0;
		REPEAT
			ch := options[i]; INC(i);
			IF ch = "x" THEN opt := opt / {inxchk}
			ELSIF ch = "v" THEN opt := opt / {ovflchk}
			ELSIF ch = "t" THEN opt := opt / {typchk}
			ELSIF ch = "s" THEN opt := opt / {newsf}
			ELSIF ch = "p" THEN opt := opt / {ptrinit}
			ELSIF ch = "a" THEN opt := opt / {assert}
			ELSIF ch = "S" THEN opt := opt / {systemchk}
			ELSIF ch = "n" THEN opt := opt / {nofiles}
			ELSIF ch = "e" THEN opt := opt / {extsf}
			ELSIF ch = "f" THEN opt := opt / {findpc}; opt := opt - {portable}
			ELSIF ch = "w" THEN opt := opt / {warning}
			ELSIF ch = "u" THEN opt := opt / {update}
			ELSIF ch = "P" THEN opt := opt + {portable}
			ELSIF ch = "N" THEN opt := opt - {portable}
			ELSIF ch = "X" THEN opt := opt + {prefix}
			ELSIF ch = "2" THEN opt := opt / {oberon2}

			ELSIF ch = "i" THEN opt := opt + {noarrinit}

			END
		UNTIL ch = 0X;
		IF nofiles IN opt THEN EXCL(opt, newsf) END;
		OPM.Init(opt, source, log);

		OPT.Init; OPV.Init(opt, breakpc);
		OPB.typSize := OPV.TypSize;
		newSF := newsf IN opt;
		OPT.OpenScope(0, NIL);
		OPP.Module(p, modName, opt, systemchk IN opt);

		IF OPM.noerr THEN

			OPL.Init;
			OPV.AdrAndSize(OPT.topScope);
			OPM.errpos := 0;
			key := OPM.NewKey();
			OPT.Export(modName, newSF, key);

			IF newSF THEN OPM.LogWStr(" new symbol file")
			ELSIF extSF THEN OPM.LogWStr(" extended symbol file")
			END;


			IF OPM.noerr THEN
				OPM.OpenRefObj(modName);
				OPC.Init(opt); (*OPV.Init(opt, breakpc);*)
				OPV.Module(p);
				IF OPM.noerr THEN
					OPL.OutCode(modName, key);
					IF OPM.noerr THEN 
						IF ~(nofiles IN opt) THEN OPM.CloseRefObj END;
						OPM.LogWStr ("   "); OPM.LogWNum(OPO.pc, 1); 

						IF Loaded(modName) THEN OPM.LogWStr("  (in use)") END

					END
				END
			END ;
			OPL.Close

		END ;
		OPT.CloseScope; OPT.Close;
		OPM.LogWLn; error := ~OPM.noerr;

		OPT.Init; OPM.Close;
		OPS.Init;


	END Module;
	
	PROCEDURE CompileFile*(name, options: ARRAY OF CHAR; breakpc: LONGINT; log: Texts.Text; VAR error: BOOLEAN);
	CONST SourceCoder = 011FFH;
	VAR F: Files.File; R: Files.Rider; tag: INTEGER; cmd: ARRAY 64 OF CHAR; par: Texts.Text; pos: LONGINT;
		source: Texts.Text;  sourceR: Texts.Reader;
	BEGIN
		source := NIL; F := Files.Old(name);
		IF F # NIL THEN
			Files.Set(R, F, 0); Files.ReadInt(R, tag);
			IF tag = SourceCoder THEN
				OPS.Get := NIL;
				Files.ReadString(R, cmd);
				par := Oberon.Par.text; pos := Oberon.Par.pos;
				NEW(Oberon.Par.text); Texts.Open(Oberon.Par.text, ""); Oberon.Par.pos := 0; Texts.WriteString(W, name);
				Texts.Append(Oberon.Par.text, W.buf);
				Oberon.Call(cmd, Oberon.Par, FALSE, tag);
				Oberon.Par.text := par; Oberon.Par.pos := pos;
				IF OPS.Get # NIL THEN NEW(source); Texts.Open(source, "")
				ELSE
					Texts.WriteString(W, cmd); Texts.WriteString(W, " not found");
					Texts.WriteLn(W); Texts.Append(log, W.buf)
				END
			ELSE NEW(source); Texts.Open(source, name)
			END
		ELSE
			Texts.WriteString(W, name); Texts.WriteString(W, " not found");
			Texts.WriteLn(W); Texts.Append(log, W.buf)
		END;
		IF source # NIL THEN
			error := FALSE;
			Texts.OpenReader(sourceR, source, 0);
			OPS.Init;
			Module(sourceR, options, breakpc, log, error)
		ELSE error := TRUE;
		END
	END CompileFile;
	
	PROCEDURE Compile*;
		VAR beg, end, time: LONGINT; error: BOOLEAN; ch: CHAR; F: Display.Frame;
			defopt: ARRAY 32 OF CHAR;  SourceCoder: BOOLEAN;  source: Texts.Text;  sourceR: Texts.Reader;

		PROCEDURE GetOptions(VAR options: ARRAY OF CHAR);
			VAR i: SHORTINT;
		BEGIN	i:=0; 
			ch := S.nextCh; i:=0;
			WHILE ((ch >= "0") & (ch <= "9") OR (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")) DO	
				i:=0; WHILE (options[i]#ch) & (options[i]#0X) DO INC(i) END;
				IF options[i]=0X THEN options[i]:=ch; options[i+1]:=0X END;
				Texts.Read(S, ch)	
			END;
			S.nextCh := ch; Texts.Scan(S)
		END GetOptions;
		
		PROCEDURE InOptions(VAR options: ARRAY OF CHAR; opt: CHAR): BOOLEAN;
			VAR i: INTEGER;
		BEGIN	i:=0; WHILE (options[i]#opt) & (options[i]#0X) DO INC(i) END;
			RETURN options[i]#0X;
		END InOptions;

		PROCEDURE Locate(F: Display.Frame;  T: Texts.Text;  pos: LONGINT);
		VAR M: Oberon.CaretMsg;  N: Oberon.ControlMsg;
		BEGIN
			IF pos < 0 THEN pos := 0
			ELSIF pos > T.len THEN pos := T.len
			END;
            N.F := NIL; N.id := Oberon.neutralize; Display.Broadcast(N);
            Oberon.FadeCursor(Oberon.Pointer);
			M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
		END Locate;

		PROCEDURE ScanModName(source: Texts.Text;  beg: LONGINT;  VAR name: ARRAY OF CHAR);
		VAR S1: Texts.Scanner;  i: INTEGER;
		BEGIN
			name[0] := 0X;
			Texts.OpenScanner(S1, source, beg); Texts.Scan(S1);
			WHILE ~S1.eot & ((S1.class # Texts.Name) OR (S1.s # "MODULE")) DO Texts.Scan(S1) END;
			IF (S1.class = Texts.Name) & (S1.s = "MODULE") THEN
				Texts.Scan(S1);
				IF S1.class = Texts.Name THEN COPY (S1.s, name) END
			END
		END ScanModName;
		
		PROCEDURE Do(filename: ARRAY OF CHAR; beg: LONGINT; options: ARRAY OF CHAR;  F: Display.Frame);
			VAR S1: Texts.Scanner; line, i: INTEGER;
				fbeg, fend, ftime, breakpc: LONGINT; ftext: Texts.Text; f, prefix: BOOLEAN;

		BEGIN
			line := S.line; i := 0; f := FALSE; Texts.Scan(S);
			IF (S.line = line) & (S.class = Texts.Char) & ((S.c = Oberon.OptionChar) OR (S.c = "%")) THEN GetOptions(options) END;
			
			prefix := InOptions(options, "X");
			IF prefix THEN	(* copy prefix to path *)
				i := -1;  REPEAT INC(i);  OPM.outputPath[i] := filename[i] UNTIL (filename[i] = 0X) OR (filename[i] = ".");
				IF OPM.outputPath[i] # 0X THEN
					INC(i);  OPM.outputPath[i] := 0X
				END
			END;
			
			Texts.WriteString(W, filename); Texts.WriteString(W, "  compiling  ");
			IF ~SourceCoder THEN
				ScanModName(source, beg, ModName);
				IF ModName # "" THEN
					IF prefix THEN Texts.WriteString(W, OPM.outputPath) END;
					Texts.WriteString(W, ModName)
				END
			END;
			Texts.Append(Oberon.Log, W.buf);
			
			IF InOptions(options, "f") THEN
				Oberon.GetSelection(ftext, fbeg, fend, ftime);
				IF ftime >= 0 THEN
					Texts.OpenScanner(S1, ftext, fbeg); Texts.Scan(S1); line := S1.line;
					WHILE (S1.class # Texts.Int) & (S1.line = line) DO Texts.Scan(S1) END
				ELSE
					S1.class := Texts.Inval
				END;
				IF S1.class = Texts.Int THEN
					breakpc := S1.i; f := TRUE
				ELSE
					Texts.WriteString(W, "  pc not selected"); Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf); error := TRUE;
					RETURN
				END
			END;

			IF TRUE THEN 

				Texts.OpenReader(sourceR, source, beg);
				OPS.Init;
				Module(sourceR, options, breakpc, Oberon.Log, error);
				IF prefix THEN COPY(dpath, OPM.outputPath) END;
				IF f & (F # NIL) THEN Locate(F, source, OPM.breakpos) END
			END
		END Do;

		PROCEDURE OpenSource(VAR name: ARRAY OF CHAR; VAR text: Texts.Text; options: ARRAY OF CHAR);	(* ejz, 19.4.95 *)
		CONST SCTag = 011FFH;
		VAR F: Files.File; R: Files.Rider; tag: INTEGER; cmd: ARRAY 64 OF CHAR; par: Texts.Text; pos: LONGINT;
		BEGIN
			OPS.Get := NIL; SourceCoder := FALSE;
			F := Files.Old(name); par := NIL;
			IF F # NIL THEN
				Files.Set(R, F, 0);
				Files.ReadInt(R, tag);
				IF tag = SCTag THEN
					Files.ReadString(R, cmd);
					par := Oberon.Par.text; pos := Oberon.Par.pos;
					NEW(Oberon.Par.text); Texts.Open(Oberon.Par.text, ""); Oberon.Par.pos := 0; Texts.WriteString(W, name);
					Texts.Append(Oberon.Par.text, W.buf);
					Oberon.Call(cmd, Oberon.Par, FALSE, tag);
					Oberon.Par.text := par; Oberon.Par.pos := pos;
					IF OPS.Get # NIL THEN Texts.Open(text, ""); SourceCoder := TRUE
					ELSE text := NIL
					END
				ELSE Texts.Open(text, name)
				END
			ELSE text := NIL
			END;
			IF (par = NIL) & ((text = NIL) OR (text.len = 0)) THEN error := TRUE;
				Texts.WriteString(W, name); Texts.WriteString(W, " not found");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			ELSE Do(name, 0, options, NIL)
			END
		END OpenSource;

	BEGIN

		error := FALSE;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		defopt[0]:=0X; COPY(dpath, OPM.outputPath); OPS.Get := NIL; SourceCoder := FALSE;

		IF (S.class = Texts.Char) & (S.c # Oberon.OptionChar) THEN
			IF S.c = "*" THEN
				source := GetText(F);
				IF source # NIL THEN Do("", 0, defopt, F) END
			ELSIF S.c = "^" THEN
				Oberon.GetSelection(source, beg, end, time);
				IF time >= 0 THEN
					Texts.OpenScanner(S, source, beg); Texts.Scan(S); NEW(source); 
					IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) & (Texts.Pos(S) - S.len <= end) THEN
						defopt[0] := 0X; GetOptions(defopt)
					END;
					WHILE (S.class IN {Texts.Name, Texts.String}) & (Texts.Pos(S) - S.len <= end) & ~error DO
						OpenSource(S.s, source, defopt)	(* ejz, 19.4.95 *)
					END
				END
			ELSIF S.c = "@" THEN
				Oberon.GetSelection(source, beg, end, time);
				IF time >= 0 THEN Do("", beg, defopt, NIL) END
			END
		ELSE NEW(source);
			IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) & ~error THEN
				defopt[0] := 0X; GetOptions(defopt)
			END;
			WHILE (S.class IN {Texts.Name, Texts.String}) & ~error DO
				OpenSource(S.s, source, defopt) (* ejz, 19.4.95 *)
			END
		END;

		COPY(dpath, OPM.outputPath)
	END Compile;



BEGIN

	prog := NIL; Texts.OpenWriter(W); SignOn

END Compiler.


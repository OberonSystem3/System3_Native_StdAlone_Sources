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

MODULE System; (*JG 3.10.90 / NW 26.11.91 / ARD 4. 2. 93 / nm / jm / pjm 09.02.96 *)

  IMPORT SYSTEM, Kernel, Modules, Files, FileDir, Display, Disk, Viewers,
    Oberon, Objects, Texts, TextFrames, Fonts, Input, Reals;

  VAR W, V: Texts.Writer;
    trapped: SHORTINT; 
	resetfp: Modules.Command;
	init: BOOLEAN;
	count, total, trap: LONGINT;
	detail: BOOLEAN;

  PROCEDURE OpenText(title: ARRAY OF CHAR; T: Texts.Text; system: BOOLEAN);
  	VAR W: INTEGER;
  BEGIN	
  	IF system THEN W := Display.Width DIV 8*3 - 20 ELSE W := Display.Width DIV 8*3 + 20 END;
  	Oberon.OpenText(title, T, W, 200)
  END OpenText;

  (* ------------- Toolbox for system control ---------------*)

  PROCEDURE SetFont*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text; S: Texts.Scanner;
      f: Fonts.Font;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN
        	f := Fonts.This(S.s);
        	IF f # NIL THEN Oberon.SetFont(f) END
        END
      END
    ELSIF S.class = Texts.Name THEN 
		f := Fonts.This(S.s);
		IF f # NIL THEN Oberon.SetFont(f) END
    END
  END SetFont;

  PROCEDURE SetColor*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text; S: Texts.Scanner; ch: CHAR;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenReader(S, T, beg); Texts.Read(S, ch); Oberon.SetColor(S.col)
      END
    ELSIF S.class = Texts.Int THEN Oberon.SetColor(SHORT(SHORT(S.i)))
    END
  END SetColor;

  PROCEDURE SetOffset*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text;S: Texts.Scanner; ch: CHAR;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenReader(S, T, beg); Texts.Read(S, ch); Oberon.SetOffset(S.voff)
      END
    ELSIF S.class = Texts.Int THEN Oberon.SetOffset(SHORT(SHORT(S.i)))
    END
  END SetOffset;
  
  PROCEDURE Time*;
  VAR par: Oberon.ParList;
      S: Texts.Scanner;
      t, d, hr, min, sec, yr, mo, day: LONGINT;
  BEGIN par := Oberon.Par;
    Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
    IF S.class = Texts.Int THEN (*set date*)
      day := S.i; Texts.Scan(S); mo := S.i; Texts.Scan(S); yr := S.i; Texts.Scan(S);
      hr := S.i; Texts.Scan(S); min := S.i; Texts.Scan(S); sec := S.i;
      t := (hr*64 + min)*64 + sec; d := (yr*16 + mo)*32 + day;
      Kernel.SetClock(t, d)
    ELSE (*read date*)
      Texts.WriteString(W, "System.Time");
      Oberon.GetClock(t, d); Texts.WriteDate(W, t, d); Texts.WriteLn(W);
      Texts.Append(Oberon.Log, W.buf)
    END
  END Time;

  PROCEDURE Collect*;
  BEGIN Oberon.Collect
  END Collect;

  (* ------------- Toolbox for standard display ---------------*)

  PROCEDURE Open*;
  VAR par: Oberon.ParList;
      T: Texts.Text;
      S: Texts.Scanner;
      beg, end, time: LONGINT;
  BEGIN
    par := Oberon.Par;
    Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") OR (S.line # 0) THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    IF S.class = Texts.Name THEN
      OpenText(S.s, TextFrames.Text(S.s), TRUE)
    END
  END Open;

  PROCEDURE OpenLog*;
  BEGIN
    OpenText("System.Log", Oberon.Log, TRUE);
  END OpenLog;

PROCEDURE Clear*;
VAR S: Texts.Scanner; par: Oberon.ParList; F: Display.Frame; L: Objects.LinkMsg; A: Objects.AttrMsg;
BEGIN	(* ejz *)
	par := Oberon.Par; F := NIL;
	L.id := Objects.get; L.name := "Model"; L.obj := NIL;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "*") THEN
		F := Oberon.MarkedFrame()
	ELSIF (par.vwr # NIL) & (par.vwr.dsc # NIL) THEN
		F := par.vwr.dsc.next;
		F.handle(F, L);
		IF (L.obj # NIL) & (L.obj IS Display.Frame) THEN
			A.id := Objects.get; A.name := "Gen"; L.obj.handle(L.obj, A);
			IF A.s = "PanelDocs.NewDoc" THEN (* Desktop *)
				F := Oberon.Par.obj(Display.Frame);
				F := F.dlink(Display.Frame);
				F := F.next.dsc
			ELSE
				F := L.obj(Display.Frame)
			END
		END
	END;
	IF F # NIL THEN
		F.handle(F, L);
		IF (L.obj # NIL) & (L.obj IS Texts.Text) THEN
			Texts.Delete(L.obj(Texts.Text), 0, L.obj(Texts.Text).len)
		END
	END
END Clear;

  PROCEDURE Close*;
  VAR par: Oberon.ParList; V: Viewers.Viewer; 
  BEGIN par := Oberon.Par;
    IF par.frame = par.vwr.dsc THEN V := par.vwr
    ELSE V := Oberon.MarkedViewer()
    END;
    Viewers.Close(V)
  END Close;

  PROCEDURE CloseTrack*;
  VAR V: Viewers.Viewer;
  BEGIN V := Oberon.MarkedViewer(); Viewers.CloseTrack(V.X)
  END CloseTrack;

  PROCEDURE Recall*;
  VAR V: Viewers.Viewer; M: Display.ControlMsg;
  BEGIN
    Viewers.Recall(V);
    IF (V#NIL) & (V.state = 0) THEN
      Viewers.Open(V, V.X, V.Y + V.H); M.F := NIL; M.id := Display.restore; V.handle(V, M)
    END
  END Recall;

  PROCEDURE Copy*;
  VAR V, V1: Viewers.Viewer; M: Objects.CopyMsg; N: Display.ControlMsg;
  BEGIN
        M.id := Objects.shallow;
    V := Oberon.Par.vwr; V.handle(V, M); V1 := M.obj(Viewers.Viewer);
    Viewers.Open(V1, V.X, V.Y + V.H DIV 2);
    N.F := NIL; N.id := Display.restore; V1.handle(V1, N)
  END Copy;

  PROCEDURE Grow*;
  VAR par: Oberon.ParList; V, V1: Viewers.Viewer; M: Objects.CopyMsg; N: Display.ControlMsg;
      DW, DH: INTEGER;
  BEGIN par := Oberon.Par;
    IF par.frame = par.vwr.dsc THEN V := par.vwr
    ELSE V := Oberon.MarkedViewer()
    END;
    DW := Oberon.DisplayWidth(V.X); DH := Oberon.DisplayHeight(V.X);
    IF V.H < DH - Viewers.minH THEN Oberon.OpenTrack(V.X, V.W)
    ELSIF V.W < DW THEN Oberon.OpenTrack(Oberon.UserTrack(V.X), DW)
    END;
    IF (V.H < DH - Viewers.minH) OR (V.W < DW) THEN
      M.id := Objects.shallow;
            V.handle(V, M); V1 := M.obj(Viewers.Viewer);
      Viewers.Open(V1, V.X, DH);
      N.F := NIL; N.id := Display.restore; V1.handle(V1, N)
    END
  END Grow;

  (* ------------- Toolbox for module management ---------------*)

    PROCEDURE Free*;
    VAR par: Oberon.ParList; S: Texts.Scanner; F: TextFrames.Frame; time, beg, end, pos: LONGINT; T: Texts.Text;
            
      PROCEDURE FreeFile;
      BEGIN
        (*IF S.nextCh # "*" THEN Modules.Free(S.s, FALSE)
        ELSE Modules.Free(S.s, TRUE); Texts.Scan(S)
        END*);
        Modules.Free(S.s, FALSE);
        IF Modules.res = 0 THEN
          Texts.WriteString(W, S.s); Texts.WriteString(W, " unloaded")
        ELSE
          Texts.WriteString(W, Modules.resMsg)
        END;
        Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
      END FreeFile;
            
    BEGIN par := Oberon.Par;
       Oberon.GetSelection(T, beg, end, time);
       Texts.WriteString(W, "System.Free"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
        IF par.vwr.dsc # par.frame THEN
          Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
          IF (S.class = Texts.Char) & (S.c = "^") THEN
            IF time >= 0 THEN
              Texts.OpenScanner(S, T, beg); pos := Texts.Pos(S)-1; Texts.Scan(S);
              WHILE ~S.eot & (S.class = Texts.Name) & (pos < end) DO
                beg := 0;  WHILE (S.s[beg] # 0X) & (S.s[beg] # ".") DO INC(beg) END;
                S.s[beg] := 0X;  FreeFile;  pos := Texts.Pos(S); Texts.Scan(S);
                WHILE ~S.eot & (S.class = Texts.Int) DO pos := Texts.Pos(S); Texts.Scan(S) END
              END
            END
          ELSE
            WHILE S.class = Texts.Name DO FreeFile; Texts.Scan(S) END
          END
        ELSE
          F := par.vwr.dsc.next(TextFrames.Frame);
          IF F.sel > 0 THEN
            Texts.OpenScanner(S, F.text, F.selbeg.pos);      
            WHILE ~S.eot & (Texts.Pos(S) < F.selend.pos) DO Texts.Scan(S); 
              IF S.class = Texts.Name THEN FreeFile;
                IF Modules.res = 0 THEN
                  Texts.OpenReader(S, F.text, F.selbeg.pos); 
                  REPEAT Texts.Read(S, S.nextCh) UNTIL S.eot OR (S.nextCh = 0DX);
                  Texts.Delete(F.text, F.selbeg.pos, Texts.Pos(S)); 
                  DEC(F.selend.pos, Texts.Pos(S) - F.selbeg.pos);
                  Texts.OpenScanner(S, F.text, F.selbeg.pos);
                END
              ELSE F.selbeg.pos := Texts.Pos(S)
              END
            END
          END
        END
    END Free;

  PROCEDURE ShowModules*;
  VAR T: Texts.Text;
      M: Modules.Module;
      size, n, t: LONGINT;
  BEGIN T := TextFrames.Text("");
    M := Kernel.modules; n := 0; t := 0;
    WHILE M # NIL DO
      size := SIZE(LONGINT) * (LEN(M.varEntries)+LEN(M.entries)+LEN(M.ptrTab)+
      	LEN(M.tdescs)+LEN(M.imports)) + SIZE(Kernel.Cmd)*LEN(M.cmds) + 
      	LEN(M.data)+LEN(M.code);
      IF (SYSTEM.VAL(LONGINT, M.refs) # 0) & (LEN(M.refs) # 0) THEN INC(size, LEN(M.refs)) END;
      Texts.WriteString(W, M.name); Texts.WriteInt(W, size, 8);
      Texts.WriteInt(W, M.refcnt, 4); 
      Texts.WriteLn(W); M := M.next;
      INC(n); INC(t, size)
    END;
    IF n > 1 THEN
      Texts.WriteLn(W); Texts.WriteInt(W, n, 1); Texts.WriteString(W, " modules use ");
      Texts.WriteInt(W, (t+512) DIV 1024, 1); Texts.WriteString(W, "K bytes")
    END;
    Texts.WriteLn(W); Texts.Append(T, W.buf);
    OpenText("Modules|System.Close System.Free Edit.Store", T, TRUE)
  END ShowModules;

   (* ------------- Toolbox for library management ---------------*)
		
  PROCEDURE ListLibrary (L: Objects.Library);
  BEGIN Texts.WriteString(W, L.name); Texts.WriteLn(W); INC(count)
  END ListLibrary;

  PROCEDURE ShowLibraries*;
  VAR t: Texts.Text;
  BEGIN t := TextFrames.Text(""); count := 0;
    Objects.Enumerate(ListLibrary);
    IF count > 1 THEN
      Texts.WriteLn(W);  Texts.WriteInt(W, count, 1);  Texts.WriteString(W, " public libraries")
    END;
    Texts.WriteLn(W);  Texts.Append(t, W.buf);
    OpenText("Libraries", t, TRUE)
  END ShowLibraries;

  PROCEDURE FreeLibraries*;
    VAR par: Oberon.ParList;
      T: Texts.Text; S: Texts.Scanner;
      beg, end, time: LONGINT;
  BEGIN		
    par := Oberon.Par;
    Texts.WriteString(W, "System.FreeLibraries "); Texts.WriteLn(W);
    Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    WHILE S.class = Texts.Name DO
      Objects.FreeLibrary(S.s); Texts.WriteString(W,S.s); Texts.WriteLn(W);
      Texts.Scan(S);
    END;
    Texts.Append(Oberon.Log, W.buf)
  END FreeLibraries;

 (* ------------- Toolbox of file system ---------------*)

  PROCEDURE *List(name: ARRAY OF CHAR;  time, date, size: LONGINT; 
  		VAR cont: BOOLEAN);
  BEGIN
    INC(count);
    Texts.WriteString(W, name);
    IF (time # 0) & (date # 0) & (size # MIN(LONGINT)) THEN
      Texts.WriteString(W, "  "); Texts.WriteDate(W, time, date);
      Texts.WriteString(W, "  "); Texts.WriteInt(W, size, 5); INC(total, size)
    END;
    Texts.WriteLn(W)
  END List;

  PROCEDURE Directory*;
  VAR par: Oberon.ParList;
      R: Texts.Reader;
      T, t: Texts.Text;
      beg, end, time: LONGINT;
      i: INTEGER;
      ch: CHAR;
      pat: ARRAY 32 OF CHAR;
      diroption: CHAR;
  BEGIN
    par := Oberon.Par; 
    Texts.OpenReader(R, par.text, par.pos); Texts.Read(R, ch);
    WHILE (ch <= " ") & (ch # 0DX) DO Texts.Read(R, ch) END;
    IF (ch = "^") OR (ch = 0DX) THEN
       Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
        WHILE ch <= " " DO Texts.Read(R, ch) END
      END
    END;
    i := 0;
    WHILE (ch > " ") & (ch # Oberon.OptionChar) DO pat[i] := ch; INC(i); Texts.Read(R, ch) END;
    pat[i] := 0X;
    IF ch = Oberon.OptionChar THEN Texts.Read(R, diroption) ELSE diroption := 0X END;
    t := TextFrames.Text("");
    count := 0; total := 0;
    FileDir.Enumerate(pat, (diroption = "d"), List);
    IF count > 1 THEN
      Texts.WriteLn(W);  Texts.WriteInt(W, count, 1); Texts.WriteString(W, " files");
      IF diroption = "d" THEN
      	Texts.WriteString(W, " use "); Texts.WriteInt(W, (total+512) DIV 1024, 1);
      	Texts.WriteString(W, "K bytes")
      END
    END;
    Texts.WriteLn(W); Texts.Append(t, W.buf);
    OpenText("Directory", t, TRUE)
  END Directory;

  PROCEDURE CopyFile(name: ARRAY OF CHAR; VAR S: Texts.Scanner);
  CONST BufLen = 8000;
  VAR f, g: Files.File; Rf, Rg: Files.Rider; 
      buf : ARRAY BufLen OF CHAR; i : LONGINT;
  BEGIN Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "=") THEN Texts.Scan(S);
      IF (S.class = Texts.Char) & (S.c = ">") THEN Texts.Scan(S);
        IF S.class = Texts.Name THEN
          Texts.WriteString(W, name); Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
          Texts.WriteString(W, " copying"); Texts.Append(Oberon.Log, W.buf);
          f := Files.Old(name);
          IF f # NIL THEN 
            g := Files.New(S.s);
            Files.Set(Rf, f, 0); Files.Set(Rg, g, 0); 
            i := 0;
            WHILE i < Files.Length(f) DIV BufLen DO
              Files.ReadBytes(Rf,buf,BufLen); Files.WriteBytes(Rg,buf,BufLen); INC(i) 
            END;
            Files.ReadBytes(Rf,buf, Files.Length(f) MOD BufLen); 
            Files.WriteBytes(Rg,buf, Files.Length(f) MOD BufLen); 
            Files.Register(g)
          ELSE Texts.WriteString(W, " failed") END;
          Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
        END
      END
    END
  END CopyFile;

  PROCEDURE CopyFiles*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text;
      S: Texts.Scanner;
  BEGIN Texts.WriteString(W, "System.CopyFiles"); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN CopyFile(S.s, S) END
      END
    ELSE
      WHILE S.class = Texts.Name DO CopyFile(S.s, S); Texts.Scan(S) END
    END
  END CopyFiles;

  PROCEDURE RenameFile (name: ARRAY OF CHAR; VAR S: Texts.Scanner);
  VAR res: INTEGER;
  BEGIN Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "=") THEN Texts.Scan(S);
      IF (S.class = Texts.Char) & (S.c = ">") THEN Texts.Scan(S);
        IF S.class = Texts.Name THEN
          Texts.WriteString(W, name); Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
          Texts.WriteString(W, " renaming"); Texts.Append(Oberon.Log, W.buf);
          Files.Rename(name, S.s, res);
          IF res > 1 THEN Texts.WriteString(W, " failed") END;
          Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
        END
      END
    END
  END RenameFile;

  PROCEDURE RenameFiles*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text;
      S: Texts.Scanner;
  BEGIN Texts.WriteString(W, "System.RenameFiles"); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN RenameFile(S.s, S) END
      END
    ELSE
      WHILE S.class = Texts.Name DO RenameFile(S.s, S); Texts.Scan(S) END
    END
  END RenameFiles;

  PROCEDURE DeleteFile(VAR name: ARRAY OF CHAR);
   VAR res: INTEGER;
  BEGIN Texts.WriteString(W, name); Texts.WriteString(W, " deleting");
    Texts.Append(Oberon.Log, W.buf); Files.Delete(name, res);
    IF res # 0 THEN Texts.WriteString(W, " failed") END;
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END DeleteFile;

  PROCEDURE DeleteFiles*;
  VAR beg, end, time: LONGINT;
      T: Texts.Text;
      S: Texts.Scanner;
  BEGIN Texts.WriteString(W, "System.DeleteFiles"); Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf);
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN DeleteFile(S.s) END
      END
    ELSE
      WHILE S.class = Texts.Name DO DeleteFile(S.s); Texts.Scan(S) END
    END
  END DeleteFiles;

  (* ------------- Toolbox for system inspection ---------------*)

  PROCEDURE Watch*;
  BEGIN
    Texts.WriteString(W, "System.Watch");  Texts.WriteLn(W);
    Texts.WriteString(W, "  memory free: ");  Texts.WriteInt(W, (Kernel.Available()+512) DIV 1024, 1);
    Texts.WriteString(W, "K bytes");  Texts.WriteLn(W);
    Texts.WriteString(W, "  largest free block: ");  Texts.WriteInt(W, (Kernel.LargestAvailable()+512) DIV 1024, 1);
    Texts.WriteString(W, "K bytes");  Texts.WriteLn(W);
    Texts.WriteString(W, "  total memory: ");  Texts.WriteInt(W, (Kernel.Available()+Kernel.Used()+512) DIV 1024, 1);
    Texts.WriteString(W, "K bytes");  Texts.WriteLn(W);
    Texts.WriteString(W, "  disk space free: ");  Texts.WriteInt(W, Disk.Available()*Disk.SectorSize DIV 1024, 1);
    Texts.WriteString(W, "K bytes");  Texts.WriteLn(W);
    Texts.WriteString(W, "  total disk space: ");  Texts.WriteInt(W, Disk.Size()*Disk.SectorSize DIV 1024, 1);
    Texts.WriteString(W, "K bytes");  Texts.WriteLn(W);
    Texts.Append(Oberon.Log, W.buf)
  END Watch;
  
	PROCEDURE ReadNum (VAR pos: LONGINT; VAR i: LONGINT);
		VAR n: LONGINT; s: SHORTINT; x: CHAR;
	BEGIN
		s := 0; n := 0; SYSTEM.GET(pos, x); INC(pos);
		WHILE ORD(x) >= 128 DO INC(n, ASH(ORD(x) - 128, s)); INC(s, 7); SYSTEM.GET(pos, x); INC(pos) END;
		i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
	END ReadNum;
	
  PROCEDURE Locals(pos, limit: LONGINT; base: LONGINT);
  VAR adr, val: LONGINT;
      sval, form: SHORTINT;
      ch, mode: CHAR;
      ival, i: INTEGER;
      rval: REAL;
      lrval: LONGREAL;
      mod: Modules.Module;
  BEGIN Texts.WriteLn(W); SYSTEM.GET(pos, mode); INC(pos);
    WHILE (pos < limit) & (mode < 0F8X) DO
      SYSTEM.GET(pos, form); INC(pos); ReadNum(pos, adr);
      Texts.WriteString(W, "    ");
      SYSTEM.GET(pos, ch); INC(pos);
      WHILE ch # 0X DO Texts.Write(W, ch); SYSTEM.GET(pos, ch); INC(pos) END;
      Texts.WriteString(W, " = "); INC(adr, base);
      IF mode = 3X THEN SYSTEM.GET(adr, adr) (*indirect*) END;
      IF adr < 4096 THEN
      	Texts.WriteString(W, "NIL reference (");  Texts.WriteHex(W, adr);
      	Texts.WriteString(W, " )");  form := -1
      END;
      CASE form OF
        -1: (* skip *)
      |  2: (*BOOL*) SYSTEM.GET(adr, sval);
        IF sval = 0 THEN Texts.WriteString(W, "FALSE")
          ELSE Texts.WriteString(W, "TRUE")
        END
      | 1,3: (*CHAR*) SYSTEM.GET(adr, ch);
        IF (" " <= ch) & (ch <= "~") THEN Texts.Write(W, ch)
          ELSE Texts.WriteHex(W, ORD(ch)); Texts.Write(W, "X")
        END
      | 4: (*SINT*) SYSTEM.GET(adr, sval); Texts.WriteInt(W, sval, 1)
      | 5: (*INT*) SYSTEM.GET(adr, ival); Texts.WriteInt(W, ival, 1)
      | 6: (*LINT*) SYSTEM.GET(adr, val); Texts.WriteInt(W, val, 1)
      | 7: (*REAL*) SYSTEM.GET(adr, rval); Texts.WriteReal(W, rval, 15)
      | 8: (*LREAL*) SYSTEM.GET(adr, lrval); Texts.WriteLongReal(W, lrval, 24)
      | 9, 13: (*SET, POINTER*)
        SYSTEM.GET(adr, val); Texts.WriteHex(W, val); Texts.Write(W, "H")
      | 14: (* PROCVAR *)
        SYSTEM.GET(adr, val);
        mod := SYSTEM.VAL(Modules.Module, Kernel.GetMod(val));
        IF mod = NIL THEN
          Texts.WriteHex(W, val); Texts.Write(W, "H")
        ELSE
          Texts.Write(W, "["); Texts.WriteString(W, mod.name); Texts.WriteString(W, " PC ="); 
          Texts.WriteInt(W, val-SYSTEM.ADR(mod.code[0]), 6); Texts.Write(W, "]")
        END 
      | 15, 17, 18: (*String*) i := 0; Texts.Write(W, 22X);
        LOOP SYSTEM.GET(adr, ch);
          IF (ch < " ") OR (ch >= 90X) OR (i = 64) THEN EXIT END;
          Texts.Write(W, ch); INC(i); INC(adr)
        END;
        Texts.Write(W, 22X)
      END;
      (*IF detail THEN
        Texts.Write(W, 9X);  Texts.WriteInt(W, ORD(mode), 4);
        Texts.WriteInt(W, form, 4);  Texts.WriteHex(W, adr)
      END;*)
      Texts.WriteLn(W); SYSTEM.GET(pos, mode); INC(pos)
    END
  END Locals;

  PROCEDURE OutState (VAR name: ARRAY OF CHAR; t: Texts.Text);
  VAR mod: Modules.Module;
    refpos, x, limit: LONGINT;
    ch: CHAR; i: INTEGER;
   BEGIN
    i := 0;  WHILE (name[i] # 0X) & (name[i] # ".") DO INC(i) END;
    name[i] := 0X;
    Texts.WriteString(W, name); mod := Kernel.modules;
    WHILE (mod # NIL) & (mod.name # name) DO mod := mod.next END;
    IF mod # NIL THEN
      Texts.WriteString(W, "  SB ="); Texts.WriteHex(W, mod.sb);
      refpos := SYSTEM.ADR(mod.refs[0]);
      limit := refpos + LEN(mod.refs);
      LOOP SYSTEM.GET(refpos, ch); INC(refpos);
        IF refpos >= limit THEN EXIT END;
        IF ch = 0F8X THEN
          ReadNum(refpos, x);  i := SHORT(x);  SYSTEM.GET(refpos, ch); INC(refpos);
          IF ch = "$" THEN INC(refpos, 2); EXIT END;
          REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X  (*skip name*)
        ELSIF ch < 0F8X THEN  (*skip object*)
          INC(refpos);	(* skip typeform *)
          ReadNum(refpos, x);	(* skip offset *)
          REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
        END
      END;
      IF refpos < limit THEN Locals(refpos, limit, mod.sb) END
    ELSE Texts.WriteString(W, " not loaded") END;
    Texts.WriteLn(W); Texts.Append(t, W.buf)
  END OutState;
  
  PROCEDURE State*;
  VAR T: Texts.Text;
      S: Texts.Scanner;
      beg, end, time: LONGINT;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    IF S.class = Texts.Name THEN
      T := TextFrames.Text(""); OutState(S.s, T);
      OpenText("State", T, TRUE)
    END
  END State;

  PROCEDURE ShowCommands*;
  VAR M: Modules.Module;
    beg, end, time: LONGINT;
    T: Texts.Text;
    S: Texts.Scanner;
    i: INTEGER;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "^") THEN
      Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
    END;
    IF S.class = Texts.Name THEN
      i := 0; WHILE (S.s[i] # 0X) & (S.s[i] # ".") DO INC(i) END; S.s[i] := 0X;
      M := Modules.ThisMod(S.s);
      IF M # NIL THEN
        T := TextFrames.Text("");
        i := 0; 
        WHILE i < LEN(M.cmds) DO
          Texts.WriteString(W, S.s); Texts.Write(W, "."); Texts.WriteString(W, M.cmds[i].name); Texts.WriteLn(W); INC(i)
        END;
        Texts.Append(T, W.buf);
        OpenText("Commands", T, TRUE)
      ELSE
        Texts.WriteString(W, Modules.resMsg);  Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
      END
    END
  END ShowCommands;

PROCEDURE ShowTasks*;
VAR T: Texts.Text;  n: Oberon.Task;  ofs, t: LONGINT;  m: Kernel.Module;
BEGIN
	n := Oberon.NextTask;  t := Input.Time();
	REPEAT
		ofs := SYSTEM.VAL(LONGINT, n.handle);  m := Kernel.GetMod(ofs);
		Texts.WriteString(W, m.name);  Texts.WriteString(W, "  PC = ");  
		Texts.WriteInt(W, ofs-SYSTEM.ADR(m.code[0]), 1);
		IF n.safe THEN Texts.WriteString(W, "  safe  ")
		ELSE Texts.WriteString(W, "  unsafe  ")
		END;
		Texts.WriteInt(W, n.time, 1);
		IF n.time <= t THEN 
			Texts.WriteString(W, " active")
		ELSE
			Texts.WriteString(W, " waiting ");  Texts.WriteInt(W, (n.time-t)*1000 DIV Input.TimeUnit, 1);  
			Texts.WriteString(W, "ms")
		END;
		Texts.WriteLn(W);
		n := n.next
	UNTIL n = Oberon.NextTask;
	T := TextFrames.Text("");
	Texts.Append(T, W.buf);
	OpenText("Tasks", T, TRUE)
END ShowTasks;

(* FPS - Return floating point unit state *)

PROCEDURE FPS(): LONGINT;
CODE
	PUSH EAX
	FNSTSW [ESP]
	FNSTCW 2[ESP]
	WAIT
	POP EAX
END FPS;

PROCEDURE Trap*(error, fp, pc, page: LONGINT);	(* exported for Debug debugger *)
VAR
	T: Texts.Text;  refpos, limit, bp, x: LONGINT;  
	ch, ch0: CHAR;  
	mod: Modules.Module;  
	procstart, refstart: LONGINT;

	PROCEDURE Registers(s : ARRAY OF CHAR; i : LONGINT);
	BEGIN
		SYSTEM.GET(bp+i, i);
		Texts.WriteString(V, " ");  Texts.WriteString(V, s);  Texts.WriteString(V, " =");  Texts.WriteHex(V, i)
	END Registers;

BEGIN
	IF trapped = 0 THEN
		trapped := 1;
		(* the registers *)
		IF detail THEN
			SYSTEM.GETREG(5, bp);	(* EBP *)
			SYSTEM.GET(bp, bp);	(* interrupt handler frame *)
			Texts.WriteLn(V);
			Registers("EAX", 36);  Registers("EBX", 24);  Registers("ECX", 32);  Texts.WriteLn(V);
			Registers("EDX", 28);  Registers("ESI", 12);  Registers("EDI", 8);  Texts.WriteLn(V);
			Registers("FLG", 56);  Registers("EBP", 16);  Registers("ESP", 20);	(* actually ESP-16 *)
			Texts.WriteLn(V);  Registers("EIP", 48);
			Texts.WriteString(V, " CR2 =");  Texts.WriteHex(V, page);  Registers("ERR", 44);
			Texts.WriteLn(V);  Texts.WriteString(V, " SBT =");  Texts.WriteHex(V, Kernel.StackOrg);
			SYSTEM.GET(bp+52, x);	(* CS *)
			IF x MOD 4 = 0 THEN Texts.WriteString(V, " OSP = --------")
			ELSE Registers("OSP", 60)
			END;
			Texts.WriteString(V, " FPS =");
			IF Kernel.copro THEN Texts.WriteHex(V, FPS()) ELSE Texts.WriteString(V, " --------") END;
			Texts.WriteLn(V)
		END;
		Display.ResetClip;
		IF Kernel.copro THEN Reals.SetFCR(Reals.DefaultFCR) ELSE resetfp() END;
		Viewers.Close(NIL);	(* close offending viewer, if any *)
		T := TextFrames.Text("");
		mod := SYSTEM.VAL(Modules.Module, Kernel.GetMod(pc));
		Texts.WriteString(W, "TRAP "); Texts.WriteInt(W, error, 1);
		Texts.WriteString(W, "  ");
	
		IF error = 0 THEN
			Texts.WriteString(W, "Division by zero")
		ELSIF ABS(error) = 4 THEN
			Texts.WriteString(W, "Overflow")
		ELSIF error = -6 THEN
			Texts.WriteString(W, "Invalid instruction")
		ELSIF error = -12 THEN
			Texts.WriteString(W, "Stack overflow")
		ELSIF error = -13 THEN 
			Texts.WriteString(W, "General protection fault")
		ELSIF error = -14 THEN
			IF (page >= -4) & (page < 4096) THEN
				Texts.WriteString(W, "NIL reference (");
				Texts.WriteHex(W, page);  Texts.WriteString(W, "H )")
			ELSIF (page >= 100000H) & (page < Kernel.StackOrg) THEN
				Texts.WriteString(W, "Stack overflow (");
				Texts.WriteHex(W, page);  Texts.WriteString(W, "H )")
			ELSE
				Texts.WriteString(W, "Page fault at");
				Texts.WriteHex(W, page);  Texts.Write(W, "H")
			END
		ELSIF error = -16 THEN
			Texts.WriteString(W, "Floating-point error")	(* generic *)
		ELSIF error = -32 THEN
			Texts.WriteString(W, "Floating-point division by 0")
		ELSIF error = -33 THEN
			Texts.WriteString(W, "Floating-point overflow")
		ELSIF error = -34 THEN
			Texts.WriteString(W, "Floating-point operation invalid")
		ELSIF error = -35 THEN
			Texts.WriteString(W, "Floating-point stack fault")
		ELSIF error = 1 THEN
			Texts.WriteString(W, "WITH guard failed")
		ELSIF error = 2 THEN
			Texts.WriteString(W, "CASE invalid")
		ELSIF error = 3 THEN
			Texts.WriteString(W, "RETURN missing")
		ELSIF error = 5 THEN
			Texts.WriteString(W, "Implicit type guard failed")
		ELSIF error = 6 THEN
			Texts.WriteString(W, "Type guard failed")
		ELSIF error = 7 THEN
			Texts.WriteString(W, "Index out of range")
		ELSIF error = 8 THEN
			Texts.WriteString(W, "ASSERT failed")
		ELSIF error = 9 THEN
			Texts.WriteString(W, "Array dimension error")
		ELSIF error = 13 THEN
			Texts.WriteString(W, "Keyboard interrupt")
		ELSIF error = 14 THEN
			Texts.WriteString(W, "Out of memory")
		ELSIF error = 15 THEN
			Texts.WriteString(W, "Bad sector number")
		ELSIF error = 16 THEN
			Texts.WriteString(W, "Disk full")
		ELSIF error = 17 THEN
			Texts.WriteString(W, "Disk error")
		ELSIF error = 18 THEN
			Texts.WriteString(W, "File too large")
		ELSIF error = 19 THEN
			Texts.WriteString(W, "Buffer overflow")
		ELSIF error = MAX(INTEGER) THEN
			Texts.WriteString(W, "Trace ");  Texts.WriteInt(W, trap, 1);  INC(trap)
		ELSIF error < 0 THEN
			Texts.WriteString(W, "CPU exception")
		ELSE
			Texts.WriteString(W, "HALT statement")
		END;
		Texts.WriteLn(W);

		LOOP 
			IF mod = NIL THEN
				Texts.WriteString(W, "NIL  PC =");  Texts.WriteHex(W, pc);
				Texts.WriteString(W, "  FP =");  Texts.WriteHex(W, fp);
				Texts.WriteLn(W)
			ELSE
				Texts.WriteString(W, mod.name);
				IF (SYSTEM.VAL(LONGINT, mod.refs) # 0) & (LEN(mod.refs) # 0) THEN
					refstart := 0;  refpos := SYSTEM.ADR(mod.refs[0]);
					limit := refpos + LEN(mod.refs);
					LOOP
						SYSTEM.GET(refpos, ch); INC(refpos);
						IF refpos >= limit THEN EXIT END;
						IF ch = 0F8X THEN (* start proc *)
							ReadNum(refpos, procstart);
							IF pc < SYSTEM.ADR(mod.code[0]) + procstart THEN EXIT END;
							refstart := refpos;
							REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
						ELSIF ch < 0F8X THEN (* skip object *)
							INC(refpos);	(* skip typeform *)
							ReadNum(refpos, procstart);	(* skip offset *)
							REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
						END
					END;
					refpos := refstart;
					IF refpos # 0 THEN
						Texts.Write(W, "."); SYSTEM.GET(refpos, ch); INC(refpos); ch0 := ch;
						WHILE ch # 0X DO Texts.Write(W, ch); SYSTEM.GET(refpos, ch); INC(refpos) END
					END;
					Texts.WriteString(W, "  PC ="); Texts.WriteInt(W, pc-SYSTEM.ADR(mod.code[0]), 6);
					IF refpos # 0 THEN
						IF ch0 = "$" THEN Locals(refpos, limit, mod.sb) ELSE Locals(refpos, limit, fp) END
					ELSE
						Texts.WriteLn(W)
					END
				ELSE
					Texts.WriteString(W, "  PC ="); Texts.WriteInt(W, pc-SYSTEM.ADR(mod.code[0]), 6);
					Texts.WriteLn(W)
				END
			END;  (* ELSE *)
			SYSTEM.GET(fp+4, pc);  SYSTEM.GET(fp, fp); (* return addr from stack *)
			IF (fp < 0) OR (fp >= Kernel.StackOrg) THEN EXIT END; (* not called from stack *)
			mod := SYSTEM.VAL(Modules.Module, Kernel.GetMod(pc))
		END; (* LOOP *)
		Texts.Append(T, W.buf);
		IF detail THEN Texts.Append(T, V.buf) END;
		OpenText("Trap", T, TRUE)
	ELSIF trapped = 1 THEN
		trapped := 2;
		T := TextFrames.Text(""); Texts.WriteLn(W);
		Texts.WriteString(W, "TRAP "); Texts.WriteInt(W, error, 3);  Texts.WriteString(W, " (recursive)");
		Texts.WriteLn(W); Texts.Append(T, W.buf);
		IF detail THEN Texts.Append(T, V.buf) END;
		OpenText("Trap", T, TRUE)
	ELSIF trapped = 2 THEN
		trapped := 3;
		Texts.WriteLn(W);  Texts.WriteString(W, "TRAP "); Texts.WriteInt(W, error, 3);
		Texts.WriteString(W, " (recursive)");  Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
	ELSE (* skip *)
	END;
	trapped := 0
END Trap;

PROCEDURE Quit*;
BEGIN
	Oberon.OpenTrack(0, Display.Width);
	Display.ReplConst(Display.FG, 0, 0, Display.Width, Display.Height, Display.replace);
	Kernel.Shutdown(1)
END Quit;

PROCEDURE Reboot*;
BEGIN
	Kernel.Shutdown(0)
END Reboot;

PROCEDURE Init*;	(* called from Oberon init, when Oberon Text is ready *)
VAR
	S: Texts.Scanner;  Wt: Texts.Writer;  ok: BOOLEAN;  m: Modules.Module;
	T: Texts.Text;  F: TextFrames.Frame;
BEGIN 
	IF ~init THEN init := TRUE;	(* avoid user call *)
		Texts.OpenWriter(Wt);
		Oberon.OpenScanner(S, "System.LoadGadgets");
		IF (S.class = Texts.Name) & (CAP(S.s[0]) = "Y") THEN
			NEW(Oberon.Par);  Oberon.Par.vwr := Viewers.This(0, 0);
			m := Modules.ThisMod("TextDocs");
			IF m = NIL THEN
				Texts.WriteString(W, Modules.resMsg);  Texts.WriteString(W, " - Gadgets not installed?");
				Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
			END
		END;
		Oberon.OpenScanner(S, "System.TraceDetail");
		IF (S.class = Texts.Name) & (CAP(S.s[0]) = "Y") THEN
			detail := TRUE;
			Texts.OpenWriter(V);  Texts.SetFont(V, Fonts.This("Courier10.Scn.Fnt"))
		END;
		Oberon.OpenScanner(S, "System.InitCommands");
		IF S.class = Texts.Inval THEN
			OpenLog;
			OpenText("System.Tool", TextFrames.Text("System.Tool"), TRUE)
		ELSE
			WHILE ~S.eot & (S.class = Texts.Char) & (S.c = "{") DO
				ok := FALSE;  Texts.Scan(S);
				IF S.class = Texts.Name THEN
					ok := TRUE;  Texts.WriteString(Wt, S.s)
				END;
				IF ~((S.class = Texts.Char) & (S.c = "}")) THEN
					WHILE ~S.eot & (S.nextCh # "}") DO
						IF ok THEN Texts.Write(Wt, S.nextCh) END;
						Texts.Read(S, S.nextCh)
					END
				END;
				IF ok THEN
					Texts.WriteLn(Wt);  T := TextFrames.Text("");  Texts.Append(T, Wt.buf);
					F := TextFrames.NewText(T, 0);  TextFrames.Call(F, 0, FALSE)
				END;
				Texts.Scan(S);  Texts.Scan(S)
			END
		END
	END
END Init;

PROCEDURE Greetings;
VAR t, d: LONGINT;
BEGIN
	Oberon.GetClock(t, d);  Texts.WriteString(W, "System.Time");
	Texts.WriteDate(W, t, d);  Texts.WriteLn(W); 
    Texts.WriteString(W, "ETH Native Oberon (TM)  ");
    IF Display.Width < 1024 THEN Texts.WriteLn(W) END;
    Texts.WriteString(W, "System 3  Release 2.2  07.11.97");  Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END Greetings;

BEGIN 
	Kernel.EnableGC;  Kernel.InstallLoop(Oberon.Loop);
	trapped := 0;  Kernel.InstallTrap(Trap);  Texts.OpenWriter(W);
	Oberon.Log := TextFrames.Text("");  init := FALSE;  trap := 0;  detail := FALSE;
	Greetings;
	IF Kernel.copro THEN
		resetfp := NIL
	ELSE
		resetfp := Modules.ThisCommand(Modules.ThisMod("FPA"), "Reset");
		IF resetfp # NIL THEN
			Texts.WriteString(W, "Floating point emulator loaded");  Texts.WriteLn(W)
		END
	END;
    Texts.Append(Oberon.Log, W.buf)
END System.

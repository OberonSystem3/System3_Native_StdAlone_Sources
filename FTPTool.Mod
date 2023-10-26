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

MODULE FTPTool; (* EJZ,   *)
	IMPORT HyperDocs, FTP, Files, Strings, Texts, Oberon;

(** A simple single session FTP Tool using commands. Useful for transfering many files to or from the
		same server. *)

	CONST
		Tab = 9X;
		ScanStringSize = 64;	(* LEN(Texts.Scanner.s) *)
		
	VAR
		S: FTP.Session;
		W: Texts.Writer;
		log: Texts.Text;
		col: INTEGER;

	PROCEDURE ShowRes();
	BEGIN
		Texts.WriteString(W, S.reply);
		Texts.WriteLn(W);
		Texts.Append(log, W.buf)
	END ShowRes;

	PROCEDURE OpenScanner(VAR S: Texts.Scanner);
		VAR
			beg, end, time: LONGINT;
			text: Texts.Text;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			time := -1;
			text := NIL;
			Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time >= 0) THEN
				Texts.OpenScanner(S, text, beg);
				Texts.Scan(S)
			END
		END
	END OpenScanner;

(** FTPTool.Open (server | "^")
		Open an ftp connection to server using username and password set with FTP.SetUser. *)
	PROCEDURE Open*;
		VAR
			Sc: Texts.Scanner;
			host, path, user, passwd: ARRAY 64 OF CHAR;
			key: LONGINT;
			port: INTEGER;
			type: CHAR;
	BEGIN
		IF S = NIL THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				COPY(Sc.s, host); Sc.s := "ftp://"; Strings.Append(Sc.s, host);
				key := FTP.SplitFTPAdr(Sc.s, host, path, user, passwd, type, port);
				IF key # HyperDocs.UndefKey THEN
					FTP.Open(host, user, passwd, port, log, S);
					ShowRes();
					IF S.res # FTP.Done THEN
						S := NIL
					END
				END
			END
		ELSE
			Texts.WriteString(W, "already connected");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf)
		END
	END Open;

	PROCEDURE Con(): BOOLEAN;
	BEGIN
		IF S = NIL THEN
			Texts.WriteString(W, "not connected");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			RETURN FALSE
		ELSE
			RETURN TRUE
		END
	END Con;

(** FTPTool.Close
		Close an previously opened FTP connection. *)
	PROCEDURE Close*;
	BEGIN
		IF Con() THEN
			FTP.Close(S);
			ShowRes();
			IF S.res = FTP.Done THEN
				S := NIL
			END
		END
	END Close;

(** FTPTool.ChangeDir (newdir | "^")
		Change the current directory on the FTP server to newdir. *)
	PROCEDURE ChangeDir*;
		VAR Sc: Texts.Scanner;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				FTP.ChangeDir(S, Sc.s);
				ShowRes()
			END
		END
	END ChangeDir;

	PROCEDURE *ShowEntry(entry: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, entry);
		Texts.WriteLn(W);
		Texts.Append(log, W.buf)
	END ShowEntry;

(** FTPTool.Dir
		List the contents of the current directory on the FTP server. *)
	PROCEDURE Dir*;
	BEGIN
		IF Con() THEN
			FTP.EnumDir(S, ShowEntry);
			ShowRes()
		END
	END Dir;

	PROCEDURE *ShowCompactEntry(entry: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE entry[i] # 0X DO
			INC(i)
		END;
		DEC(i);
		WHILE (i > 0) & (entry[i] > " ") DO
			DEC(i)
		END;
		IF entry[i] <= " " THEN
			INC(i)
		END;
		WHILE entry[i] # 0X DO
			INC(col);
			Texts.Write(W, entry[i]);
			INC(i)
		END;
		INC(col);
		IF col >= 50  THEN
			Texts.WriteLn(W);
			col := 0
		ELSE
			INC(col);
			Texts.Write(W, Tab)
		END;
		Texts.Append(log, W.buf)
	END ShowCompactEntry;

(** FTPTool.CompactDir
		List the contents of the current directory on the FTP server in a more
		compact form. *)
	PROCEDURE CompactDir*;
	BEGIN
		IF Con() THEN
			col := 0;
			FTP.EnumDir(S, ShowCompactEntry);
			IF col > 0 THEN
				Texts.WriteLn(W);
				Texts.Append(log, W.buf)
			END;
			ShowRes()
		END
	END CompactDir;

(** FTPTool.CurDir
		Display the current path on the FTP server *)
	PROCEDURE CurDir*;
		VAR curdir: ARRAY 256 OF CHAR;
	BEGIN
		IF Con() THEN
			FTP.GetCurDir(S, curdir);
			ShowRes()
		END
	END CurDir;

(** FTPTool.MakeDir (server | "^")
		Create a new directory. *)
	PROCEDURE MakeDir*;
		VAR Sc: Texts.Scanner;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				FTP.MakeDir(S, Sc.s);
				ShowRes()
			END
		END
	END MakeDir;

(** FTPTool.RmDir (server | "^")
		Remove an existing directory. *)
	PROCEDURE RmDir*;
		VAR Sc: Texts.Scanner;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				FTP.RmDir(S, Sc.s);
				ShowRes()
			END
		END
	END RmDir;

(** FTPTool.DeleteFiles ({remname} | "^")
		Delete the files remname on the FTP server. *)
	PROCEDURE DeleteFiles*;
		VAR
			Sc: Texts.Scanner;
			beg, end, time, pos: LONGINT;
			text: Texts.Text;
	BEGIN
		IF Con() THEN
			end := Oberon.Par.text.len;
			Texts.OpenScanner(Sc, Oberon.Par.text, Oberon.Par.pos);
			pos := Texts.Pos(Sc);
			Texts.Scan(Sc);
			IF (Sc.class = Texts.Char) & (Sc.c = "^") THEN
				time := -1;
				text := NIL;
				Oberon.GetSelection(text, beg, end, time);
				IF (text # NIL) & (time >= 0) THEN
					Texts.OpenScanner(Sc, text, beg);
					pos := Texts.Pos(Sc);
					Texts.Scan(Sc)
				ELSE
					end := Oberon.Par.text.len
				END
			END;
			Texts.WriteString(W, "FTP.DeleteFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE (Sc.class IN {Texts.Name, Texts.String}) & (pos < end) & (S.res = FTP.Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, Sc.s);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				FTP.DeleteFile(S, Sc.s);
				ShowRes();
				pos := Texts.Pos(Sc);
				Texts.Scan(Sc)
			END
		END
	END DeleteFiles;

	PROCEDURE ScanPair(VAR S: Texts.Scanner; VAR name1, name2: ARRAY OF CHAR): BOOLEAN;
	BEGIN (* while loop from pieter *)
		WHILE ~(S.class IN {Texts.Name, Texts.String}) & ((S.class # Texts.Char) OR (S.c # "~")) & ~S.eot DO
			Texts.Scan(S)
		END;
		IF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, name1);
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						COPY(S.s, name2);
						Texts.Scan(S);
						RETURN TRUE
					END
				END
			ELSE
				COPY(name1, name2);
				RETURN TRUE
			END
		END;
		RETURN FALSE
	END ScanPair;

(** FTPTool.GetFiles ({remname "=>" locname} | "^")
		Get files remname from the FTP server and store them as locname. *)
	PROCEDURE GetFiles*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY ScanStringSize OF CHAR;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.GetFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, rem, loc) & (S.res = FTP.Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, rem);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, loc);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				FTP.GetFile(S, rem, loc);
				Texts.Append(log, W.buf);
				Texts.WriteLn(W);
				ShowRes()
			END
		END
	END GetFiles;

(** FTPTool.GetTexts ({remname "=>" locname} | "^")
		Get text-files remname from the FTP server and store them as locname. *)
	PROCEDURE GetTexts*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY ScanStringSize OF CHAR;
			T: Texts.Text;
			F: Files.File;
			len: LONGINT;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.GetText");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, rem, loc) & (S.res = FTP.Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, rem);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, loc);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				FTP.GetText(S, rem, W);
				NEW(T);
				Texts.Open(T, "");
				Texts.Append(T, W.buf);
				F := Files.New(loc);
				Texts.Store(T, F, 0, len);
				Files.Register(F);
				ShowRes()
			END
		END
	END GetTexts;

(** FTPTool.PutFiles ({locname "=>" remname} | "^")
		Put files locname as remname on the FTP server. *)
	PROCEDURE PutFiles*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY ScanStringSize OF CHAR;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.PutFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, loc, rem) & (S.res = FTP.Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, loc);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, rem);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				FTP.PutFile(S, rem, loc);
				Texts.WriteLn(W);
				ShowRes()
			END
		END
	END PutFiles;

(** FTPTool.PutTexts ({locname "=>" remname} | "^")
		Put text-files locname as remname on the FTP server. *)
	PROCEDURE PutTexts*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY ScanStringSize OF CHAR;
			text: Texts.Text;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.PutFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, loc, rem) & (S.res = FTP.Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, loc);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, rem);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				NEW(text);
				Texts.Open(text, loc);
				FTP.PutText(S, rem, text);
				Texts.WriteLn(W);
				ShowRes()
			END
		END
	END PutTexts;

	PROCEDURE OpenLog*;
	BEGIN
		IF log = Oberon.Log THEN
			NEW(log); Texts.Open(log, "")
		END;
		Oberon.OpenText("FTPTool.Log", log, HyperDocs.docW, HyperDocs.docH)
	END OpenLog;

BEGIN
	S := NIL; log := Oberon.Log;
	Texts.OpenWriter(W)
END FTPTool.

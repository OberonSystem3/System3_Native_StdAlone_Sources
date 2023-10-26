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

MODULE HTMLTables; (* ejz,   *)
	IMPORT Display, Texts, HTMLDocs;

(** HTML 3.0 Table support.
	[HTMLTags]
	CAPTION=HTMLTables.NewCAPTION
	TABLE=HTMLTables.NewTABLE
	TD=HTMLTables.NewTD
	TH=HTMLTables.NewTH
	TR=HTMLTables.NewTR *)

	PROCEDURE *TABLE(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		HTMLDocs.HorzRule(S.page, Display.Width, 1, S.page.textC)
	END TABLE;

	PROCEDURE *TR(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			HTMLDocs.WriteLn(S.page)
		END
	END TR;

	PROCEDURE *TH(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF ~on THEN
			Texts.Write(S.page.W, 09X)
		END
	END TH;

	PROCEDURE *TD(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF ~on THEN
			Texts.Write(S.page.W, 09X)
		END
	END TD;

	PROCEDURE *CAPTION(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			HTMLDocs.HorzRule(S.page, Display.Width, 1, S.page.textC);
			HTMLDocs.WriteLn(S.page)
		END
	END CAPTION;

	PROCEDURE *Dummy(P: HTMLDocs.Page);
	BEGIN
	END Dummy;

	PROCEDURE NewTABLE*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TABLE;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTABLE;

	PROCEDURE NewTR*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TR;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTR;

	PROCEDURE NewTH*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TH;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTH;

	PROCEDURE NewTD*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TD;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTD;

	PROCEDURE NewCAPTION*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := CAPTION;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewCAPTION;

END HTMLTables.

"http://home.mcom.com:80/assist/net_sites/table_sample.html"

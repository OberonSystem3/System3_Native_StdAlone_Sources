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

MODULE WTSPict;

	IMPORT WTS, Pictures, Objects, Files, Rembrandt;
	
	PROCEDURE Load(P: Pictures.Picture; VAR R: Files.Rider);
		VAR len: LONGINT; ch: CHAR;
	BEGIN Files.Read(R, ch); Files.Read(R, ch);
		Files.Read(R, ch); Files.Read(R, ch);	(*pict id*)
		Pictures.Load(P, Files.Base(R), Files.Pos(R), len);
		(*Files.Set(R, Files.Base(R), Files.Pos(R)+len)*)
	END Load;

	PROCEDURE New*;
		VAR pict: Pictures.Picture; F: Rembrandt.Frame;
	BEGIN NEW(pict); Load(pict, WTS.R);
		NEW(F);
		Rembrandt.NewP(F, pict); Objects.NewObj := F
	END New;

END WTSPict.



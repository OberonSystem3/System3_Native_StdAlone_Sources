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

MODULE Out;	(* Stream-oriented text output, MR 1992, NW 12.1.93, JG 26.7.93 *)

(** Standard output routines for writing text into the Oberon log.
*)

  IMPORT Texts, Oberon;

  VAR W: Texts.Writer;

(** Initialize log output by writing the current time and date. *)
PROCEDURE Open*;
  VAR t, d: LONGINT;
BEGIN Texts.WriteString(W, "Out.Open");
  Oberon.GetClock(t, d); Texts.WriteDate(W, t, d); Texts.WriteLn(W);
  Texts.Append(Oberon.Log, W.buf)
END Open;

(** Write character. *)
PROCEDURE Char* (ch: CHAR);
BEGIN Texts.Write(W, ch); Texts.Append(Oberon.Log, W.buf)
END Char;

(** Write a string. *)
PROCEDURE String* (str: ARRAY OF CHAR);
BEGIN Texts.WriteString(W, str); Texts.Append(Oberon.Log, W.buf)
END String;

(** Write the integer i in n field positions. *)
PROCEDURE Int* (i, n: LONGINT);
BEGIN Texts.WriteInt(W, i, n); Texts.Append(Oberon.Log, W.buf)
END Int;

(** Write the real x in n field positions. *)
PROCEDURE Real* (x: REAL; n: INTEGER);
BEGIN Texts.WriteRealFix(W, x, n, 2, 0); Texts.Append(Oberon.Log, W.buf)
END Real;

(** Write the longreal x in n field positions. *)
PROCEDURE LongReal* (x: LONGREAL; n: INTEGER);
BEGIN Texts.WriteLongRealFix(W, x, n, 2, 0); Texts.Append(Oberon.Log, W.buf)
END LongReal;

(** Write a carriage return (CR or end-of-line). *)
PROCEDURE Ln*;
BEGIN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Ln;

(** Write all parameters of command, up to and including ~. *)
PROCEDURE Echo*;
	VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	LOOP
		Texts.Scan(S);
		IF (S.class = Texts.Inval) OR ((S.class = Texts.Char) & (S.c = "~")) THEN EXIT END;
		CASE S.class OF
			Texts.Name, Texts.String: Texts.WriteString(W, S.s)
			|Texts.Int: Texts.WriteInt(W, S.i, 0)
			|Texts.Real: Texts.WriteReal(W, S.x, 15)
			|Texts.LongReal: Texts.WriteLongReal(W, S.y, 15)
			|Texts.Char: Texts.Write(W, S.c)
			|Texts.Object, Texts.Inval:
		END;
		Texts.Write(W, " ");
		IF S.eot THEN EXIT END
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Echo;

BEGIN Texts.OpenWriter(W)
END Out.

(** Remarks:

1. Out uses the Writers of module Texts to write output to the log. Writing output using Out is slow when much output has to be written. This is related to the fact that for each call to a procedure in module Out, a corresponding Texts.UpdateMsg is broadcast through the display space. For fast and professional output, the use of module Texts is recommended.

*)
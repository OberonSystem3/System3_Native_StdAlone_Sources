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

MODULE Magnifier;	(** PS   **)
(**
	This module provieds a new mouse cursor. It zooms an area of 5x5 pixels around the mouse position
	to an area of 15x 15 pixels.
*)

IMPORT
	Display, Effects, Oberon;

CONST
	Size = 25;	(* = 5, 15 or 25 *)
	HalfSize = Size DIV 2; PixSize = Size DIV 5; PixHalfSize = PixSize DIV 2;

VAR
	Magnifier*: Oberon.Marker;

(** Starts the zooming. The operation will be stopped by pressing on any mouse button. *)
PROCEDURE Zoom*;
VAR X, Y: INTEGER; keys: SET;
BEGIN
	REPEAT Effects.TrackMouse(keys, X, Y, Magnifier) UNTIL keys # {};
	REPEAT Effects.TrackMouse(keys, X, Y, Effects.Arrow) UNTIL keys = {}
END Zoom;

PROCEDURE DrawColumn(sx, dx, y, t1, t2: INTEGER);
BEGIN
	WHILE (t1 < 0) DO
		Display.CopyBlock(sx, y + (t1 + PixHalfSize) DIV PixSize, 1, 1, dx, y + t1, Display.replace);
		INC(t1)
	END;
	WHILE t2 >= 0 DO
		Display.CopyBlock(sx, y + (t2 + PixHalfSize) DIV PixSize, 1, 1, dx, y + t2, Display.replace);
		DEC(t2)
	END
END DrawColumn;

PROCEDURE * DrawMag(x, y: INTEGER);
VAR s, w, h, u, v, sx: INTEGER;
BEGIN
	s := x DIV Display.Width * Display.Width; x := x - s;
	IF x < HalfSize THEN w:= HalfSize + 1 + x; u:= -x
	ELSIF x > Display.Width - HalfSize - 1 THEN w:= Display.Width - x + HalfSize; u:= -HalfSize
	ELSE w:= Size; u:= -HalfSize
	END;
	x := x + s;
	IF y < HalfSize THEN h:= HalfSize + 1 + y; v:= -y
	ELSIF y > Display.Height - HalfSize - 1 THEN y := Display.Height - y + HalfSize; v:= -y
	ELSE h:= Size; v:= -HalfSize
	END;

	Effects.OpenCursor(x+u, y+v, w, h);
	s:= u;
	WHILE (s < 0) DO
		DrawColumn(x + (s + PixHalfSize) DIV PixSize, x + s, y, v, h + v - 1);
		INC(s)
	END;
	s:= w + u -1;
	WHILE (s >= 0) DO
		DrawColumn(x + (s + PixHalfSize) DIV PixSize, x + s, y, v, h + v - 1);
		DEC(s)
	END;

	Display.ReplConst(1, x+u, y+v, w, 1, Display.replace);
	Display.ReplConst(1, x+u, y+v, 1, h, Display.replace);
	Display.ReplConst(1, x+u, y+v+h-1, w, 1, Display.replace);
	Display.ReplConst(1, x+u+w-1, y+v, 1, h, Display.replace)
END DrawMag;

PROCEDURE * FadeMag(x, y: INTEGER);
BEGIN Effects.CloseCursor
END FadeMag;

BEGIN
	Magnifier.Draw:= DrawMag;
	Magnifier.Fade:= FadeMag
END Magnifier.Zoom


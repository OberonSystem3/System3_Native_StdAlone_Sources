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

MODULE Printer;  (*bh, ard 27.11.92  /  kr 23.12. 92 / 03.08.93*)

(* Empty.Printer.Mod and Rel.Printer.Mod *)

	IMPORT Fonts;
	
	CONST 
		PW = 2336; PH = 3281; 
		
	VAR res*: INTEGER; (*0 = done, 1 = not done*)		
		Width*, Height*, Depth*: INTEGER;
		FrameX*, FrameY*, FrameW*, FrameH*: INTEGER;
		Unit*: LONGINT;

	PROCEDURE Error;
	VAR error: ARRAY 32 OF CHAR;
	BEGIN
		error := "No printer configured";  HALT(99)
	END Error;
	
	PROCEDURE Open*(name, options: ARRAY OF CHAR);
	BEGIN Error
	END Open;

	PROCEDURE ReplConst*(x, y, w, h: INTEGER);
	BEGIN Error
	END ReplConst;

	PROCEDURE UseListFont*(VAR name: ARRAY OF CHAR);
	BEGIN Error
	END UseListFont;

	PROCEDURE GetMetric*(fnt: Fonts.Font): Fonts.Font;
	BEGIN
		RETURN NIL
	END GetMetric;

	PROCEDURE String*(x, y: INTEGER; s: ARRAY OF CHAR; fnt: Fonts.Font);
	BEGIN Error
	END String;

	PROCEDURE ContString*(s: ARRAY OF CHAR; fnt: Fonts.Font);
	BEGIN Error
	END ContString;

	PROCEDURE ReplPattern*(x, y, w, h, col: INTEGER);
	BEGIN Error
	END ReplPattern;

	PROCEDURE Line*(x0, y0, x1, y1: INTEGER);
	BEGIN Error
	END Line;

	PROCEDURE Circle*(x0, y0, r: INTEGER);
	BEGIN Error
	END Circle;

	PROCEDURE Ellipse*(x0, y0, a, b: INTEGER);
	BEGIN Error
	END Ellipse;

	PROCEDURE Spline*(x0, y0, n, open: INTEGER; VAR X, Y: ARRAY OF INTEGER);
	BEGIN Error
	END Spline;

	PROCEDURE Picture*(x, y, w, h, mode: INTEGER; adr: LONGINT);
	BEGIN Error
	END Picture;

	PROCEDURE Page*(nofcopies: INTEGER);
	BEGIN Error
	END Page;

	PROCEDURE Close*;
	BEGIN Error
	END Close;
	
	PROCEDURE UseColor*(red,green,blue : INTEGER);
	BEGIN Error
	END UseColor;
	
BEGIN 
	Width := PW; Height := PH; Unit := 3048;
	FrameX := 94; FrameY := 177; FrameW := 2336; FrameH := 3280
END Printer.Print  


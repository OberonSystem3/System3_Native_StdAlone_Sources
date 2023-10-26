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

MODULE Display;

(* VESA 2.0 linear frame buffer display driver, done by Martin Pirker (crf@sbox.tu-graz.ac.at)
	based on ET4000PM.Mod,
	Oberon ET4000 Display driver  for PC Native Oberon  pm 10.12.95/ 14.12.95 19.03.96	*)

(* pjm 27.03.96 - added configurability *)
(* pjm 08.01.97 - modified for new kernel *)
(* pjm 21.01.97 - release 2.2 changes *)

IMPORT Kernel, SYSTEM, Objects;

CONST 
		BG* = 0; FG* = 15; (*background, foreground*)
		replace* = 0; paint* = 1; invert* = 2; (*operation modes*)
		
		remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (*ControlMsg id*)
		reduce* = 0; extend* = 1; move* = 2; (*ModifyMsg id*)
		display* = 0; state* = 1; (*ModifyMsg mode*)
		screen* = 0; printer* = 1; (* DisplayMsg device *)
		full* = 0; area* = 1; contents* = 2; (* DisplayMsg id. *)
		get* = 0; set* = 1; reset* = 2; (*SelectMsg id*)
		drop* = 0; integrate* = 1; (*ConsumeMsg id*)
		
		BASE= 0A0000H;

TYPE Pattern* = LONGINT;
		PatternPtr = POINTER TO RECORD w, h, pixmap: SHORTINT END;
		List = POINTER TO ListDesc;
		ListDesc = RECORD
			next: List;
			pat: PatternPtr
		END;

		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Objects.ObjDesc)
			next*, dsc*: Frame;
			X*, Y*, W*, H*: INTEGER
		END;
 
		FrameMsg* = RECORD (Objects.ObjMsg)
			F*: Frame; (*target*)
			x*, y*, res*: INTEGER
		END;
	
		ControlMsg* = RECORD (FrameMsg)
			id*: INTEGER
		END;
	
		ModifyMsg* = RECORD (FrameMsg)
			id*, mode*: INTEGER;
			dX*, dY*, dW*, dH*: INTEGER;
			X*, Y*, W*, H*: INTEGER
		END;
	
		DisplayMsg* = RECORD (FrameMsg)
			device*: INTEGER;
			id*: INTEGER;
			u*, v*, w*, h*: INTEGER
		END;
	
		LocateMsg* = RECORD (FrameMsg)
			loc*: Frame;
			X*, Y*, u*, v*: INTEGER
		END;
	
		SelectMsg* = RECORD (FrameMsg)
			id*: INTEGER;
			time*: LONGINT;
			sel*: Frame;
			obj*: Objects.Object
		END;
	
		ConsumeMsg* = RECORD (FrameMsg)
			id*: INTEGER;
			u*, v*: INTEGER;
			obj*: Objects.Object
		END;
		
		MsgProc* = PROCEDURE (VAR M: FrameMsg);

VAR 
		LinearBase:LONGINT;

		Unit*: LONGINT; (* RasterUnit = Unit/36000 mm *)
		Left*, (* left margin of black-and-white maps *)
		ColLeft*, (* left margin of color maps *)
		Bottom*, (* bottom of primary map *)
		UBottom*, (* bottom of secondary map *)
		Width*, (* map width *)
		Height*: (* map hight*)
			INTEGER;
			
		arrow*, star*, cross*, downArrow*, hook*: Pattern;
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

		Broadcast*: MsgProc;

		Pat: List;

		clipx, clipy, clipright, cliptop: INTEGER;	(* clipping variables *)

		bank: SHORTINT;
		Version: ARRAY 16 OF CHAR;

(* Copy - Copy size bytes from source to dest.  (No overlap allowed) *)

PROCEDURE Copy(source, dest, size: LONGINT);
CODE
	MOV ESI, source[EBP]
	MOV EDI, dest[EBP]
	MOV ECX, size[EBP]
	CLD
	CMP ECX, 8
	JB bytemove
	XOR EAX, EAX
	SHRD EAX, ESI, 2
	JZ copyd
	TEST EDI, 3
	JZ copyd
	SHRD EAX, EDI, 2
	SHR EAX, 28
	CMP AL, 10
	JZ mov2
	CMP AL, 5
	JZ mov3
	NOT AL
	AND AL, 5
	JNZ copyd
	MOVSB
	DEC ECX
	JMP copyd
mov3:
	MOVSB
	DEC ECX
mov2:
	MOVSW
	SUB ECX, 2
copyd:
	SHRD EAX, ECX, 2
	SHR ECX, 2
	REP MOVSD
	SHLD ECX, EAX, 2
bytemove:
	REP MOVSB
END Copy;

PROCEDURE Map*(X: INTEGER): LONGINT;
BEGIN
	RETURN LinearBase
END Map;

PROCEDURE AdjustClip*(X, Y, W, H: INTEGER);
VAR right, top: INTEGER;
BEGIN 
	right := X + W; top := Y + H;
	IF X> clipx THEN clipx:= X END; IF Y> clipy THEN clipy:= Y END;
	IF right < clipright THEN clipright:= right END; IF top < cliptop THEN cliptop:= top END;
END AdjustClip;

PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
VAR si: SHORTINT;
BEGIN SYSTEM.GET(pat, si); w := si; SYSTEM.GET(pat+1, si); h := si; 
END GetDim;

PROCEDURE ResetClip*;
BEGIN 
	clipx := 0; clipy := UBottom;  clipright := Width; cliptop := Height+1 (* ?? *)
END ResetClip;

PROCEDURE SetClip*(x, y, w, h: INTEGER);
BEGIN  
	clipright := x+w; cliptop := y+h; clipy := y; clipx := x
END SetClip;

PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
BEGIN 
	x := clipx; y := clipy; w := clipright - clipx; h := cliptop - clipy
END GetClip;

PROCEDURE SetColor*(col, red, green, blue: INTEGER);	(* 0 <= col, red, green, blue < 256 *)
VAR ch: CHAR;
BEGIN
	IF (col = 0) OR (col = 15) THEN	(* either 0 or 15 must be black.  set the border to black. *)
		SYSTEM.PORTIN(3DAH, ch);
		SYSTEM.PORTOUT(3C0H, 11X);
		IF (red = 0) & (green = 0) & (blue = 0) THEN SYSTEM.PORTOUT(3C0H, CHR(col))
		ELSE SYSTEM.PORTOUT(3C0H, CHR(15-col))
		END;
		SYSTEM.PORTOUT(3C0H, 20X)
	END;
	SYSTEM.PORTOUT( 3C8H, CHR( col));
	SYSTEM.PORTOUT( 3C9H, CHR( red DIV 4));
	SYSTEM.PORTOUT( 3C9H, CHR( green DIV 4));
	SYSTEM.PORTOUT( 3C9H, CHR( blue DIV 4));	
END SetColor;

PROCEDURE GetColor*(col: INTEGER; VAR red, green, blue: INTEGER);
VAR ch: CHAR;
BEGIN
	SYSTEM.PORTOUT( 3C7H, CHR( col));
	SYSTEM.PORTIN( 3C9H, ch); red:= ORD( ch)*4;
	SYSTEM.PORTIN( 3C9H, ch); green:= ORD( ch)*4;
	SYSTEM.PORTIN( 3C9H, ch); blue:= ORD( ch)*4;
END GetColor;

PROCEDURE Dot*(col, x, y, mode: INTEGER);
VAR ch: CHAR;
		adr: LONGINT;
BEGIN
	IF (y < clipy) OR (y >= cliptop) OR  (x < clipx) OR (x >=  clipright) THEN RETURN END;
	adr:= ( Height-1-y) * LONG( Width) + x + LinearBase;
	IF mode # replace THEN
		SYSTEM.GET( adr, ch);
		IF mode = paint THEN
			col:= SYSTEM.VAL( INTEGER, SYSTEM.VAL( SET, ch)+ SYSTEM.VAL( SET, col));
		ELSE col:= SYSTEM.VAL( INTEGER, SYSTEM.VAL( SET, ch)/ SYSTEM.VAL( SET, col));
		END;
	END;
	SYSTEM.PUT( adr, CHR( col));
END Dot;

PROCEDURE CopyBlock*(SX, SY, W, H, DX, DY, mode: INTEGER);
VAR width, top, right, dX, dY, k: INTEGER;
		src, dst, i, j: LONGINT; set: SET;
		buf: ARRAY 256 OF SET;
BEGIN
	IF SX<0 THEN DEC( DX, SX); INC( W, SX); SX:= 0; END;
	IF SX+W> Width THEN W:= Width-SX; END;
	right := DX + W; top := DY + H; dX := DX; dY := DY;
	IF DX < clipx THEN DEC( W, (clipx - DX)); DX := clipx END; 
	IF DY < clipy THEN DEC( H, (clipy - DY)); DY := clipy END;
	IF  clipright < right THEN  W :=  clipright - DX END; 
	IF cliptop  < top THEN H := cliptop - DY END;
	DEC( SX,( dX - DX)); DEC( SY,( dY - DY));
	IF DY < SY THEN src := Height-1; dst := Height-1; width:= -Width;
	ELSE src := Height- H; dst := Height- H; width:= Width;
	END;
	src := ( src- SY) * LONG( Width) + SX + LinearBase;
	dst := ( dst- DY) * LONG( Width) + DX + LinearBase;
	IF ( src = dst) OR (W <= 0) OR (H <= 0) THEN RETURN END;
	IF mode = replace THEN
		REPEAT
			Copy(src, dst, W);
			DEC( H); INC( src, LONG(width)); INC( dst, LONG(width));
		UNTIL H=0;
		bank:= -1;
	ELSE
		k:= ( SX+ W-1) DIV 4;
		buf[ SX DIV 4] := {}; buf[ k] := {};
		REPEAT
			j:= src; i:= dst;
			Copy( j, SYSTEM.ADR( buf[ 0])+SX, W);
			i:= i DIV 4 * 4;
			j:= SX DIV 4;
			REPEAT
				SYSTEM.GET( i, set);
				IF mode = invert THEN set := buf[ j] / set;
				ELSE (* mode = paint *) set := buf[ j]+ set ;
				END;
				SYSTEM.PUT( i, set);
				INC( i, 4); INC( j );
			UNTIL j>k;
			DEC( H); INC( src, LONG(width)); INC( dst, LONG(width));
		UNTIL H=0;
	END;
END CopyBlock;

PROCEDURE SetMode*(X: INTEGER; s: SET);
BEGIN END SetMode;

PROCEDURE CopyPattern*(col: INTEGER; pat: LONGINT; X, Y, mode: INTEGER);
VAR i, w, h: SHORTINT; ch1, ch2: CHAR;
	cpX, cpY, cpR, cpH, x, y: INTEGER;
	adr, adr2, pat2: LONGINT;
BEGIN
	SYSTEM.GET(pat, w); INC( pat); SYSTEM.GET(pat, h); INC( pat);
	cpR := w + X; cpH := h + Y; 
	w:= ( w+7) DIV 8;
	x := X; y := Y;
	IF x < clipx THEN X := clipx END;
	IF y < clipy THEN Y := clipy END;
	IF cpR > clipright THEN cpR := clipright END;
	IF cpH > cliptop THEN cpH := cliptop END;
	cpX := X - x; cpY := Y - y;
	DEC( cpR, X - cpX ); DEC( cpH, Y); 
	IF (cpR <= cpX) OR (cpH <= 0) OR (cpX < 0) OR (cpY < 0) THEN RETURN END;
	adr:= ( Height-1- cpY- LONG( y))*  Width + x + LinearBase;
	INC( pat, LONG(cpY*w));
	REPEAT
		pat2:= pat; adr2:= adr;
		i:= SHORT( cpX ); INC( pat2, LONG(cpX DIV 8));
		IF i MOD 8 #0 THEN SYSTEM.GET( pat2, ch1); INC( pat2); END;
		IF mode # invert THEN
			REPEAT
				IF i MOD 8= 0 THEN SYSTEM.GET( pat2, ch1); INC( pat2); END;
				IF (( i MOD 8) IN SYSTEM.VAL( SET, ch1)) THEN
					SYSTEM.PUT( adr2 +i, CHR( col));
				END;
				INC( i);
			UNTIL i =cpR;
		ELSE
			REPEAT
				IF i MOD 8= 0 THEN SYSTEM.GET( pat2, ch1); INC( pat2); END;
				IF ( i MOD 8) IN SYSTEM.VAL( SET, ch1) THEN
					SYSTEM.GET( adr2+ i, ch2);
					IF mode = paint THEN 
						ch2:= SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch2) + SYSTEM.VAL( SET, col));
					ELSE (* mode = invert *)
						ch2:= SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch2) / SYSTEM.VAL( SET, col));
					END;
					SYSTEM.PUT( adr2 +i, ch2);
				END;
				INC( i);
			UNTIL i= cpR;
		END;
		DEC( adr, LONG(Width));
		INC( pat, LONG( LONG( w)));
		DEC( cpH);
	UNTIL cpH=0;
END CopyPattern;

PROCEDURE ReplConst*(col, X, Y, W, H, mode: INTEGER);
VAR ch, ch2: CHAR;
		right, top, x, y, w, int, int2: INTEGER;
		adr, adr2: LONGINT; set, set2: SET;
BEGIN
	ch:= CHR( col); int:= SHORT( ASH(col, 8) + LONG( col MOD 256));
	set:= SYSTEM.VAL( SET, ASH( int, 16)) +SYSTEM.VAL( SET, int)* {0..15};
	top := Y + H; right := X + W; 
	IF X < clipx THEN X := clipx END;
	IF Y < clipy THEN Y := clipy END;
	IF clipright < right THEN right :=  clipright END; 
	IF cliptop < top THEN top := cliptop END;
	W := right - X; H := top - Y;
	IF (W <= 0) OR (H <= 0) OR (X < 0) (* OR (Y < 0)*) THEN RETURN END;
	IF Y=Height THEN RETURN END;
	adr := LONG( Height -1- Y ) *  Width + X + LinearBase;
	x:= X+W;
	IF mode = replace THEN
		REPEAT
			w:= W; adr2:= adr;
			IF 0 IN SYSTEM.VAL( SET, adr2) THEN SYSTEM.PUT( adr2, ch); INC( adr2); DEC( w); END;
			IF w> 1 THEN
				IF ( 1 IN SYSTEM.VAL( SET, adr2)) THEN SYSTEM.PUT( adr2, int); INC( adr2, 2); DEC( w, 2); END;
				WHILE w>= 4 DO SYSTEM.PUT( adr2, set); INC( adr2, 4); DEC( w, 4); END;
				IF w>= 2  THEN SYSTEM.PUT( adr2, int); INC( adr2, 2); END;
			END;
			IF ODD( w) THEN SYSTEM.PUT( adr2, ch); END;
			DEC( H); DEC( adr, LONG(Width));
		UNTIL (H=0) OR (adr<LinearBase);
	ELSIF mode = paint THEN
		REPEAT
			w:= W; adr2:= adr;
			IF 0 IN SYSTEM.VAL( SET, adr2) THEN SYSTEM.GET( adr2, ch2); SYSTEM.PUT( adr2, SYSTEM.VAL( CHAR, set+ SYSTEM.VAL( SET, ch2))); INC( adr2); DEC( w); END;
			IF w> 1 THEN
				IF (1 IN SYSTEM.VAL( SET, adr2)) THEN SYSTEM.GET( adr2, int2); SYSTEM.PUT( adr2, SYSTEM.VAL( INTEGER, set+ SYSTEM.VAL( SET, int2))); INC( adr2, 2); DEC( w, 2); END;
				WHILE w>= 4 DO
					SYSTEM.GET( adr2, set2); SYSTEM.PUT( adr2, set+ set2); INC( adr2, 4); DEC( w, 4);
				END;
				IF w>= 2  THEN SYSTEM.GET( adr2, int2); SYSTEM.PUT( adr2, SYSTEM.VAL( INTEGER, set+ SYSTEM.VAL( SET, int2))); INC( adr2, 2); END;
			END;
			IF ODD( w) THEN SYSTEM.GET( adr2, ch2); SYSTEM.PUT( adr2, SYSTEM.VAL( CHAR, set+ SYSTEM.VAL( SET, ch2))); END;
			DEC( H); DEC( adr, LONG(Width));
		UNTIL (H=0) OR (adr<LinearBase);
	ELSE (* mode = invert *)
		REPEAT
			w:= W; adr2:= adr;
			IF 0 IN SYSTEM.VAL( SET, adr2) THEN SYSTEM.GET( adr2, ch2); SYSTEM.PUT( adr2, SYSTEM.VAL( CHAR, set/ SYSTEM.VAL( SET, ch2))); INC( adr2); DEC( w); END;
			IF w> 1 THEN
				IF ( 1 IN SYSTEM.VAL( SET, adr2)) THEN SYSTEM.GET( adr2, int2); SYSTEM.PUT( adr2, SYSTEM.VAL( INTEGER, set/ SYSTEM.VAL( SET, int2))); INC( adr2, 2); DEC( w, 2); END;
				WHILE w>= 4 DO
					SYSTEM.GET( adr2, set2); SYSTEM.PUT( adr2, set/ set2); INC( adr2, 4); DEC( w, 4);
				END;
				IF w>= 2  THEN SYSTEM.GET( adr2, int2); SYSTEM.PUT( adr2, SYSTEM.VAL( INTEGER, set/ SYSTEM.VAL( SET, int2))); INC( adr2, 2); END;
			END;
			IF ODD( w) THEN SYSTEM.GET( adr2, ch2); SYSTEM.PUT( adr2, SYSTEM.VAL( CHAR, set/ SYSTEM.VAL( SET, ch2))); END;
			DEC( H); DEC( adr, LONG(Width));
		UNTIL (H=0) OR (adr<LinearBase);
	END;	
END ReplConst;

	PROCEDURE FillPattern*(col: INTEGER; pat: Pattern; pX, pY, X, Y, W, H, mode: INTEGER);
	VAR w, h: SHORTINT; ch: CHAR;
			p0, wi, right, top: INTEGER;
			apat, dadr, dadr2: LONGINT; set: SET;
	BEGIN
		SYSTEM.GET(pat, w); INC( pat);
		SYSTEM.GET(pat, h); INC( pat);
		top := Y + H; right := X + W; 
		IF X < clipx THEN X := clipx END;
		IF Y < clipy THEN Y := clipy END;
		IF  clipright < right THEN right :=  clipright END; 
		IF cliptop < top THEN top := cliptop END;
		W := right - X; H := top - Y;
		dadr:= ( Height - 1 - LONG( Y))* Width+ X + LinearBase;
		IF (W <= 0) OR (H <= 0) OR (X < 0) OR (Y < 0) OR 
						(( w#16) & (w#32)) THEN RETURN	END;
		apat:= pat;
		REPEAT
			dadr2:= dadr;
			IF w=16 THEN
				SYSTEM.GET( apat, p0); INC( apat, 2);
				IF apat >= pat + 2* h THEN apat:= pat; END;
				set:= SYSTEM.VAL( SET, ASH( LONG( p0), 16)) + SYSTEM.VAL( SET, p0)* {0..15}; (* ! *)
			ELSE
				SYSTEM.GET( apat, set); INC( apat, 4);
				IF apat >= pat + 4* h THEN apat:= pat; END;
			END;
			set:= SYSTEM.ROT( set, -( pX MOD 32));
			IF ( mode # invert) THEN
				wi:=0;
				REPEAT
					IF wi MOD 32 IN set THEN SYSTEM.PUT( dadr2, SHORT( col)); END;
					INC( dadr2); INC( wi);
				UNTIL wi=W;
			ELSE
				wi:= W;
				REPEAT
					IF 0 IN set THEN
						SYSTEM.GET( dadr2, ch);
						IF mode = paint THEN
							ch:= SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch) + SYSTEM.VAL( SET, col));
						ELSE (* mode= invert *)
							ch:= SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch) / SYSTEM.VAL( SET, col));
						END;
						SYSTEM.PUT( dadr2, ch);
					END;
					set:=SYSTEM.ROT( set, -1);
					INC( dadr2); DEC( wi);
				UNTIL wi=0;
			END;
			DEC( H); DEC( dadr, LONG(Width));
		UNTIL H=0;
	END FillPattern;
	
PROCEDURE ReplPattern*(col: INTEGER; pat: Pattern; X, Y, W, H, mode: INTEGER);
BEGIN FillPattern( col, pat, 0, 0, X, Y, W, H, mode);
	(* or FillPattern(col,pat,X,Y,X,Y,W,H,mode); like in the ET4000 driver from Pircher?? *)
END ReplPattern;

PROCEDURE NewPattern*(width, height: INTEGER; VAR image: ARRAY OF SET): Pattern;
VAR len, src, dest: LONGINT; i: INTEGER; p: PatternPtr; inter: SET;  pl: List;
BEGIN 
	len := (width+7) DIV 8;
	SYSTEM.NEW(p, 4+len*height); p.w := SHORT(width); p.h := SHORT(height);
	src := SYSTEM.ADR(image); dest := SYSTEM.ADR(p.pixmap);
	i := 0;
	WHILE i < height DO SYSTEM.MOVE(src, dest, len); INC(src, 4); INC(dest, len); INC(i) END;
	NEW(pl);  pl.pat := p;  pl.next := Pat;  Pat := pl;	(* put in list to avoid GC *)
	RETURN SYSTEM.ADR(p.w)
END NewPattern;

PROCEDURE CreatePatterns;
VAR image: ARRAY 16 OF SET;
BEGIN
	image[0] := {13};	image[1] := {12..14};
	image[2] := {11..13};	image[3] := {10..12};
	image[4] := {9..11};	image[5] := {8..10};
	image[6] := {7..9};	image[7] := {0, 6..8};
	image[8] := {0, 1, 5..7};	image[9] := {0..2, 4..6};
	image[10] := {0..5};	image[11] := {0..4};
	image[12] := {0..5};	image[13] := {0..6};
	image[14] := {0..7};
	arrow := NewPattern(15, 15, image);
	
	image[0] := {0, 10};	image[1] := {1, 9};
	image[2] := {2, 8};	image[3] := {3, 7};
	image[4] := {4, 6};	image[5] := {};
	image[6] := {4, 6};	image[7] := {3, 7};
	image[8] := {2, 8};	image[9] := {1, 9};
	image[10] := {0, 10};
	cross := NewPattern(11, 11, image); 
	
	image[0] := {6};	image[1] := {5..7};
	image[2] := {4..8};	image[3] := {3..9};
	image[4] := {2..10};	image[5] := {5..7};
	image[6] := {5..7};	image[7] := {5..7};
	image[8] := {5..7};	image[9] := {5..7};
	image[10] := {5..7};	image[11] := {5..7};
	image[12] := {5..7};	image[13] := {5..7};
	image[14] := {};
	downArrow := NewPattern(15, 15, image);
	
	image[0] := {0, 4, 8, 12};	image[1] := {};
	image[2] := {2, 6, 10, 14};	image[3] := {};
	grey0 := NewPattern(16, 4, image);
	
	image[0] := {0, 2, 4, 6, 8, 10, 12, 14};	image[1] := {1, 3, 5, 7, 9, 11, 13, 15};
	grey1 := NewPattern(16, 2, image);

	image[0] := {0, 1, 4, 5, 8, 9, 12, 13};	image[1] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[2] := {2, 3, 6, 7, 10, 11, 14, 15};	image[3] := {2, 3, 6, 7, 10, 11, 14, 15};
	grey2 := NewPattern(16, 4, image);
	
	image[0] := {0..2, 8..11};	image[1] := {0..2, 7..10};
	image[2] := {0..2, 6..9};	image[3] := {0..2, 5..8};
	image[4] := {0..2, 4..7};	image[5] := {0..6};
	image[6] := {0..5};	image[7] := {0..4};
	image[8] := {0..3};	image[9] := {0..2};
	image[10] := {0, 1};	image[11] := {0};
	hook := NewPattern(12, 12, image);
	
	image[0] := {7};	image[1] := {7};
	image[2] := {2, 7, 12};	image[3] := {3, 7, 11};
	image[4] := {4, 7, 10};	image[5] := {5, 7, 9};
	image[6] := {6..8};	image[7] := {0..6, 8..14};
	image[8] := {6..8};	image[9] := {5, 7, 9};
	image[10] := {4, 7, 10};	image[11] := {3, 7, 11};
	image[12] := {2, 7, 12};	image[13] := {7};
	image[14] := {7};
	star := NewPattern(15, 15, image);

	image[0] := {};	image[1] := {};
	image[2] := {0};	image[3] := {};
	image[4] := {};	image[5] := {};
	image[6] := {};	image[7] := {};
	image[8] := {};	image[9] := {};
	image[10] := {};	image[11] := {};
	image[12] := {};	image[13] := {};
	image[14] := {};	image[15] := {};
	ticks := NewPattern(16, 16, image);
	
	image[0] := -{};
	solid := NewPattern(16, 1, image);
	
END CreatePatterns;

PROCEDURE Depth*(X: INTEGER): INTEGER;
BEGIN RETURN 8 END Depth;

PROCEDURE DisplayBlock*(B:LONGINT; DX, DY, W, H, SX, SY, mode:INTEGER);
VAR ch, ch2: CHAR;
	j, x, w, h: INTEGER;
	dadr, dadr2, y: LONGINT;
BEGIN
	SYSTEM.GET( B, w); SYSTEM.GET( B+2, h); SYSTEM.GET( B+12, B);
	dadr:= ( Height -2 (* ?? *) -LONG( SY))*Width+ SX + LinearBase; j:= 0;
	y:= DY* LONG( w);
	IF mode # invert THEN
		WHILE j <H  DO
			dadr2:= dadr;
			IF y >= h* LONG( w) THEN y:= 0 END;
			Copy( B+y+ DX, dadr2, W);
			INC( j); DEC( dadr, LONG(Width)); INC( y, LONG(w));
		END;
	ELSE
		WHILE j <H  DO
			dadr2:= dadr;
			IF y >= h* LONG( w) THEN y:= 0 END;
			FOR x:= DX TO W-1 DO
				SYSTEM.GET( B + y+ x, ch);
				SYSTEM.GET( dadr2, ch2);
				IF mode = paint THEN
					ch:= SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch) + SYSTEM.VAL( SET, ch2));
				ELSE ch:= SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch) / SYSTEM.VAL( SET, ch2));
				END;
				SYSTEM.PUT( dadr2, ch);
				INC( dadr2);
			END;
		END;
		INC( j); DEC( dadr, LONG(Width)); INC( y, LONG(w));
	END;
END DisplayBlock;

PROCEDURE StrToInt(s: ARRAY OF CHAR): LONGINT;
VAR i, j: SHORTINT;  v, sgn, m: LONGINT;
BEGIN
	j := 0;  WHILE s[j] # 0X DO INC(j) END;
	IF (j > 0) & (CAP(s[j-1]) = "H") THEN m := 16; DEC(j) ELSE m := 10 END;
	v := 0;  i := 0;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	WHILE i < j DO
		IF (s[i] >= "0") & (s[i] <= "9") THEN v := v*m + (ORD(s[i])-ORD("0"))
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN v := v*m + (ORD(CAP(s[i]))-ORD("A")+10)
		ELSE sgn := 0;  j := i
		END;
		INC(i)
	END;
	RETURN sgn*v
END StrToInt;

PROCEDURE GetVal(str: ARRAY OF CHAR): LONGINT;
VAR s: ARRAY 12 OF CHAR;
BEGIN
	Kernel.GetConfig(str, s);
	RETURN StrToInt(s)
END GetVal;

BEGIN
	Kernel.WriteString("Vesa:");
	LinearBase := GetVal("=1");	(* from DX:CX in Init string *)
	Kernel.WriteString(" DX:CX=");  Kernel.WriteHex(LinearBase, 8);
	IF LinearBase = 0 THEN
		LinearBase:= GetVal("LB") *1048576
	END;
	Kernel.WriteString(" LinBuf=");  Kernel.WriteHex(LinearBase, 8);
	Kernel.WriteLn;

	Left:= 0; ColLeft:= 0; Bottom:= 0;
	Pat := NIL;
	Width := SHORT(GetVal("DWidth"));
	IF Width = 0 THEN Width := 1024 END;	(* assume 1024 if not specified *)
	Height := SHORT(GetVal("DHeight"));
	IF Height = 0 THEN Height := 768 END;	(* assume 768 if not specified *)

	UBottom := Height - SHORT(GetVal("DMem")*1024 DIV Width);
	IF UBottom = Height THEN UBottom := -256 END;	(* assume 1Mb if not specified *)
	IF UBottom > -255 THEN HALT(99) END;	(* not enough space *)

	ResetClip;
	CreatePatterns;
	bank:= -1;
	Unit := 10000;
	
	(* Version:="pm 19.03.96"; *)
	Version:= "CRF 23.02.97";
END Display.

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
(* Type: S3Trio	based on the S3C805 driver from A. R. Disteli	*)
(*
	tested only on Trio64V(+), but should work on Trio64, Trio32, 868? 968? too.
	Vesa Mode 100H: 640x400x8
						103H: 800x600x8
						105H: 1024x768x8
	03.12.96	p.matthias: 
							clipping bug in AdjustClip fixed
							CopyPattern, FillPattern streamlined
							memory mapped I/O
							disabled programmed I/O to non standart VGA registers
							automatic detection of Dmem, Width, Height for chips of the Trio family
							disabled border
	16.01.97 pjm: removed border disabling, added border colour setting in SetColor
*)
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
		
		(* S3 Constants , packed MMIO *)
		curY= 0A8100H;		curX= 0A8102H;
		axStep= 0A8108H;		diaStep= 0A810AH;
		errTerm= 0A8110H;
		cmd= 0A8118H;
		shortStroke= 0A811CH;
		BGcol= 0A8120H;
		FGcol= 0A8124H;
		wrtMask= 0A8128H;
		rdMask= 0A812CH;
		ColorCMP= 0A8130H;
		BGmix= 0A8134H;	FGmix= 0A8136H;	AltMix= 0A8134H;
		ScissorsT= 0A8138H;	ScissorsL= 0A813AH;	(* clippint top, left *)
		ScissorsB= 0A813CH;	ScissorsR= 0A813EH;	(* clipping bottom, right *)
		PixCntl= 0A8140H;	MultMisc2= 0A8142H;
		MultMisc= 0A8144H;	ReadSel= 0A8146H;
		MinAxis= 0A8148H;	MajAxis= 0A814AH;
	
		pixTrans = 0AE2E8H;
		
	TYPE Pattern* = LONGINT;
			PatternPtr = POINTER TO RECORD w, h: SHORTINT; pixmap: ARRAY 2048 OF CHAR END;
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
		dmem, base: LONGINT;
		clipx, clipy, clipright, cliptop: INTEGER;	(* clipping variables *)
			
	PROCEDURE Wait;
	VAR wait: INTEGER;
	BEGIN
		REPEAT SYSTEM.GET( cmd, wait) UNTIL ~ODD( ASH( wait, -9));
	END Wait;
	
	PROCEDURE Map*(X: INTEGER): LONGINT;
	BEGIN RETURN base		(* of linear framebuffer *)
	END Map;
	
	PROCEDURE AdjustClip*(X, Y, W, H: INTEGER);
	VAR right, top, left, bottom: INTEGER;
	BEGIN 
		right := X + W;
		IF X> clipx THEN clipx:= X END;
		IF right< clipright THEN clipright:= right END;
		left:= clipx;
		IF left < 0 THEN left := 0 ELSIF left > Width THEN left := Width-1 END;
		right := clipright-1;
		IF right < 0 THEN right := 0 ELSIF right > Width THEN right := Width-1 END;
		top := Y + H;
		IF Y> clipy THEN clipy:= Y END;
		IF top< cliptop THEN cliptop:= top END;
		top := cliptop-1;
		IF top < 0 THEN top := 0 ELSIF top >= Height THEN top := Height-1 END;
		bottom := clipy;
		IF bottom < 0 THEN bottom := 0 ELSIF bottom > Height THEN bottom := Height-1 END;
		SYSTEM.PUT( ScissorsT, 1000H+ Height-1-top);		(* top *)
		SYSTEM.PUT( ScissorsL, 2000H+ left); 			 			(* left *)
		SYSTEM.PUT( ScissorsB, 3000H+ Height-1-bottom);	(* bottom *)
		SYSTEM.PUT( ScissorsR, 4000H+ right); 					 (* right *)
	END AdjustClip;

	PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
	VAR p: PatternPtr;
	BEGIN 
		p:= SYSTEM.VAL( PatternPtr, pat);
		w:= p^.w; h:= p^.h;
	END GetDim;

	PROCEDURE ResetClip*;
	BEGIN 
		clipx := 0; clipy := UBottom; 
		clipright := Width;
		cliptop := Height;
		SYSTEM.PUT( ScissorsT, 1000H);	(* top *)
		SYSTEM.PUT( ScissorsL, 2000H);	(* left *)
		SYSTEM.PUT( ScissorsB, 3000H+ Height-1-UBottom);	(* bottom *)
		SYSTEM.PUT( ScissorsR, 4000H+ Width-1);	(* right *)
	END ResetClip;
	
	PROCEDURE SetClip*(x, y, w, h: INTEGER);
	BEGIN	
		clipright := x+w;
		cliptop := y+h;
		clipy := y; clipx := x;
		SYSTEM.PUT( ScissorsT, 1000H+ Height-cliptop);	(* top *)
		SYSTEM.PUT( ScissorsL, 2000H+ clipx); 					 (* left *)
		SYSTEM.PUT( ScissorsB, 3000H+ Height-1-clipy );	(* bottom *)
		SYSTEM.PUT( ScissorsR, 4000H+ clipright-1); 		 (* right *)
	END SetClip;
	
	PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
	BEGIN 
		x := clipx; y := clipy; w := clipright - clipx; h := cliptop - clipy;
	END GetClip;

	PROCEDURE SetColor*(col, red, green, blue: INTEGER);	(* 0 <= col, red, green, blue < 256 *)
	VAR ch: CHAR;
	BEGIN
		IF (col = 0) OR (col = 15) THEN	(* either 0 or 15 must be black.  set the border to black. *)
				(* note: the S3 uses the palette for the border colour too *)
			SYSTEM.PORTIN(3DAH, ch);
			SYSTEM.PORTOUT(3C0H, 11X);
			IF (red = 0) & (green = 0) & (blue = 0) THEN SYSTEM.PORTOUT(3C0H, CHR(col))
			ELSE SYSTEM.PORTOUT(3C0H, CHR(15-col))
			END;
			SYSTEM.PORTOUT(3C0H, 20X)
		END;
		SYSTEM.PORTOUT(3C8H, SHORT(col));
		SYSTEM.PORTOUT(3C9H, SHORT(red DIV 4));
		SYSTEM.PORTOUT(3C9H, SHORT(green DIV 4));
		SYSTEM.PORTOUT(3C9H, SHORT(blue DIV 4))
	END SetColor;

	PROCEDURE GetColor*(col: INTEGER; VAR red, green, blue: INTEGER);
	VAR help: CHAR;
	BEGIN
		SYSTEM.PORTOUT(3C7H, SHORT(col));
		SYSTEM.PORTIN(3C9H, help); red := ORD(help)*4+ ORD( help) DIV 16;
		SYSTEM.PORTIN(3C9H, help); green := ORD(help)*4+ ORD( help) DIV 16;
		SYSTEM.PORTIN(3C9H, help); blue := ORD(help)*4+ ORD( help) DIV 16;
	 END GetColor;
	
	PROCEDURE Dot*(col, x, y, mode: INTEGER);
	BEGIN
		IF mode = invert THEN SYSTEM.PUT(FGmix, LONG(25H));
		ELSIF mode= paint THEN SYSTEM.PUT( FGmix, LONG(2BH));
		ELSE SYSTEM.PUT(FGmix, LONG(27H));
		END;
		SYSTEM.PUT(FGcol, col);
		SYSTEM.PUT( PixCntl, LONG( 0));
		SYSTEM.PUT(curX, x);
		SYSTEM.PUT(curY, Height-1-y);
		Wait;
		SYSTEM.PUT(cmd, 121BH);
		SYSTEM.PUT(shortStroke, LONG(10H));
	END Dot;

	PROCEDURE CopyBlock*(SX, SY, W, H, DX, DY, mode: INTEGER);
	VAR comd: INTEGER;
	BEGIN
		IF (W > 0) & (H > 0) THEN
			comd := SYSTEM.VAL(INTEGER, 0C073H);
			IF SY <= DY THEN
				INC(SY, H-1); INC(DY, H-1); INC(comd, 128);
				IF SX < DX THEN INC(SX, W-1); INC(DX, W-1); DEC(comd, 32) END
			END;
			IF mode = invert THEN SYSTEM.PUT(FGmix, LONG(65H))
			ELSE SYSTEM.PUT(FGmix, LONG(67H))
			END;
			SYSTEM.PUT(PixCntl, LONG(0));
			SYSTEM.PUT(curX, SX);
			SYSTEM.PUT(curY, Height - 1 - SY);
			SYSTEM.PUT(diaStep, DX);
			SYSTEM.PUT(axStep, Height -1 - DY);
			SYSTEM.PUT(MajAxis, W-1);
			SYSTEM.PUT(MinAxis, H-1);
			Wait;
			SYSTEM.PUT(cmd, comd)
		END
	END CopyBlock;

	PROCEDURE SetMode*(X: INTEGER; s: SET);
	BEGIN END SetMode;
	
	PROCEDURE CopyPattern*(col: INTEGER; pat: Pattern; X, Y, mode: INTEGER);
	VAR wth, pwidth, pos: LONGINT; p: PatternPtr;
	BEGIN
		p:= SYSTEM.VAL( PatternPtr, pat);
		wth:=(p^.w+7) DIV 8;
		INC(X, SHORT( wth*8-1)); 
		Y := Height-Y-p.h;
		IF mode= invert THEN SYSTEM.PUT( AltMix, 250003H);
		ELSIF mode= replace THEN SYSTEM.PUT( AltMix, 270001H);
		ELSE SYSTEM.PUT( AltMix, 270003H);
		END;
		SYSTEM.PUT(FGcol, col);
		SYSTEM.PUT( PixCntl, ORD( 80X));
		SYSTEM.PUT(MajAxis, SHORT( wth*8-1));
		pos:= wth*p^.h;
		WHILE pos>0 DO
			SYSTEM.PUT(curX, X);
			SYSTEM.PUT(curY, Y);
			Wait;
			SYSTEM.PUT(cmd, 219BH);
			pwidth:= wth;
			REPEAT
				DEC( pos); DEC( pwidth);
				SYSTEM.PUT( pixTrans, p^.pixmap[ pos]);
			UNTIL (pwidth<=0);
			INC( Y);
		END;
	END CopyPattern;

	PROCEDURE ReplConst*(col, X, Y, W, H, mode: INTEGER);
		BEGIN
		IF (W > 0) & (H > 0) THEN 
			IF mode = invert THEN SYSTEM.PUT(FGmix, LONG(25H));
			ELSIF mode= paint THEN SYSTEM.PUT( FGmix, LONG(2BH));
			ELSE SYSTEM.PUT(FGmix, LONG(27H)) END;
			SYSTEM.PUT(FGcol, col);
			SYSTEM.PUT( PixCntl, LONG( 0));
			SYSTEM.PUT(curX, X);
			SYSTEM.PUT(curY, Height-1-Y);
			SYSTEM.PUT(MajAxis, W-1);
			SYSTEM.PUT(MinAxis, H-1);
			Wait;
			SYSTEM.PUT(cmd, 4073H)
		END
	END ReplConst;

	PROCEDURE FillPattern*(col: INTEGER; pat: Pattern; pX, pY, X, Y, W, H, mode: INTEGER);
		VAR bit16: INTEGER;
				pat0, bit32, yo, hgt, wdt: LONGINT;
				p: PatternPtr;
	BEGIN 
		IF (W <= 0) OR (H <= 0) THEN RETURN END;
		p:= SYSTEM.VAL( PatternPtr, pat);
		INC(pat, 2);
		INC(X, W-1);
		yo:= (Y + pY) MOD p^.h;
		Y := Height-1-Y;
		IF mode= invert THEN SYSTEM.PUT( AltMix, 250003H);
		ELSIF mode= replace THEN SYSTEM.PUT( AltMix, 270001H);
		ELSE SYSTEM.PUT( AltMix, 270003H);
		END;
		SYSTEM.PUT(FGcol, col);
		SYSTEM.PUT( PixCntl, ORD( 80X));
		SYSTEM.PUT(MajAxis, W-1);
		pat0 := pat+ p^.w DIV 8 * yo;
		hgt := p^.h - yo;
		WHILE H > 0 DO
			wdt:= ( W + 7 ) DIV 8;
			IF p^.w = 16 THEN
				SYSTEM.GET(pat0, bit16); INC(pat0, 2);
				bit32:= LONG( bit16)* 10000H+ LONG( bit16) MOD 10000H;
			ELSIF p^.w = 32 THEN SYSTEM.GET(pat0, bit32); INC(pat0, 4);
			END;
			bit32 := SYSTEM.ROT(bit32, pX-X);	(* SYSTEM.ROT(bit32, pX-X0+16) ?? *)
			SYSTEM.PUT(curX, X);
			SYSTEM.PUT(curY, Y);
			Wait;
			SYSTEM.PUT(cmd, 239BH);
			WHILE wdt >0 DO
				SYSTEM.PUT(pixTrans, bit32);
				DEC( wdt,4);
			END;
			DEC(Y);
			DEC(H); DEC(hgt);
			IF hgt <= 0 THEN hgt := p^.h; pat0 := pat END;
		END;
	END FillPattern;
	
	PROCEDURE ReplPattern*(col: INTEGER; pat: Pattern; X, Y, W, H, mode: INTEGER);
	BEGIN FillPattern(col, pat, 0, 0, X, Y, W, H, mode)
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
		image[0] := {13};
		image[1] := {12..14};
		image[2] := {11..13};
		image[3] := {10..12};
		image[4] := {9..11};
		image[5] := {8..10};
		image[6] := {7..9};
		image[7] := {0, 6..8};
		image[8] := {0, 1, 5..7};
		image[9] := {0..2, 4..6};
		image[10] := {0..5};
		image[11] := {0..4};
		image[12] := {0..5};
		image[13] := {0..6};
		image[14] := {0..7};
		arrow := NewPattern(15, 15, image);
		
		image[0] := {0, 10};
		image[1] := {1, 9};
		image[2] := {2, 8};
		image[3] := {3, 7};
		image[4] := {4, 6};
		image[5] := {};
		image[6] := {4, 6};
		image[7] := {3, 7};
		image[8] := {2, 8};
		image[9] := {1, 9};
		image[10] := {0, 10};
		cross := NewPattern(11, 11, image); 
		
		image[0] := {6};
		image[1] := {5..7};
		image[2] := {4..8};
		image[3] := {3..9};
		image[4] := {2..10};
		image[5] := {5..7};
		image[6] := {5..7};
		image[7] := {5..7};
		image[8] := {5..7};
		image[9] := {5..7};
		image[10] := {5..7};
		image[11] := {5..7};
		image[12] := {5..7};
		image[13] := {5..7};
		image[14] := {};
		downArrow := NewPattern(15, 15, image);
		
		image[0] := {0, 4, 8, 12};
		image[1] := {};
		image[2] := {2, 6, 10, 14};
		image[3] := {};
		image[4] := {0, 4, 8, 12};
		image[5] := {};
		image[6] := {2, 6, 10, 14};
		image[7] := {};
		image[8] := {0, 4, 8, 12};
		image[9] := {};
		image[10] := {2, 6, 10, 14};
		image[11] := {};
		image[12] := {0, 4, 8, 12};
		image[13] := {};
		image[14] := {2, 6, 10, 14};
		image[15] := {};
		grey0 := NewPattern(16, 16, image);
		
		image[0] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[1] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[2] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[3] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[4] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[5] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[6] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[7] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[8] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[9] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[10] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[11] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[12] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[13] := {1, 3, 5, 7, 9, 11, 13, 15};
		image[14] := {0, 2, 4, 6, 8, 10, 12, 14};
		image[15] := {1, 3, 5, 7, 9, 11, 13, 15};
		grey1 := NewPattern(16, 16, image);
		
		image[0] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[1] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[2] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[3] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[4] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[5] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[6] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[7] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[8] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[9] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[10] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[11] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[12] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[13] := {0, 1, 4, 5, 8, 9, 12, 13};
		image[14] := {2, 3, 6, 7, 10, 11, 14, 15};
		image[15] := {2, 3, 6, 7, 10, 11, 14, 15};
		grey2 := NewPattern(16, 16, image);
		
		image[0] := {0..2, 8..11};
		image[1] := {0..2, 7..10};
		image[2] := {0..2, 6..9};
		image[3] := {0..2, 5..8};
		image[4] := {0..2, 4..7};
		image[5] := {0..6};
		image[6] := {0..5};
		image[7] := {0..4};
		image[8] := {0..3};
		image[9] := {0..2};
		image[10] := {0, 1};
		image[11] := {0};
		hook := NewPattern(12, 12, image);
		
		image[0] := {7};
		image[1] := {7};
		image[2] := {2, 7, 12};
		image[3] := {3, 7, 11};
		image[4] := {4, 7, 10};
		image[5] := {5, 7, 9};
		image[6] := {6..8};
		image[7] := {0..6, 8..14};
		image[8] := {6..8};
		image[9] := {5, 7, 9};
		image[10] := {4, 7, 10};
		image[11] := {3, 7, 11};
		image[12] := {2, 7, 12};
		image[13] := {7};
		image[14] := {7};
		star := NewPattern(15, 15, image);
		
		image[0] := {};
		image[1] := {};
		image[2] := {0};
		image[3] := {};
		image[4] := {};
		image[5] := {};
		image[6] := {};
		image[7] := {};
		image[8] := {};
		image[9] := {};
		image[10] := {};
		image[11] := {};
		image[12] := {};
		image[13] := {};
		image[14] := {};
		image[15] := {};
		ticks := NewPattern(16, 16, image);
		
		image[0] := -{};
		image[1] := -{};
		solid := NewPattern(16, 2, image);
		
	END CreatePatterns;
	
	PROCEDURE Depth*(X: INTEGER): INTEGER;
	BEGIN RETURN 8 END Depth;
	
	PROCEDURE DBasm( adr, bw, wdt, h: LONGINT);
	CODE
		MOV ESI, adr[ EBP]
		MOV EAX, bw[ EBP]
		MOV EBX, wdt[ EBP]
		ADD EBX, 3
		AND EBX, 0FFFFFFFCH
		SUB EAX, EBX
		SHR EBX, 2
		MOV EDX, h[ EBP]
		CLD
labY:
		MOV EDI, 0A0000H
		MOV ECX, EBX
		REP
		MOVSD
		ADD ESI, EAX
		DEC EDX
		JNZ labY
	END DBasm;
(*
	PROCEDURE DBobn( adr, bw, wdt, h: LONGINT);
	VAR i, j: LONGINT;
	BEGIN
		WHILE h>0 DO
			FOR i:=0 TO wdt BY 4 DO
				SYSTEM.GET( adr+i, j);
				SYSTEM.PUT( pixTrans, j);		(* pixTrans or 0A0000H..0A7FFCH *)
			END;			
			INC( adr, bw);
			DEC( h);
		END;
	END DBobn;
*)
	PROCEDURE DisplayBlock*(B:LONGINT; DX, DY, W, H, SX, SY, mode:INTEGER);
	TYPE
		Block= POINTER TO BlockDesc;
		BlockDesc= RECORD
						w, h: INTEGER;
						dummy: ARRAY 4 OF CHAR;
						width: LONGINT;		(* width = w !!? *)
						adr: LONGINT;	(*	POINTER TO ARRAY 40000H OF SET; (* 1 MB *) *)
					END;
	VAR block: Block;
	BEGIN
		block:= SYSTEM.VAL( Block, B);
		SY:= Height-2-SY;		(* !! -2 ?? !! *)
		IF mode=replace THEN SYSTEM.PUT( FGmix, 47H);
		ELSIF mode=invert THEN SYSTEM.PUT( FGmix, 45H);
		ELSE SYSTEM.PUT( FGmix, 4BH);
		END;
		SYSTEM.PUT( PixCntl, LONG( 0H));
		SYSTEM.PUT( curX, SX);
		SYSTEM.PUT( curY, SY);
		SYSTEM.PUT( MajAxis, W-1);
		SYSTEM.PUT( MinAxis, H-1);
		Wait;
		SYSTEM.PUT( cmd, 5531H);
		DBasm( block.adr+ block.width*DY+ DX, block.width, W, H);
(* or
		DBobn( block.adr+ block.width*DY+ DX, block.width, W, H);
*)
	END DisplayBlock;
	
	PROCEDURE GetVal(str: ARRAY OF CHAR): LONGINT;
	VAR i: SHORTINT;  v, sgn: LONGINT;  s: ARRAY 10 OF CHAR;
	BEGIN
		Kernel.GetConfig(str, s);
		v := 0;  i := 0;
		WHILE s[i] # 0X DO v := v*10+(ORD(s[i])-48); INC(i) END;
		RETURN v
	END GetVal;
	
	PROCEDURE InitS3;
	VAR ch: CHAR; mask: LONGINT;
	BEGIN
		Width := SHORT(GetVal("DWidth"));
		IF Width = 0 THEN Width := 1024 END;	(* assume 1024 if not specified *)
		Height := SHORT(GetVal("DHeight"));
		IF Height = 0 THEN Height := 768 END;	(* assume 768 if not specified *)
		dmem := GetVal("DMem")*1024;
		IF dmem = 0 THEN dmem := 1024*1024 END;	(* assume 1Mb if not specified *)
		SYSTEM.PORTOUT( 3D4H, 2DH);
		SYSTEM.PORTIN( 3D5H, ch);
		IF ch= 88X THEN
			SYSTEM.PORTOUT( 3D4H, 2EH);
			SYSTEM.PORTIN( 3D5H, ch);
			IF ch= 11X THEN																(*	Trio found	*)
				Width:=0; Height:=0;
				SYSTEM.PORTOUT( 3D4H, 5DH);								(* get Width *)
				SYSTEM.PORTIN( 3D5H, ch);
				IF ODD( ORD( ch) DIV 2) THEN Width:= 256*8 END;
				SYSTEM.PORTOUT( 3D4H, 1);
				SYSTEM.PORTIN( 3D5H, ch);
				INC( Width, ( ORD( ch)+1)*8);

				SYSTEM.PORTOUT( 3D4H, 5EH);									(* get Height *)
				SYSTEM.PORTIN( 3D5H, ch);
				IF ODD( ORD( ch) DIV 2) THEN Height:= 1024 END;
				SYSTEM.PORTOUT( 3D4H, 7);
				SYSTEM.PORTIN( 3D5H, ch);
				IF ODD( ORD( ch) DIV 2) THEN INC( Height, 256) END;
				IF ODD( ORD( ch) DIV 64) THEN INC( Height, 512) END;
				SYSTEM.PORTOUT( 3D4H, 12H);
				SYSTEM.PORTIN( 3D5H, ch);
				INC( Height, ORD( ch)+1);

				SYSTEM.PORTOUT( 3D4H, 36H);									(* get MemSize *)
				SYSTEM.PORTIN( 3D5H, ch);
				mask:= ASH( ORD( ch), -5);
				IF mask= 0 THEN dmem:= 4096*1024;
				ELSIF mask= 4 THEN dmem:= 2048*1024;
				ELSE dmem:= 1024*1024;
				END;
			END;
		END;
		UBottom := Height - SHORT((dmem-4096) DIV Width) + 1;	(* Space for 4 Sprites reserved *)

		SYSTEM.PORTOUT( 3D4H, 1053H);	(*	10H: enable old MMIO 18H: old & new MMIO	*)
		mask:= -1;
		SYSTEM.PUT(wrtMask, mask);				(* Write mask *)
		SYSTEM.PUT(rdMask, mask);					(* Read mask *)
		base:=0E0000000H;	(* must be mapped with MapAdr0=0E0000000H and MapLen0=00200000H *)
(*		Kernel.NewMap( base, dmem); *)
		IF base< 0 THEN										(* enable lfb *)
			SYSTEM.PORTOUT( 3D4H, 0831H);		(* CR31  bit 3: enhanced mode mapping*)
			IF dmem<=1024*1024 THEN SYSTEM.PORTOUT( 3D4H, 1158H);
			ELSIF dmem<=2024*1024 THEN SYSTEM.PORTOUT( 3D4H, 1258H);
			ELSE SYSTEM.PORTOUT( 3D4H, 1358H);		(* bit 4: enable lfb, bit 0,1: size: 0= 64k, 1=1MB, 2= 2MB, 3= 4MB *)
			END;
			SYSTEM.PORTOUT( 3D4H, 59H);			(* set base adr for lfb *)
			SYSTEM.PORTOUT( 3D5H, CHR( ASH( base, -24) ));
			SYSTEM.PORTOUT( 3D4H, 5AH);
			SYSTEM.PORTOUT( 3D5H, CHR( ASH( base, -16) ));

(*
			SYSTEM.PORTOUT( 3D4H, 33H);			(* disable border *)
			SYSTEM.PORTIN( 3D5H, ch);
			SYSTEM.PORTOUT( 3D5H, SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch)+{5}));
*)

		END;
		SYSTEM.PORTOUT( 3C4H, SYSTEM.VAL( INTEGER, 8009H));		(* disable programmed I/O *)
	END InitS3;

BEGIN
	Left:= 0; ColLeft:= 0; Bottom:= 0;
	Pat := NIL;
	InitS3;
	ResetClip;
	CreatePatterns;
	Unit := 10000
END Display.

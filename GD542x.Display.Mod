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

(*
	Oberon System 3 VESA compatible display driver
	for 256 colors/pixel
*)
(*
	Q&D driver for GD542x.  Based on ET4000 driver.  Bank switch replaced.
	ReplPattern replace missing
*)
	IMPORT Objects, SYSTEM;

	CONST
		BG* = 0; FG* = 15; (*background, foreground*)
		replace* = 0; paint* = 1; invert* = 2; (*operation modes*)
		remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (* ControlMsg id *)
		reduce* = 0; extend* = 1; move* = 2; (*ModifyMsg id*)
		display* = 0; state* = 1; (*ModifyMsg mode*)
		screen* = 0; printer* = 1; (* DisplayMsg device *)
		full* = 0; area* = 1; contents* = 2; (* DisplayMsg id. *)
		get* = 0; set* = 1; reset* = 2; (*SelectMsg id*)
		drop* = 0; integrate* = 1; (*ConsumeMsg id*)
		
		bufLen = 8192;
		winSize = 10000H;
		
		DisplayAdr = 0A0000H;
		
	TYPE
		Pattern* = LONGINT;
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
			F*: Frame;
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
		Unit*: LONGINT;	(* RasterUnit = Unit/36000 mm *)
		Left*: INTEGER;	(* left margin of black-and-white maps *)
		ColLeft*: INTEGER;	(* left margin of color maps *)
		Bottom*: INTEGER;	(* bottom of primary map *)
		UBottom*: INTEGER;	(* bottom of secondary map *)
			
		Width*: INTEGER; (* map width *)
		Height*: INTEGER; (* map hight*)
		
		arrow*, star*, cross*, downArrow*, hook*: Pattern;
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

		Broadcast*: MsgProc;

		Pat: ARRAY 60 OF PatternPtr;
		N: INTEGER;

		buf: ARRAY bufLen OF CHAR;	(*scan line buffer*)

		bits: ARRAY 16 OF SET;
		msk: ARRAY 5 OF SET;
		clipL, clipR, clipT, clipB: INTEGER;	(*clipping*)

		rbnk, wbnk, gran: LONGINT;
		wth, i: INTEGER;
		read, write: INTEGER;
		
	PROCEDURE Switch(win, bank: LONGINT);
	VAR a: ARRAY 5 OF CHAR;
	BEGIN
		SYSTEM.PORTIN(3C4H, a[0]);  SYSTEM.PORTIN(3D4H, a[1]);
		SYSTEM.PORTIN(3B4H, a[2]);  SYSTEM.PORTIN(3CEH, a[3]);
		
		SYSTEM.PORTIN(3CEH, a[4]);
		SYSTEM.PORTOUT(3CEH, SHORT(ASH(gran*bank, 8) + 9+win));
		SYSTEM.PORTOUT(3CEH, a[4]);
		
		SYSTEM.PORTIN(3CEH, a[3]);  SYSTEM.PORTIN(3B4H, a[2]);
		SYSTEM.PORTIN(3D4H, a[1]);  SYSTEM.PORTIN(3C4H, a[0]);

		IF win = read THEN rbnk := bank END;
		IF win = write THEN wbnk := bank END
	END Switch;

	PROCEDURE SwitchAll(bank: LONGINT);
	BEGIN Switch(write, bank);
		IF rbnk # bank THEN Switch(read, bank) END
	END SwitchAll;

	PROCEDURE Map* (X: INTEGER): LONGINT;
	BEGIN RETURN DisplayAdr
	END Map;
	
	PROCEDURE AdjustClip* (X, Y, W, H: INTEGER);
		VAR top, rgt: INTEGER;
	BEGIN top := Y+H; rgt := X+W;
		IF X > clipL THEN clipL := X END;
		IF Y > clipB THEN clipB := Y END;
		IF rgt < clipR THEN clipR := rgt END;
		IF top < clipT THEN clipT := top END;
	END AdjustClip;

	PROCEDURE GetDim* (pat: LONGINT; VAR w, h: INTEGER);
		VAR x: CHAR;
	BEGIN SYSTEM.GET(pat, x); w := ORD(x);
		SYSTEM.GET(pat+1, x); h := ORD(x)
	END GetDim;

	PROCEDURE ResetClip*;
	BEGIN clipL := 0; clipB := UBottom; clipR := Width; clipT := Height
	END ResetClip;

	PROCEDURE SetClip* (x, y, w, h: INTEGER);
	BEGIN clipL := x; clipB := y; clipR := x+w; clipT := y+h
	END SetClip;

	PROCEDURE GetClip* (VAR x, y, w, h: INTEGER);
	BEGIN x := clipL; y := clipB; w := clipR-clipL; h := clipT-clipB
	END GetClip;

	PROCEDURE SetColor* (col, red, green, blue: INTEGER);
	BEGIN	(*PELW/PELD*)
		SYSTEM.PORTOUT(3C8H, CHR(col));
		SYSTEM.PORTOUT(3C9H, CHR((red + 4) DIV 4 -1));
		SYSTEM.PORTOUT(3C9H, CHR((green + 4) DIV 4 -1));
		SYSTEM.PORTOUT(3C9H, CHR((blue + 4) DIV 4 -1))
	END SetColor;

	PROCEDURE GetColor* (col: INTEGER; VAR red, green, blue: INTEGER);
		VAR x: CHAR;
	BEGIN	(*PELR/PELD*)
		SYSTEM.PORTOUT(3C7H, CHR(col));
		SYSTEM.PORTIN(3C9H, x); red := ORD(x) * 4 + ORD(x) DIV 16;
		SYSTEM.PORTIN(3C9H, x); green := ORD(x) * 4 + ORD(x) DIV 16;
		SYSTEM.PORTIN(3C9H, x); blue := ORD(x) * 4 + ORD(x) DIV 16
	END GetColor;

	PROCEDURE Dot* (col, x, y, mode: INTEGER);
		VAR adr: LONGINT; b: CHAR;
	BEGIN
		IF (x < clipL) OR (x >= clipR) OR (y < clipB) OR (y >= clipT) THEN RETURN END;
		adr := LONG(Height-1-y)*wth+x;
		IF adr DIV winSize # wbnk THEN
			Switch(write, adr DIV winSize)	(*adr DIV (4*1024*)
		END;
		IF mode < 2 THEN SYSTEM.PUT(DisplayAdr+adr MOD winSize, CHR(col))
		ELSE
			IF rbnk # wbnk THEN Switch(read, wbnk) END;
			SYSTEM.GET(DisplayAdr+adr MOD winSize, b);
			SYSTEM.PUT(DisplayAdr+adr MOD winSize,
				SYSTEM.VAL(CHAR,
						SYSTEM.VAL(SET, col)/SYSTEM.VAL(SET, b)))
		END
	END Dot;

	PROCEDURE OutBlock(adr, W, H: LONGINT);
		VAR dw, i, H0: LONGINT;
	BEGIN i := 0;
		H0 := SHORT((winSize-adr-W) DIV wth) +1;
		IF H0 > H THEN H0 := H END;
		INC(adr, DisplayAdr);
		WHILE H > 0 DO DEC(H, H0);
			WHILE H0 > 0 DO
				SYSTEM.MOVE(SYSTEM.ADR(buf)+i, adr, W);
				INC(i, W); INC(adr, LONG(wth)); DEC(H0)
			END;
			IF H > 0 THEN DEC(adr, DisplayAdr);
				IF adr < winSize THEN dw := winSize-adr;
					SYSTEM.MOVE(SYSTEM.ADR(buf)+i, DisplayAdr+adr, dw);
					Switch(write, wbnk+1);
					SYSTEM.MOVE(SYSTEM.ADR(buf)+i+dw, DisplayAdr, W-dw);
					DEC(H); INC(adr, wth-winSize); INC(i, W)
				ELSE Switch(write, wbnk+1); DEC(adr, winSize)
				END;
				H0 := SHORT((winSize-adr-W) DIV wth) +1;
				IF H0 > H THEN H0 := H END;
				INC(adr, DisplayAdr)
			END
		END
	END OutBlock;
	
	PROCEDURE InBlock(adr, W, H: LONGINT);
		VAR dw, i, H0: LONGINT;
	BEGIN i := 0;
		H0 := SHORT((winSize-adr-W) DIV wth) +1;
		IF H0 > H THEN H0 := H END;
		INC(adr, DisplayAdr);
		WHILE H > 0 DO DEC(H, H0);
			WHILE H0 > 0 DO
				SYSTEM.MOVE(adr, SYSTEM.ADR(buf)+i, W);
				INC(i, W); INC(adr, LONG(wth)); DEC(H0)
			END;
			IF H > 0 THEN DEC(adr, DisplayAdr);
				IF adr < winSize THEN dw := winSize-adr;
					SYSTEM.MOVE(DisplayAdr+adr, SYSTEM.ADR(buf)+i, dw);
					Switch(read, rbnk+1);
					SYSTEM.MOVE(DisplayAdr, SYSTEM.ADR(buf)+i+dw, W-dw);
					DEC(H); INC(adr, wth-winSize); INC(i, W)
				ELSE Switch(read, rbnk+1); DEC(adr, winSize)
				END;
				H0 := SHORT((winSize-adr-W) DIV wth) +1;
				IF H0 > H THEN H0 := H END;
				INC(adr, DisplayAdr)
			END
		END
	END InBlock;
	
	PROCEDURE CopyBlock* (SX, SY, W, H, DX, DY, mode: INTEGER);
		VAR src, dst, wth0(*, sbk, dbk*): LONGINT;
			top, rgt, dX, dY: INTEGER;
			k, disp, dw: LONGINT;
			H0: INTEGER;
	BEGIN
		rgt := DX + W; top := DY + H; dX := DX; dY := DY;
		IF DX < clipL THEN DX := clipL END;
		IF DY < clipB THEN DY := clipB END;
		IF rgt > clipR THEN rgt := clipR END;
		IF top > clipT THEN top := clipT END;
		W := rgt - DX; H := top - DY;
		IF (W <= 0) OR (H <= 0) THEN RETURN END;
		INC(SX, DX-dX); INC(SY, DY-dY);
		src := LONG(Height-SY-H)*wth+SX;
		dst := LONG(Height-DY-H)*wth+DX;
		IF src = dst THEN RETURN END;
		wth0 := wth;
		IF dst > src THEN wth0 := -wth END;
		IF FALSE THEN
		ELSE
			H0 := bufLen DIV W;
			IF H0 > H THEN H0 := H END;
			IF wth0 < 0 THEN INC(src, LONG(H-H0)*wth); INC(dst, LONG(H-H0)*wth) END;
			WHILE H > H0 DO
				IF src DIV winSize # rbnk THEN Switch(read, src DIV winSize) END;
				InBlock(src MOD winSize, W, H0); INC(src, H0*wth0);
				IF dst DIV winSize # wbnk THEN Switch(write, dst DIV winSize) END;
				OutBlock(dst MOD winSize, W, H0); INC(dst, H0*wth0);
				DEC(H, H0)
			END;
			IF wth0 < 0 THEN INC(src, LONG(H0-H)*wth); INC(dst, LONG(H0-H)*wth) END;
			IF src DIV winSize # rbnk THEN Switch(read, src DIV winSize) END;
			InBlock(src MOD winSize, W, H);
			IF dst DIV winSize # wbnk THEN Switch(write, dst DIV winSize) END;
			OutBlock(dst MOD winSize, W, H)
		END
	END CopyBlock;

	PROCEDURE SetMode* (X: INTEGER; s: SET);
	END SetMode;

	PROCEDURE CopyPattern* (col: INTEGER; pat: LONGINT; X, Y, mode: INTEGER);
		VAR q, b, colmsk, m: SET; c: ARRAY 4 OF CHAR; x, p4: CHAR;
			w, h, pb, w0, h0: INTEGER; adr, adec: LONGINT;
			p8, i: INTEGER;
			ox, oy, pb0: INTEGER;
			ptn: ARRAY 128 OF CHAR;
	BEGIN
		SYSTEM.GET(pat, x); w := ORD(x);
		SYSTEM.GET(pat+1, x); h := ORD(x); INC(pat, 2);
		pb := (w+7) DIV 8;
		ox := 0; oy := 0; w0 := w;
		IF X < clipL THEN ox := clipL-X; X := clipL; DEC(w, ox) END;
		IF Y < clipB THEN oy := clipB-Y; Y := clipB; DEC(h, oy) END;
		IF X+w > clipR THEN w := clipR-X END;
		IF Y+h > clipT THEN h := clipT-Y END;
		IF (w <= 0) OR (h <= 0) THEN RETURN END;
		IF (ox = 0) & (w0 = w) THEN (*INC(Y, oy); DEC(h, oy);*) INC(pat, LONG(oy*pb))
		ELSE	(*create scratch pat*)
			(*DEC(w, ox); DEC(h, oy);*)
			m := {0..w-1}; INC(pat, LONG(oy*pb));
			pb0 := (w+7) DIV 8; h0 := h; i := 0;
			WHILE h0 > 0 DO
				SYSTEM.GET(pat, q);
				SYSTEM.PUT(SYSTEM.ADR(ptn[i]), m*SYSTEM.ROT(q, -ox));
				INC(pat, LONG(pb)); INC(i, pb0); DEC(h0)
			END;
			pat := SYSTEM.ADR(ptn[0]); pb := pb0;
			(*INC(X, ox); INC(Y, oy)*)
		END;
		(*w := rgt - X; h := top - Y;*)
		adr := LONG(Height-Y-h)*wth+X;
		IF (adr DIV winSize # wbnk) OR (rbnk # wbnk) THEN
			SwitchAll(adr DIV winSize)
		END;
		c[0] := CHR(col); c[1] := c[0]; c[2] := c[0]; c[3] := c[0]; 
		colmsk := SYSTEM.VAL(SET, c);
		adr := adr MOD winSize; adec := wth-pb*8;	(*line+pat wid*)
		h0 := SHORT((winSize-adr-w) DIV wth) +1;
		IF h0 > h THEN h0 := h END;
		INC(adr, DisplayAdr); INC(pat, LONG((h-1)*pb)); INC(pb, pb);
		IF mode < 2 THEN
			WHILE h > 0 DO DEC(h, h0);
				WHILE h0 > 0 DO w0 := w;
					WHILE w0 > 0 DO SYSTEM.GET(pat, p4); INC(pat);
						SYSTEM.GET(adr, b); q := bits[ORD(p4) MOD 10H];
						SYSTEM.PUT(adr, b-q + q*colmsk); INC(adr, 4);
						IF w0 > 4 THEN
							SYSTEM.GET(adr, b); q := bits[ORD(p4) DIV 10H];
							SYSTEM.PUT(adr, b-q + q*colmsk)
						END;
						INC(adr, 4); DEC(w0, 8)
					END;
					INC(adr, adec); DEC(h0); DEC(pat, LONG(pb))
				END;
				IF h > 0 THEN DEC(adr, DisplayAdr);	(*adr+w > winSize*)
					IF adr < winSize THEN i := 0; w0 := w;
						WHILE w0 > 0 DO
							IF i = 0 THEN SYSTEM.GET(pat, p4); INC(pat) END;
							IF i IN SYSTEM.VAL(SET, p4) THEN
								SYSTEM.PUT(DisplayAdr+adr, CHR(col))
							END;
							i := (i+1) MOD 8; INC(adr); DEC(w0);
							IF adr = winSize THEN SwitchAll(wbnk+1); adr := 0 END
						END;
						INC(adr, LONG(wth-w)); DEC(h); DEC(pat, LONG(pb))
					ELSE SwitchAll(wbnk+1); DEC(adr, winSize)
					END;
					h0 := SHORT((winSize-adr-w) DIV wth) +1;
					IF h0 > h THEN h0 := h END;
					INC(adr, DisplayAdr)
				END
			END
		ELSE
			WHILE h > 0 DO DEC(h, h0);
				WHILE h0 > 0 DO w0 := w;
					WHILE w0 > 0 DO SYSTEM.GET(pat, p4); INC(pat);
						SYSTEM.GET(adr, b); q := bits[ORD(p4) MOD 10H];
						SYSTEM.PUT(adr, b/(q*colmsk)); INC(adr, 4);
						IF w0 > 4 THEN
							SYSTEM.GET(adr, b); q := bits[ORD(p4) DIV 10H];
							SYSTEM.PUT(adr, b/(q*colmsk))
						END;
						INC(adr, 4); DEC(w0, 8)
					END;
					INC(adr, adec); DEC(h0); DEC(pat, LONG(pb))
				END;
				IF h > 0 THEN DEC(adr, DisplayAdr);	(*adr+w > winSize*)
					IF adr < winSize THEN i := 0; w0 := w;
						WHILE w0 > 0 DO
							IF i = 0 THEN SYSTEM.GET(pat, p4); INC(pat) END;
							IF i IN SYSTEM.VAL(SET, p4) THEN
								SYSTEM.GET(DisplayAdr+adr, x);
								SYSTEM.PUT(DisplayAdr+adr,
									SYSTEM.VAL(CHAR,
											SYSTEM.VAL(SET, col)/SYSTEM.VAL(SET, x)))
							END;
							i := (i+1) MOD 8; INC(adr); DEC(w0);
							IF adr = winSize THEN SwitchAll(wbnk+1); adr := 0 END
						END;
						INC(adr, LONG(wth-w)); DEC(h); DEC(pat, LONG(pb))
					ELSE SwitchAll(wbnk+1); DEC(adr, winSize)
					END;
					h0 := SHORT((winSize-adr-w) DIV wth) +1;
					IF h0 > h THEN h0 := h END;
					INC(adr, DisplayAdr)
				END
			END
		END
	END CopyPattern;

	PROCEDURE ReplC(colmsk: SET; adr, w: LONGINT);
	BEGIN INC(adr, DisplayAdr);
(*
			MOV EAX, adr[EBP]
			MOV EDI, EAX
			MOV ECX, w[EBP]
			MOV EAX, colmsk[EBP]
			SHR ECX, 2
			JZ less4
			REP STOSD
			MOV ECX, w[EBP]
less4	AND ECX, $03
			JZ end
			REP STOSB
end	END
*)
		WHILE w > 3 DO SYSTEM.PUT(adr, colmsk); INC(adr, 4); DEC(w, 4) END;
		WHILE w > 0 DO
			SYSTEM.PUT(adr, SYSTEM.VAL(CHAR, colmsk)); INC(adr); DEC(w)
		END
	END ReplC;

	PROCEDURE ReplCI(colmsk: SET; adr, w: LONGINT);
		VAR b: SET;
	BEGIN INC(adr, DisplayAdr);
		WHILE w > 3 DO
			SYSTEM.GET(adr, b); SYSTEM.PUT(adr, b/colmsk);
			INC(adr, 4); DEC(w, 4)
		END;
		IF w > 0 THEN
			SYSTEM.GET(adr, b); SYSTEM.PUT(adr, b/(colmsk*msk[w]))
		END
	END ReplCI;

	PROCEDURE ReplConst* (col, X, Y, W, H, mode: INTEGER);
		VAR adr, as: LONGINT; colmsk: SET; c: ARRAY 4 OF CHAR;
			H0, top, rgt: INTEGER;
	BEGIN
		top := Y + H; rgt := X + W;
		IF X < clipL THEN X := clipL END;
		IF Y < clipB THEN Y := clipB END;
		IF rgt > clipR THEN rgt := clipR END;
		IF top > clipT THEN top := clipT END;
		W := rgt - X; H := top - Y;
		IF (W <= 0) OR (H <= 0) THEN RETURN END;
		adr := LONG(Height-Y-H)*wth+X;
		IF adr DIV winSize # wbnk THEN
			SwitchAll(adr DIV winSize)
		END;
		adr := adr MOD winSize;
		c[0] := CHR(col); c[1] := c[0]; c[2] := c[0]; c[3] := c[0]; 
		colmsk := SYSTEM.VAL(SET, c);
		H0 := SHORT((winSize-adr-W) DIV wth) +1;
		IF H0 > H THEN H0 := H END;
		IF mode < 2 THEN
			WHILE H > 0 DO DEC(H, H0);
				WHILE H0 > 0 DO
					ReplC(colmsk, adr, W); INC(adr, LONG(wth)); DEC(H0)
				END;
				IF H > 0 THEN
					IF adr < winSize THEN
						ReplC(colmsk, adr, winSize-adr); Switch(write, wbnk+1);
						ReplC(colmsk, 0, W+adr-winSize);
						INC(adr, wth-winSize); DEC(H)
					ELSE Switch(write, wbnk+1); DEC(adr, winSize)
					END;
					H0 := SHORT((winSize-adr-W) DIV wth) +1;
					IF H0 > H THEN H0 := H END
				END
			END
		ELSE
			IF rbnk # wbnk THEN Switch(read, wbnk) END;
			WHILE H > 0 DO DEC(H, H0);
				WHILE H0 > 0 DO
					ReplCI(colmsk, adr, W); INC(adr, LONG(wth)); DEC(H0)
				END;
				IF H > 0 THEN
					IF adr < winSize THEN
						ReplCI(colmsk, adr, winSize-adr); SwitchAll(wbnk+1);
						ReplCI(colmsk, 0, W+adr-winSize);
						INC(adr, wth-winSize); DEC(H)
					ELSE SwitchAll(wbnk+1); DEC(adr, winSize)
					END;
					H0 := SHORT((winSize-adr-W) DIV wth) +1;
					IF H0 > H THEN H0 := H END
				END
			END
		END
	END ReplConst;

	PROCEDURE ReplP(adr, pat, n: LONGINT; lmsk, rmsk, colmsk: SET);
		VAR q, b: SET;
	BEGIN INC(adr, DisplayAdr);
		q := bits[pat MOD 10H]; pat := SYSTEM.ROT(pat, -4);
		SYSTEM.GET(adr, b);
		q := b-lmsk*q+lmsk*q*colmsk;
		WHILE n > 0 DO
			SYSTEM.PUT(adr, q); INC(adr, 4); DEC(n);
			q := bits[pat MOD 10H]; pat := SYSTEM.ROT(pat, -4);
			SYSTEM.GET(adr, b);
			q := b-q+q*colmsk
		END;
		(*SYSTEM.GET(adr, b);*)
		SYSTEM.PUT(adr, b-rmsk+q*rmsk)
	END ReplP;

	PROCEDURE ReplPI(adr, pat, n: LONGINT; lmsk, rmsk, colmsk: SET);
		VAR q, b: SET;
	BEGIN INC(adr, DisplayAdr);
		q := bits[pat MOD 10H]; pat := SYSTEM.ROT(pat, -4);
		SYSTEM.GET(adr, b);
		q := b/(lmsk*q*colmsk);
		WHILE n > 0 DO
			SYSTEM.PUT(adr, q); INC(adr, 4); DEC(n);
			q := bits[pat MOD 10H]; pat := SYSTEM.ROT(pat, -4);
			SYSTEM.GET(adr, b);
			q := b/(q*colmsk)
		END;
		(*SYSTEM.GET(adr, b);*)
		SYSTEM.PUT(adr, b-rmsk+q*rmsk)
	END ReplPI;

	PROCEDURE FillPattern* (col: INTEGER; pat: LONGINT; pX, pY, X, Y, W, H, mode: INTEGER);
		VAR adr, as: LONGINT; c: ARRAY 4 OF CHAR; x: CHAR;
			lmsk, rmsk, colmsk: SET;
			H0, w, h, y0, pinc: INTEGER;
			pbits, p, n, dn: LONGINT;
			top, rgt: INTEGER;
	BEGIN
		top := Y + H; rgt := X + W;
		IF X < clipL THEN X := clipL END;
		IF Y < clipB THEN Y := clipB END;
		IF rgt > clipR THEN rgt := clipR END;
		IF top > clipT THEN top := clipT END;
		W := rgt - X; H := top - Y;
		IF (W <= 0) OR (H <= 0) THEN RETURN END;
		SYSTEM.GET(pat, x); w := ORD(x);
		SYSTEM.GET(pat+1, x); h := ORD(x); INC(pat, 2);
		(*IF (w # 16) OR (w # 32) THEN RETURN END;*)
		pinc := (w+7)DIV 8 *(h-1);
		adr := LONG(Height-Y-H)*wth+X;
		IF (adr DIV winSize # wbnk) OR (wbnk # rbnk) THEN
			SwitchAll(adr DIV winSize)
		END;
		adr := adr MOD winSize DIV 4 * 4;	(*aligned*)
		c[0] := CHR(col); c[1] := c[0]; c[2] := c[0]; c[3] := c[0]; 
		colmsk := SYSTEM.VAL(SET, c);
		lmsk := {0..31}-msk[X MOD 4]; rmsk := msk[(X+W) MOD 4];
		n := (X+W) DIV 4 - X DIV 4;
		(*DEC(X, pX); DEC(Y, pY);*)
		IF w <= 16 THEN pX := pX MOD 16 ELSE pX := pX MOD 32 END;
		y0 := (Y-pY+H-1) MOD h; p := pat + (w+7)DIV 8 *y0;
		H0 := SHORT((winSize-adr-W) DIV wth) +1;
		IF H0 > H THEN H0 := H END;
		IF mode < 2 THEN
			WHILE H > 0 DO DEC(H, H0);
				WHILE H0 > 0 DO
					SYSTEM.GET(p, pbits); DEC(p, 4); DEC(y0);
					IF w <= 16 THEN INC(p, 2); pbits := pbits MOD 10000H+ pbits*10000H END;
					IF y0 < 0 THEN p := pat+pinc; y0 := h-1 END;
					pbits := SYSTEM.ROT(pbits, -(X DIV 4 MOD 8 * 4 -pX));
					ReplP(adr, pbits, n, lmsk, rmsk, colmsk);
					INC(adr, LONG(wth)); DEC(H0)
				END;
				IF H > 0 THEN
					IF adr < winSize THEN
						dn := (winSize-adr) DIV 4;
						SYSTEM.GET(p, pbits); DEC(p, 4); DEC(y0);
						IF w <= 16 THEN INC(p, 2); pbits := pbits MOD 10000H+ pbits*10000H END;
						IF y0 < 0 THEN p := pat+pinc; y0 := h-1 END;
						pbits := SYSTEM.ROT(pbits, -(X DIV 4 MOD 8 * 4 -pX));
						ReplP(adr, pbits, dn, lmsk, {0..31}, colmsk);
						SwitchAll(wbnk+1);
						(*adjust pattern!!*)
						ReplP(0, pbits, n-dn, {0..31}, rmsk, colmsk);
						INC(adr, wth-winSize); DEC(H)
					ELSE SwitchAll(wbnk+1); DEC(adr, winSize)
					END;
					H0 := SHORT((winSize-adr-W) DIV wth) +1;
					IF H0 > H THEN H0 := H END
				END
			END
		ELSE
			WHILE H > 0 DO DEC(H, H0);
				WHILE H0 > 0 DO
					SYSTEM.GET(p, pbits); DEC(p, 4); DEC(y0);
					IF w <= 16 THEN INC(p, 2); pbits := pbits MOD 10000H+ pbits*10000H END;
					IF y0 < 0 THEN p := pat+pinc; y0 := h-1 END;
					pbits := SYSTEM.ROT(pbits, -(X DIV 4 MOD 8 * 4 -pX));
					ReplPI(adr, pbits, n, lmsk, rmsk, colmsk);
					INC(adr, LONG(wth)); DEC(H0)
				END;
				IF H > 0 THEN
					IF adr < winSize THEN
						dn := (winSize-adr) DIV 4;
						SYSTEM.GET(p, pbits); DEC(p, 4); DEC(y0);
						IF w <= 16 THEN INC(p, 2); pbits := pbits MOD 10000H+ pbits*10000H END;
						IF y0 < 0 THEN p := pat+pinc; y0 := h-1 END;
						pbits := SYSTEM.ROT(pbits, -(X DIV 4 MOD 8 * 4 -pX));
						ReplPI(adr, pbits, dn, lmsk, {0..31}, colmsk);
						SwitchAll(wbnk+1);
						(*adjust pattern!!*)
						ReplPI(0, pbits, n-dn, {0..31}, rmsk, colmsk);
						INC(adr, wth-winSize); DEC(H)
					ELSE SwitchAll(wbnk+1); DEC(adr, winSize)
					END;
					H0 := SHORT((winSize-adr-W) DIV wth) +1;
					IF H0 > H THEN H0 := H END
				END
			END
		END
	END FillPattern;

	PROCEDURE ReplPattern* (col: INTEGER; pat: LONGINT; X, Y, W, H, mode: INTEGER);
	BEGIN FillPattern(col, pat, 0, 0, X, Y, W, H, mode)
	END ReplPattern;

	PROCEDURE NewPattern* (width, height: INTEGER; VAR image: ARRAY OF SET): LONGINT;
		VAR len, src, dest: LONGINT; i: INTEGER; p: PatternPtr; inter: SET;
	BEGIN 
		len := (width+7) DIV 8;
		SYSTEM.NEW(p, 4+len*height); p.w := SHORT(width); p.h := SHORT(height);
		src := SYSTEM.ADR(image); dest := SYSTEM.ADR(p.pixmap);
		i := 0;
		WHILE i < height DO SYSTEM.MOVE(src, dest, len); INC(src, 4); INC(dest, len); INC(i) END;
		Pat[N] := p; INC(N);
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
	
	PROCEDURE Depth* (X: INTEGER): INTEGER;
	BEGIN RETURN 8
	END Depth;

(*
	Bitmap* = POINTER TO BitmapDesc;
	BitmapDesc* = RECORD
		width*, height*, depth* : INTEGER;
		wth*, address* : LONGINT;
	END;
*)

	PROCEDURE DisplayBlock* (B: LONGINT; DX, DY, W, H, SX, SY, mode: INTEGER);
		VAR bwth, badr, adr, dw: LONGINT;
			bw, bh, H0: INTEGER;
			top, rgt: INTEGER;
	BEGIN	(*area totally in B*)
		SYSTEM.GET(B+2, bh);
		SYSTEM.GET(B+8, bwth); SYSTEM.GET(B+12, badr);
(*
		rgt := SX + W; top := SY + H;
		IF SX < clipL THEN SX := clipL END;
		IF SY < clipL THEN SY := clipB END;
		IF rgt > clipR THEN rgt := clipR END;
		IF top > clipT THEN top := clipT END;
		W := rgt - SX; H := top - SY;
		IF (W <= 0) OR (H <= 0) THEN RETURN END;
*)
		adr := LONG(Height-1-SY-H)*wth+SX;	(*-1 ???*)
		INC(badr, LONG(DY+H-1)*bwth+DX);
		IF adr DIV winSize # wbnk THEN
			Switch(write, adr DIV winSize)
		END;
		adr := adr MOD winSize;
		H0 := SHORT((winSize-adr-W) DIV wth) +1;
		IF H0 > H THEN H0 := H END;
		INC(adr, DisplayAdr);
		WHILE H > 0 DO DEC(H, H0);
			WHILE H0 > 0 DO
				SYSTEM.MOVE(badr, adr, W); DEC(badr, bwth); INC(adr, LONG(wth));
				DEC(H0)
			END;
			IF H > 0 THEN DEC(adr, DisplayAdr);
				IF adr < winSize THEN
					SYSTEM.MOVE(badr, DisplayAdr+adr, winSize-adr);
					Switch(write, wbnk+1);
					SYSTEM.MOVE(badr+winSize-adr, DisplayAdr, W+adr-winSize);
					DEC(H); INC(adr, wth-winSize); DEC(badr, bwth)
				ELSE Switch(write, wbnk+1); DEC(adr, winSize)
				END;
				H0 := SHORT((winSize-adr-W) DIV wth) +1;
				IF H0 > H THEN H0 := H END;
				INC(adr, DisplayAdr)
			END
		END
	END DisplayBlock;

	PROCEDURE Init;
	BEGIN
		Width := 1024;  Height := 768;  wth := 1024;
		read := 0;  write := 0;  gran := 16;
		clipL := 0; clipB := UBottom; clipR := Width; clipT := Height
	END Init;
	
BEGIN
	Left:= 0; ColLeft:= 0; Bottom:= 0; UBottom:= -256; 
	rbnk := -1; wbnk := -1;
	Init;
	bits[0] := {}; bits[1] := {0..7}; bits[2] := {8..15}; bits[4] := {16..23};
	bits[8] := {24..31};
	bits[3] := {0..15};
	bits[5] := {0..7, 16..23};
	bits[6] := {8..23};
	bits[7] := {0..23};
	i  := 9; WHILE i < 16 DO bits[i] := bits[8]+bits[i-8]; INC(i) END;
	msk[0] := {}; msk[1] := {0..7}; msk[2] := {0..15};
	msk[3] := {0..23}; msk[4] := {0..31};
	N := 0; CreatePatterns;
	Unit := 10000
END Display.

Init="bb0501b8024fcd10"

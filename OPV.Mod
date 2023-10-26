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


MODULE OPV;

(* OPV - parse tree traverser (back end) *)
(* NM, MH, rml, prk 16.05.97  *)


	IMPORT OPS, OPT, OPL, OPO, OPC, OPM, Oberon, SYSTEM;

	
	CONST
		(* intermediate code output *)
		InitOPI = "OPI.Init";
		DumpCode = "OPI.DumpCode";

		(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;
		
		(* item mode *)
		Abs = OPO.Abs;

		(* symbol values and ops *)
		times = 1; slash = 2; div = 3; mod = 4;
		and = 5; plus = 6; minus = 7; or = 8; eql = 9;
		neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		in = 15; is = 16; ash = 17; msk = 18; len = 19;
		conv = 20; abs = 21; cap = 22; odd = 23; not = 33;

		low=34; size=35;


		(*SYSTEM*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;

		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		realSet = {Real, LReal};
		

		(* composite structure forms *)
		Basic = 1; Array = 2; SDynArr = 3; DynArr = 4; Record = 5;	(* rml sda *)
		
		(* Arrays extlev *)
		static = 0; dynamic = 1; sdynamic = 2;


		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse =20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28; Nassembler = 29;	(* iASM *)

		Nret = 32;


		(*function number*)
		assign = 0; newfn = 1; incfn = 13; decfn = 14;
		inclfn = 15; exclfn = 16; copyfn = 18; assertfn = 32;
		passivatefn = 64; activatefn = 65; lockfn = 66; renewfn = 67;
		terminatefn = 68;

		(*SYSTEM function number*)
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;
		stifn = 33; clifn = 34; poutfn = 35; pinfn = 36;						(* New Functions *)

		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3; asmProc = 7;
		activeObj = 5;		shared = 10;

	MaxAdr 	= OPM.MaxLInt;
	MinAdr 	= OPM.MinLInt;
	VarParSize 	= OPM.PointerSize;
	RecVarParSize 	= 8; 	(* push ADR (rec); push TAG (reg) *)
	LProcOffSL 	= 12; 	(* parameter offset with static link *)
	LProcOff 	= 8; 	(* parameter offset without static link *)
	ExtProcOff 	= 8; 	(* parameter offset of external procedures *)

	VAR
		dumpCode*: BOOLEAN; (* set by OP2 *)
		ProcName*: OPS.Name; (* accessed by OPI (read only) *)
		EntryNr*: INTEGER; (* accessed by OPI (read only) *)
		ExitChain: OPC.Label;
		allocTd, assert, findpc: BOOLEAN; 	(* allocTd used only by OM *)
	
	PROCEDURE Init* (opt: SET; bpc: LONGINT);
		CONST ass = 6; fpc = 7;
		VAR res: INTEGER;
	BEGIN
		assert := ass IN opt; findpc := fpc IN opt;
		allocTd := TRUE;			(* allocTd used only by OM *)
		IF findpc THEN OPM.breakpc := bpc ELSE OPM.breakpc := MAX(LONGINT) END;
		IF dumpCode THEN Oberon.Call (InitOPI, Oberon.Par, FALSE, res) END
	END Init;

	PROCEDURE IncAdr(VAR adr: LONGINT; s: LONGINT);
	BEGIN
		IF (s >= 0) & (adr <= MaxAdr - s) OR (s < 0) & (adr >= MinAdr - s) THEN INC(adr, s)
		ELSE OPM.err(242)
		END
	END IncAdr;
	
	PROCEDURE AlignFld(VAR offset: LONGINT; elemsize: LONGINT);
	(* offset is initialized to base type size, 0 if none *)
	BEGIN
		IF elemsize >= 4 THEN IncAdr(offset, (-offset) MOD 4)
		ELSIF elemsize = 2 THEN IncAdr(offset, offset MOD 2)
		END
	END AlignFld;
	
	PROCEDURE AllocFld(VAR offset, this: LONGINT; elemsize: LONGINT);
	BEGIN
		this := offset; IncAdr(offset, elemsize)
	END AllocFld;
	
	PROCEDURE AlignRec(VAR size: LONGINT);
	BEGIN 
		IncAdr(size, (-size) MOD 4)
	END AlignRec;
	
	PROCEDURE AlignPar(VAR elemsize: LONGINT);
	BEGIN 
		IncAdr(elemsize, (-elemsize) MOD 4)
	END AlignPar;
	
	PROCEDURE AllocPar (VAR adr, this: LONGINT; elemsize: LONGINT);
	BEGIN
		IncAdr(adr, elemsize); this := adr
	END AllocPar;

	PROCEDURE AlignVar(VAR adr: LONGINT; elemsize: LONGINT);
	BEGIN
		IF elemsize >= 4 THEN IncAdr(adr, - (adr MOD 4))
		ELSIF elemsize = 2 THEN IncAdr(adr, - (adr MOD 2))
		END
	END AlignVar;
	
	PROCEDURE AllocVar(VAR adr, this: LONGINT; elemsize: LONGINT);
	BEGIN
		IncAdr(adr, -elemsize); this := adr
	END AllocVar;
	
	PROCEDURE AlignBlock(adr: LONGINT; VAR dsize: LONGINT);
	BEGIN 
		IncAdr(adr, - (adr MOD 4)); dsize := -adr
	END AlignBlock;

	PROCEDURE ^ParamAdr(VAR firstPar: OPT.Object; VAR psize, dsize: LONGINT; TProc, Inline, allocDesc: BOOLEAN);

	PROCEDURE ^ProcSize(obj: OPT.Object; firstpass: BOOLEAN);
	
	PROCEDURE ^Traverse(obj: OPT.Object; exported: BOOLEAN);

	PROCEDURE ^VisitTProcs(obj: OPT.Object);

	PROCEDURE RecursionTest (typ: OPT.Struct; mode: LONGINT): BOOLEAN;
		VAR p: OPT.Object;
	BEGIN
		IF typ # NIL THEN
			IF typ.txtpos < 0 THEN RETURN FALSE
			ELSIF (typ.txtpos < mode) OR (typ.txtpos > 5) THEN
				(* traverse btyp *)
				IF ((typ.form = Pointer) & typ.init) OR (typ.form = Comp) THEN
					typ.txtpos := -typ.txtpos;
					IF ~RecursionTest (typ.BaseTyp, mode) THEN RETURN FALSE END;
					IF typ.comp = Record THEN
						p := typ.link;
						WHILE (p # NIL) & (p.mode = Fld) DO 
							IF ~RecursionTest (p.typ, 2) THEN OPM.errpos := p.conval.intval; OPM.err(58); p.typ := OPT.undftyp END;
							p := p.link
						END
					END
				END
			END;
			typ.txtpos := mode
		END; 
		RETURN TRUE
	END RecursionTest;

	PROCEDURE TypSize* (typ: OPT.Struct; allocDesc: BOOLEAN);
		VAR f, c: INTEGER; offset, size, dummy: LONGINT;
			fld: OPT.Object; btyp, ftyp: OPT.Struct; sizeUndef, doAlloc: BOOLEAN;		(* ftyp, OM only *)
			BEGIN
		IF typ = OPT.undftyp THEN OPM.err(58)		(* MH 26.1.94; bug fix RC 17.6.93 *)

		ELSE
			sizeUndef := typ^.size = -1;
			IF ~RecursionTest (typ, 1) THEN OPM.errpos := -typ.txtpos; OPM.err(58); typ.BaseTyp := OPT.undftyp END;
			doAlloc := allocDesc & (typ^.tdadr = OPM.TDAdrUndef) & (typ^.offset = OPM.TDAdrUndef);
			IF sizeUndef OR doAlloc THEN
				IF doAlloc THEN typ^.tdadr := -2 (* avoid cycles *) END ;
				f := typ^.form; c := typ^.comp; btyp := typ^.BaseTyp;
				IF c = Record THEN
					IF btyp = NIL THEN offset := 0;
					ELSE TypSize(btyp, allocDesc); offset := btyp^.size;
					END ;

					IF doAlloc THEN
						IF btyp = NIL THEN typ^.n := 0 ELSE typ^.n := btyp^.n END ;
						IF (*OPM.allowProcesses &*) (typ^.strobj # NIL) & (hasBody IN typ^.strobj^.conval^.setval) THEN VisitTProcs(typ^.strobj) END;
						VisitTProcs(typ^.link)		(* !!! *)
					END ;

					fld := typ^.link;
					WHILE (fld # NIL) (*& (fld^.mode = Fld)*) DO	(* !!! *)
						IF fld^.mode = Fld THEN
							ftyp := fld^.typ; TypSize(ftyp, allocDesc);
							IF sizeUndef THEN size := ftyp^.size;
								WHILE (ftyp^.comp = Array)  & (ftyp.extlev=static)  DO ftyp := ftyp^.BaseTyp END ;
								AlignFld(offset, ftyp^.size);
								AllocFld(offset, fld^.adr, size)
							END
						END;
						fld := fld^.link
					END ;
					IF sizeUndef THEN AlignRec(offset); typ^.size := offset END ;

					IF doAlloc THEN
						OPL.AllocTypDesc (typ); (* typ.tdadr = Entry number *)
						IF (typ^.strobj # NIL) & (typ^.strobj^.conval # NIL) & (hasBody IN typ^.strobj^.conval.setval) THEN ProcSize(typ^.strobj, TRUE) END;
						Traverse(typ^.link, TRUE);
						Traverse(typ^.link, FALSE)	(* !!! *)
					END


				ELSIF c IN {Array, SDynArr} THEN
					TypSize(btyp, allocDesc);
					IF sizeUndef THEN 
						IF typ.extlev=static THEN typ^.size := typ^.n * btyp^.size
						ELSIF typ.extlev=sdynamic THEN typ.size:=4
						ELSE typ^.size:=btyp.size
						END;
						IF btyp.comp IN {Array, SDynArr, DynArr} THEN typ.offset:=btyp.offset+8 ELSE typ.offset:=8 END
					END
				ELSIF f = Pointer THEN
					typ^.size := OPM.PointerSize;
					IF doAlloc THEN
						TypSize(btyp, allocDesc);
						IF (btyp.comp IN {Array, SDynArr, DynArr}) THEN typ.n:=btyp.offset DIV 8 END;
					END

				ELSIF f = ProcTyp THEN
					typ^.size := OPM.ProcSize;

					IF doAlloc THEN 
						TypSize(btyp, TRUE); size := ExtProcOff; ParamAdr(typ^.link, size, dummy, FALSE, FALSE, TRUE);
					END

				ELSE (* (c = DynArr) & doAlloc *)
					TypSize(btyp, allocDesc);

					typ.size:=(typ.n*4)+8; IF typ.lb=MAX(LONGINT) THEN INC(typ.size, 4) END;
					IF btyp.comp IN {Array, SDynArr, DynArr} THEN typ.offset:=btyp.offset+8 ELSE typ.offset:=8 END

				END
			END
		END
	END TypSize;

	PROCEDURE ParamAdr(VAR firstPar: OPT.Object; VAR psize, dsize: LONGINT; TProc, Inline, allocDesc: BOOLEAN);

		VAR par, parOld: OPT.Object; typ: OPT.Struct; adr, s: LONGINT; stop: BOOLEAN;
	BEGIN 

		allocDesc := TRUE;			(* default when not using OM *)

		adr := 0;
		IF TProc THEN par := firstPar.link ELSE par := firstPar END;		(* guarantee that self is always the last parameter *)
		(*par := firstPar;*)
		WHILE par # NIL DO
			typ := par^.typ; TypSize(typ, allocDesc(*TRUE*));

			IF (typ.comp IN {Array, SDynArr, DynArr})&(typ.extlev=dynamic) THEN s:= typ.size
			ELSIF (par.mode=Var) & (typ.comp IN {Array, SDynArr, Record}) THEN s:=typ.size

			ELSIF (par.mode = VarPar) OR ((typ.size > 4) & (typ.form # LReal)) THEN 
					(* ValPar (RECORD), size > 4 are equal to VarPar *)
				IF (typ.comp = Record) & (par.mode = VarPar) THEN s:= RecVarParSize
				ELSE s:= VarParSize
				END
			ELSE s:= typ.size
			END;
			AlignPar(s);
			AllocPar(adr, par^.adr, s); 
			par := par.link
		END;
		IF TProc THEN
			TypSize(firstPar.typ, TRUE);
			IF firstPar.mode = VarPar THEN s:= RecVarParSize ELSE s := firstPar.typ.size END;
			AlignPar(s); AllocPar(adr, firstPar^.adr, s)
		END;
		psize := psize + adr;
		par := firstPar;
		IF ~Inline THEN
			WHILE par # NIL DO
				par^.adr := psize - par^.adr;

				par^.linkadr:= par.adr;

				par := par.link;
			END
		END
	END ParamAdr;


	PROCEDURE VarAdr(var: OPT.Object; VAR dsize: LONGINT);
		VAR adr, s: LONGINT; list: OPT.Object;	(* used by the inline feature *)
	BEGIN 
		adr := -dsize; list := var;
		WHILE var # NIL DO
			IF
 (var.link2 = NIL) 	&	 TRUE 
			THEN
				TypSize(var^.typ, TRUE); s := var^.typ^.size;
				AlignVar(adr, s);
				AllocVar(adr, var^.linkadr, s);

				IF (var.mnolev = 0) & (var.vis IN {external, externalR}) THEN (* exported variable *)
						OPL.NewVarEntry (var.linkadr, var.adr) (* var.adr = entry number *)
				ELSE var.adr:= 0
				END;

			END;
			var := var^.link
		END ;
		AlignBlock(adr, dsize);

		WHILE list # NIL DO			(* process inline parameters *)
			IF list^.link2 # NIL THEN
				list^.linkadr := list^.link2^.adr + dsize
			END;
			list := list^.link
		END

	END VarAdr;

	PROCEDURE ArgSize (par: OPT.Object): LONGINT;
		VAR
			size: LONGINT; comp: SHORTINT; typ: OPT.Struct;
	BEGIN
		size:= 0;
		WHILE par # NIL DO
			typ:= par.typ; comp:= typ.comp;

			IF (comp IN {Array, SDynArr, DynArr}) &(typ.extlev=dynamic) THEN INC (size, typ.size)

			ELSIF par.mode = VarPar THEN
				IF comp = Record THEN INC (size, 8)
				ELSE INC (size, 4)
				END
			ELSIF par.typ.form = LReal THEN INC (size, 8)

			ELSIF comp IN {Array, SDynArr, Record} THEN INC(size, typ.size)

			ELSE INC (size, 4)
			END;
			par:= par.link
		END;
		AlignPar (size);
		RETURN size
	END ArgSize;
	

	PROCEDURE ProcSize0(obj: OPT.Object; firstpass: BOOLEAN);

		VAR psize, oldPos, entryNr: LONGINT;
	BEGIN

		ASSERT (obj.prio # 127);

		oldPos := OPM.errpos;
		IF obj.scope # NIL THEN
				OPM.errpos := obj^.scope^.adr;
		ELSE OPM.errpos := 0
		END;

		IF (((obj^.vis # internal) = firstpass) OR (obj^.mode IN {Typ})) (* & (obj.prio<127) *) THEN

			IF (obj^.mode = LProc) OR (OPM.allowProcesses & (obj^.mode = XProc) & (obj^.mnolev >= 0) & (slNeeded IN obj^.conval^.setval)) THEN
				IF slNeeded IN obj^.conval^.setval THEN psize := LProcOffSL ELSE psize := LProcOff END ;
				obj^.adr := 0
			ELSE psize := ExtProcOff
			END ;

			IF ~(obj^.mode IN {LProc, CProc}) THEN

				OPL.NewEntry (entryNr); INC (obj.adr, entryNr)
			END;
			TypSize(obj^.typ, TRUE);
			ParamAdr(obj^.link, psize, obj^.conval^.intval2, obj^.mode IN {TProc}, obj^.mode = CProc, TRUE); obj^.conval^.intval := psize;
			obj^.linkadr := OPM.LANotAlloc;
		END ;

		IF (~firstpass ) & (obj^.mode # Typ) (* & (obj.prio<127) *) THEN

			IF ~(hasBody IN obj^.conval^.setval) THEN OPM.err(129) END ;
			VarAdr(obj^.scope^.scope, obj^.conval^.intval2);	(* local variables *)
			Traverse(obj^.scope^.right, FALSE)
		END;
		OPM.errpos := oldPos

	END ProcSize0;

	PROCEDURE ProcSize(obj: OPT.Object; firstpass: BOOLEAN);
	BEGIN
		IF obj.prio = 127 THEN
			obj := obj.link2;
			WHILE obj # NIL DO ProcSize0 (obj, firstpass); obj := obj.left END
		ELSE ProcSize0 (obj, firstpass)
		END
	END ProcSize;

	PROCEDURE VisitTProcs(obj: OPT.Object);	(* TProcs of base type already visited *)
		VAR typ, t: OPT.Struct; redef: OPT.Object;
	BEGIN
		IF obj # NIL THEN
			IF obj^.mode # Typ THEN VisitTProcs(obj^.left) END;
			IF obj^.mode IN {TProc, Typ} THEN
				typ := obj^.link^.typ;	(* <- type of self *)
				IF typ^.form = Pointer THEN typ := typ^.BaseTyp END ;
				redef := NIL;
				(* <- Active only, but seems to be safe *)
				IF obj^.mode = Typ THEN	(* Body Method *)
					t := typ.BaseTyp;
					WHILE (t # NIL) & ~(hasBody IN t.strobj.conval.setval) DO t := t.BaseTyp END;
					IF t # NIL THEN redef := t.strobj END
				ELSIF typ^.BaseTyp # NIL THEN	(* Normal Method *)
					IF (typ^.BaseTyp^.strobj = NIL) OR (typ^.BaseTyp^.strobj^.scope = NIL) THEN	(* Oberon-2 *)
						IF typ^.BaseTyp.link # NIL THEN OPT.FindInScope(obj^.name, typ^.BaseTyp.link, redef) END
					ELSE OPT.FindInScope(obj^.name, typ^.BaseTyp^.strobj^.scope, redef);
					END;
					IF (redef # NIL) & (redef.mode # TProc) THEN
						redef := NIL END
				END;
				IF redef # NIL THEN
					obj^.adr := 10000H*(redef^.adr DIV 10000H) (*mthno*) + (obj^.adr MOD 10000H) (*entno*);
					IF ~(isRedef IN obj^.conval^.setval) THEN OPM.err(119) END
				ELSE 
					obj.adr := (obj.adr MOD 10000H) + 10000H*typ.n; INC(typ^.n);
				END;
(*	<- old version, the new OM version is compatible and safer!
				IF redef # NIL THEN
					obj^.adr := 10000H*(redef^.adr DIV 10000H) (*mthno*) + obj^.adr (*entno*);
					IF ~(isRedef IN obj^.conval^.setval) THEN OPM.err(119) END
				ELSE 
					INC(obj^.adr, 10000H * typ^.n); INC(typ^.n)
				END
*)
			END;
			IF obj^.mode # Typ THEN VisitTProcs(obj^.right) END;
		END
	END VisitTProcs;

	PROCEDURE Traverse(obj: OPT.Object; exported: BOOLEAN);
	BEGIN
		IF obj # NIL THEN
			Traverse(obj^.left, exported);
			IF (obj^.mode = Typ) & ((obj^.vis # internal) = exported) THEN TypSize(obj^.typ, TRUE);

			ELSIF obj^.mode IN {LProc, XProc, TProc, CProc, IProc} THEN ProcSize(obj, exported)
			END ;
			Traverse(obj^.right, exported);
		END
	END Traverse;




	PROCEDURE AdrAndSize* (topScope: OPT.Object);
	BEGIN
		OPM.errpos := topScope^.adr;	(* text position of scope used if error *)
		Traverse(topScope^.right, TRUE);	(* first pass only on exported types and procedures  *)
		VarAdr(topScope^.scope, OPO.dsize);	(* global variables *)
		Traverse(topScope^.right, FALSE)	(* second pass *)
	END AdrAndSize;

	
	PROCEDURE^ Expression(n: OPT.Node; VAR z: OPC.Item; selfForUnlock: OPT.Node);

	PROCEDURE Designator (n: OPT.Node; VAR x: OPC.Item);
		VAR
			obj: OPT.Object; 
			y: OPC.Item;
			index: LONGINT;
			varRec: BOOLEAN;
	BEGIN
		CASE n.class OF
			Nvar, Nvarpar:
				obj := n.obj; 
				WHILE obj.scope # NIL DO obj := obj.scope; n.obj := obj END;	(* WITH-bug fix *)
				x.node := n; x.mnolev := obj.mnolev; x.scale := OPO.noScale; x.inx := OPL.none;
				IF obj.mnolev <= 0 THEN (* global or imported variable *)
					x.mode := Abs;
					IF obj.mnolev < 0 THEN (* imported variable *)
						IF obj.adr DIV 10000H = 0 THEN (* no VarConsLink index yet *)
							OPL.NewVarCons (-obj.mnolev, SHORT (obj.adr), index);
							obj.adr := index * 10000H + obj.adr;	(* index entry *)
						END;
						x.adr := 0
					ELSE x.adr := obj.linkadr
					END
				ELSE (* Var, VarPar *)
					x.mode := obj.mode; x.adr := obj.linkadr
				END;
				x.offs := 0;

				IF (obj.typ.comp IN {DynArr, SDynArr, Array}) & (x.mode  IN {Var, VarPar}) THEN
					x.descReg := OPL.RiscFP; x.descOffs := x.adr;
					IF obj.typ.extlev=sdynamic THEN x.mode:=VarPar END
				END

		  | Nfield:
				Designator (n.left, x);
				OPC.Field (x, n.obj.adr)
		  | Nderef:
				Designator (n.left, x); 
				OPC.DeRef (x);

				IF (n.typ.comp IN {Array, SDynArr, DynArr}) THEN
					x.descReg := x.adr; x.descOffs := OPC.PtrToArrOffs;
					x.offs := OPC.PtrToArrOffs + 8 + n.typ.offset;
					(* x.descOffs = length descriptor start - 4 => same descriptor layout as for open array params *)
				END

		  | Nindex:
				Designator (n.left, x); Expression (n.right, y, NIL); OPC.Index (x, y)
		  | Nguard:
				varRec := (n.left.class = Nvarpar) & (n.left.typ.comp = Record);
				Designator (n.left, x);
				OPC.TypeTest (x, n.typ, TRUE, FALSE, varRec)
		  | Neguard:
				varRec := (n.left.class = Nvarpar) & (n.left.typ.comp = Record);
				Designator (n.left, x);
				OPC.TypeTest (x, n.typ, TRUE, TRUE, varRec)
		  | Nproc:
				IF (n.obj.mode IN {XProc, TProc}) & (n.obj.conval.intval = -1) THEN
					n.obj.conval.intval := ArgSize (n.obj.link) + (* 4 *) 8
				END;
				OPC.Procedure (x, n)
		END;
		x.typ := n.typ
	END Designator;


	PROCEDURE ActualPar (n: OPT.Node; fp: OPT.Object; tproc: BOOLEAN; VAR proc, sizeItem: OPC.Item);
		VAR ap: OPC.Item; retval: OPT.Node; offset: LONGINT;
			selfn: OPT.Node; selfo: OPT.Object;
	BEGIN 
		IF (n#NIL) & (n.class=Nret) THEN
			retval:=n;
			OPC.ReserveRetArea(sizeItem, retval); IF sizeItem.mode#Con THEN offset:=4 END;
			WHILE n.class=Nret DO n:=n.link END;
		END;
		IF tproc THEN
			selfn := n; n := n.link; selfo := fp; fp := fp.link
		END;
		WHILE n # NIL DO										(* Calling convention *)
			ASSERT(n.class#Nret);
			IF (n.class=Nderef)&(n.left.class=Ncall) & (n.typ.comp IN {Array, SDynArr, DynArr}) THEN	(* dynamic array to open param *) (* rml da *)
				Expression (n.left, ap, NIL); INC(retval.obj.adr, offset); retval.typ:=n.left.typ; OPC.MoveToStack(retval, ap, fp);
				ap.offs:=OPC.PtrToArrOffs + 8 + n.typ.offset; ap.typ:=n.typ; ap.descOffs:=OPC.PtrToArrOffs; ap.descReg:=ap.adr;
				retval:=retval.link
			ELSE
				Expression (n, ap, NIL)
			END;
			IF (n.class=Ncall) & (n.typ.comp IN {Array, SDynArr}) & (n.typ.extlev=sdynamic) THEN	(* rml sda *)
				INC(retval.obj.adr, offset); OPC.MoveToStack(retval, ap, fp); retval:=retval.link;
			ELSIF (n.class=Ncall) & (n^.typ#NIL) & (n.typ.comp=Array) & (n.typ.extlev=static) & (fp.typ.extlev=dynamic) THEN				
				INC(retval.obj.adr, offset); OPC.MoveToStack(retval, ap, fp); retval:=retval.link;  
			END;
			INC(offset, fp.typ^.size);
			AlignPar(offset);
			OPC.Parameter( ap, fp, n^.class = Nderef, n.class=Ncall);	(* rml cr *)
			n := n.link; fp := fp.link
		END;
		IF tproc THEN
			Expression(selfn, ap, NIL);
			OPC.Parameter( ap, selfo, selfn^.class = Nderef, FALSE)	(* rml da *)
		END
	END ActualPar;


	PROCEDURE^ Statement (n, selfForUnlock: OPT.Node);

	PROCEDURE Expression (n: OPT.Node; VAR z: OPC.Item; selfForUnlock: OPT.Node);
		VAR x, y, tag  , sizeItem  : OPC.Item; f: INTEGER; real: REAL; con: OPT.Const;
		
		PROCEDURE AllocConst (VAR bytes: ARRAY OF SYSTEM.BYTE; len, align: LONGINT);
			VAR con1, con2: OPT.Const;
		BEGIN
			con1 := con;
			IF n.obj = NIL THEN OPL.AllocConst (bytes, len, align, con1.intval)
			ELSE
				con2 := n.obj.conval;
				IF con2.intval = OPM.ConstNotAlloc THEN OPL.AllocConst (bytes, len, align, con2.intval) END;
				con1.intval := con2.intval
			END
		END AllocConst;
		
	BEGIN
		z.node := NIL;
		CASE n.class OF
			Nconst:
				z.typ := n.typ; z.mnolev := 0; z.node := NIL; (* constants have no node *)
				con := n.conval;
				CASE z.typ.form OF
					Byte..LInt, NilTyp, Pointer:
						z.mode := Con; z.adr := con.intval
				  | Set:
						z.mode := Con; z.adr := SYSTEM.VAL (LONGINT, con.setval)
				  | String:
						AllocConst (con.ext^, con.intval2, 4); 
						z.mode := Abs; z.adr := con.intval; z.offs := con.intval2 (* length *); z.inx := OPL.none
				  | Real:
						real := SHORT (con.realval);
						AllocConst (real, 4, 4); 
						z.mode := Abs; z.adr := con.intval; z.inx := OPL.none
				  | LReal:
						AllocConst (con.realval, 8, 4);
						z.mode := Abs; z.adr := con.intval; z.inx := OPL.none
				END
		  | Nupto:
				Expression (n.left, x, selfForUnlock); Expression (n.right, y, selfForUnlock); OPC.SetRange (z, x, y)
		  | Nmop:
				IF (n.subcl # is)  & (n.subcl#size)  THEN Expression (n.left, x, selfForUnlock) END;
				z := x;
				CASE n.subcl OF
					not:
						OPC.Not (z, x)
				  | minus:
						OPC.Neg (z, x)
				  | is:
						Designator (n.left, z);
						IF n.obj.typ.form = Pointer THEN OPC.TypeTest (z, n.obj.typ, FALSE, FALSE, FALSE)
						ELSE OPC.TypeTest (z, n.obj.typ, FALSE, FALSE, TRUE)
						END
				  | conv:
						IF n.typ.form = Set THEN OPC.SetElem (z, x)
						ELSE
							z := x; OPC.Convert (z, n.typ.form)
						END
				  | abs:
						OPC.AbsVal (z, x)
				  | cap:
						OPC.Cap (z, x)
				  | odd:
						OPC.Odd (z, x)
				  | adr, cc, val: (* Module SYSTEM *)
						OPC.SYSmop (z, x, n.subcl, n.typ)

				 | size:
				  	  OPC.SDynArrSize(z, n.left.typ)

				END;
		  | Ndop:
				Expression (n.left, x, selfForUnlock); f := x.typ.form; 
				IF n.subcl = and THEN OPC.CondAnd (x)
				ELSIF n.subcl = or THEN OPC.CondOr (x)
				ELSIF (n.subcl >= eql) & (n.subcl <= geq) THEN OPC.Relation (x)
				END;
				Expression (n.right, y, selfForUnlock);
				CASE n.subcl OF
					times:
						OPC.Mul (z, x, y, f)
				  | slash, div:
						OPC.Div (z, x, y, f)
				  | mod:
						OPC.Mod (z, x, y)
				  | and:
						OPC.And (z, x, y)
 				 | plus:
						OPC.Add (z, x, y, f)
				  | minus:
						OPC.Sub (z, x, y, f)
				  | or:
						OPC.Or (z, x, y)
				  | eql..geq:
						OPC.Cmp (z, x, y, n.subcl)
				  | in:
						OPC.In (z, x, y)
				  | ash:
						OPC.Ash (z, x, y)
				  | msk:
						OPC.Msk (z,  x, y)
				  | len:
						OPC.Len (z, x, y)

				 | low:
				  	  OPC.Low (z, x, y)

				  | (* SYSTEM *) bit, lsh, rot:
						OPC.SYSdop (z, x, y, n.subcl)
				END
		  | Ncall:
				OPC.PushRegs;

				sizeItem.mode:=0;
				ActualPar (n.right, n.obj, (n.left.obj # NIL) & (n.left.obj.mode = TProc), z,  sizeItem);

				IF n.subcl = 2 THEN
					Statement (n.left, selfForUnlock)
				ELSE
					Designator (n.left, z);
					IF n.left.class = Nproc THEN OPC.Call (z, n.left.obj, n)
					ELSE OPC.Call (z, NIL, n)
					END
				END;

				OPC.ClearRetArea(sizeItem);

				OPC.PopResult (n, z); (* pop register and put result into z *)
		ELSE
			Designator (n, z)
		END;
		z.typ := n.typ;
	END Expression;
	
	PROCEDURE IfStat (n, selfForUnlock: OPT.Node; VAR Lfix, Lcfix: OPC.Label; else: BOOLEAN);
		VAR x: OPC.Item;
	BEGIN
		LOOP
			OPM.errpos := n.conval.intval;
			Expression (n.left, x, selfForUnlock);  OPC.Jncc (x, Lcfix, n); Statement (n.right, selfForUnlock);
			IF n.link = NIL THEN EXIT END;
			OPC.Jmp (Lfix, n); OPC.FixLink (Lcfix);
			n := n.link
		END;
		IF else THEN OPC.Jmp (Lfix, n) END
	END IfStat;
	
	PROCEDURE CaseStat (n, selfForUnlock: OPT.Node);
		VAR 
			case, interval: OPT.Node;
			x: OPC.Item;
			L, elseLabel, dummy: OPC.Label;
			low, high, tab: LONGINT;
	BEGIN
		Expression (n.left, x, selfForUnlock); low := n.right.conval.intval; high := n.right.conval.intval2;
		L := OPC.Nil;
		OPC.Case (x, low, high, tab, elseLabel, n);
		case := n.right.left;
		WHILE case # NIL DO
			OPC.DefLabel (dummy); (* label entry: used for common subexpression elimination *)
			interval := case.left;
			WHILE interval # NIL DO
				OPL.CaseJump (OPC.pc, tab, interval.conval.intval - low, interval.conval.intval2 - low);
				interval := interval.link
			END;
			Statement (case.right, selfForUnlock); OPC.Jmp (L, n);
			case := case.link;
		END;
		OPC.FixLink (elseLabel); elseLabel := OPC.pc;
		IF n.right.conval.setval # {} THEN Statement (n.right.right, selfForUnlock) (* ELSE part *)
		ELSE OPC.Trap (OPL.CaseTrap, n)
		END;
		OPC.CaseFixup (tab, elseLabel, high - low + 1);
		OPC.FixLink (L) 
	END CaseStat;


	PROCEDURE MakeVar(VAR var: OPC.Item; obj: OPT.Object);
	BEGIN
		ASSERT(obj^.mode=Var);
		var.typ:=obj^.typ; var.inx:=OPL.none; var.node:=NIL; var.mnolev:=obj^.mnolev;
		var.mode:=Var; var.offs:=0; var.adr:=obj^.linkadr
	END MakeVar;

	PROCEDURE Dim (VAR z, nofelem: OPC.Item; n: OPT.Node; typ: OPT.Struct; nofdim: LONGINT);
		VAR
			nofArrElems: LONGINT; 
			len, cons: OPC.Item;
			btyp: OPT.Struct; cnt: SHORTINT;
	BEGIN
		IF (typ.comp IN {Array, SDynArr}) & (typ.extlev=dynamic) THEN 
			IF typ.comp=Array THEN
				OPC.MakeCon(len, OPT.linttyp, typ.n); OPC.PushLen (len);
				IF nofdim=1 THEN
					OPC.MakeCon(nofelem, OPT.linttyp, typ.n)
				ELSE
					OPC.MakeCon(len, OPT.linttyp, typ.n); OPC.MulDim(nofelem, len)
				END
			ELSE
				MakeVar(len, typ.link); OPC.PushLen (len);
				IF nofdim=1 THEN
					MakeVar(nofelem, typ.link)
				ELSE
					OPC.MulDim(nofelem, len)
				END
			END;
			OPC.PushLowerBound(typ);
			Dim(z, nofelem, n, typ.BaseTyp, nofdim+1);
			OPC.PopLenLow(z);
			INC(z.offs, 4)
		ELSIF (typ.comp IN {Array, SDynArr}) & (typ.extlev IN {static, sdynamic}) THEN
			nofdim:=0;
			WHILE typ.comp IN {Array, SDynArr} DO
				IF typ.comp=Array THEN
					OPC.MakeCon(len, OPT.linttyp, typ.n); OPC.PushLen (len);
					IF nofdim=0 THEN
						OPC.MakeCon(nofelem, OPT.linttyp, typ.n)
					ELSE
						OPC.MakeCon(len, OPT.linttyp, typ.n); OPC.MulDim(nofelem, len)
					END;
				ELSE
					MakeVar(len, typ.link); OPC.PushLen (len);
					IF nofdim=0 THEN nofelem:=len ELSE OPC.MulDim(nofelem, len) END
				END;
				OPC.PushLowerBound(typ);
				INC(nofdim); typ:=typ.BaseTyp
			END;
			OPC.NewArray (z, nofelem, nofdim, typ);
			WHILE nofdim>0 DO OPC.PopLenLow (z); INC (z.offs, 4); DEC(nofdim) END
		ELSE
			Expression (n, len, NIL);
			OPC.PushLen (len);
			IF len.mode # Con THEN OPC.GenDimTrap (len) END;
			IF nofdim = 1 THEN 
				nofelem := len; nofelem.typ := OPT.linttyp
			ELSE OPC.MulDim (nofelem, len)
			END;
			OPC.PushLowerBound(typ);
			IF n.link # NIL THEN Dim (z, nofelem, n.link, typ.BaseTyp, nofdim + 1)
			ELSE
				btyp := typ.BaseTyp; nofArrElems := 1 (*0*) ;	(* <<< mh 30.3.1994 *)
				cnt:=0;
				WHILE btyp.comp IN {Array, SDynArr} DO
					IF btyp.comp=Array THEN
						nofArrElems := nofArrElems * btyp.n;
						OPC.MakeCon(len, OPT.linttyp, btyp.n); OPC.PushLen (len)
					ELSE
						MakeVar(len, btyp.link); OPC.PushLen (len);
						IF nofelem.mode#Con THEN OPC.MulDim(nofelem, len) ELSE nofelem:=len END
					END;
					OPC.PushLowerBound(btyp); btyp := btyp.BaseTyp; INC(cnt); INC(nofdim)
				END;
				IF nofArrElems # 1 (*0*) THEN	(* <<< mh 30.3.1994 *)
					cons.mode := Con; cons.typ := OPT.linttyp; cons.adr := nofArrElems; cons.node := NIL;
					OPC.MulDim (nofelem, cons)
				END;
				OPC.NewArray (z, nofelem, nofdim, btyp);
				INC (z.offs, 4); (* z -> first len element *)
				WHILE cnt>0 DO OPC.PopLenLow (z); INC (z.offs, 4); DEC(cnt) END
			END;
			OPC.PopLenLow (z); (* fill in each dimension size *)
			INC (z.offs, 4)
		END
	END Dim;


	PROCEDURE Statement (n, selfForUnlock: OPT.Node);
		VAR 
			x, y, z, times  , sizeItem  : OPC.Item; t: OPT.Struct; p: OPT.Node;
			L, Lc, prevExitChain: OPC.Label;
			proc, par: OPT.Object;
			name: ARRAY 64 OF CHAR;
			i, j: LONGINT;
			ch: CHAR;
			res: INTEGER;
	BEGIN 
		WHILE ~OPO.CodeErr & (n # NIL) DO 
			OPC.NewStat (n.conval.intval); 
			CASE n.class OF
				Nenter:
					IF n.obj = NIL THEN (* enter module *)
						OPC.pc := 0; OPC.RiscCodeErr := FALSE;
						OPC.Enter (NIL, 0, NIL);
						Statement (n.right, NIL);
						OPC.Exit (NIL);
						IF dumpCode THEN
							ProcName := "Body"; EntryNr := -1;
							Oberon.Call (DumpCode, Oberon.Par, FALSE, res)
						END;
						IF ~OPC.RiscCodeErr THEN
							OPL.GenCode (OPC.pc);
							OPL.OutRefPoint (NIL); OPL.OutRefName ("$$"); OPL.OutRefs (OPT.topScope)
						END;
						INC (OPC.level); Statement (n.left, NIL); DEC (OPC.level)
					ELSE (* procedure *)
						proc := n.obj; par := proc.link;
						INC (OPC.level); Statement (n.left, NIL); DEC (OPC.level);
						OPC.pc := 0; OPC.RiscCodeErr := FALSE;
						IF hasBody IN proc.conval.setval THEN
							OPC.Enter (proc, proc.conval.intval2, n);

							IF proc#NIL THEN	(* rml sda *)
								IF proc.code#NIL THEN Statement(proc.code, NIL) END;
								OPC.AllocSDynArr(proc)
							END;

							Statement (n.right, NIL);
							IF (proc.typ # OPT.notyp) & ~(asmProc IN proc.conval.setval) & (proc.mode # Typ) THEN OPC.Trap (OPL.FuncTrap, n)
							ELSE OPC.Exit (proc)
							END;
							OPL.OutRefPoint (proc);
							IF proc.mode = TProc THEN
								t := proc.link.typ;
								IF (t.comp = Record) OR (t.BaseTyp.strobj = NIL) THEN par := t.strobj ELSE par := t.BaseTyp.strobj END;	(* <- can be POINTER or RECORD *)
								i := 0;
								WHILE par.name[i] # 0X DO name[i] := par.name[i]; INC(i) END;
								name[i] := "."; INC(i);
								j := 0;
								WHILE proc.name[j] # 0X DO name[i] := proc.name[j]; INC(i); INC(j) END;
								name[i] := 0X
							ELSIF proc.mode = Typ THEN			(* Type body *)
								i := 0;
								WHILE proc.name[i] # 0X DO name[i] := proc.name[i]; INC(i) END;
								name[i] := "."; name[i+1] := "$"; name[i+2] := "$"; name[i+3] := 0X
							ELSE COPY (proc.name, name)
							END;
							OPL.OutRefName (name); OPL.OutRefs (proc.scope.right);
							IF dumpCode THEN
								ProcName := proc.name; 
								IF proc.vis = external THEN EntryNr := SHORT (proc.adr MOD 10000H)
								ELSE EntryNr := -1
								END;
								Oberon.Call (DumpCode, Oberon.Par, FALSE, res)
							END;
							IF ~OPC.RiscCodeErr THEN OPL.GenCode (OPC.pc) END
						END
					END
			  | Ninittd: (* done by the loader *)
			  | Nassign:
			  	  IF (n.subcl = stifn) OR (n.subcl = clifn) THEN					(* New Functions *)
			  	  	OPC.SYSinterrupt(n.subcl=clifn)
			  	  ELSE
						IF (n.subcl # lockfn) THEN
							Expression (n.left, z, selfForUnlock)
						END;
						IF (n.subcl # newfn) & (n.subcl # renewfn) & (n.subcl # activatefn) & (n.subcl # terminatefn) THEN
							Expression (n.right, x, selfForUnlock)
						END; 
						IF n.subcl = movefn (* SYSTEM.Move *) THEN
							Expression (n.right.link, times, selfForUnlock); OPC.SYSmove (z, x, times)
						ELSE
							CASE n.subcl OF
								assign: OPC.Assign (z, x)
							  | incfn, decfn: OPC.IncDec (z, x, n.subcl = incfn)
							  | inclfn, exclfn: OPC.Include (z, x, n.subcl = inclfn)
						 	 | getfn, putfn: OPC.SYSgetput (z, x, n.subcl = getfn)
						  	| getrfn, putrfn: OPC.SYSgetputReg (z, x, n.subcl = getrfn)
							  | pinfn, poutfn: OPC.SYSportio (z, x, n.subcl = pinfn)					(* New Functions *)
							  | passivatefn: Expression(n.right.link, y, selfForUnlock); OPC.Passivate(z, x, y)
							  | activatefn: OPC.Activate(z)
(*
							  | terminatefn: OPC.Terminate(z)
*)
							  | lockfn: Expression (n.right.link, z, NIL); OPC.Lock(x, z); Statement(n.left, n.right);
							  				Expression (n.right, x, NIL); Expression (n.right.link, z, NIL); OPC.Unlock(x, z);
						  	| copyfn: OPC.Copy (z, x)
						  	| sysnewfn: OPC.NewSys (z, x)
						  	| newfn:
									t := n.left.typ.BaseTyp;

									IF (t.comp IN {Array, SDynArr, DynArr}) THEN (* pointer to array *)

										Dim (z, x, n.right, z.typ.BaseTyp, 1)
									ELSE 
										OPC.NewRec (z, z.typ.BaseTyp);
										IF (t.strobj # NIL) & (t.strobj.conval # NIL) THEN

											IF n.left.link # NIL THEN	(* object parametrisation *)
												n.left.link.conval := n.conval;
												Statement(n.left.link, selfForUnlock)
											END;

											p := n.right;
											WHILE p # NIL DO
												Expression(n.left, z, selfForUnlock); Expression(p, x, selfForUnlock);
												OPC.CallRecBody(z, x, z.typ.BaseTyp);
												p := p.link
											END

										END
									END

							END (* CASE *)
						END
					END
			  | Ncall:
					OPC.PushRegs;

					sizeItem.mode:=0;
					ActualPar (n.right, n.obj, (n.left.obj # NIL) & (n.left.obj.mode = TProc), x, sizeItem);

					IF n.subcl = 2 THEN
						Statement (n.left, selfForUnlock)
					ELSE
						Designator (n.left, x);
						IF n.left.class = Nproc THEN OPC.Call (x, n.left.obj, n)
						ELSE OPC.Call (x, NIL, n)
						END
					END;

					OPC.ClearRetArea(sizeItem);

					OPC.PopResult (NIL, x) (* only pop register *)
			  | Nifelse:
					IF (n.subcl # assertfn) OR assert THEN
						L := OPC.Nil; Lc := OPC.Nil;
						IfStat (n.left, selfForUnlock, L, Lc, n.right # NIL); (* L label for jump to END of if statment, Lc for the ELSE statement *)
						OPC.FixLink (Lc);
						IF n.right # NIL THEN Statement (n.right, selfForUnlock) END;
						OPC.FixLink (L)
					END
			  | Ncase:
					CaseStat (n, selfForUnlock)
			  | Nwhile:
					L := OPC.Nil; OPC.Jmp (L, n);
					OPC.DefLabel (Lc); Statement (n.right, selfForUnlock);
					OPC.FixLink (L); Expression (n.left, x, selfForUnlock);
					OPC.Jcc (x, Lc, n)
			  | Nrepeat:
					OPC.DefLabel (L); Statement (n.left, selfForUnlock);
					Expression (n.right, x, selfForUnlock);
					OPC.Jncc (x, L, n)
			  | Nloop:
					prevExitChain := ExitChain; ExitChain := OPC.Nil;
					OPC.DefLabel (L); Statement (n.left, selfForUnlock); OPC.Jmp (L, n);
					OPC.FixLink (ExitChain); ExitChain := prevExitChain
			  | Nexit:
					OPC.Jmp (ExitChain, n)
			  | Nreturn:
					IF n.left # NIL THEN (* function *)
						Expression (n.left, x, NIL);

						OPC.Return (x, n.obj.typ)

					END;
					IF selfForUnlock # NIL THEN
						OPC.PushRegs;
						Expression(selfForUnlock, x, NIL);
						Expression (selfForUnlock.link, z, NIL);
						OPC.Unlock(x, z);
						OPC.PopResult(NIL, x);
					END;
					OPC.Exit (n.obj)
			  | Nwith:
					L := OPC.Nil; Lc := OPC.Nil;
					IfStat (n.left, selfForUnlock, L, Lc, TRUE); (* L label for jump to END of if statement, Lc for the ELSE statement *)
					OPC.FixLink (Lc);
					IF n.subcl = 1 (*  # NIL *) THEN Statement (n.right, selfForUnlock)
					ELSE OPC.Trap (OPL.WithTrap, n)
					END;
					OPC.FixLink (L)
			  | Ntrap:
					OPC.Trap (n.right.conval.intval, n)
			  | Nassembler:
			  	 OPC.GenAsm(n)
			END;
			n := n.link
		END; 
	END Statement;
	
	PROCEDURE Module* (prog: OPT.Node);
	BEGIN
		Statement (prog, NIL);
		IF findpc & OPM.noerr THEN OPM.err (254) END
	END Module;

BEGIN


END OPV.


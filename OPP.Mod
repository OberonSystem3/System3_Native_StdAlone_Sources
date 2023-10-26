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


MODULE OPP;

(* Oberon Portable Parser (front end) *)
(* NW, RC, JM, rml, pjm, prk 16.05.97 *)


	IMPORT OPT, OPS, OPM, OPB, ASM;

		
	CONST
		(* numtyp values *)
		char = 1; integer = 2; real = 3; longreal = 4;

		(* symbol values *)
		null = 0; times = 1; slash = 2; div = 3; mod = 4;
		and = 5; plus = 6; minus = 7; or = 8; eql = 9;
		neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		in = 15; is = 16; arrow = 17; period = 18; comma = 19;
		colon = 20; upto = 21; rparen = 22; rbrak = 23; rbrace = 24;
		of = 25; then = 26; do = 27; to = 28; by = 29;
		lparen = 30; lbrak = 31; lbrace = 32; not = 33; becomes = 34;
		number = 35; nil = 36; true = 37; false = 38; string = 39;
		ident = 40; semicolon = 41; bar = 42; end = 43; else = 44;
		elsif = 45; until = 46; if = 47; case = 48; while = 49;
		repeat = 50; for = 51; loop = 52; with = 53; exit = 54;
		return = 55; array = 56; record = 57; pointer = 58; begin = 59;
		const = 60; type = 61; var = 62; procedure = 63; import = 64;
		module = 65; code = 66; eof = 67;
		pow = 68; 

		(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;

		(* Structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		intSet = {SInt..LInt};
		
		(* composite structure forms *)
		Basic = 1; Array = 2; SDynArr = 3; DynArr = 4; Record = 5;
		
		(* Arrays extlev *)
		static = 0; dynamic = 1; sdynamic = 2; open = 3;

		(*function number*)
		haltfn = 0; newfn = 1; incfn = 13; sysnewfn = 30;
		passivatefn = 64;

		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse = 20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28;
		Nassembler = 29; Ncode = 30; (* Ncode isn't a duplicate of Nret, it's used only with Nassembler *)
		Nret = 32;

		(* node subclasses *)
		super = 1;
		
		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3; locked =6; asmProc = 7; operatorFlag = 8;
		
		(* record flags (flags) *)
		passiveObj = 4; activeObj = 5; safe = 8;	timed = 9; shared = 10;
		needPointer = 11;
		
		(* process defaults *)
		DefaultProcessPrio = 0; DefaultProcessTyp = 0;

		(* the hidden parameter for methods *)
		HiddenSelf = "@SELF";
	
	TYPE
		CaseTable = ARRAY OPM.MaxCases OF
			RECORD
				low, high: LONGINT
			END ;

	CONST
		FTarget = 1; FExpr = 2; FAssign = 3; FCall = 4; FCond = 5; 
		FParam = 6; FPassExpr = 7; FPassHint = 8; FReturn = 9;
		
	TYPE
		FixPtr = POINTER TO FixDesc;
		FixDesc = RECORD
			mode: LONGINT; nofFwd: INTEGER; scope: OPT.Object; node: OPT.Node; stream: OPS.TokenStream; next: FixPtr
		END;
		
	VAR
		SignOnMessage*: ARRAY 80 OF CHAR;
		sym, level: SHORTINT;
		LoopLevel: INTEGER;
		TDinit, lastTDinit: OPT.Node;
		nofFwdPtr: INTEGER;
		FwdPtr: ARRAY 64 OF OPT.Struct;
		CondNodes: OPT.Node;
		CondCount: SHORTINT;
		UsesGlobals, ObjLocal: BOOLEAN;
		UndefFlag, FixPhase: BOOLEAN;
		UndefObj: OPT.Object;
		
		nofTypeFix: LONGINT;
		TypeFix: ARRAY 64 OF RECORD pos: LONGINT; obj: OPT.Object; name: OPS.Name END;
		FixList, FixLast: FixPtr;
		ExtObj: OPT.Object;
		RecInit, lastRecInit: OPT.Node;
		Oberon2: BOOLEAN;
		ParameterMode: BOOLEAN;
		ActualOperator: OPT.Object;
		suppressOX: BOOLEAN;

	PROCEDURE^ Type(VAR typ, banned: OPT.Struct);
	PROCEDURE^ Expression(VAR x: OPT.Node);

	PROCEDURE^ Block(VAR procdec, statseq: OPT.Node);

	PROCEDURE err(n: INTEGER);
	BEGIN OPM.err(n)
	END err;

	PROCEDURE CheckSym(s: INTEGER);
	BEGIN
		IF sym = s THEN OPS.Get(sym) ELSE OPM.err(s) END
	END CheckSym;

	PROCEDURE IsModuleScope ():BOOLEAN;
	BEGIN
		RETURN OPT.topScope^.link^.mode = Mod
	END IsModuleScope;
	
	PROCEDURE IsObjectScope ():BOOLEAN;
	BEGIN
		RETURN OPT.topScope^.link^.mode = Typ
	END IsObjectScope;

	PROCEDURE IsRecordScope(): BOOLEAN;
		VAR owner: OPT.Object;
	BEGIN	owner:=OPT.topScope.link;
		RETURN (owner.mode=Typ) & (owner.typ#NIL) & (owner.typ.comp=Record)
	END IsRecordScope;

	PROCEDURE IsScopeOf (mode: INTEGER):BOOLEAN;
	BEGIN
		RETURN OPT.topScope^.link^.mode = mode
	END IsScopeOf;
	
	PROCEDURE IsProcProtectable (): BOOLEAN;
	BEGIN
		RETURN ((OPT.topScope.link.mode IN {Typ, Mod}) & (passiveObj IN OPT.topScope.link.conval.setval)) OR	(* Body of Mod/Obj *)
			((OPT.topScope.left # NIL) & (OPT.topScope.left.link.mode IN {Typ, Mod}) & (passiveObj IN OPT.topScope.left.link.conval.setval))
	END IsProcProtectable;
	
	PROCEDURE SetFlags (obj: OPT.Object; flag: SET);
	BEGIN
		obj^.conval^.setval := obj^.conval^.setval + flag
	END SetFlags;
	
	PROCEDURE GetFlags (obj: OPT.Object):SET;
	BEGIN
		RETURN obj^.conval^.setval
	END GetFlags;
	
	PROCEDURE DumpScope(o: OPT.Object);
	BEGIN
		IF o # NIL THEN
			DumpScope(o.left);
			OPM.LogWLn; OPM.LogWStr(o.name); OPM.LogWNum (o.mode, 4);
			DumpScope(o.right);
		END
	END DumpScope;
	
	PROCEDURE GetSelf():OPT.Object;
		VAR name: OPS.Name; self: OPT.Object;
	BEGIN
		name := OPS.name; OPS.name := HiddenSelf; OPT.Find(self); OPS.name := name;
		RETURN self
	END GetSelf;

	PROCEDURE InsertTypeFix (name: OPS.Name; obj: OPT.Object);
	BEGIN
		IF nofTypeFix < LEN (TypeFix) THEN
			TypeFix [nofTypeFix].pos := OPM.errpos; TypeFix [nofTypeFix].obj := obj;
			COPY (name, TypeFix [nofTypeFix].name); INC (nofTypeFix)
		ELSE err (260)
		END
	END InsertTypeFix;
	
	PROCEDURE InsertFix (mode: LONGINT; stream: OPS.TokenStream; node: OPT.Node);
		VAR fix: FixPtr;
	BEGIN

		NEW (fix);
		fix.mode := mode; fix.stream := stream; fix.scope := OPT.topScope; fix.node := node;
		fix.nofFwd := nofFwdPtr;	fix.next := NIL;
		IF FixLast = NIL THEN FixList := fix	ELSE FixLast.next := fix	END;
		FixLast := fix;
		node.link := NIL
	END InsertFix;
	
	PROCEDURE IsOperator(VAR sym: SHORTINT): BOOLEAN;
	BEGIN
		RETURN ((times<=sym) & (sym<=arrow)) OR (sym=not) OR (sym=becomes) OR (sym=pow)
	END IsOperator;
	
	PROCEDURE qualident(VAR id: OPT.Object);
		VAR obj, fld, self: OPT.Object; lev: SHORTINT; m: BOOLEAN;
	BEGIN (*sym = ident*)
		OPT.Find(obj);
		IF (obj # NIL) & ((obj.mode = Fld) OR (obj.mode = TProc)) THEN obj := GetSelf()
		ELSE OPS.Get(sym)
		END;
		IF (sym = period) & (obj # NIL) & (obj^.mode = Mod) THEN
			m := TRUE;
			OPS.Get(sym);
			IF sym = ident THEN
				OPT.FindImport(obj, obj); OPS.Get(sym)
			ELSIF IsOperator(sym) THEN	(* -> semantical test of operator name already done in compilation *)
				OPT.FindImport(obj, obj); IF obj=NIL THEN err(100) END	(* no operators found *)
			ELSE err(ident); obj := NIL
			END
		ELSE m := FALSE
		END ;
		IF obj = NIL THEN
			IF FixPhase OR m THEN
				err(0);
				obj := OPT.NewObj(); obj^.mode := Var; obj^.typ := OPT.undftyp; obj^.adr := 0
			ELSE UndefFlag := TRUE; obj := UndefObj
			END
		ELSE lev := obj^.mnolev;
			IF (obj^.mode IN {Var, VarPar}) & (lev # level) THEN
				obj^.leaf := FALSE;
				IF lev > 0 THEN OPB.StaticLink(level-lev) END
			END
		END ;
		id := obj
	END qualident;
	
	PROCEDURE ConstExpression(VAR x: OPT.Node);
	BEGIN Expression(x);
		IF x^.class # Nconst THEN
			err(50); x := OPB.NewIntConst(1) 
		END
	END ConstExpression;

	PROCEDURE CheckMark(VAR vis: SHORTINT; rdonlyAllowed: BOOLEAN);
	BEGIN OPS.Get(sym);
		IF (sym = times) OR (sym = minus) THEN
			IF level > 0 THEN err(47) END ;
			IF sym = times THEN vis := external
				ELSIF rdonlyAllowed & Oberon2 THEN vis := externalR 
				ELSE err(47) 
				END ;
			OPS.Get(sym)
		ELSE vis := internal
		END
	END CheckMark;
	
	PROCEDURE CheckSysFlag(VAR sysflag: SHORTINT; default: SHORTINT);
		VAR x: OPT.Node; sf: LONGINT;
	BEGIN
		IF sym = lbrak THEN OPS.Get(sym); ConstExpression(x);
			IF x^.typ^.form IN intSet THEN sf := x^.conval^.intval;
				IF (sf < 0) OR (sf > OPM.MaxSysFlag) THEN err(220); sf := 0 END
			ELSE err(51); sf := 0
			END ;
			sysflag := SHORT(SHORT(sf)); CheckSym(rbrak)
(*

*)
		ELSE sysflag := default
		END
	END CheckSysFlag;

	PROCEDURE BodyMode (VAR flag: SET);
		VAR x: OPT.Node;

	BEGIN
		LOOP
			IF sym = ident THEN

				IF OPS.name = "PARALLEL" THEN
					IF ~IsObjectScope() & ~IsModuleScope() THEN err(200) END;
					INCL (flag, activeObj);

					OPS.Get(sym);
					IF sym = lparen THEN
						ConstExpression(x);
						IF x^.typ^.form IN {SInt} THEN OPT.topScope^.link^.prio := SHORT(SHORT(x^.conval^.intval))
						ELSE err(50)	(* expression must be constant *)
						END
					ELSE
						x := OPB.NewIntConst(0)
					END
				ELSIF OPS.name = "SAFE" THEN
					INCL (flag, safe); OPS.Get(sym)
				ELSIF OPS.name = "TIMESLICED" THEN
					INCL (flag, timed); OPS.Get(sym)
				ELSIF OPS.name = "EXCLUSIVE" THEN
					OPS.Get (sym);

					IF ~IsProcProtectable() THEN err (136) ELSE INCL (flag, locked) END;

				ELSIF OPS.name = "SHARED" THEN

					IF ~IsProcProtectable() THEN err (136) ELSE INCL (flag, shared); INCL (flag, locked) END;

					OPS.Get(sym)
				ELSE err(0); OPS.Get(sym)
				END
			ELSIF sym # rbrace THEN err(0); OPS.Get(sym)
			END;
			IF sym = rbrace THEN EXIT END;
			CheckSym(comma);
		END;
		CheckSym(rbrace)
	END BodyMode;

	PROCEDURE ^ ProcedureDeclaration(VAR x: OPT.Node);
	
	PROCEDURE RecordType(VAR procdec: OPT.Node; VAR typ, banned: OPT.Struct; VAR owner: OPT.Object);
		VAR base, scope, link: OPT.Object;  btyp: OPT.Struct;
			sysflag: SHORTINT;
			x: OPT.Node; c, i: LONGINT;
			statseq: OPT.Node; lev: SHORTINT; name: OPS.Name;
	BEGIN typ := OPT.NewStr(Comp, Record); typ^.BaseTyp := NIL;
		IF owner = NIL THEN
			owner := OPT.NewObj(); owner.mode := Typ; owner.name := ""; owner.vis := internal; owner.typ := typ
		ELSE
			(* fix the forward references, because the fields can be accessed through a pointer !! *)
			i := nofFwdPtr;
			WHILE i > 0 DO DEC (i);
				IF FwdPtr[i]^.link^.name = owner^.name THEN FwdPtr[i]^.BaseTyp := typ; FwdPtr[i]^.link^.name := "";
					IF typ.ptr = NIL THEN typ.ptr := FwdPtr[i] END
				END
			END
		END;
(*	
		WHILE i > 0 DO DEC (i);
			IF FwdPtr[i]^.link^.name = owner^.name THEN FwdPtr[i]^.BaseTyp := typ; (* FwdPtr[i]^.link^.name := "" *) (* used in the body *)
			END
		END;
*)
		owner^.conval := OPT.NewConst(); typ.strobj := owner;
		CheckSysFlag(sysflag, -1);
		IF sym = lparen THEN
			OPS.Get(sym); (*record extension*)
			IF sym = ident THEN
				qualident(base);
				IF (base^.mode = Typ) & ((base^.typ^.comp = Record) OR
						((base^.typ^.form = Pointer) & (base^.typ^.BaseTyp^.comp = Record))) THEN
					IF base^.typ = banned THEN err(58)
					ELSE 
						IF base^.typ^.form = Pointer THEN base := base^.typ^.BaseTyp^.strobj END;
						IF passiveObj IN GetFlags(base^.typ^.strobj) THEN SetFlags(owner, {passiveObj}) END;

						typ^.BaseTyp := base^.typ; typ^.extlev := base^.typ^.extlev + 1; typ^.sysflag := base^.typ^.sysflag;
						typ^.strobj^.link2 := base^.link2;	(* inherit initialiser *)
					END
				ELSIF base = UndefObj THEN
					UndefFlag := FALSE;
					IF sym = period THEN
						OPT.FindInScope (OPS.name, ExtObj, base);
						OPS.Get (sym);
						IF (base # NIL) & (base.mode = Mod) THEN
							OPT.FindImport (base, base)
						END;
						CheckSym (ident);
						IF base = NIL THEN err (0); typ.BaseTyp := NIL
						ELSIF base.mode = Typ THEN
							IF base^.typ # banned THEN typ.BaseTyp := base^.typ ELSE err(58); typ.BaseTyp := NIL END
						ELSE err (52); typ.BaseTyp := NIL
						END
					ELSE typ.BaseTyp := NIL; InsertTypeFix (OPS.name, owner)
					END
				ELSE err(52)
				END
			ELSE err(ident)
			END ;
			CheckSym(rparen)
		END;
		IF sysflag >= 0 THEN typ^.sysflag := sysflag END ;
		OPT.OpenScope(0, owner);
		scope := OPT.topScope^.left;
		IF typ^.BaseTyp # NIL THEN SetFlags(owner, {isRedef}); OPT.topScope^.left := typ.BaseTyp.strobj^.scope		(* upper scope = scope of BaseType *)
		ELSIF base = UndefObj THEN	OPT.topScope^.left := NIL	(* base scope is undefined *)
		ELSE
			WHILE (OPT.topScope.left.link # NIL) & (OPT.topScope.left.link.mode = Typ) DO 
				OPT.topScope.left := OPT.topScope.left.left
			END	(* this is a distinct record, not an extension *)
		END;
		lev := level; level := 0;
	(* search a pointer to this type *)
		c := OPM.errpos;
		IF sym = semicolon THEN OPS.Get(sym) END;
		Block(procdec, statseq);
		link:=typ.link; typ.init:=FALSE;
		WHILE (link#NIL)& (~typ.init) & (link.mode = Fld) DO typ.init:=link.typ.init; link:=link.link END;
		btyp:=typ.BaseTyp;
		WHILE ~typ.init & (btyp#NIL) DO typ.init:=btyp.init; btyp:=btyp.BaseTyp END;
		IF typ^.link = NIL THEN typ^.link := OPT.topScope^.right END;
		IF (procdec # NIL) OR (statseq # NIL) THEN
			OPB.Enter(CondNodes, statseq, owner); CondNodes^.link := procdec; procdec := CondNodes;
			procdec^.conval := OPT.NewConst(); procdec^.conval^.intval := c;
			IF statseq # NIL THEN SetFlags(owner, {hasBody}) END
		END;
		level := lev; OPT.CloseScope;
		OPT.topScope := scope								(* restore normal scope *)
	END RecordType;

	PROCEDURE OwnScope(VAR obj: OPT.Object);
	BEGIN
		IF ~(obj.mode IN {Con, Typ, SProc}) THEN
			IF IsRecordScope()
			OR ((obj.mnolev=OPT.topScope.mnolev)&(obj.link2=NIL)&(obj.myscope=OPT.topScope))  THEN err(90) END;
		END
	END OwnScope;
	
	PROCEDURE PtrToArr(VAR typ: OPT.Struct);
		VAR ptyp: OPT.Struct;
	BEGIN
		ptyp:=OPT.NewStr(Pointer, Basic); CheckSysFlag(ptyp^.sysflag, 0);
		ptyp^.BaseTyp:=typ; ptyp.init:=TRUE;
		IF ParameterMode & (typ.strobj=NIL) THEN ptyp.extlev:=open END;
		typ:=ptyp
	END PtrToArr;

	PROCEDURE ArrayType(VAR typ, banned: OPT.Struct);
	
		PROCEDURE SetPos(x: OPT.Node);
		BEGIN
			x^.conval := OPT.NewConst(); x^.conval^.intval := OPM.errpos
		END SetPos;
		
		PROCEDURE HiddenVar (name: OPS.Name; exp: OPT.Node): OPT.Object;
			VAR dim, owner: OPT.Object; y: OPT.Node;
		BEGIN
			owner:=OPT.topScope;  (* insert var at first place in the variables of the actual scope *)
			WHILE (OPT.topScope.left#NIL) & (OPT.topScope.link=OPT.topScope.left.link) DO (* to do ?? *)
				OPT.topScope:=OPT.topScope.left
			END;
			OPT.Insert("@@", dim); dim^.name:=name;
			dim^.link:=NIL; dim^.mode:=Var; dim^.typ:=OPT.linttyp;
			IF OPT.topScope^.scope=NIL THEN OPT.topScope^.scope:=dim
			ELSE
				dim^.link:=OPT.topScope^.scope; OPT.topScope^.scope:=dim
			END;
			OPT.topScope:=owner;
			y:=OPB.NewLeaf(dim); OPB.Assign(y, exp); (* generate assignment instructions *)
			SetPos(y); OPB.CodeInsert(y);
			RETURN dim;
		END HiddenVar;

		PROCEDURE Interval(VAR typ, banned: OPT.Struct): BOOLEAN;	(* returns TRUE if open array *)
			VAR x: OPT.Node; n, lb: LONGINT; sysflag: SHORTINT;
				low: OPT.Object;
						
			PROCEDURE DynArrType (open: BOOLEAN);	(*dynamic array ARRAY [[?:]*] OF *)
			BEGIN
				typ := OPT.NewStr(Comp, DynArr); typ^.mno := 0; typ^.sysflag := sysflag; typ.extlev:=dynamic; typ.lb:=lb;
				IF sym=comma THEN OPS.Get(sym); IF Interval(typ^.BaseTyp, banned) THEN err(88) END;
				ELSIF sym=of THEN OPS.Get(sym); Type(typ^.BaseTyp, banned);

					IF ~open & (typ.BaseTyp.comp IN {DynArr}) THEN err(88) END;
				ELSE err(of)
				END;
				IF typ^.BaseTyp^.comp = DynArr THEN 
					typ^.n := typ^.BaseTyp^.n + 1;
					IF typ.BaseTyp.lb=MAX(LONGINT) THEN INC(typ.n) END
				ELSIF typ^.BaseTyp^.comp IN {Array, SDynArr} THEN typ^.n := typ^.BaseTyp^.offset
				ELSE typ.n:=0
				END;
				typ.init:=typ.BaseTyp.init
			END DynArrType;
			
			PROCEDURE StaticArrType;
				VAR dim: OPT.Object;
			BEGIN
				IF x^.class = Nconst THEN 	(* ARRAY ...:N OF *)
					typ := OPT.NewStr(Comp, Array); typ^.sysflag := sysflag;
					IF x^.typ^.form IN intSet THEN n := x^.conval^.intval;
						IF (n <= 0) OR (n > OPM.MaxIndex) THEN err(63); n := 1
						ELSIF (low=NIL) & (lb#MAX(LONGINT)) & (OPM.MaxIndex-n+1<lb) THEN err(81)
						END
					ELSE err(51); n := 1
					END;
					typ^.n := n; typ^.link:=NIL;
				ELSE										(* ARRAY ...:n OF *)
					typ := OPT.NewStr(Comp, SDynArr); typ^.sysflag := sysflag;
					IF ((level=0) & IsModuleScope()) OR ParameterMode THEN err(50); typ.n:=0 (* tests *)
					ELSIF ~(x^.typ^.form IN intSet) THEN typ.n:=0; err(68)
					ELSE
						typ^.link:=HiddenVar ("@dim", x)
					END
				END;					
				IF sym = of THEN
					OPS.Get(sym); Type(typ^.BaseTyp, banned); typ.offset:=0;

					IF typ.BaseTyp.comp IN {DynArr} THEN err(88) END;
					IF typ.link=NIL THEN typ.extlev:=static ELSE typ.extlev:=sdynamic END;
				ELSIF sym = comma THEN
					OPS.Get(sym); IF sym # of THEN
						IF Interval(typ^.BaseTyp, banned) THEN err(88) END
					END;
					IF typ.link=NIL THEN typ.extlev:=typ.BaseTyp.extlev
					ELSIF typ.BaseTyp.extlev IN {static, sdynamic} THEN typ.extlev:=sdynamic
					ELSE typ.extlev:=dynamic
					END;
					IF typ^.BaseTyp^.comp = DynArr THEN typ.offset:=typ.BaseTyp.n+1; (*typ^.BaseTyp := OPT.undftyp; err(88)*)
						IF typ.BaseTyp.lb=MAX(LONGINT) THEN INC(typ.offset) END
					ELSE typ.offset:=typ.BaseTyp.offset
					END
				ELSE err(35)
				END;
				typ.lb:=lb; typ.init:=typ.BaseTyp.init
			END StaticArrType;
			
		BEGIN
			CheckSysFlag(sysflag, 0); low:=NIL; x:=NIL; lb := 0;
			IF sym = of THEN DynArrType(TRUE); RETURN TRUE
(*		(*rm lb*)
			ELSIF sym = colon THEN
				OPS.Get(sym); lb := MAX(LONGINT);
				IF sym=times THEN err(of); OPS.Get(sym); DynArrType(TRUE);
				ELSIF (sym=comma) OR (sym=of) THEN DynArrType(TRUE)		(* ARRAY *:* OF *)
				ELSE 
					IF ~ParameterMode THEN err(89) END;
					OPB.verify:=OwnScope; Expression(x); OPB.verify:=NIL; StaticArrType		(* ARRAY *:n OF *)
				END;
				RETURN TRUE
*)
			ELSIF sym=times THEN OPS.Get(sym);
				IF suppressOX THEN err(of) END;
				IF sym IN {comma, of} THEN lb:=0; DynArrType(FALSE)	(* ARRAY *, ...  OF, ARRAY * OF *)
(*		(*rm lb*)
				ELSIF sym=colon THEN
					err(of);
					IF ~ParameterMode THEN err(89) END;
					OPS.Get(sym); lb:=MAX(LONGINT); 
					IF sym=times THEN OPS.Get(sym); DynArrType(FALSE)		(* ARRAY *:* OF *)
					ELSE OPB.verify:=OwnScope; Expression(x); OPB.verify:=NIL; StaticArrType		(* ARRAY *:n OF *)
					END
*)
				ELSE err(35)
				END;
			ELSE
				OPB.verify:=OwnScope; Expression(x); OPB.verify:=NIL;
				IF sym IN {comma, of} THEN lb:=0; StaticArrType	(* ARRAY n,... OF, ARRAY n OF *)
(*		(*rm lb*)
				ELSIF sym=colon THEN low:=NIL;
					IF x^.class = Nconst THEN 	(* ARRAY L:... OF *)
						IF x^.typ^.form IN intSet THEN lb:=x.conval.intval;
							IF (lb < OPM.MinBound) OR (lb > OPM.MaxBound) THEN err(63); lb:=0 END
						ELSE err(51); lb:=0
						END
					ELSE										(* ARRAY l:... OF *)
						IF ((level=0) & IsModuleScope()) OR ParameterMode OR IsRecordScope() THEN err(50); x:=OPB.NewIntConst(1) 
						ELSIF ~(x^.typ^.form IN intSet) THEN err(68)
						END;
						low := HiddenVar ("@lowb", x);
					END;					
					OPS.Get(sym); x:=NIL;
					IF sym=times THEN OPS.Get(sym); DynArrType(FALSE)	(*  ARRAY ...:*  OF *)
					ELSE OPB.verify:=OwnScope; Expression(x); OPB.verify:=NIL; StaticArrType	(* ARRAY ...:? OF *)
					END;
					typ.lbound:=low
*)
				ELSE err(35)
				END;
			END;
			RETURN FALSE
		END Interval;
	
	BEGIN
		IF ~Interval(typ, banned) & (typ.comp IN {SDynArr, DynArr}) & (typ.extlev=dynamic) THEN PtrToArr (typ) END;
	END ArrayType;

	PROCEDURE PointerType(VAR typ, banned: OPT.Struct);
		VAR id: OPT.Object;
	BEGIN typ := OPT.NewStr(Pointer, Basic); CheckSysFlag(typ^.sysflag, 0);
		CheckSym(to);
		IF sym = ident THEN OPT.Find(id);
			IF id = NIL THEN
				IF nofFwdPtr < LEN(FwdPtr) THEN FwdPtr[nofFwdPtr] := typ; INC(nofFwdPtr)
				ELSE err(224)
				END ;
				typ^.link := OPT.NewObj(); COPY(OPS.name, typ^.link^.name);
				typ^.BaseTyp := OPT.undftyp; OPS.Get(sym) (*forward ref*)
			ELSE qualident(id);
				IF id^.mode = Typ THEN
					(* fix POINTER TO a, where a is ARRAY OF T case. Pointer already generated *)
					IF (id.typ.form = Pointer) & (id.typ.BaseTyp.comp = DynArr) & (id.typ.init = TRUE) THEN
						typ := id.typ; typ.init := FALSE;
					ELSIF id^.typ^.comp IN {Record} THEN
						IF id.typ.ptr # NIL THEN typ := id.typ.ptr END;
						typ.BaseTyp := id.typ;
					ELSIF id^.typ^.comp IN {Array, DynArr} THEN 
(*
					ELSIF id^.typ^.comp IN {Record, Array, DynArr} THEN 
*)
						typ^.BaseTyp := id^.typ
					ELSE typ^.BaseTyp := OPT.undftyp; err(57)
					END
				ELSE typ^.BaseTyp := OPT.undftyp; err(52)
				END
			END
		ELSE Type(typ^.BaseTyp, banned);
			IF typ.BaseTyp.ptr # NIL THEN	(* use the pointer of the record *)
				typ.BaseTyp.ptr.sysflag := typ.sysflag; typ := typ.BaseTyp.ptr
			END;
			IF ~(typ^.BaseTyp^.comp IN {Record, Array, DynArr}) THEN
				typ^.BaseTyp := OPT.undftyp; err(57)
			END
		END;
		typ.init:=FALSE
	END PointerType;
	
	PROCEDURE FormalParameters(VAR firstPar: OPT.Object; VAR resTyp: OPT.Struct);
		VAR mode: SHORTINT;
				par, first, last, res: OPT.Object; typ: OPT.Struct;
	BEGIN first := NIL; last := firstPar;
		IF (sym = ident) OR (sym = var) THEN ParameterMode:=TRUE;
			LOOP
				IF sym = var THEN OPS.Get(sym); mode := VarPar ELSE mode := Var END ;
				LOOP
					IF sym = ident THEN
						OPT.Insert(OPS.name, par); OPS.Get(sym);
						par^.mode := mode; par^.link := NIL;
						IF first = NIL THEN first := par END ;
						IF firstPar = NIL THEN firstPar := par ELSE last^.link := par END ;
						last := par
					ELSE err(ident)
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF sym = ident THEN err(comma)
					ELSIF sym = var THEN err(comma); OPS.Get(sym)
					ELSE EXIT
					END
				END ;
				CheckSym(colon); Type(typ, OPT.notyp);
				IF (typ.strobj = NIL) & (typ.comp # DynArr) THEN err(-305) END;
				IF (mode = VarPar) & (typ = OPT.sysptrtyp) THEN err(-303) END;

				WHILE first # NIL DO
					IF typ = OPT.undftyp THEN
						first.mode := -first.mode;	(* mark variable *)
						InsertTypeFix (OPS.name, first);
					END;
					first^.typ := typ; first := first^.link
				END ;
				IF sym = semicolon THEN OPS.Get(sym)
				ELSIF sym = ident THEN err(semicolon)
				ELSE EXIT
				END
			END
		END ;
		CheckSym(rparen);
		IF sym = colon THEN
			OPS.Get(sym); resTyp := OPT.undftyp;
			IF sym = ident THEN qualident(res);
				IF res = UndefObj THEN resTyp := NIL;		(* special handling *)
				ELSIF res^.mode = Typ THEN
					resTyp := res^.typ
				ELSE err(52)
				END
			ELSE err(ident)
			END
		ELSE resTyp := OPT.notyp
		END;
		ParameterMode:=FALSE
	END FormalParameters;

	PROCEDURE CheckAndFix(typ: OPT.Struct);
		VAR lev: SHORTINT;
	BEGIN
		WHILE (typ#NIL)&((typ.form=Pointer) OR (typ.comp IN {Array, SDynArr, DynArr})) DO
			IF typ.form=Pointer THEN typ:=typ.BaseTyp
			ELSE
				IF typ.link#NIL THEN
					IF IsRecordScope() THEN err(90)
					ELSE
						lev:=typ.link.mnolev;
						IF lev#level THEN typ.link.leaf:=FALSE; IF lev>0 THEN OPB.StaticLink(level-lev) END END
					END
				END;
				IF typ.lbound#NIL THEN
					IF IsRecordScope() THEN err(90)
					ELSE
						lev:=typ.lbound.mnolev;
						IF lev#level THEN typ.lbound.leaf:=FALSE; IF lev>0 THEN OPB.StaticLink(level-lev) END END
					END
				END;
				typ:=typ.BaseTyp
			END
		END
	END CheckAndFix;

	PROCEDURE TypeDecl(VAR x: OPT.Node; VAR typ, banned: OPT.Struct; VAR owner: OPT.Object);
		VAR id: OPT.Object; name: OPS.Name; old: BOOLEAN;
	BEGIN typ := OPT.undftyp; x := NIL;
		old := suppressOX;
		IF sym < lparen THEN err(12);
			REPEAT OPS.Get(sym) UNTIL sym >= lparen
		END ;
		COPY (OPS.name, name);
		IF sym = ident THEN qualident(id);
			COPY (name, OPS.name);
			IF id = UndefObj THEN typ := OPT.undftyp; UndefFlag := FALSE;
				IF (sym = period) THEN
					OPT.FindInScope (name, ExtObj, id);
					IF (id # NIL) & (id.mode = Mod) THEN
						OPS.Get (sym); OPT.FindImport (id, id); OPS.Get(sym);
					END;
					IF id = NIL THEN err (0); typ := OPT.undftyp
					ELSIF id.mode = Typ THEN
						IF id^.typ # banned THEN typ := id^.typ ELSE err(58) END
					ELSE err (52); typ := OPT.undftyp
					END
				END
			ELSIF id^.mode = Typ THEN
				IF id^.typ # banned THEN typ := id^.typ ELSE err(58) END
			ELSE err(52)
			END;
			IF id#NIL THEN CheckAndFix(id.typ) END
		ELSIF sym = array THEN
			OPS.Get(sym); ArrayType(typ, banned);
		ELSIF sym = record THEN
			suppressOX := FALSE;
			OPS.Get(sym); RecordType(x, typ, banned, owner);
			OPB.Inittd(TDinit, lastTDinit, typ); (*CheckSym(end)*)	(* --> done in RecordType *)
		ELSIF sym = pointer THEN
			old := suppressOX; suppressOX := TRUE;
			OPS.Get(sym); PointerType(typ, banned);
			suppressOX := old;
		ELSIF sym = procedure THEN
			suppressOX := FALSE;
			OPS.Get(sym); typ := OPT.NewStr(ProcTyp, Basic); CheckSysFlag(typ^.sysflag, 0);
			IF sym = lparen THEN
				OPS.Get(sym); OPT.OpenScope(level, NIL);
				FormalParameters(typ^.link, typ^.BaseTyp); OPT.CloseScope
				;IF UndefFlag THEN err(1009); UndefFlag := FALSE END;
			ELSE typ^.BaseTyp := OPT.notyp; typ^.link := NIL
			END
		ELSE err(12)
		END ;
		IF (typ.comp IN {Array, DynArr} ) & (typ.BaseTyp = OPT.undftyp) THEN (* ARRAY OF T, T not declared yet *)
			NEW (id); id.mode := Typ; id.typ := typ; InsertTypeFix (OPS.name, id)
		END;
		LOOP
			IF (sym >= semicolon) & (sym <= else) OR (sym = rparen) OR (sym = eof) OR (sym = ident) THEN EXIT END;
			err(15); IF sym = ident THEN EXIT END;
			OPS.Get(sym)
		END;
		suppressOX := old
	END TypeDecl;
	
	PROCEDURE Type(VAR typ, banned: OPT.Struct);
		VAR x: OPT.Node; link: OPT.Object;
	BEGIN 
		x := NIL;
		TypeDecl(x, typ, banned, link);
		IF x # NIL THEN
			OPB.Link(RecInit, lastRecInit, x);
		END;
(*		IF (x # NIL) (*OR (link # NIL)*) THEN err(200) END;*)
	END Type;

	PROCEDURE selector(VAR x: OPT.Node);
		VAR obj, proc: OPT.Object; y: OPT.Node; typ: OPT.Struct; name: OPS.Name; b: BOOLEAN; i: LONGINT;
	BEGIN
		IF x.obj.name = "SELF" THEN
			(* object self or module self ? *)
			OPT.FindInScope ("@SELF", OPT.topScope, obj);
			IF obj.typ.comp = Record THEN	(* <- local self *)
				(* x <= S.VAL (PTR, S.ADR (x)) *)
				x := OPB.NewLeaf (obj);
				IF sym # period THEN
					OPB.StPar0 (x, 20); OPB.StFct (x, 20, 1);	(* S.ADR *)
					x.typ := OPT.sysptrtyp;
					i := nofFwdPtr-1; typ := obj.typ;
					WHILE (i >= 0) & (FwdPtr[i].BaseTyp # typ) DO DEC (i) END;
					IF i < 0 THEN err (252); x.typ := OPT.sysptrtyp
					ELSE
						x.typ := FwdPtr[i]
					END;
					SetFlags (obj.typ.strobj, {needPointer})
				END
			ELSIF obj.typ # OPT.sysptrtyp THEN	(* local, but already pointer (i.e. in the body) *)
				x := OPB.NewLeaf (obj)
			END
		END;
		LOOP
			IF sym = lbrak THEN OPS.Get(sym);
				LOOP
					IF (x^.typ # NIL) & (x^.typ^.form = Pointer) THEN OPB.DeRef(x); UsesGlobals := TRUE END ;
					(*b := UndefFlag; UndefFlag := FALSE;*)
					Expression(y); IF ~UndefFlag THEN OPB.Index(x, y) END;
					(*UndefFlag := UndefFlag OR b;*)
					IF sym = comma THEN OPS.Get(sym) ELSE EXIT END
				END ;
				CheckSym(rbrak)
			ELSIF (sym = period) OR ((x.obj # NIL) & (x.obj.name = HiddenSelf) & (sym = ident)) THEN 
				IF sym = period THEN (*b := FALSE;*) OPS.Get(sym) (*ELSE b := TRUE*) END;
				IF sym = ident THEN name := OPS.name; OPS.Get(sym);
					IF x^.typ # NIL THEN
						IF x^.typ^.form = Pointer THEN 

							OPB.DeRef(x); UsesGlobals := TRUE
						END;
						IF x^.typ^.comp = Record THEN

							OPT.FindInScope(name, x^.typ^.strobj^.scope, obj); 

							IF ((obj = NIL) OR (obj.mode < 0)) & ~FixPhase THEN UndefFlag := TRUE ELSE OPB.Field(x, obj) END;
							IF (obj # NIL) & (obj^.mode = TProc) THEN
								IF sym = arrow THEN  (* super call *) OPS.Get(sym);
									y := x^.left;
									IF y^.class = Nderef THEN y := y^.left END ;	(* y = record variable *)
									IF y^.obj # NIL THEN
										proc := OPT.topScope;	(* find innermost scope which owner is a TProc *)
										WHILE (proc^.link # NIL) & (proc^.link^.mode # TProc) DO proc := proc^.left END ;
										IF (proc^.link = NIL) OR (proc^.link^.link # y^.obj) THEN err(75) END ;
										typ := y^.obj^.typ;
										IF typ^.form = Pointer THEN typ := typ^.BaseTyp END ;

										IF isRedef IN GetFlags(obj) THEN

											x^.subcl := super;
										ELSE err(74) END
									ELSE err(75)
									END	(* y^.obj # NIL *)
								END ; (* sym = arrow *)
								IF (obj^.typ # OPT.notyp) & (sym # lparen) THEN err(lparen) END
							END (* (obj # NIL) & (obj^.mode = TProc) *)
						ELSIF x.typ = OPT.undftyp THEN UndefFlag := TRUE
						ELSE err(53)
						END (* x^.typ^.comp = Record *)
						ELSIF ~UndefFlag THEN err(52)
					END
				ELSE err(ident)
				END
			ELSIF sym = arrow THEN OPS.Get(sym);
				IF ~UndefFlag THEN
					IF (x.typ.form # Pointer) OR (x.typ.init # FALSE) THEN err(84)
					ELSE OPB.DeRef(x)
					END
				END
			ELSIF (sym = lparen) & (x^.class < Nconst) & (x^.typ^.form # ProcTyp) &
					~UndefFlag &
					((x^.obj = NIL) OR (x^.obj^.mode # TProc)) THEN
				OPS.Get(sym);
				IF sym = ident THEN
					qualident(obj);
					IF obj^.mode = Typ THEN OPB.TypTest(x, obj, TRUE)
					ELSIF ~UndefFlag THEN err(52)
					ELSIF sym = period THEN	(* M.T -> Module not defined *)
						err (0); OPS.Get (sym); CheckSym (ident)
					END
				ELSE err(ident)
				END ;
				CheckSym(rparen)
			ELSE EXIT
			END
		END
	END selector;

	PROCEDURE RetReservation(VAR retnode: OPT.Node; VAR typ: OPT.Struct);
		VAR retfld: OPT.Object;
	BEGIN
		retfld:=OPT.NewObj(); retfld.mode:=Var; retfld.typ:=typ; retfld.mnolev:=OPT.topScope.mnolev;
		retnode:=OPT.NewNode(Nret); retnode^.obj:=retfld; retnode.typ:=typ
	END RetReservation;

	PROCEDURE ActualParameters(VAR aparlist: OPT.Node; fpar: OPT.Object; x: OPT.Node);
		VAR apar, last, retnode, aparret, lastret: OPT.Node;
			s: OPS.TokenStream; b: BOOLEAN;
	BEGIN aparlist := NIL; last := NIL; b := UndefFlag; lastret:=NIL; aparret:=NIL;
		IF sym # rparen THEN
			LOOP 
					Expression(apar);
					IF fpar # NIL THEN
						IF ~UndefFlag & ~ b THEN
							OPB.Param(apar, fpar);
							IF (apar.class=Ncall) & (apar.typ#NIL) & (apar.typ.comp=Array) & (apar.typ.extlev=static) & (fpar.typ.extlev=dynamic) THEN
								RetReservation(retnode, apar.left.typ); OPB.Link(aparret, lastret, retnode);
							ELSIF (fpar.typ.comp=DynArr)&(apar.class=Nderef) & (apar.left.class=Ncall) & (apar.typ.comp IN {Array, SDynArr, DynArr}) THEN
								RetReservation(retnode, apar.left.typ); OPB.Link(aparret, lastret, retnode);
							ELSIF (apar.class=Ncall) & (apar.typ.comp IN {Array, SDynArr}) & (apar.typ.extlev=sdynamic) THEN
								RetReservation(retnode, apar.left.typ); OPB.Link(aparret, lastret, retnode);
							END;
							OPB.Link(aparlist, last, apar)
						END;
						fpar := fpar^.link;
					ELSIF ~UndefFlag & ~ b THEN err(64)
					END;
				IF sym = comma THEN OPS.Get(sym)
				ELSIF (lparen <= sym) & (sym <= ident) THEN err(comma)
				ELSE EXIT
				END
			END;
			IF aparret#NIL THEN lastret.link:=aparlist; aparlist:=aparret END
		END ;
		IF (fpar # NIL) & ~UndefFlag & ~ b THEN err(65) END;
		UndefFlag := UndefFlag OR b
	END ActualParameters;

	PROCEDURE Passivate(VAR x: OPT.Node; VAR n: INTEGER);
		VAR proc, self, scope: OPT.Object; exp, cond: OPT.Node; name: OPS.Name; f: SET; i: LONGINT; ts: OPS.TokenStream;
	BEGIN
		self := GetSelf();
		IF sym = lparen THEN
			n := 1; OPS.Get(sym);
		(* Create guard evaluation function *)
			IF OPT.topScope^.link = NIL THEN COPY("$$", name)
			ELSE COPY(OPT.topScope^.link^.name, name) END;
			i := 0; WHILE name[i] # 0X DO INC(i) END;
			name[i] := "."; INC(i); name[i] := "C"; INC(i); name[i] := "o"; INC(i);
			name[i] := "n"; INC(i); name[i] := "d"; INC(i); name[i] := CHR(CondCount + ORD("A")); INC(i);
			name[i] := 0X; INC(CondCount);
			OPT.Insert(name, proc); proc.mode := XProc;		(* XProc, because this proc is passed as param, needs fixup!! *)
			proc.link := NIL; proc.vis := internal; proc.adr := 0;
			proc^.typ := OPT.booltyp; proc.conval := OPT.NewConst(); proc^.conval^.setval := {hasBody, slNeeded};
			proc.conval.intval := 12;
			INC(level); OPT.OpenScope(level, proc);
			UsesGlobals := FALSE;
			scope := OPT.topScope;
			WHILE (scope # NIL) & ~(scope.link.mode IN {Typ, Mod}) DO scope := scope^.left END;
			ObjLocal := (scope # NIL) & (scope.link.mode = Typ);
			UsesGlobals := (scope = NIL) OR ~(passiveObj IN GetFlags(scope.link));(* if the scope isn't protectable, local evaluation has no sense *)
			Expression(x);
			IF UndefFlag THEN
				exp := x; proc.typ := x.typ; OPB.Return(x, proc); proc^.typ := OPT.booltyp
			ELSE
				OPB.StPar0(x, passivatefn); OPB.Return(x, proc);
			END;
			OPT.CloseScope; DEC(level);
			x.conval := OPT.NewConst(); x^.conval.intval := OPM.errpos;
			cond := NIL; OPB.Enter(cond, x, proc); cond.link := CondNodes; CondNodes := cond;
			cond.conval := OPT.NewConst(); cond^.conval.intval := OPM.errpos;
		(* Create parameters for the passivate call *)
			x := OPB.NewLeaf(proc); 
			x.link := OPB.NewLeaf(self);	(* Always push SELF *)
			IF sym = comma THEN OPS.Get(sym);
				Expression(x.link.link);
				IF x.link.link.typ # OPT.booltyp THEN err(113) END
			END;
			CheckSym(rparen); 
		ELSE

			err (65)

		END;
		IF x.link.link = NIL THEN x.link.link := OPB.NewBoolConst(UsesGlobals) END;
		IF (x.link.link.conval.intval = 1) & (self.typ # OPT.sysptrtyp (*has the td here*)) THEN
			SetFlags (self.typ.strobj, {needPointer})
		END;
		IF UndefFlag THEN
			UndefFlag := FALSE; OPS.StopRecording (ts);
			InsertFix (FPassExpr, ts, exp); InsertFix (FPassHint, ts, x.link.link)
		END;
		IF x.link.link.conval.intval = 1 THEN
			OPM.LogWLn; OPM.LogWStr("  PASSIVATE at "); OPM.LogWNum(OPM.errpos,0);
			OPM.LogWStr(": non-local condition")
		END
	END Passivate;
	
	PROCEDURE StandProcCall(VAR x: OPT.Node);
		VAR y: OPT.Node; m: SHORTINT; n: INTEGER;
	BEGIN m := SHORT(SHORT(x^.obj^.adr)); n := 0;
		IF m = passivatefn THEN
			Passivate(x, n)
		ELSIF sym = lparen THEN OPS.Get(sym);
			IF sym # rparen THEN
				LOOP
					IF n = 0 THEN Expression(x);
						(* intercept derefencing of undefined types *)
						IF ~UndefFlag & ~FixPhase & (m = newfn) & (n = 0) & (x.typ.BaseTyp = OPT.undftyp) THEN UndefFlag := TRUE END;
						IF ~UndefFlag THEN OPB.StPar0(x, m) END; n := 1
					ELSIF n = 1 THEN Expression(y); IF ~UndefFlag THEN OPB.StPar1(x, y, m) END; n := 2
					ELSE Expression(y); IF ~UndefFlag THEN OPB.StParN(x, y, m, n) END; INC(n)
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF (lparen <= sym) & (sym <= ident) THEN err(comma)
					ELSE EXIT
					END
				END ;
				CheckSym(rparen)
			ELSE OPS.Get(sym)
			END ;
		END ;
		IF ~UndefFlag THEN OPB.StFct(x, m, n) END;
		IF (level > 0) & ((m = newfn) OR (m = sysnewfn)) THEN OPT.topScope^.link^.leaf := FALSE END
	END StandProcCall;
	
	PROCEDURE InlineProc(VAR x: OPT.Node; VAR apar: OPT.Node; fpar: OPT.Object);			(* Inline *)
		VAR inline, par, list: OPT.Object; glueCode, src, trg: OPT.Node; assembly: BOOLEAN; c: OPT.Const;
		
			PROCEDURE CopyLocals(obj: OPT.Object);
				VAR	new: OPT.Object; name: OPS.Name; i, j: LONGINT;
			BEGIN
				IF obj # NIL THEN
					IF (obj^.mode = Var) OR (assembly & (obj^.mode = VarPar)) THEN
						i := 0; WHILE inline^.name[i] # 0X DO name[i] := inline^.name[i]; INC(i) END;
						name[i] := "."; INC(i);
						j := 0; WHILE obj^.name[j] # 0X DO name[i] := obj^.name[j]; INC(j); INC(i) END;
						name[i] := 0X;
						OPT.Insert(name, new);
						par.link := new; par := new;
						new^.leaf := FALSE(*obj^.leaf*); new^.mode := obj^.mode;
						new^.vis := internal; new^.typ := obj^.typ;
						obj^.link2 := new;
						IF assembly THEN new^.link2 := obj END
					END;
					CopyLocals(obj^.left);		(* pre-order traversing --> prevents a degenerated list *)
					CopyLocals(obj^.right)
				END
			END CopyLocals;
			
	BEGIN
			inline := x^.obj; assembly := asmProc IN inline^.conval^.setval;
			IF assembly & (inline^.scope^.scope # NIL) THEN OPM.Mark(260, inline^.code^.conval^.intval)		(* asm inline cannot have local variables *)
			END;
		(* get parameters *)
			IF ~OPM.noerr THEN RETURN END;
			IF ~(hasBody IN inline^.conval^.setval) THEN err(129); RETURN END;
		(* insert locals *)
			IF inline^.link2 # OPT.topScope THEN	(* do it only the first time *)
				par := OPT.topScope.scope;
				IF par # NIL THEN 
					WHILE par^.link # NIL DO par := par^.link END;
					CopyLocals(inline^.scope^.right)
				ELSE
					NEW(list); par := list;
					CopyLocals(inline^.scope^.right);
					IF OPT.topScope.scope # NIL THEN OPT.topScope.scope := list^.link END
				END;
				inline^.link2 := OPT.topScope;
			END;
		(* insert glue-code *)
			IF assembly THEN
				OPB.Call(x, apar, fpar);				(* this is the glue code for the inline *)
				OPB.CopyAndSubst(x^.left, inline^.code);
				x^.subcl := 2;	(* inlined proc *)
			ELSE
				x := NIL; glueCode := NIL;
				c := OPT.NewConst(); c^.intval := OPM.errpos;
				WHILE fpar # NIL DO
					IF fpar^.mode = VarPar THEN
						fpar^.link2 := apar^.obj;
						apar := apar^.link
					ELSE
						(* move apar to fpar *)
							src := apar; apar := apar^.link; src^.link := NIL;
							trg := OPB.NewLeaf(fpar^.link2);
							OPB.Assign(trg, src); trg.conval := c;
							IF glueCode = NIL THEN x := trg ELSE glueCode^.link := trg END;
							glueCode := trg
					END;
					fpar := fpar^.link
				END;
		(* copy parse tree *)
				IF glueCode = NIL THEN
					OPB.CopyAndSubst(x, inline^.code)
				ELSE
					OPB.CopyAndSubst(glueCode^.link, inline^.code)
				END
			END
	END InlineProc;
	
	PROCEDURE Element(VAR x: OPT.Node);
		VAR y: OPT.Node;
	BEGIN Expression(x);
		IF sym = upto THEN
			OPS.Get(sym); Expression(y); OPB.SetRange(x, y)
		ELSE OPB.SetElem(x)
		END
	END Element;

	PROCEDURE Sets(VAR x: OPT.Node);
		VAR y: OPT.Node;
	BEGIN
		IF sym # rbrace THEN
			Element(x);
			LOOP
				IF sym = comma THEN OPS.Get(sym)
				ELSIF (lparen <= sym) & (sym <= ident) THEN err(comma)
				ELSE EXIT
				END ;
				Element(y); OPB.Op(plus, x, y)
			END
		ELSE x := OPB.EmptySet()
		END ;
		CheckSym(rbrace)
	END Sets;
	
	PROCEDURE Resolve(VAR obj: OPT.Object; VAR name: OPS.Name; VAR x, y: OPT.Node);
		VAR wrn: BOOLEAN; dist: SHORTINT;
	BEGIN
		IF obj=NIL THEN
			obj:=OPT.Resolve(name, x, y)
		ELSE
			OPT.QualResolve(obj, x, y, dist, wrn);
			IF wrn THEN err(-310) END	(* ambiguous operator *)
		END;

	END Resolve;
	
	PROCEDURE OpCall(VAR op: OPT.Object; VAR x: OPT.Node; y: OPT.Node);
		VAR fpar: OPT.Object; proc, apar, last, ret, retlist, lastret: OPT.Node;
	BEGIN apar:=NIL; last:=NIL; retlist:=NIL; lastret:=NIL;
		IF op#NIL THEN
			(*IF op.prio=125 THEN err(136) END;*)
			proc:=OPB.NewLeaf(op); OPB.PrepCall(proc, fpar);
			IF (x.class=Ncall) & (x.typ#NIL) & (x.typ.comp=Array) & (x.typ.extlev=static) & (op.link.typ.extlev=dynamic) THEN
				RetReservation(ret, x.typ); OPB.Link(retlist, lastret, ret)
			ELSIF (op.link.typ.comp=DynArr)&(x.class=Ncall) & (x.typ.form=Pointer) THEN
				RetReservation(ret, x.typ); OPB.Link(retlist, lastret, ret)
			ELSIF (x.class=Ncall) & (x.typ.comp IN {Array, SDynArr}) & (x.typ.extlev=sdynamic) THEN
				RetReservation(ret, x.typ); OPB.Link(retlist, lastret, ret)
			END;
			IF (x.typ.form=Pointer) & (op.link.typ.comp=DynArr) THEN OPB.DeRef(x) END;
			OPB.Link(apar, last, x);
			IF y#NIL THEN
				IF (y.class=Ncall) & (y.typ#NIL) & (y.typ.comp=Array) & (y.typ.extlev=static) & (op.link.link.typ.extlev=dynamic) THEN
					RetReservation(ret, y.typ); OPB.Link(retlist, lastret, ret)
				ELSIF (op.link.link.typ.comp=DynArr)&(y.class=Ncall) & (y.typ.form=Pointer) THEN
					RetReservation(ret, y.typ); OPB.Link(retlist, lastret, ret)
				ELSIF (y.class=Ncall)  & (y.typ.comp IN {Array, SDynArr}) & (y.typ.extlev=sdynamic) THEN
					RetReservation(ret, y.typ); OPB.Link(retlist, lastret, ret)
				END;
				IF (y.typ.form=Pointer) & (op.link.link.typ.comp=DynArr) THEN OPB.DeRef(y) END;
				OPB.Link(apar, last, y)
			END;
			IF retlist#NIL THEN lastret.link:=apar; apar:=retlist END;
			OPB.Call(proc, apar, fpar);
			x:=proc
		ELSE err(137)
		END
	END OpCall;

	PROCEDURE Primary (VAR x: OPT.Node);	(* factor changed in primary *)
		VAR fpar, id: OPT.Object; apar, y: OPT.Node; name: OPS.Name;
	BEGIN
		IF sym < lparen THEN err(13);
			REPEAT OPS.Get(sym) UNTIL sym >= lparen
		END ;
		IF sym = ident THEN
			qualident(id);
		END;
		IF (id#NIL) & (id.prio#127) THEN	(*found object is not an operator *)
			x := OPB.NewLeaf(id); selector(x);
			UsesGlobals := UsesGlobals OR (id.mnolev < 0) OR ((x # NIL) & (x.obj # NIL) & (x.obj.typ.form = ProcTyp));
			UsesGlobals := UsesGlobals OR (~ObjLocal & (id.mnolev = 0) & ~(id.mode IN {Fld, TProc, Con}));
			IF (x^.class = Nproc) & (x^.obj^.mode = SProc) THEN 
				IF (x.obj.name = "SIZE") & ~FixPhase THEN UndefFlag := TRUE END;
				StandProcCall(x)	(* x may be NIL *)
			ELSIF sym = lparen THEN
					UndefFlag := UndefFlag OR (x.typ = NIL);
					OPS.Get(sym);
					IF UndefFlag THEN
						ActualParameters(apar, fpar, x)
					ELSE
						OPB.PrepCall(x, fpar); ActualParameters(apar, fpar, x);
						IF (x^.class = Nproc) & (x^.obj^.mode = CProc) THEN InlineProc (x, apar, fpar)
						ELSE OPB.Call(x, apar, fpar)
						END;
					END;
					CheckSym(rparen);
					IF level > 0 THEN OPT.topScope^.link^.leaf := FALSE END
			END
		ELSIF (id#NIL) & (id.prio=127) THEN (* imported operator/ *)
			 OPS.Get(sym); Primary(x); Resolve(id, name, x, y); OpCall(id, x, NIL)
		ELSIF sym = number THEN
			CASE OPS.numtyp OF
			   char: x := OPB.NewIntConst(OPS.intval); x^.typ := OPT.chartyp
			| integer: x := OPB.NewIntConst(OPS.intval)
			| real: x := OPB.NewRealConst(OPS.realval, OPT.realtyp)
			| longreal: x := OPB.NewRealConst(OPS.lrlval, OPT.lrltyp)
			END ;
			OPS.Get(sym)
		ELSIF sym = true THEN
			x := OPB.BoolConst(1); OPS.Get(sym)	(* 1 is a compiler internal representation only *)
		ELSIF sym = false THEN
			x := OPB.BoolConst(0); OPS.Get(sym)	(* 0 is a compiler internal representation only *)
		ELSIF sym = string THEN
			x := OPB.NewString(OPS.str, OPS.intval); OPS.Get(sym)
		ELSIF sym = nil THEN
			x := OPB.Nil(); OPS.Get(sym)
		ELSIF sym = lparen THEN
			OPS.Get(sym); Expression(x); CheckSym(rparen)
		ELSIF sym = lbrak THEN
			OPS.Get(sym); err(lparen); Expression(x); CheckSym(rparen)
		ELSIF sym = lbrace THEN OPS.Get(sym); Sets(x)
		ELSIF (sym = not)  THEN
			name:=OPS.name; OPS.Get(sym); y:=NIL; id:=NIL;
			Primary(x); Resolve(id, name, x, y);
			IF id=NIL THEN OPB.MOp(not, x)
			ELSE OpCall(id, x, y)
			END
		ELSE err(13); OPS.Get(sym); x := NIL
		END ;
		IF sym=ident THEN
			qualident(ActualOperator);	(* qualificated operators *)
			IF ActualOperator=NIL THEN err(1)
			ELSIF UndefFlag THEN err(semicolon); UndefFlag := FALSE
			ELSIF ActualOperator.mode # Mod THEN err(semicolon)
			END
		END;
		IF x = NIL THEN x := OPB.NewIntConst(1); x^.typ := OPT.undftyp END
	END Primary;
	
	PROCEDURE Factor(VAR x: OPT.Node); (* only for '**' *)
		VAR y: OPT.Node; name: OPS.Name; op: OPT.Object;
	BEGIN Primary(x);
		WHILE sym=pow DO
			op:=ActualOperator; ActualOperator:=NIL; name:=OPS.name;
			OPS.Get(sym); Primary(y);
			IF ~UndefFlag THEN
				Resolve(op, name, x, y); OpCall(op, x, y)
			END
		END
	END Factor;

	PROCEDURE Term(VAR x: OPT.Node);
		VAR y: OPT.Node; mulop: SHORTINT; name: OPS.Name; op: OPT.Object;
	BEGIN Factor(x);
		WHILE (times <= sym) & (sym <= and) DO 
			op:=ActualOperator; ActualOperator:=NIL; mulop := sym; name:=OPS.name;
			OPS.Get(sym); Factor(y); 
			IF ~UndefFlag THEN Resolve(op, name, x, y);
				IF op=NIL THEN OPB.Op(mulop, x, y) 
				ELSE OpCall(op, x, y)
				END
			END
		END
	END Term;
	
	PROCEDURE SimpleExpression(VAR x: OPT.Node);
		VAR y: OPT.Node; addop : SHORTINT; name: OPS.Name; op: OPT.Object;
	BEGIN
		IF (sym=plus) OR (sym=minus) THEN
			op:=ActualOperator; ActualOperator:=NIL; addop := sym; name:=OPS.name; OPS.Get(sym); 
			Term(x); y:=NIL;
			IF ~UndefFlag THEN Resolve(op, name, x, y);
				IF op=NIL THEN OPB.MOp(addop, x)
				ELSE OpCall(op, x, y)
				END
			END
		ELSE Term(x)
		END ;
		WHILE (plus <= sym) & (sym <= or) DO
			op:=ActualOperator; ActualOperator:=NIL; addop := sym; name:=OPS.name; OPS.Get(sym);
			Term(y);
			IF ~UndefFlag THEN Resolve(op, name, x, y);
				IF op=NIL THEN OPB.Op(addop, x, y)
				ELSE OpCall(op, x, y)
				END
			END
		END
	END SimpleExpression;
	
	PROCEDURE Expression(VAR x: OPT.Node);
		VAR y: OPT.Node; obj: OPT.Object; relation: SHORTINT; name: OPS.Name; 
	BEGIN SimpleExpression(x);
		IF (eql <= sym) & (sym <= geq) THEN
			obj:=ActualOperator; ActualOperator:=NIL; relation := sym; name:=OPS.name;
			OPS.Get(sym); SimpleExpression(y);
			IF ~UndefFlag THEN Resolve(obj, name, x, y);
				IF obj=NIL THEN OPB.Op(relation, x, y)
				ELSE OpCall(obj, x, y)
				END
			END
		ELSIF sym = in THEN
			obj:=ActualOperator; ActualOperator:=NIL; name:=OPS.name;
			OPS.Get(sym); SimpleExpression(y);
			IF ~UndefFlag THEN Resolve(obj, name, x, y);
				IF obj=NIL THEN OPB.In(x, y)
				ELSE OpCall(obj, x, y)
				END
			END
		ELSIF sym = is THEN
			OPS.Get(sym);
			IF sym = ident THEN
				qualident(obj);
				IF ~UndefFlag THEN
					IF obj^.mode = Typ THEN OPB.TypTest(x, obj, FALSE)
					ELSE err(52)
					END
				ELSE
					IF sym = period THEN err (0); OPS.Get (sym); CheckSym (ident) END
				END
			ELSE err(ident)
			END
		END
	END Expression;
	
	PROCEDURE ProcedureDeclaration(VAR x: OPT.Node);
		 (* operator prio =126
			 sentinel prio = 127
			 temp against recursive oper = 128 *)

		VAR proc, fwd: OPT.Object;
			name: OPS.Name;
			mode, vis, prio: SHORTINT;
			forward, init: BOOLEAN;
			i: INTEGER; flags: SET;
			scope: OPT.Object; redef: BOOLEAN;
			selfname: OPS.Name; selftype, selfrec: OPT.Struct; selfmode: SHORTINT;

		PROCEDURE GetParam;	(* set link and typ *)
		BEGIN
			proc.typ := OPT.notyp; proc.link := NIL;
			IF mode = TProc THEN (* insert hidden self *)
				OPT.Insert (selfname, proc.link); 
				proc.link.mode := selfmode; proc.link.typ := selftype;
			END;
			IF sym = lparen THEN
				OPS.Get(sym); 
				IF mode # TProc THEN FormalParameters(proc^.link, proc^.typ) ELSE FormalParameters(proc^.link^.link, proc^.typ) END;
				IF UndefFlag OR ((fwd#NIL) & (fwd.typ=NIL)) THEN
					UndefFlag := FALSE; proc.typ := NIL; InsertTypeFix (OPS.name, proc)
				END
			ELSIF prio=126 THEN err(30)	(* operator should have parameters *)
			END;
			IF prio=126 THEN
				IF proc^.typ=OPT.notyp THEN err(141) END;
				IF ~forward THEN OPT.Contextualize(proc);  proc.prio:=125; OPT.topScope.link:=proc
				ELSE err(145)
				END
			END;
			IF (fwd # NIL) & (prio<126) THEN
				IF (mode = TProc) & redef THEN OPB.CheckParameters (proc.link.link, fwd.link.link, FALSE);
					IF proc.link.mode # fwd.link.mode THEN err(115) END
				ELSE OPB.CheckParameters (proc.link, fwd.link, TRUE)
				END;
				IF proc.typ # fwd.typ THEN err(117) END;
				IF ~redef THEN proc := fwd; OPT.topScope := fwd.scope 
				ELSE INCL (proc.conval.setval, isRedef)
				END
			END;
			
			(* general checks *)
			IF init & (proc.typ # OPT.notyp) THEN err(134) END;
			IF init & (OPT.topScope.left.link.mode = Mod) & (proc.link # NIL) THEN err(133) END;
		END GetParam;

		PROCEDURE Body;
			VAR c, n: LONGINT; ext: OPT.ConstExt; procdec, statseq: OPT.Node;
		BEGIN
			c := OPM.errpos; INCL(proc.conval.setval, hasBody);
			IF (sym = number) (*& (mode = CProc)*) THEN		(* old style inline *)
				IF ~OPT.SYSimported THEN err(135) END ;
				statseq := OPT.NewNode(Ncode); statseq.conval := OPT.NewConst(); procdec := NIL;
				n := 0; ext := OPT.NewExt(); statseq.conval.ext := ext;
				OPB.Construct (Nassembler, statseq, NIL); statseq.conval := OPT.NewConst(); statseq.conval.intval := c;
				INCL (proc.conval.setval, asmProc); proc.conval.ext := ext;
				LOOP
					IF sym = number THEN INC(n);
						IF (OPS.intval < 0) OR (OPS.intval > 255) OR (n = OPT.MaxConstLen) THEN
							err(63); OPS.intval := 1; n := 1
						END ;
						ext[n] := CHR(OPS.intval);
						OPS.Get(sym); 
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF sym = number THEN err(comma)
					ELSE
						ext[0] := CHR(n);
						EXIT
					END
				END
			ELSE		(* oberon procedure *)
				CheckSym(semicolon);
				Block(procdec, statseq);
				IF (sym=number) OR (sym=string) THEN COPY (OPS.str, OPS.name); sym := ident; proc.prio := prio END;
				IF sym = ident THEN
					IF OPS.name # proc.name THEN err(4) END;
					OPS.Get(sym)
				ELSE err(ident)
				END
			END;
			
			IF mode = CProc THEN
				IF ~(asmProc IN proc.conval.setval) & ((proc.typ # OPT.notyp) OR (procdec # NIL)) THEN err(200) END;
				proc.code := statseq; procdec := NIL
			ELSE
				OPB.Enter(procdec, statseq, proc);
				procdec.conval := OPT.NewConst(); procdec.conval.intval := c;
			END;
			x := procdec;
		END Body;
		
		PROCEDURE Receiver;
			VAR obj: OPT.Object;
		BEGIN
			IF IsObjectScope() THEN
				mode := TProc;
				selfmode := VarPar; selfname := HiddenSelf; selftype := OPT.topScope.link.typ; selfrec := selftype
			ELSIF (sym = lparen) & Oberon2 THEN
				mode := TProc; OPS.Get(sym);
				IF sym = var THEN selfmode := VarPar; OPS.Get(sym) ELSE selfmode := Var END;
				selfname := OPS.name; CheckSym(ident); CheckSym(colon);
				IF sym = ident THEN OPT.Find (obj); OPS.Get(sym);
					IF obj = NIL THEN err(0)
					ELSIF obj^.mode # Typ THEN err(72)
					ELSE selftype := obj^.typ; selfrec := selftype;
						IF selftype^.form = Pointer THEN selfrec := selfrec^.BaseTyp END ;
						IF ~((selfmode = Var) & (selftype^.form = Pointer) & (selfrec^.comp = Record) OR
							(selfmode = VarPar) & (selftype^.comp = Record)) THEN err(70); (*rec := NIL*) END ;
						IF (selfrec # NIL) & (selfrec^.mno # level) THEN err(72); (*rec := NIL*) END;
						IF selfrec.comp = Record THEN OPT.topScope := selfrec.strobj.scope END;
					END
				ELSE err(ident)
				END;
				CheckSym(rparen)
			END
		END Receiver;
		
	BEGIN
		(* init vars *)
		forward := FALSE; scope := OPT.topScope;
		proc := NIL; x := NIL; mode := LProc; init := FALSE; flags := {};
		prio := 0;

		IF sym = arrow THEN forward := TRUE; OPS.Get(sym) END;
		Receiver;	(* set mode + scope + selfXYZ vars *)
		
		(* special modes *)
		IF (sym # ident) & (sym # string) & (sym # number) THEN
			IF sym = times THEN	(* mode set later in OPB.CheckAssign *)
			ELSIF sym = plus THEN
				IF mode = TProc THEN err(47) END;
				mode := IProc; 
				IF ~OPT.SYSimported THEN err(135) END ;
			ELSIF sym = and THEN init := TRUE;
				IF ~IsObjectScope() & ~IsModuleScope() THEN err(253) END;
				IF (OPT.topScope.link.link2 # NIL) & (OPT.topScope.link.link2.link.scope = OPT.topScope) THEN err(144) END
			ELSIF sym = minus THEN
				IF mode = TProc THEN err(47) END;
				mode := CProc
			ELSE err(ident)
			END;
			OPS.Get (sym)
		END;
		IF (sym=number) OR (sym=string) THEN
			OPS.CheckOperator(prio);
			IF prio=126 THEN
				sym:=ident;
				IF IsObjectScope() THEN err(140)
				ELSIF ~forward & (operatorFlag IN OPT.topScope.conval.setval) THEN err(-212)
				END
			ELSE
				err(142)
			END
		ELSIF ~IsObjectScope() THEN INCL(OPT.topScope.conval.setval, operatorFlag)
		END;

		IF (sym = ident) OR (sym=number) OR (sym=string) THEN OPT.Find (fwd);
			name := OPS.name; CheckMark(vis, TRUE);
			IF init THEN vis := external END;
			IF (vis # internal) & (mode = LProc) THEN mode := XProc END ;

			(* false forwards *)
			IF (fwd # NIL) & (~(fwd.mode IN {TProc, LProc, XProc, CProc, IProc}) OR ((fwd.mnolev >= 0) & (fwd.mnolev # level)) OR ((mode=TProc) & (fwd.mode#TProc)) OR (prio=126)) THEN 
				fwd := NIL
			END;
			redef := (fwd # NIL) & (mode = TProc) & (fwd.mode = TProc) & (selfrec # fwd.link.typ) & (selfrec # fwd.link.typ.BaseTyp) ;
			IF (fwd = NIL) OR redef THEN
				OPT.Insert (name, proc);
				(* special case for o2-methods in an empty record *)
				IF (scope # OPT.topScope) & (selfrec.link = NIL) THEN selfrec.link := OPT.topScope.right END;
				proc.prio := prio
			ELSE
				IF vis # fwd.vis THEN err(118) END;
				IF hasBody IN fwd.conval.setval THEN err(1) END;
				proc := OPT.NewObj(); proc^.leaf := TRUE;
			END;
			
			proc.mode := mode; proc.vis := vis;
			proc.conval := OPT.NewConst(); proc.conval.setval := flags;
			
			(* general limitations and link setup *)
			IF (mode # LProc) & (level > 0) THEN err(73) END ;
			IF init THEN OPT.topScope.link.link2 := proc END;
			
			(* parse params+body *)
			OPT.topScope := scope;
			INC(level); OPT.OpenScope(level, proc); OPT.topScope.adr := OPM.errpos;
			OPT.topScope.conval := OPT.NewConst();
			GetParam;
			IF ~forward THEN Body END;
			DEC(level); OPT.CloseScope;
			
		ELSE err(ident)
		END;
	END ProcedureDeclaration;

	PROCEDURE CaseLabelList(VAR lab: OPT.Node; LabelForm: INTEGER; VAR n: INTEGER; VAR tab: CaseTable);
		VAR x, y, lastlab: OPT.Node; i, f: INTEGER; xval, yval: LONGINT;
	BEGIN lab := NIL; lastlab := NIL;
		LOOP ConstExpression(x); f := x^.typ^.form;
			IF f IN intSet + {Char} THEN  xval := x^.conval^.intval
			ELSE err(61); xval := 1
			END ;
			IF f IN intSet THEN
				IF LabelForm < f THEN err(60) END
			ELSIF LabelForm # f THEN err(60)
			END ;
			IF sym = upto THEN
				OPS.Get(sym); ConstExpression(y); yval := y^.conval^.intval;
				IF (y^.typ^.form # f) & ~((f IN intSet) & (y^.typ^.form IN intSet)) THEN err(60) END ;
				IF yval < xval THEN err(63); yval := xval END
			ELSE yval := xval
			END ;
			x^.conval^.intval2 := yval;
			(*enter label range into ordered table*)  i := n;
			IF i < OPM.MaxCases THEN
				LOOP
					IF i = 0 THEN EXIT END ;
					IF tab[i-1].low <= yval THEN
						IF tab[i-1].high >= xval THEN err(62) END ;
						EXIT
					END ;
					tab[i] := tab[i-1]; DEC(i)
				END ;
				tab[i].low := xval; tab[i].high := yval; INC(n)
			ELSE err(213)
			END ;
			OPB.Link(lab, lastlab, x);
			IF sym = comma THEN OPS.Get(sym)
			ELSIF (sym = number) OR (sym = ident) THEN err(comma)
			ELSE EXIT
			END
		END
	END CaseLabelList;

	PROCEDURE CheckBool(VAR x: OPT.Node);
	BEGIN
		IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126); x := OPB.NewBoolConst(FALSE)
		ELSIF x.typ = NIL THEN err(120); x := OPB.NewBoolConst(FALSE)
		ELSIF x^.typ^.form # Bool THEN err(120); x := OPB.NewBoolConst(FALSE)
		END ;
	END CheckBool;

	PROCEDURE DoFixes;
		VAR id, obj, typ, fpar, topscope, scope: OPT.Object; x, y, z, link, apar: OPT.Node; conval: OPT.Const; i: LONGINT;
	BEGIN
		FixPhase := TRUE; topscope := OPT.topScope; i := 0;
		WHILE nofTypeFix > i DO OPM.errpos := TypeFix[i].pos;

			OPT.FindInScope (TypeFix[i].name, OPT.topScope, typ);
			IF typ = NIL THEN	err (0)
			ELSIF typ.mode # Typ THEN	err (52)
			ELSE
				obj := TypeFix[i].obj; typ := typ.typ.strobj;
				IF obj.mode = Typ THEN
					obj.typ.BaseTyp := typ.typ;
					IF obj.typ.comp = Record THEN
						obj.scope.left := typ.scope;
						obj.typ.extlev := typ.typ.extlev + 1;
						IF obj.link2 = NIL THEN obj.link2 := typ.link2 END;
						IF passiveObj IN GetFlags (typ) THEN SetFlags (obj, {passiveObj}) END
					END
				ELSE
					obj.mode := ABS(obj.mode); obj.typ := typ.typ;
					IF (typ.typ.comp = Record) & (activeObj IN GetFlags(typ)) THEN err(254) END;
					IF (typ.typ.comp = Record) & (needPointer IN GetFlags(typ)) THEN err(256) END;
					IF (obj.mode = TProc) & (isRedef IN GetFlags(obj)) THEN
						IF (obj.link.typ.BaseTyp # NIL) & (obj.link.typ.BaseTyp.strobj # NIL) & (obj.link.typ.BaseTyp.strobj.scope # NIL) THEN
							OPT.FindInScope (obj.name, obj.link.typ.BaseTyp.strobj.scope, id)
						ELSE err (117)
						END;
						IF id = NIL THEN err (1008)
						ELSIF id.typ # obj.typ THEN err (117)
						END
					END
				END
			END;
			INC (i)
		END;
		
		WHILE FixList # NIL DO
			OPT.topScope := FixList.scope; OPS.StartPlaying (FixList.stream); x := FixList.node; OPS.Get (sym);
			nofFwdPtr := FixList.nofFwd;
			link := x.link; x.link := NIL; conval := x.conval; x.conval := NIL;

			CASE FixList.mode OF
			| FTarget:

					NEW(y); y := x^.left;
					qualident (id); z := OPB.NewLeaf (id); selector (z); OPB.Assign (z, y)
			| FExpr:

					NEW(z); z^ := x^;
					Expression (y); OPB.Assign (z, y)
			| FAssign:

					qualident(id); z := OPB.NewLeaf(id); selector(z);
					IF sym = becomes THEN
						OPS.Get(sym); Expression(y); OPB.Assign(z, y)
					ELSE err (1002)
					END
			| FCall:

					qualident(id);
					z := OPB.NewLeaf(id); selector(z);
					IF (z^.class = Nproc) & (z^.obj^.mode = SProc) THEN
						StandProcCall(z);
						IF (z # NIL) & (z^.typ # OPT.notyp) THEN err(55) END
					ELSE OPB.PrepCall(z, fpar);
						IF sym = lparen THEN
							OPS.Get(sym); ActualParameters(apar, fpar, z); CheckSym(rparen)
						ELSE apar := NIL;
							IF fpar # NIL THEN err(65) END
						END ;
						IF (z^.class = Nproc) & (z^.obj^.mode = CProc) THEN InlineProc (z, apar, fpar)
						ELSE OPB.Call(z, apar, fpar)
						END;
						IF z^.typ # OPT.notyp THEN err(55) END ;
						IF level > 0 THEN OPT.topScope^.link^.leaf := FALSE END
					END ;
			| FCond:

					Expression (z); CheckBool (z);
					conval := z.conval
			| FParam:

					obj := x.obj;
					Expression (z);  OPB.Param (z, obj)
			| FPassExpr:

					(* sym = PASSIVATE *)
					OPS.Get (sym); (* sym = "(" *)
					OPS.Get (sym);
					UsesGlobals := FALSE;
					scope := OPT.topScope;
					WHILE (scope # NIL) & ~(scope.link.mode IN {Typ, Mod}) DO scope := scope^.left END;
					ObjLocal := (scope # NIL) & (scope.link.mode = Typ);
					UsesGlobals := (scope = NIL) OR ~(passiveObj IN GetFlags(scope.link));(* if the scope isn't protectable, local evaluation has no sense *)
					Expression (z);
					OPB.StPar0(z, passivatefn);
					IF sym = comma THEN OPS.Get(sym);
						Expression(y);
						UsesGlobals := y.conval.intval = 1;
						(*IF y # OPT.booltyp THEN err(113) END*)
					END;
					obj := GetSelf();
					IF UsesGlobals & (obj.typ # OPT.sysptrtyp (*has the td here*)) THEN
						SetFlags (obj.typ.strobj, {needPointer})
					END
			| FPassHint:

					z := OPB.NewBoolConst (UsesGlobals)
			| FReturn:
					Expression (z); OPB.Return(z, OPT.topScope^.link)
			END;
			IF z = NIL THEN
				(* construct a NOP node -> ninittd don't generate code !! this is not clean !! *)
				OPB.Construct (Ninittd, z, NIL)
			END;
			x^ := z^; x.link := link; x.conval := conval;
			FixList := FixList.next
		END;
		OPT.topScope := topscope
	END DoFixes;

	PROCEDURE StatSeq(VAR stat: OPT.Node);
		VAR fpar, id, t, obj, owner: OPT.Object; idtyp: OPT.Struct; e: BOOLEAN;
				x1, x2, s, x, y, z, apar, last, lastif: OPT.Node; pos: LONGINT;
				ts: OPS.TokenStream;

		PROCEDURE CasePart(VAR x: OPT.Node);
			VAR n: INTEGER; low, high: LONGINT; e: BOOLEAN;
					tab: CaseTable; cases, lab, y, lastcase: OPT.Node; 
		BEGIN
			Expression(x); pos := OPM.errpos;
			IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
			ELSIF ~(x^.typ^.form IN {Char..LInt}) THEN err(125)
			END ;
			CheckSym(of); cases := NIL; lastcase := NIL; n := 0;
			LOOP
				IF sym < bar THEN
					CaseLabelList(lab, x^.typ^.form, n, tab);
					CheckSym(colon); StatSeq(y);
					OPB.Construct(Ncasedo, lab, y); OPB.Link(cases, lastcase, lab)
				END ;
				IF sym = bar THEN OPS.Get(sym) ELSE EXIT END
			END ;
			IF n > 0 THEN low := tab[0].low; high := tab[n-1].high;
				IF high - low > OPM.MaxCaseRange THEN err(209) END
			ELSE low := 1; high := 0; err (213)
			END ;
			e := sym = else;
			IF e THEN OPS.Get(sym); StatSeq(y) ELSE y := NIL END ;
			OPB.Construct(Ncaselse, cases, y); OPB.Construct(Ncase, x, cases);
			cases^.conval := OPT.NewConst();
			cases^.conval^.intval := low; cases^.conval^.intval2 := high;
			IF e THEN cases^.conval^.setval := {1} ELSE cases^.conval^.setval := {} END
		END CasePart;
		
		PROCEDURE SetPos(x: OPT.Node);
		BEGIN
			x^.conval := OPT.NewConst(); x^.conval^.intval := pos
		END SetPos;

	BEGIN stat := NIL; last := NIL; UndefFlag := FALSE;
		LOOP x := NIL;
			IF sym < ident THEN err(14);
				REPEAT OPS.Get(sym) UNTIL sym >= ident
			END ;
			IF UndefFlag THEN err (1001); UndefFlag := FALSE END;
			IF sym = ident THEN
				OPS.StartRecording (sym);
				qualident(id); x := OPB.NewLeaf(id); selector(x);
				IF sym = becomes THEN
					OPS.Get(sym);
					IF UndefFlag THEN UndefFlag := FALSE; x := NIL;
						Expression (x); OPS.StopRecording (ts);
						IF UndefFlag THEN InsertFix (FAssign, ts, x); UndefFlag := FALSE
						ELSE OPB.Construct (Ntrap(*dummy*), x, NIL); InsertFix (FTarget, ts, x) END
					ELSE OPS.StartRecording (sym); Expression(y); OPS.StopRecording (ts);
						IF UndefFlag THEN InsertFix (FExpr, ts, x); UndefFlag := FALSE
						ELSE 
							OPB.Assign(x, y)
						END
					END
				ELSIF sym = eql THEN
					err(becomes); OPS.Get(sym); Expression(y); OPB.Assign(x, y)
				ELSIF (x^.class = Nproc) & (x^.obj^.mode = SProc) THEN
					StandProcCall(x);
					OPS.StopRecording (ts);
					IF UndefFlag THEN UndefFlag := FALSE; InsertFix (FCall, ts, x)
					ELSIF (x # NIL) & (x^.typ # OPT.notyp) THEN err(55)
					END;
				ELSE 
					IF ~UndefFlag THEN OPB.PrepCall(x, fpar) END;
					IF sym = lparen THEN
						OPS.Get(sym); ActualParameters(apar, fpar, x); CheckSym(rparen)
					ELSE apar := NIL;
						IF (fpar # NIL) & ~UndefFlag THEN err(65) END
					END ;
					IF ~UndefFlag THEN 
						IF (x^.class = Nproc) & (x^.obj^.mode = CProc) THEN InlineProc (x, apar, fpar)
						ELSE OPB.Call(x, apar, fpar) END
					END;
					IF ~UndefFlag & (x^.typ # OPT.notyp) THEN err(55) END ;
					OPS.StopRecording(ts);
					IF UndefFlag THEN UndefFlag := FALSE; InsertFix (FCall, ts, x) END;
					IF level > 0 THEN OPT.topScope^.link^.leaf := FALSE END
				END ;
				pos := OPM.errpos
			ELSIF sym = if THEN
				OPS.Get(sym);
				OPS.StartRecording (sym); Expression(x); OPS.StopRecording (ts);
				IF UndefFlag THEN InsertFix (FCond, ts, x); UndefFlag := FALSE
				ELSE CheckBool(x)
				END;
				CheckSym(then); StatSeq(y);
				OPB.Construct(Nif, x, y); SetPos(x); lastif := x;
				WHILE sym = elsif DO
					OPS.Get(sym);
					OPS.StartRecording (sym); Expression(y); OPS.StopRecording (ts);
					IF UndefFlag THEN InsertFix (FCond, ts, y); UndefFlag := FALSE
					ELSE CheckBool(y)
					END;
					CheckSym(then); StatSeq(z);
					OPB.Construct(Nif, y, z); SetPos(y); OPB.Link(x, lastif, y);
				END ;
				IF sym = else THEN OPS.Get(sym); StatSeq(y)
				ELSE y := NIL
				END ;
				OPB.Construct(Nifelse, x, y); CheckSym(end); OPB.OptIf(x); pos := OPM.errpos
			ELSIF sym = case THEN
				OPS.Get(sym); CasePart(x); CheckSym(end)
			ELSIF sym = while THEN
				OPS.Get(sym);
				OPS.StartRecording (sym); Expression(x); OPS.StopRecording (ts);
				IF UndefFlag THEN InsertFix (FCond, ts, x); UndefFlag := FALSE
				ELSE CheckBool(x)
				END;
				CheckSym(do); StatSeq(y);
				OPB.Construct(Nwhile, x, y); CheckSym(end)
			ELSIF sym = repeat THEN
				OPS.Get(sym); StatSeq(x);
				IF sym = until THEN OPS.Get(sym);
					OPS.StartRecording (sym); Expression(y); OPS.StopRecording (ts);
					IF UndefFlag THEN InsertFix (FCond, ts, y); UndefFlag := FALSE
					ELSE CheckBool(y)
					END
				ELSE err(until)
				END ;
				OPB.Construct(Nrepeat, x, y)
			ELSIF sym = for THEN
				OPS.Get(sym);
				IF sym = ident THEN
					qualident(id); x := OPB.NewLeaf(id); selector (x);
					OPB.CopyAndSubst (x1, x); OPB.CopyAndSubst (x2, x);
					IF ~(x^.typ^.form IN intSet) THEN err(68) END;
					CheckSym(becomes);
					Expression(y); pos := OPM.errpos; OPB.Assign(x, y); SetPos(x);
					CheckSym(to); Expression(y); pos := OPM.errpos;
					IF y^.class # Nconst THEN
						owner := OPT.topScope;
						WHILE (OPT.topScope.left # NIL) & (OPT.topScope.link = OPT.topScope.left.link) DO
							OPT.topScope := OPT.topScope.left
						END;
						OPT.Insert("@@", t); t^.name := "@for"; t^.mode := Var; t^.typ := x^.left^.typ;
						obj := OPT.topScope^.scope;
						IF obj = NIL THEN OPT.topScope^.scope := t
						ELSE
							WHILE obj^.link # NIL DO obj := obj^.link END ;
							obj^.link := t
						END ;
						OPT.topScope := owner;
						z := OPB.NewLeaf(t); OPB.Assign(z, y); SetPos(z); OPB.Link(stat, last, z);
						y := OPB.NewLeaf(t)
					ELSIF (y^.typ^.form < SInt) OR (y^.typ^.form > x^.left^.typ^.form) THEN err(113)
					END ;
					OPB.Link(stat, last, x);
					IF sym = by THEN OPS.Get(sym); ConstExpression(z) ELSE z := OPB.NewIntConst(1) END ;
					pos := OPM.errpos;
					x := x1;				(* use the copy of x *)
					IF z^.conval^.intval > 0 THEN OPB.Op(leq, x, y)
					ELSIF z^.conval^.intval < 0 THEN OPB.Op(geq, x, y)
					ELSE err(63); OPB.Op(geq, x, y)
					END ;
					CheckSym(do); StatSeq(s);
					y := x2;				(* use the copy of x *)
					OPB.StPar1(y, z, incfn); SetPos(y);
					IF s = NIL THEN s := y
					ELSE z := s;
						WHILE z^.link # NIL DO z := z^.link END ;
						z^.link := y
					END ;
					CheckSym(end); OPB.Construct(Nwhile, x, s)
				ELSE err(ident)
				END
			ELSIF sym = loop THEN
				OPS.Get(sym); INC(LoopLevel); StatSeq(x); DEC(LoopLevel);
				OPB.Construct(Nloop, x, NIL); CheckSym(end); pos := OPM.errpos
			ELSIF sym = with THEN
				OPS.Get(sym); idtyp := NIL; x := NIL;
				LOOP
					IF sym = ident THEN
						qualident(id); y := OPB.NewLeaf(id);
						IF (id # NIL) & (id^.typ^.form = Pointer) & ((id^.mode = VarPar) OR ~id^.leaf) THEN
							err(-302)	(* warning 302 *)
						END ;
						CheckSym(colon);
						IF sym = ident THEN qualident(t);
							IF t^.mode = Typ THEN
								IF id # NIL THEN
									idtyp := id^.typ; OPB.TypTest(y, t, FALSE);
									IF id.mnolev # 0 THEN id^.typ := t^.typ
									ELSE
										owner := OPT.topScope^.link; OPT.OpenScope (level, owner);
										OPT.Insert (id.name, obj); obj^.mode := id^.mode; obj^.scope := id;
										obj^.typ := t^.typ
									END
								ELSE err(130)
								END
							ELSE err(52)
							END
						ELSE err(ident)
						END
					ELSE err(ident)
					END ;
					pos := OPM.errpos; CheckSym(do); StatSeq(s); OPB.Construct(Nif, y, s); SetPos(y);
					IF id.mnolev # 0 THEN
						id^.typ := idtyp
					ELSE
						IF idtyp # NIL THEN OPT.CloseScope; owner^.scope := OPT.topScope; idtyp := NIL END ;
					END;
					IF x = NIL THEN x := y; lastif := x ELSE OPB.Link(x, lastif, y) END ;
					IF (sym = bar) & Oberon2 THEN OPS.Get(sym) ELSE EXIT END
				END;
				e := sym = else;
				IF e & Oberon2 THEN OPS.Get(sym); StatSeq(s) ELSE s := NIL END ;
				OPB.Construct(Nwith, x, s); CheckSym(end); 
				IF e THEN x^.subcl := 1 END
			ELSIF sym = exit THEN
				OPS.Get(sym);
				IF LoopLevel = 0 THEN err(38) END ;
				OPB.Construct(Nexit, x, NIL);
				pos := OPM.errpos
			ELSIF sym = return THEN OPS.Get(sym);
				IF sym < semicolon THEN OPS.StartRecording (sym); Expression(x); OPS.StopRecording (ts) END ;
				IF UndefFlag OR (OPT.topScope.link.typ = NIL) THEN InsertFix (FReturn, ts, x); UndefFlag := FALSE
				ELSE
					IF level > 0 THEN OPB.Return(x, OPT.topScope^.link)
					ELSE (* not standard Oberon *) OPB.Return(x, NIL)
					END
				END;
				pos := OPM.errpos
			END ;
			IF UndefFlag THEN	err (1000); UndefFlag := FALSE	END;
			IF x # NIL THEN SetPos(x); OPB.Link(stat, last, x) END ;
			IF sym = semicolon THEN OPS.Get(sym)
			ELSIF (sym <= ident) OR (if <= sym) & (sym <= return) THEN err(semicolon)
			ELSE EXIT
			END
		END
	END StatSeq;

	PROCEDURE Block(VAR procdec, statseq: OPT.Node);
		VAR typ: OPT.Struct;
			obj, first, last, dmy: OPT.Object;
			x, lastdec: OPT.Node;
			i, pos: LONGINT; name: OPS.Name;
			fixpos: INTEGER;		(* save fwd pointers of the upper scope when tbp are defined *)

	BEGIN first := NIL; last := NIL; fixpos := nofFwdPtr; 
	procdec := NIL; lastdec := NIL;
		LOOP
			IF (sym = const) THEN
				OPS.Get(sym);
				WHILE sym = ident DO
					OPT.Insert(OPS.name, obj); CheckMark(obj^.vis, FALSE);
					IF IsObjectScope() & (obj.vis = external) THEN err (47) END;		(* <- prevent export, implementation restriction *)
					obj^.typ := OPT.sinttyp; obj^.mode := Var;	(* Var to avoid recursive definition *)
					IF sym = eql THEN
						OPS.Get(sym); ConstExpression(x)
					ELSIF sym = becomes THEN
						err(eql); OPS.Get(sym); ConstExpression(x)
					ELSE err(eql); x := OPB.NewIntConst(1)
					END ;
					obj^.mode := Con; obj^.typ := x^.typ; obj^.conval := x^.conval; (* ConstDesc ist not copied *)
					CheckSym(semicolon)
				END
			END ;
			IF (sym = type) THEN
				(*IF IsObjectScope() THEN err(41) END;*)
				OPS.Get(sym);
				WHILE sym = ident DO
					OPT.Insert(OPS.name, obj); obj^.mode := Typ; obj^.typ := OPT.undftyp;
					x := NIL;
					CheckMark(obj^.vis, FALSE);
					IF sym = eql THEN
						OPS.Get(sym); TypeDecl(x, obj^.typ, obj^.typ, obj)
					ELSIF (sym = becomes) OR (sym = colon) THEN
						err(eql); OPS.Get(sym); TypeDecl(x, obj^.typ, obj^.typ, obj)
					ELSE err(eql)
					END ;
					IF x # NIL THEN	(* insert x into parse tree *)
						x.obj := obj;		(* link code to the type *)
						OPB.Link (RecInit, lastRecInit, x);
(*
						x.obj := obj;		(* link code to the type *)
						IF lastdec = NIL THEN procdec := x ELSE lastdec^.link := x END ;
						lastdec := x;
						WHILE lastdec.link # NIL DO lastdec := lastdec.link END
*)
					END ;
					IF (obj^.typ^.comp = Record) & (sym = ident) THEN
						IF obj^.name # OPS.name THEN err(4)
						END;
						OPS.Get(sym)
					END;
					IF obj^.typ^.strobj = NIL THEN obj^.typ^.strobj := obj END ;
					IF obj^.conval = NIL THEN obj^.conval := OPT.NewConst() END;
					IF (obj^.typ^.comp = Record) & ((obj^.link # NIL) OR (obj^.link2 # NIL)) THEN
						SetFlags (obj, {needPointer})
					END;
					IF (obj^.typ^.comp IN {Record, Array, SDynArr, DynArr}) OR 
						((obj.typ.form = Pointer) & obj.typ.init) THEN
						i := fixpos;
						WHILE i < nofFwdPtr DO typ := FwdPtr[i]; INC(i);
							IF typ^.link^.name = obj^.name THEN
								IF obj^.typ^.comp IN {Record, Array, SDynArr, DynArr} THEN
									typ^.BaseTyp := obj^.typ; (*typ^.link^.name := "" *)
								ELSE typ.BaseTyp := obj.typ.BaseTyp
								END;
							END
						END
					END ;
					CheckSym(semicolon)
				END;
				IF OPT.topScope.scope#NIL THEN
					first:=OPT.topScope.scope;
					WHILE first^.link#NIL DO first:=first^.link END;
					last:=first; first:=NIL
				END
			END ;
			IF (sym = var) OR (IsObjectScope() & (sym = ident)) THEN
				IF sym = var THEN OPS.Get(sym) END;
				WHILE sym = ident DO
					LOOP
						IF sym = ident THEN
							IF IsObjectScope() THEN	(* If this is a record field, then check overriding *)
								OPT.Find(obj);
								IF (obj # NIL) & (obj.mode IN {Fld, TProc}) THEN err(1) END
							END;
							OPT.Insert(OPS.name, obj); CheckMark(obj^.vis, TRUE);
							IF IsObjectScope() THEN
								obj.conval := OPT.NewConst(); obj.conval.intval := OPM.errpos;
								obj^.mode := Fld;

							ELSE
								obj^.mode := Var; obj^.leaf := obj^.vis = internal; 
							END;
							obj^.link := NIL; obj^.typ := OPT.undftyp; obj.myscope:=OPT.topScope;
							IF first = NIL THEN first := obj END ;
							IF last = NIL THEN 
								IF IsObjectScope() THEN OPT.topScope^.link^.typ^.link := obj 
								ELSE OPT.topScope^.scope := obj
								END
							ELSE last^.link := obj END ;
							last := obj
						ELSE err(ident)
						END ;
						IF sym = comma THEN OPS.Get(sym)
						ELSIF sym = ident THEN err(comma)
						ELSE EXIT
						END
					END ;
					CheckSym(colon); Type(typ, OPT.notyp);
					IF IsObjectScope() & (OPT.topScope.link.typ = typ) THEN	err (58)	END;

					IF typ^.comp = DynArr THEN typ := OPT.undftyp; err(88) END ;
					WHILE first # NIL DO
						IF (typ = OPT.undftyp)  THEN
							first.mode := -first.mode;	(* mark variable *)
							InsertTypeFix (OPS.name, first)
						END;
						first^.typ := typ;
						first := first^.link
					END ;
					IF (typ.comp = Record) & (activeObj IN GetFlags(typ.strobj)) THEN err(254) END;
					IF (typ.comp = Record) & (needPointer IN GetFlags(typ.strobj)) THEN err(256) END;
					IF ~IsObjectScope() OR (sym # end) THEN CheckSym(semicolon) END
				END
			END ;
			IF sym = procedure THEN
				OPS.Get(sym); ProcedureDeclaration(x);
				IF x # NIL THEN
					IF lastdec = NIL THEN procdec := x ELSE lastdec^.link := x END ;
					lastdec := x;
				END ;
				CheckSym(semicolon)
			END;
			IF (sym < const) OR (sym > procedure) THEN EXIT END ;
		END ;	(* LOOP *)
		i := fixpos;
		WHILE i < nofFwdPtr DO
			IF FwdPtr[i]^.BaseTyp = OPT.undftyp THEN err(128) END ;
			INC(i)
		END ;
		nofFwdPtr := fixpos;
		OPT.topScope^.adr := OPM.errpos;
		IF IsObjectScope() & (last = NIL) THEN
			OPT.topScope^.link^.typ^.link := OPT.topScope^.right
		END;

		CondNodes := NIL; CondCount := 0;
		IF sym = begin THEN 
			IF IsObjectScope() (*OR IsScopeOf(TProc)*) THEN			(* object body, pointer required *)
				(* search for the pointer to this object *)
(*
				i := nofFwdPtr-1;
				WHILE (i>=0) & (FwdPtr[i]^.link^.name # OPT.topScope.link.name) DO DEC(i) END;
				IF i<0 THEN err(252);
					typ := OPT.NewStr(Pointer, Basic); typ^.BaseTyp := OPT.topScope^.link^.typ;
				ELSE
					typ := FwdPtr[i];
					typ^.BaseTyp := OPT.topScope.link.typ; typ^.link^.name := "";
				END;
*)
				typ := OPT.topScope.link.typ.ptr;
				IF typ = NIL THEN				(* no pointer to record declared yet! *)
					typ := OPT.NewStr(Pointer, Basic); typ^.BaseTyp := OPT.topScope^.link^.typ;
					typ.BaseTyp.ptr := typ
				END;
				OPT.Insert(HiddenSelf, obj); obj^.mode := Var; obj^.typ := typ;
				obj^.adr := OPM.errpos; obj.mnolev := 1 (*level*);
				obj^.link := NIL;
				OPT.topScope^.link^.link := obj;	(* set parameter list *)
			END;
			OPS.Get(sym); 
			IF (sym = lbrace) & OPM.allowProcesses THEN	(* Body Specifiers *)
				OPS.Get(sym);
				BodyMode (OPT.topScope^.link^.conval^.setval);
			END;
			SetFlags (OPT.topScope^.link, {hasBody});
			StatSeq(statseq); CheckSym(end);
			IF locked IN GetFlags(OPT.topScope^.link) THEN
				OPB.Lock(statseq, GetSelf(), ~(shared IN GetFlags(OPT.topScope^.link)));
				statseq^.conval := OPT.NewConst(); statseq^.conval^.intval := OPM.errpos
			END;
			IF (CondNodes # NIL) & ~IsObjectScope() THEN
				IF lastdec = NIL THEN procdec := CondNodes ELSE lastdec^.link := CondNodes END ;
				lastdec := CondNodes
			END;
		ELSIF sym = code THEN 		(* iASM *)
			pos := OPM.errpos; SetFlags(OPT.topScope^.link, {asmProc});
			ASM.Assemble(statseq); 
			IF statseq # NIL THEN statseq^.conval := OPT.NewConst(); statseq^.conval^.intval := pos END;
			OPS.Get(sym)
		ELSE 
			IF IsObjectScope() & (OPT.topScope.link.typ.BaseTyp # NIL) THEN	(* inherit body *)
				obj := OPT.topScope.link;
				(*obj.link := obj.typ.BaseTyp.strobj.link;*)		(* don't link! It will be traversed two times! *)
				SetFlags (obj, GetFlags(obj.typ.BaseTyp.strobj) - {hasBody})
			END;
			statseq := NIL; CheckSym(end)
		END ;
		IF (level = 0) & (TDinit # NIL) & IsModuleScope() THEN
			lastTDinit^.link := statseq; statseq := TDinit
		END ;
		IF (level = 0) & (RecInit # NIL) & IsModuleScope() THEN
			OPB.Link (procdec, lastdec, RecInit);
		END ;
	END Block;

	PROCEDURE Module*(VAR prog: OPT.Node; VAR modName: OPS.Name; opt: SET; systemchk: BOOLEAN);
		VAR impName, aliasName: OPS.Name;
				procdec, statseq: OPT.Node;
				c: LONGINT;
				mod: OPT.Object;
	BEGIN
		suppressOX := FALSE;
		nofFwdPtr := 0;
		UndefObj := OPT.NewObj(); UndefObj^.mode := Var; UndefObj^.typ := OPT.undftyp; UndefObj^.adr := 0;
		FixList := NIL; nofTypeFix := 0; FixPhase := FALSE; UndefFlag := FALSE;
		FixLast := NIL;
		LoopLevel := 0; level := 0; ParameterMode:=FALSE;
		Oberon2 := 19 IN opt;
		OPS.Get(sym);
		IF sym = module THEN OPS.Get(sym) ELSE err(16) END ;
		IF sym = ident THEN

			mod := OPT.NewObj(); mod.scope := OPT.topScope; OPT.topScope^.link := mod;
			OPT.topScope.conval:=OPT.NewConst();
			mod^.mode := Mod;
			mod^.conval := OPT.NewConst();
			INCL(mod^.conval^.setval, passiveObj);	(* module is always protected *)
	
			ExtObj := OPT.topScope;
			COPY(OPS.name, modName); OPS.Get(sym);
			COPY(modName, mod^.name);
			CheckSym(semicolon);
			IF sym = import THEN OPS.Get(sym);
				LOOP
					IF sym = ident THEN
						COPY(OPS.name, aliasName); COPY(aliasName, impName); OPS.Get(sym);
						IF sym = becomes THEN OPS.Get(sym);
							IF sym = ident THEN COPY(OPS.name, impName); OPS.Get(sym) ELSE err(ident) END
						END ;
							IF systemchk & (impName = "SYSTEM") THEN err(152)
							ELSE
								OPT.Import(aliasName, impName, modName)
							END
					ELSE err(ident)
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF sym = ident THEN err(comma)
					ELSE EXIT
					END
				END ;
				CheckSym(semicolon)
			END ;
			IF OPM.noerr THEN TDinit := NIL; lastTDinit := NIL; c := OPM.errpos;
				RecInit := NIL; lastRecInit := NIL;
				Block(procdec, statseq);
				OPB.Enter(procdec, statseq, NIL); prog := procdec;
				prog^.conval := OPT.NewConst(); prog^.conval^.intval := c;
				IF sym = ident THEN
					IF OPS.name # modName THEN err(4) END ;
					OPS.Get(sym)
				ELSE err(ident)
				END ;
				IF sym # period THEN err(period) END
			END
		ELSE err(ident)
		END ;
		TDinit := NIL; lastTDinit := NIL;
		RecInit := NIL; lastRecInit := NIL;

		IF OPM.noerr THEN DoFixes END;
		c := LEN(FwdPtr);
		WHILE c > 0 DO DEC (c); FwdPtr[c] := NIL END;
	END Module;

BEGIN
	SignOnMessage := "Active Oberon-X Parser / rml, prk"

END OPP.


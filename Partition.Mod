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

MODULE Partition;	(* pjm *)

IMPORT SYSTEM, Kernel, Disk, Texts, Fonts, Input, Oberon, In;

CONST
	MaxDrives* = 2;
	MaxParts* = 16;	(* max number of partitions *)
	BS = 512;	(* disk block size *)
	FreeSpace = 256;
	MinPartSize = 64;	(* absolute minimum number of blocks in Oberon partition (cleared to 0 in Create) *)

TYPE
	Raw = ARRAY 16 OF CHAR;
	Partition* = RECORD	(** single partition *)
		type*: INTEGER;
		letter*: CHAR;
		drive*: SHORTINT;
		boot*: BOOLEAN;
		primary*: BOOLEAN;
		start*, size*: LONGINT;
		ptsector, ptoffset: LONGINT;
		raw: Raw
	END;
	DiskParam* = RECORD	(** disk parameters *)
		cyls*, hds*, spt*, size*: LONGINT
	END;
	Info* = RECORD	(** all partitions and disk parameters *)
		ok*: BOOLEAN;
		numhd*: SHORTINT;
		hd*: ARRAY MaxDrives OF DiskParam;
		numpar*: SHORTINT;
		par*: ARRAY MaxParts OF Partition
	END;
	DiskBlock = ARRAY BS OF CHAR;

VAR
	verbose*: BOOLEAN;	(** Show detail *)
	parttype*: INTEGER;	(** Oberon partition type for Create *)
	InitViewer*: PROCEDURE;	(** Initialise the partition text viewer *)

(** Procedures for accessing the disk. *)
	GetBlocks*: PROCEDURE (drive: SHORTINT;  start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
	PutBlocks*: PROCEDURE (drive: SHORTINT;  start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
	GetParams*: PROCEDURE (drive: SHORTINT;  VAR cyls, hds, spt: LONGINT);
	NumDrives*: PROCEDURE (): SHORTINT;

(* writers and texts *)
	W, Wn: Texts.Writer;
	T: Texts.Text;

(* Partition table starts at 01BEH in partition table sector and consists
	of 4 records of the type:
	
	00    bootind: Types.Byte;
	01    head: Types.Byte;
	02    sectorcyl: Types.Byte;
	03    cyl: Types.Byte;
	04    type: Types.Byte;
	05    head2: Types.Byte;
	06    sector2cyl: Types.Byte;
	07    cyl2: Types.Byte;
	08    start: Types.DWord;
	12    num: Types.DWord
*)

(* WriteType - Write partition type *)

PROCEDURE WriteType(type: LONGINT);
VAR s: ARRAY 32 OF CHAR;
BEGIN
	CASE type OF	(* list from Linux fdisk *)
		1: s := "DOS12"	(* DOS 12-bit FAT *)
		|2: s := "XENIX"	(* XENIX root *)
		|3: s := "XENIX"	(* XENIX usr *)
		|4: s := "DOS16"	(* DOS 16-bit FAT <32M *)
		|5: s := "Extended"
		|6: s := "DOS"	(* DOS 16-bit FAT >=32M *)
		|7: s := "HPFS/NTFS"	(* OS/2 HPFS or QNX or Advanced UNIX or NT FS *)
		|8: s := "AIX"	(* AIX data *)
		|9: s := "AIX"	(* AIX boot or Coherent *)
		|10: s := "BootMan"	(* OS/2 Boot Manager *)
		|16: s := "OPUS"
		|64: s := "Venix"	(* Venix 80286 *)
		|65: s := "Linux"	(* Linux/MINIX (sharing disk with DRDOS) *)
		|66: s := "LinuxSwp"	(* Linux swap (sharing disk with DRDOS) *)
		|67: s := "Linux"	(* Linux native (sharing disk with DRDOS) *)
		|78: s := "Active"
		|79: s := "Oberon"	(* new *)
		|80: s := "DM"
		|81: s := "DM6"	(* DM6 Aux1 (or Novell) *)
		|82: s := "CP/M"	(* CP/M or Microport SysV/AT *)
		|83: s := "DM6"	(* DM6 Aux3 *)
		|84: s := "DM6"
		|85: s := "EZD"
		|86: s := "GB"
		|97: s := "SpeedStor"
		|99: s := "Hurd"	(* GNU HURD or Mach or Sys V/386 (such as ISC UNIX) *)
		|100: s := "Net286"	(* Novell Netware 286 *)
		|101: s := "Net386"	(* Novell Netware 386 *)
		|117: s := "PC/IX"
		|128: s := "MINIX"	(* MINIX until 1.4a *)
		|129: s := "MINIX"	(* MINIX since 1.4b, early Linux *)
		|130: s := "Linux-Swap"	(* Linux swap *)
		|131: s := "Linux"	(* Linux native *)
		|147: s := "Amoeba"
		|148: s := "Amoeba"	(* Amoeba BBT (bad block table) *)
		|165: s := "BSD/386"
		|183: s := "BSD-Ifs"
		|184: s := "BSD-Iswap"
		|199: s := "Syrinx"
		|219: s := "CP/M"	(* Concurrent CP/M or Concurrent DOS or CTOS *)
		|225: s := "DOSa"	(* DOS access or SpeedStor 12-bit FAT extended partition *)
		|226: s := "Hybrid/Gneiss"
		|227: s := "Old-Oberon"	(* old Native Oberon or DOS R/O or SpeedStor *)
		|228: s := "SpeedStor"	(* SpeedStor 16-bit FAT extended partition *)
		|241: s := "SpeedStor"
		|242: s := "DOS3"	(* DOS 3.3+ secondary *)
		|244: s := "SpeedStor"
		|254: s := "LANstep"
		|255: s := "BBT"	(* bad track table *)
		|FreeSpace: s := "*free*"
		ELSE s := ""
	END;
	IF s # "" THEN
		Texts.WriteString(W, s)
	ELSE
		IF type < 0 THEN Texts.WriteString(W, "*ERROR*")
		ELSIF type # FreeSpace THEN Texts.WriteString(W, "type");  Texts.WriteInt(W, type, 1)
		END
	END
END WriteType;

(* Consistent - Check if logical and physical numbers are consistent *)

PROCEDURE Consistent(spt, hds, start, len: LONGINT;  VAR raw: Raw): BOOLEAN;
VAR sec, hd, cyl: LONGINT;  ok0: BOOLEAN;
BEGIN
	sec := start MOD spt + 1;  hd := (start DIV spt) MOD hds;
	cyl := start DIV (spt*hds);  ok0 := TRUE;
	IF (hd # ORD(raw[1])) OR (sec # ORD(raw[2]) MOD 64) OR
		(cyl # ASH(ASH(ORD(raw[2]), -6), 8) + ORD(raw[3])) THEN
		ok0 := FALSE
	END;
	sec := (start+len-1) MOD spt + 1;  hd := ((start+len-1) DIV spt) MOD hds;
	cyl := (start+len-1) DIV (spt*hds);
	IF (hd # ORD(raw[5])) OR (sec # ORD(raw[6]) MOD 64) OR
		(cyl # ASH(ASH(ORD(raw[6]), -6), 8) + ORD(raw[7])) THEN
		ok0 := FALSE
	END;
	RETURN ok0
END Consistent;

(* FindFreeSpace - Find free space on disk *)

PROCEDURE FindFreeSpace(numhd: SHORTINT;  VAR hd: ARRAY OF DiskParam;  VAR p: ARRAY OF Partition;  VAR n: SHORTINT);
VAR i, d: SHORTINT;  t, g, start0, start1, end: LONGINT;
BEGIN
	FOR d := 0 TO numhd-1 DO
		start0 := hd[d].spt;  g := hd[d].hds*hd[d].spt;
		LOOP
			t := MAX(LONGINT);
			FOR i := 0 TO n-1 DO	(* find first partition start after or on start0 *)
				IF p[i].primary & (p[i].drive = d) & (p[i].start >= start0) & (p[i].start < t) THEN
					t := p[i].start
				END
			END;
			IF t = MAX(LONGINT) THEN t := hd[d].size END;	(* end of disk *)
				(* {start0..t-1 is free} *)
			IF start0 = hd[d].spt THEN start1 := start0	(* first partition starts first cylinder, second head *)
			ELSE start1 := start0+((-start0) MOD g)	(* other partitions must start on cylinder boundary *)
			END;
				(* {start1..t-1 is free} *)
			t := t - (t MOD g);	(* partition must end on cylinder boundary *)
			IF t-start1 > 0 THEN
				p[n].type := FreeSpace;  p[n].letter := 0X;  p[n].drive := d;  p[n].boot := FALSE;
				p[n].primary := TRUE;  p[n].start := start1;  p[n].size := t-start1;
				p[n].ptsector := 0;  p[n].ptoffset := 0;	(* always sector 0 for primary, but find free ptoffset later *)
				FOR i := 0 TO 15 DO p[n].raw[i] := 0X END;
				INC(n)
			END;
			t := MAX(LONGINT);
			FOR i := 0 TO n-1 DO	(* find first partition end after start0 *)
				IF p[i].primary & (p[i].drive = d) THEN
					end := p[i].start+p[i].size-1;
					IF (end > start0) & (end < t) THEN
						t := end
					END
				END
			END;
			IF t = MAX(LONGINT) THEN
				EXIT	(* no more partitions end after start0 *)
			ELSE
				start0 := t+1
			END
		END
	END
END FindFreeSpace;

(* ReadPrimary - Read primary partition table entries into p *)

PROCEDURE ReadPrimary(numhd: SHORTINT;  VAR hd: ARRAY OF DiskParam;  VAR p: ARRAY OF Partition;
	VAR n: SHORTINT;  VAR ok: BOOLEAN);
VAR b: DiskBlock;  e, size, endi, endj: LONGINT;  d, i, j: SHORTINT;
BEGIN
	n := 0;  ok := TRUE;
	FOR d := 0 TO numhd-1 DO
		GetBlocks(d, 0, 1, b, 0);
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN
			FOR i := 0 TO 3 DO
				e := 01BEH + 16*i;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
				IF (b[e+4] # 0X) & (size # 0) THEN
					p[n].type := ORD(b[e+4]);  p[n].letter := 0X;  p[n].drive := d;
					SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  p[n].size := size;
					p[n].boot := (b[e] # 0X);  p[n].ptsector := 0;  p[n].ptoffset := e;
					p[n].primary := TRUE;  SYSTEM.MOVE(SYSTEM.ADR(b[e]), SYSTEM.ADR(p[n].raw[0]), 16);
					IF ~Consistent(hd[d].spt, hd[d].hds, p[n].start, size, p[n].raw) THEN
						p[n].type := -p[n].type;  ok := FALSE;
					END;
					INC(n)
				END
			END
		END
	END;
		(* some more consistency checks *)
	FOR i := 0 TO n-1 DO
		d := p[i].drive;  size := hd[d].size;
		IF (p[i].start < 0) OR (p[i].start >= size) OR (p[i].size < 0) OR (p[i].start+p[i].size > size) THEN
			p[i].type := -ABS(p[i].type);  ok := FALSE	(* partition i bigger than disk *)
		END;
		FOR j := 0 TO n-1 DO
			IF (i # j) & (d = p[j].drive) THEN
				endi := p[i].start+p[i].size-1;  endj := p[j].start+p[j].size-1;
				IF ((p[i].start >= p[j].start) & (p[i].start <= endj)) OR ((endi >= p[j].start) & (endi <= endj)) THEN
					p[i].type := -ABS(p[i].type);  p[j].type := -ABS(p[j].type);  ok := FALSE	(* partition i & j overlap *)
				END
			END
		END
	END;
	IF ok THEN FindFreeSpace(numhd, hd, p, n) END
END ReadPrimary;

(* ReadLogical - Read "logical drive" partitions into p *)

PROCEDURE ReadLogical(d: SHORTINT;  first: LONGINT;  VAR p: ARRAY OF Partition;  VAR n, letter: SHORTINT);
VAR b: DiskBlock;  e: LONGINT;  sec, size: LONGINT;
BEGIN
	sec := first;
	LOOP
		GetBlocks(d, sec, 1, b, 0);
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN
			e := 01BEH;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
			IF (b[e+4] = 5X) THEN HALT(99) END;
			IF size # 0 THEN
				p[n].type := ORD(b[e+4]);  p[n].drive := d;
				IF (p[n].type < 32) & (p[n].type IN {1,4,6,7}) THEN
					p[n].letter := CHR(letter);  INC(letter)
				ELSE
					p[n].letter := 0X
				END;
				SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  INC(p[n].start, sec);
				p[n].boot := (b[e] # 0X);  p[n].size := size;  p[n].primary := FALSE;
				p[n].ptsector := sec;  p[n].ptoffset := e;
				SYSTEM.MOVE(SYSTEM.ADR(b[e]), SYSTEM.ADR(p[n].raw[0]), 16);
				INC(n)
			END;
			INC(e, 16);  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
			IF (b[e+4] # 5X) OR (size = 0) THEN EXIT END;
			SYSTEM.GET(SYSTEM.ADR(b[e+8]), sec);  INC(sec, first)
		END
	END
END ReadLogical;

(* GetHDParams - Get hard disk parameters. *)

PROCEDURE GetHDParams(drive: SHORTINT; VAR cyls, hds, spt: LONGINT);
VAR buf: DiskBlock;  p, hd, sec, phd, psec: LONGINT;  ok: BOOLEAN;  i: SHORTINT;
BEGIN
	GetParams(drive, cyls, hds, spt);	(* get parameters from system setup *)
	GetBlocks(drive, 0, 1, buf, 0);	(* read sector 0 *)
	ok := TRUE;
	IF (buf[510] = 055X) & (buf[511] = 0AAX) THEN	(* valid partition table *)
		phd := -1;	(* find end head and sector for each valid primary partition *)
		FOR i := 0 TO 3 DO
			p := 01BEH + 16*i;
			IF buf[p+4] # 0X THEN	(* partition i in use *)
				hd := ORD(buf[p+5]); 	(* end head *)
				sec := ORD(buf[p+6]) MOD 64;	(* end sector *)
				IF phd = -1 THEN phd := hd;  psec := sec
				ELSIF (phd = hd) & (psec = sec) THEN (* skip *)
				ELSE ok := FALSE	(* inconsistent table *)
				END
			END
		END;
		IF ok & (phd # -1) THEN
			(* modify the parameters to be consistent with the table.  Assume drive will do remapping. *)
			cyls := cyls*hds*spt DIV ((phd+1)*psec);
			hds := phd+1;  spt := psec
		END
	ELSE (* skip *)
	END
END GetHDParams;

(** GetInfo - Get partition table information. *)

PROCEDURE GetInfo*(VAR di: Info);
VAR
	pt: ARRAY MaxParts OF Partition;
	pn, letter, i: SHORTINT;
BEGIN
	di.numhd := NumDrives();  di.numpar := 0;
	FOR i := 0 TO di.numhd-1 DO
		GetHDParams(i, di.hd[i].cyls, di.hd[i].hds, di.hd[i].spt);
		di.hd[i].size := di.hd[i].cyls*di.hd[i].hds*di.hd[i].spt
	END;
	ReadPrimary(di.numhd, di.hd, pt, pn, di.ok);
	letter := SHORT(ORD("C"));
	FOR i := 0 TO pn-1 DO
		IF (pt[i].type < 32) & (pt[i].type IN {1,4,6,7}) THEN
			pt[i].letter := CHR(letter);  INC(letter)
		END
	END;
	FOR i := 0 TO pn-1 DO
		di.par[di.numpar] := pt[i];  INC(di.numpar);
		IF pt[i].type = 5 THEN
			ReadLogical(pt[i].drive, pt[i].start, di.par, di.numpar, letter)
		END
	END;
END GetInfo;

PROCEDURE WriteHexByte(VAR W: Texts.Writer;  b: CHAR);
	PROCEDURE HexChar(i: INTEGER): CHAR;
	BEGIN
		IF i > 9 THEN RETURN CHR(ORD("A") + i - 10)
		ELSE RETURN CHR(ORD("0") + i)
		END
	END HexChar;
BEGIN
	Texts.Write(W, HexChar(ORD(b) DIV 10H));
	Texts.Write(W, HexChar(ORD(b) MOD 10H))
END WriteHexByte;

(** Display - Display the partition tables.  Calls InitViewer to initialise the display. *)

PROCEDURE Display*(VAR di: Info);
VAR i, j: SHORTINT;  t: LONGINT;  detail: BOOLEAN;
BEGIN
	InitViewer;  detail := verbose OR ~di.ok;
	FOR i := 0 TO di.numhd-1 DO
		Texts.WriteString(Wn, "Drv ");  Texts.WriteInt(Wn, i, 1);  Texts.WriteString(Wn, ": ");
		t := di.hd[i].size DIV 2+102;	(* k *)
		IF t < 100*1024 THEN
			Texts.WriteInt(Wn, t DIV 1024, 1);
			Texts.Write(Wn, ".");
			Texts.WriteInt(Wn, (t MOD 1024)*10 DIV 1024, 1)
		ELSE Texts.WriteInt(Wn, t DIV 1024, 1)
		END;
		Texts.WriteString(Wn, " Mb");
		IF detail THEN
			Texts.WriteString(Wn, ", ");
			Texts.WriteInt(Wn, di.hd[i].cyls, 1);  Texts.WriteString(Wn, " cylinders, ");  Texts.WriteInt(Wn, di.hd[i].hds, 1);
			Texts.WriteString(Wn, " heads, ");  Texts.WriteInt(Wn, di.hd[i].spt, 1);
			Texts.WriteString(Wn, " sectors per track.")
		END;
		Texts.WriteLn(Wn)
	END;
	Texts.Append(T, Wn.buf);  Texts.WriteLn(W);
	IF detail THEN Texts.WriteString(W, "Num Drv  Mb   Start  Length Type")
	ELSE Texts.WriteString(W, "Num Drv  Mb Type")
	END;
	Texts.WriteLn(W);
	FOR i := 0 TO di.numpar-1 DO
		Texts.WriteInt(W, i, 2);
		IF di.par[i].boot THEN Texts.Write(W, "*")
		ELSE Texts.Write(W, " ")
		END;
		Texts.WriteInt(W, di.par[i].drive, 3);
		t := di.par[i].size DIV 2+102;	(* k *)
		IF t < 100*1024 THEN
			Texts.WriteInt(W, t DIV 1024, 3);
			Texts.Write(W, ".");
			Texts.WriteInt(W, (t MOD 1024)*10 DIV 1024, 1)
		ELSE Texts.WriteInt(W, t DIV 1024, 5)
		END;
		IF detail THEN
			Texts.WriteInt(W, di.par[i].start, 8);  Texts.WriteInt(W, di.par[i].size, 8);
			IF di.par[i].type # FreeSpace THEN
				Texts.WriteInt(W, di.par[i].type, 4)
			ELSE
				Texts.WriteString(W, "   -")
			END
		END;
		Texts.Write(W, " ");
		IF ~di.par[i].primary THEN Texts.Write(W, "|") END;
		IF di.par[i].letter # 0X THEN Texts.Write(W, di.par[i].letter);  Texts.Write(W, ":") END;
		WriteType(di.par[i].type);
		IF di.par[i].boot THEN Texts.WriteString(W, " boot") END;
		Texts.WriteLn(W)
	END;
	Texts.Append(T, W.buf);
	IF detail THEN
		Texts.WriteLn(W);
		Texts.WriteString(W, "Num hd sec cyl hd sec cyl  ptsector ofs");  Texts.WriteLn(W);
		FOR i := 0 TO di.numpar-1 DO
			Texts.WriteInt(W, i, 2);
			Texts.WriteInt(W, ORD(di.par[i].raw[1]), 4);
			Texts.WriteInt(W, ORD(di.par[i].raw[2]) MOD 64, 3);
			Texts.WriteInt(W, ASH(ASH(ORD(di.par[i].raw[2]), -6), 8) + ORD(di.par[i].raw[3]), 5);
			Texts.WriteInt(W, ORD(di.par[i].raw[5]), 3);
			Texts.WriteInt(W, ORD(di.par[i].raw[6]) MOD 64, 3);
			Texts.WriteInt(W, ASH(ASH(ORD(di.par[i].raw[6]), -6), 8) + ORD(di.par[i].raw[7]), 5);
			Texts.WriteInt(W, di.par[i].ptsector, 10);  Texts.WriteInt(W, di.par[i].ptoffset, 4);
			(*FOR j := 0 TO 15 DO Texts.Write(W, " ");  WriteHexByte(W, di.par[i].raw[j]) END;*)
			Texts.WriteLn(W)
		END;
		Texts.WriteLn(W);  Texts.Append(T, W.buf);
		IF ~di.ok THEN
			Texts.WriteString(Wn, "Error in partition table.");
			Texts.WriteLn(Wn);  Texts.Append(T, Wn.buf)
		END
	END
END Display;

(** Partition.Show - Display all partition tables. *)

PROCEDURE Show*;
VAR di: Info;
BEGIN
	GetInfo(di);
	Display(di)
END Show;

(* SetFlag - Set bootable flag of a primary or extended partition. *)

PROCEDURE SetFlag(VAR di: Info;  i: SHORTINT;  on: BOOLEAN);
VAR b: DiskBlock;  e: LONGINT;  mod: BOOLEAN;
BEGIN
	GetBlocks(di.par[i].drive, di.par[i].ptsector, 1, b, 0);
	e := di.par[i].ptoffset;
	ASSERT((e >= 01BEH) & (e <= 01BEH+16*3));
	mod := FALSE;
	IF on & (b[e] = 0X) THEN b[e] := 80X; mod := TRUE
	ELSIF ~on & ((b[e] >= 80X) & (b[e] <= 81X)) THEN b[e] := 0X; mod := TRUE
	END;
	IF mod THEN PutBlocks(di.par[i].drive, di.par[i].ptsector, 1, b, 0) END
END SetFlag;

(** SetActive - Set the active partition(s).  Afterwards, di is updated with GetInfo. *)

PROCEDURE SetActive*(VAR di: Info;  active: SET);
VAR i, n: SHORTINT;
BEGIN
	IF di.ok THEN
		n := di.numpar;  IF n > 32 THEN n := 32 END;
		FOR i := 0 TO n-1 DO
			IF di.par[i].type # FreeSpace THEN
				SetFlag(di, i, i IN active)
			END
		END;
		GetInfo(di)
	END
END SetActive;

(** Partition.Activate {num} ~ - Active the partition(s). *)

PROCEDURE Activate*;	(* {num} ~ *)
VAR num: INTEGER;  di: Info;  active: SET;
BEGIN
	active := {};  In.Open;  In.Int(num);
	WHILE In.Done DO
		IF (num >= 0) & (num < 32) THEN INCL(active, num) END;
		In.Int(num)
	END;
	IF active # {} THEN
		GetInfo(di);  SetActive(di, active);  Display(di)
	END
END Activate;

(* Random - Pseudo-random number. *)

PROCEDURE Random (VAR seed: LONGINT;  N :LONGINT): LONGINT;
BEGIN
	seed := (seed + 773) * 13 MOD 9999991;
	RETURN seed MOD N
END Random;

(** Partition.Check num - Check partition's sectors for readability. *)

PROCEDURE Check*;	(* num *)
VAR di: Info;  num: INTEGER;  start, size, i, pc, pr, seed: LONGINT;  buf: DiskBlock;  ch: CHAR;
BEGIN
	GetInfo(di);
	In.Open;  In.Int(num);
	IF ~In.Done THEN
		i := 0;  num := -1;
		WHILE (i < di.numpar) & (num = -1) DO
			IF di.par[i].type = parttype THEN num := SHORT(i)
			ELSE INC(i)
			END
		END
	END;
	IF num >= 0 THEN
		IF di.ok & (num < di.numpar) THEN
			Texts.WriteString(Wn, "Checking partition ");
			Texts.WriteInt(Wn, num, 1);  Texts.WriteString(Wn, "...");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf);
			start := di.par[num].start;  size := di.par[num].size;  seed := 8872365;
			FOR pc := 0 TO 99 DO
				i := Random(seed, size);
				GetBlocks(di.par[num].drive, start + i, 1, buf, 0)
			END;
			i := 0;  pr := 0;
			WHILE (i < size) & (Input.Available() = 0) DO
				pc := i*100 DIV size;
				IF pc - pr >= 10 THEN
					Texts.WriteInt(Wn, pc, 1);  Texts.WriteString(Wn, "% ");
					Texts.Append(Oberon.Log, Wn.buf);
					pr := pc
				END;
				GetBlocks(di.par[num].drive, start + i, 1, buf, 0);
				INC(i)
			END;
			WHILE Input.Available() # 0 DO Input.Read(ch) END;
			IF i = size THEN
				IF pr < 100 THEN Texts.WriteString(Wn, "100%") END;
				Texts.WriteLn(Wn);  Texts.WriteString(Wn, "No problems detected.")	(* no trap *)
			END;
			Texts.WriteLn(Wn);  Texts.Append(Oberon.Log, Wn.buf)
		END
	END
END Check;

(** Partition.ChangeType num from to - Change partition type. *)

PROCEDURE ChangeType*;	(* partition fromtype totype *)
VAR num, from, to: INTEGER;  di: Info;  b: DiskBlock;  e: LONGINT;
BEGIN
	In.Open;  In.Int(num);  In.Int(from);  In.Int(to);
	IF In.Done & (num >= 0) & (to >= 0) & (to <= 255) THEN
		GetInfo(di);
		IF di.ok & (num < di.numpar) & (di.par[num].type = from) THEN
			GetBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			e := di.par[num].ptoffset;
			ASSERT((e >= 01BEH) & (e <= 01BEH+16*3));
			ASSERT((ORD(b[e+4]) = from) & (b[510] = 055X) & (b[511] = 0AAX));
			b[e+4] := CHR(to);
			PutBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			GetInfo(di)
		ELSE
			Texts.WriteString(Wn, "Bad partition specified");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf)
		END;
		Display(di)
	END
END ChangeType;

(** Partition.Delete num type - Delete primary partition. *)

PROCEDURE Delete*;	(* partition type *)
VAR num, type: INTEGER;  di: Info;  b: DiskBlock;  e, i: LONGINT;
BEGIN
	In.Open;  In.Int(num);  In.Int(type);
	IF In.Done & (num >= 0) THEN
		GetInfo(di);
		IF di.ok & (num < di.numpar) & (di.par[num].type = type) & di.par[num].primary THEN
			GetBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			e := di.par[num].ptoffset;
			ASSERT((e >= 01BEH) & (e <= 01BEH+16*3));
			ASSERT((ORD(b[e+4]) = type) & (b[510] = 055X) & (b[511] = 0AAX));
			FOR i := 0 TO 15 DO b[e+i] := 0X END;
			PutBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			GetInfo(di)
		ELSE
			Texts.WriteString(Wn, "Bad partition specified");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf)
		END;
		Display(di)
	END
END Delete;

(** Partition.Create num sizeMb - Create primary Oberon partition. *)

PROCEDURE Create*;	(* partition size *)
VAR num: INTEGER;  di: Info;  b: DiskBlock;  e, i, t, start, size, end, spt, hds: LONGINT;  ok: BOOLEAN;  drive: SHORTINT;
BEGIN
	In.Open;  In.Int(num);  In.LongInt(size);
	IF In.Done & (num >= 0) & (size > 0) THEN
		GetInfo(di);
		IF di.ok & (num < di.numpar) & (di.par[num].type = FreeSpace) & di.par[num].primary THEN
			GetBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			ASSERT((b[510] = 055X) & (b[511] = 0AAX));
			ok := FALSE;  i := 0;
			WHILE (i # 4) & ~ok DO
				e := 01BEH + 16*i;
				SYSTEM.GET(SYSTEM.ADR(b[e+12]), t);
				IF t = 0 THEN ok := TRUE
				ELSE INC(i)
				END
			END;
			IF ok THEN
				drive := di.par[num].drive;  start := di.par[num].start;  spt := di.hd[drive].spt;  hds := di.hd[drive].hds;
				size := size*1024*2;	(* number of sectors *)
				IF size > di.par[num].size THEN size := di.par[num].size END;	(* use max *)
				DEC(size, (start+size) MOD (hds*spt));	(* round end down to multiple of cylinder *)
				IF (size >= MinPartSize) & (di.par[num].size >= size) THEN
						(* create the partition *)
					end := start+size-1;
					b[e] := 0X;  b[e+1] := CHR((start DIV spt) MOD hds);
					t := start DIV (spt*hds);  b[e+2] := CHR(ASH(ASH(t, -8), 6) + (start MOD spt) + 1);
					b[e+3] := CHR(t);  b[e+4] := CHR(parttype);
					b[e+5] := CHR((end DIV spt) MOD hds);
					t := end DIV (spt*hds);  b[e+6] := CHR(ASH(ASH(t, -8), 6) + (end MOD spt) + 1);
					b[e+7] := CHR(t);  SYSTEM.PUT(SYSTEM.ADR(b[e+8]), start);
					SYSTEM.PUT(SYSTEM.ADR(b[e+12]), size);
					PutBlocks(drive, di.par[num].ptsector, 1, b, 0);	(* update partition sector *)
						(* now clear first part of partition *)
					b[0] := 0EBX;  b[1] := 0FEX;	(* LOOP END *)
					FOR i := 2 TO BS-1 DO b[i] := 0X END;
					PutBlocks(drive, di.par[num].start, 1, b, 0);	(* overwrite boot sector *)
					b[0] := 0X;  b[1] := 0X;
					FOR i := 1 TO MinPartSize-1 DO
						PutBlocks(drive, di.par[num].start + i, 1, b, 0)	(* clear first MinPartSize-1 sectors *)
					END
				ELSE
					Texts.WriteString(Wn, "Specified partition size bad");  Texts.WriteLn(Wn);
					Texts.Append(Oberon.Log, Wn.buf)
				END
			ELSE
				Texts.WriteString(Wn, "Primary partition table full");  Texts.WriteLn(Wn);
				Texts.Append(Oberon.Log, Wn.buf)
			END;
			GetInfo(di)
		ELSE
			Texts.WriteString(Wn, "Specified partition not free");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf)
		END;
		Display(di)
	END
END Create;

(** Partition.Verbose on|off - Set state of verbose flag. *)

PROCEDURE Verbose*;
VAR s: ARRAY 10 OF CHAR;
BEGIN
	In.Open;  In.String(s);
	IF ~In.Done THEN
	ELSIF s = "on" THEN
		verbose := TRUE;
		Texts.WriteString(Wn, "Verbose on");  Texts.WriteLn(Wn);  Texts.Append(Oberon.Log, Wn.buf)
	ELSIF s = "off" THEN
		verbose := FALSE;
		Texts.WriteString(Wn, "Verbose off");  Texts.WriteLn(Wn);  Texts.Append(Oberon.Log, Wn.buf)
	END
END Verbose;

(** InitText - Initialise the output text. *)

PROCEDURE InitText*(t: Texts.Text);
BEGIN
	T := t
END InitText;

(* DefaultInitViewer - Initialise the Install viewer V and text T *)

PROCEDURE DefaultInitViewer;
BEGIN
	NEW(T);  Texts.Open(T, "");
	Oberon.OpenText("Partition.Text", T, 400, 200)
END DefaultInitViewer;

PROCEDURE Init;
VAR s: ARRAY 20 OF CHAR;  i: SHORTINT;
BEGIN
	Kernel.GetConfig("PartType", s);
	i := 0;  parttype := 0;
	WHILE (s[i] >= "0") & (s[i] <= "9") DO
		parttype := parttype*10 + (ORD(s[i])-48);
		INC(i)
	END;
	IF parttype = 0 THEN parttype := 79 END
END Init;

BEGIN
	Texts.OpenWriter(W);  Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt"));
	Texts.OpenWriter(Wn);
	InitViewer := DefaultInitViewer;
	GetBlocks := Disk.GetBlocks;  PutBlocks := Disk.PutBlocks;
	GetParams := Disk.GetParams;  NumDrives := Disk.NumDrives;
	verbose := FALSE;  Init
END Partition.

Partition.Show
Partition.Activate 0 ~
Partition.Check 0 ~
Partition.ChangeType num from to
Partition.Delete 7 79
Partition.Verbose on
Partition.Verbose ^ on off
Partition.Create 7 100

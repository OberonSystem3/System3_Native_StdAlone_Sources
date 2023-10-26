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

MODULE Disk;	(* Contributed by W. Ibl to the System 3 project *)

(* Note: AHA1520.InstDisk.Mod contains modified copy of disk driver *)

IMPORT Kernel, SYSTEM, SCSI := AHA1520;

CONST
	SectorSize* = 2048;

	BS = 512;	(* disk block size *)
	SS = SectorSize;	(* Oberon sector size *)
	SS4 = SectorSize DIV 4;
	BPS = SS DIV BS;	(* blocks per sector *)

	CS = 100;	(* default sector cache size *)
	Reserved = 32;	(* sectors reserved for trap handling *)

TYPE
	Sector* = RECORD END;	(** 2k Oberon Sector *)

	Node = POINTER TO NodeRec;
	NodeRec = RECORD
		next: Node;
		adr: LONGINT;
		data: ARRAY SS OF CHAR
	END;

	Partition = RECORD
		type: INTEGER;
		letter: CHAR;
		drive: SHORTINT;
		start, size: LONGINT
	END;

VAR
		(* sector management *)
	file, error: ARRAY 60 OF CHAR;	(* report initialisation errors *)
	numused: LONGINT;	(* number of used Sectors *)
	nummax: LONGINT;	(* total number of Sectors *)
	map: ARRAY * OF LONGINT;
	init, trapped: BOOLEAN;

		(* random sector cache *)
	cache: Node;
	cachesize, Nreads, Nwrites, Nreadhits, Nwritehits: LONGINT;

		(* driver variables *)
	large, native: BOOLEAN;
	ddrive: SHORTINT;
	partitionoffset, partitionlen, rootoffset: LONGINT;
	parttype: INTEGER;
	requ: SCSI.Command;	(* SCSI command buffer *)
	drives: SHORTINT;	(* amount of drives found on inquiry *)
	tgt: ARRAY SCSI.Targets OF SHORTINT;	(* available disks *)

PROCEDURE -CoreHalt(n: LONGINT);
CODE
	INT 3
END CoreHalt;

PROCEDURE -Error(err: LONGINT);
CODE
	POP EAX	(* for register dump *)
	PUSH 17	(* Disk error *)
	INT 3
END Error;

(* ---- Disk driver ---- *)

PROCEDURE RequestSense(tgt: INTEGER; VAR key,code: INTEGER);
(* request error information for last failed request *)
VAR
	cmd: ARRAY 6 OF CHAR;
	data: ARRAY 14 OF CHAR;
BEGIN
	cmd[0]:= 03X; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 0EX; cmd[5]:= 00X;

	requ.target:= SHORT(tgt); requ.lun:= 00H; requ.clen:= 6;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(data);
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
		
	IF (requ.status # SCSI.Good) THEN CoreHalt(17); END;
	key:= ORD(data[2]);	(* Sense Key *)
	code:= SYSTEM.LSH(ORD(data[12]),8)+ORD(data[13]);	(* Sense Code *)
END RequestSense;

PROCEDURE Inquiry(tgt: INTEGER): BOOLEAN;
(* inquire device information *)
VAR
	cmd: ARRAY 6 OF CHAR;
	data: ARRAY 1 OF CHAR;
BEGIN
	cmd[0]:= 12X; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 01X; cmd[5]:= 00X;

	requ.target:= SHORT(tgt); requ.lun:= 00H; requ.clen:= 6;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(data);
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status = SCSI.Good) THEN
		RETURN(data[0] = 00X);
	ELSIF (requ.status = SCSI.DriverError) THEN
		IF (SCSI.status = SCSI.drvNoConnect) THEN RETURN(FALSE); END;
	END;
	CoreHalt(17);
END Inquiry;

PROCEDURE TestUnitReady(tgt: INTEGER): BOOLEAN;
(* check, if device is rarrin' to go *)
VAR
	cmd: ARRAY 6 OF CHAR;
BEGIN
	cmd[0]:= 00X; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 00X; cmd[5]:= 00X;

	requ.target:= SHORT(tgt); requ.lun:= 00H; requ.clen:= 6;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= 0;
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	RETURN(requ.status = SCSI.Good);	(* no data transmission *)
END TestUnitReady;

PROCEDURE DiskError();
(* produce a nice trap in case of error occurrence *)
VAR
	target,lun,scsi,driver,key,code: INTEGER;
BEGIN
	key:= 0; code:= 0;
	target:= requ.target; lun:= requ.lun; scsi:= requ.status; driver:= SCSI.status;
	IF (driver = SCSI.Good) & (scsi = SCSI.cmdCheckCondition) THEN
		RequestSense(requ.target,key,code);
	END;
	CoreHalt(17);
END DiskError;

PROCEDURE Interrogate(dev: SET);
(* loop over all targets to get the disks connected,
	non accessible drives (not ready) are skipped without reclaims *)
VAR
	rider: SHORTINT;
	ready: BOOLEAN;
	key,code: INTEGER;
BEGIN
	drives:= 0;
	FOR rider:= 0 TO SCSI.Targets-1 DO
		IF (rider IN dev) & Inquiry(rider) THEN
			ready:= TestUnitReady(rider);
			IF ~ready THEN
				RequestSense(rider,key,code);
				(* UNIT ATTENTION & POWER ON are not really a fault *) 
				IF (key = 06H) & (code = 2900H) THEN
					ready:= TestUnitReady(rider);	(* so try again *)
				END;
			END;
			IF ready THEN tgt[drives]:= rider; INC(drives); END;
		END;
	END;
	FOR rider:= drives TO SCSI.Targets-1 DO tgt[rider]:= -1; END;
END Interrogate;

(* ---- Ceres-like interface ---- *)

(** AllocSector - Allocate a new Sector.  "hint" can be previously allocated
	Sector to preserve adjacency, or 0 if previous Sector not known *)

PROCEDURE AllocSector*(hint: LONGINT; VAR sec: LONGINT);
VAR i : LONGINT;
BEGIN
	i := hint+29;
	IF ~init OR (i < 29) OR (i MOD 29 # 0) THEN CoreHalt(15) END;
	IF ~trapped & (nummax - numused <= Reserved) THEN
		trapped := TRUE;  CoreHalt(16) (* Disk full *)
	END;
	i := i DIV 29;  hint := i-1;
	IF hint > nummax THEN hint := 0 END;
	LOOP
		IF i > nummax THEN i := 0 END;
		IF native THEN
			IF (i MOD 32) IN SYSTEM.VAL(SET, map[i DIV 32]) THEN INC(i)	(* in use *)
			ELSE
				sec := i;  INCL(SYSTEM.VAL(SET, map[i DIV 32]), i MOD 32);  INC(numused);
				sec := sec*29;	(* "Encode" sector number. *)
				EXIT
			END
		ELSE
			IF map[i] < 0 THEN INC(i)	(* in use *)
			ELSE
				sec := i;  map[i] := -map[i];  INC(numused);
				sec := sec*29;	(* "Encode" sector number. *)
				EXIT
			END
		END;
		IF i = hint THEN CoreHalt(16) (* Disk full *) END
	END
END AllocSector;

(** MarkSector - Mark an unused Sector as used.  Do not mark already marked sectors. *)

PROCEDURE MarkSector*(sec: LONGINT);
BEGIN
	IF ~init OR (sec MOD 29 # 0) THEN CoreHalt(15) END;
	sec := sec DIV 29;
	IF (sec < 1) OR (sec > nummax) THEN CoreHalt(15) END;
	IF native THEN INCL(SYSTEM.VAL(SET, map[sec DIV 32]), sec MOD 32)
	ELSE map[sec] := -ABS(map[sec])
	END;
	INC(numused)
END MarkSector;

(** FreeSector - Mark a used Sector as unused.  Do not unmark already unmarked sectors. *)

PROCEDURE FreeSector*(sec: LONGINT);
BEGIN
	IF ~init OR (sec MOD 29 # 0) THEN CoreHalt(15) END;
	sec := sec DIV 29;
	IF (sec < 1) OR (sec > nummax) THEN CoreHalt(15) END;
	IF native THEN EXCL(SYSTEM.VAL(SET, map[sec DIV 32]), sec MOD 32)
	ELSE map[sec] := ABS(map[sec])
	END;
	DEC(numused)
END FreeSector;

(** Marked - Test if a sector is marked as used. *)

PROCEDURE Marked*(sec: LONGINT): BOOLEAN;
BEGIN
	IF ~init OR (sec MOD 29 # 0) THEN CoreHalt(15) END;
	sec := sec DIV 29;
	IF (sec < 1) OR (sec > nummax) THEN CoreHalt(15) END;
	IF native THEN RETURN (sec MOD 32) IN SYSTEM.VAL(SET, map[sec DIV 32])
	ELSE RETURN map[sec] < 0
	END
END Marked;

PROCEDURE ^PutBlocks*(drive: SHORTINT; start,num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
PROCEDURE ^GetBlocks*(drive: SHORTINT; start,num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);

(* Find - Find a sector in the cache *)

PROCEDURE Find(adr: LONGINT): Node;
VAR p, c: Node;
BEGIN
	p := NIL;  c := cache;
	WHILE (c # NIL) & (c.adr # adr) DO p := c; c := c.next END;
	IF c # NIL THEN
		IF p # NIL THEN	(* move to front *)
			p.next := c.next;  c.next := cache;  cache := c
		END
	END;
	RETURN c
END Find;

(* Replace - Replace a sector in the cache *)

PROCEDURE Replace(): Node;
VAR p, c: Node;
BEGIN
	p := NIL;  c := cache;
	WHILE (c.next # NIL) & (c.adr # -1) DO p := c; c := c.next END;
	IF c.adr = -1 THEN (* unused sector, use it *)
		IF p # NIL THEN
			p.next := c.next;  c.next := cache;  cache := c
		END
	ELSE	(* replace last node and move to front *)
		p.next := NIL;  c.next := cache;  cache := c
	END;
	RETURN c
END Replace;

(* StrToInt - Convert a string to an integer *)

PROCEDURE StrToInt(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

PROCEDURE InitCache;
VAR n: Node;  i: LONGINT;  s: ARRAY 10 OF CHAR;
BEGIN
	cache := NIL;  Nreads := 0;  Nwrites := 0;  Nreadhits := 0;  Nwritehits := 0;  i := 0;
	Kernel.GetConfig("DiskCache", s);
	IF s = "" THEN cachesize := CS
	ELSE cachesize := StrToInt(i, s)
	END;
	FOR i := 1 TO cachesize DO
		NEW(n);  n.next := cache;  n.adr := -1;  cache := n
	END
END InitCache;

PROCEDURE -CopySector(src, dst: LONGINT);
CODE
	CLD
	POP EDI
	POP ESI
	MOV ECX, SS4
	REP MOVSD
END CopySector;

(** GetSector - Read a 2k Sector from disk *)

PROCEDURE GetSector*(src: LONGINT; VAR dest: Sector);
VAR err: LONGINT;  n: Node;
BEGIN
	IF ~init OR (src MOD 29 # 0) THEN CoreHalt(15) END;
	src := src DIV 29;
	IF (src < 1) OR (src > nummax) THEN err := -1; CoreHalt(15) END;
	INC(Nreads);
(*
	Kernel.WriteChar("G");  Kernel.WriteInt(src, 1);  Kernel.WriteChar(" ");
	IF Nreads MOD 10 = 0 THEN Kernel.WriteLn END;
*)
	n := Find(src);
	IF n = NIL THEN	(* miss *)
		IF native THEN
			GetBlocks(ddrive,rootoffset+partitionoffset+(src-1)*BPS,BPS,dest,0);
		ELSE
			GetBlocks(ddrive,partitionoffset+ABS(map[src]),BPS,dest,0);
		END;
		IF cache # NIL THEN
			n := Replace();  n.adr := src;
			CopySector(SYSTEM.ADR(dest), SYSTEM.ADR(n.data[0]))
		END
	ELSE	(* hit *)
		INC(Nreadhits);
		CopySector(SYSTEM.ADR(n.data[0]), SYSTEM.ADR(dest))
	END
END GetSector;

(** PutSector - Write a 2k Sector to disk *)

PROCEDURE PutSector*(dest: LONGINT; VAR src: Sector);
VAR err: LONGINT;  n: Node;
BEGIN
	IF ~init OR (dest MOD 29 # 0) THEN CoreHalt(15) END;
	dest := dest DIV 29;
	IF (dest < 1) OR (dest > nummax) THEN err := -1; CoreHalt(15) END;
	INC(Nwrites);
(*
	Kernel.WriteString("P");  Kernel.WriteInt(dest, 1);  Kernel.WriteChar(" ");
	IF Nwrites MOD 10 = 0 THEN Kernel.WriteLn END;
*)
	n := Find(dest);
	IF n # NIL THEN	(* hit *)
		INC(Nwritehits);
		CopySector(SYSTEM.ADR(src), SYSTEM.ADR(n.data[0]))
	END;
	IF native THEN
		PutBlocks(ddrive,rootoffset+partitionoffset+(dest-1)*BPS,BPS,src,0);
	ELSE
		PutBlocks(ddrive,partitionoffset+ABS(map[dest]),BPS,src,0);
	END
END PutSector;

(** GetBlocks - Read 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to read into
	"ofs" - offset from start of buf in bytes *)

PROCEDURE GetBlocks*(drive: SHORTINT; start,num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
VAR
	cmd: ARRAY 10 OF CHAR;
BEGIN
	cmd[0]:= 28X;
	cmd[1]:= 00X;
	cmd[2]:= CHR(SYSTEM.LSH(start,-24));
	cmd[3]:= CHR(SYSTEM.LSH(start,-16));
	cmd[4]:= CHR(SYSTEM.LSH(start,-8));
	cmd[5]:= CHR(start);
	cmd[6]:= 00X;
	cmd[7]:= CHR(SYSTEM.LSH(num,-8));
	cmd[8]:= CHR(num);
	cmd[9]:= 00X;

	requ.target:= tgt[drive]; requ.lun:= 00H;
	requ.clen:= 10; requ.dlen:= num * 512;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(buf) + ofs;

	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status # SCSI.Good) THEN DiskError(); END;
END GetBlocks;

(** PutBlocks - Write 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to write from
	"ofs" - offset from start of buf in bytes *)

PROCEDURE PutBlocks*(drive: SHORTINT; start,num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
VAR
	cmd: ARRAY 10 OF CHAR;
BEGIN
	cmd[0]:= 2AX;
	cmd[1]:= 00X;
	cmd[2]:= CHR(SYSTEM.LSH(start,-24));
	cmd[3]:= CHR(SYSTEM.LSH(start,-16));
	cmd[4]:= CHR(SYSTEM.LSH(start,-8));
	cmd[5]:= CHR(start);
	cmd[6]:= 00X;
	cmd[7]:= CHR(SYSTEM.LSH(num,-8));
	cmd[8]:= CHR(num);
	cmd[9]:= 00X;

	requ.target:= tgt[drive]; requ.lun:= 00H;
	requ.clen:= 10; requ.dlen:= num * 512;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(buf) + ofs;

	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status # SCSI.Good) THEN DiskError(); END;
END PutBlocks;

(* ---- Read partition table ---- *)

(* Partition table starts at 01BEH in partition table sector and consists
	of 4 records of the type:
	
	00    bootind: Types.Byte;
	01    head: Types.Byte;
	02    sector: Types.Byte;
	03    cyl: Types.Byte;
	04    type: Types.Byte;
	05    head2: Types.Byte;
	06    sector2: Types.Byte;
	07    cyl2: Types.Byte;
	08    start: Types.DWord;
	12    num: Types.DWord
*)

PROCEDURE ReadPrimary(VAR p: ARRAY OF Partition;  VAR n: SHORTINT);
VAR d, i: SHORTINT;  b: ARRAY 512 OF CHAR;  e: LONGINT;  size: LONGINT;
BEGIN
	n := 0;
	FOR d := 0 TO drives-1 DO
		GetBlocks(d, 0, 1, b, 0);
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN
			FOR i := 0 TO 3 DO
				e := 01BEH + 16*i;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
				IF (b[e+4] # 0X) & (size # 0) THEN
					p[n].type := ORD(b[e+4]);  p[n].letter := 0X;  p[n].drive := d;
					SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  p[n].size := size;
					INC(n)
				END
			END
		END
	END
END ReadPrimary;

PROCEDURE ReadLogical(d: SHORTINT;  first: LONGINT;  VAR p: ARRAY OF Partition;  VAR n, letter: SHORTINT);
VAR b: ARRAY 512 OF CHAR;  e: LONGINT;  sec, size: LONGINT;
BEGIN
	sec := first;
	LOOP
		GetBlocks(d, sec, 1, b, 0);
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN
			e := 01BEH;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
			IF (b[e+4] = 5X) THEN Error(6084) END;
			IF size # 0 THEN
				p[n].type := ORD(b[e+4]);  p[n].drive := d;
				IF (p[n].type < 32) & (p[n].type IN {1,4,6,7}) THEN
					p[n].letter := CHR(letter);  INC(letter)
				ELSE
					p[n].letter := 0X
				END;
				SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  INC(p[n].start, sec);
				p[n].size := size;  INC(n)
			END;
			INC(e, 16);  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
			IF (b[e+4] # 5X) OR (size = 0) THEN EXIT END;
			SYSTEM.GET(SYSTEM.ADR(b[e+8]), sec);  INC(sec, first)
		END
	END
END ReadLogical;

PROCEDURE ReadPartitionTable(VAR p: ARRAY OF Partition;  VAR n: SHORTINT);
VAR
	pt: ARRAY 8 OF Partition;
	pn, letter, i: SHORTINT;
BEGIN
	ReadPrimary(pt, pn);
	letter := SHORT(ORD("C"));  n := 0;
	FOR i := 0 TO pn-1 DO
		IF (pt[i].type < 32) & (pt[i].type IN {1,4,6,7}) THEN
			pt[i].letter := CHR(letter);  INC(letter)
		END
	END;
	FOR i := 0 TO pn-1 DO
		IF pt[i].type = 5 THEN
			ReadLogical(pt[i].drive, pt[i].start, p, n, letter)
		ELSE
			p[n] := pt[i];  INC(n)
		END
	END
END ReadPartitionTable;

(* ---- Mapping to oberon.dsk ---- *)

PROCEDURE Err(err: LONGINT);
VAR i: INTEGER;
BEGIN
	error := "Error xxxxx";  i := 5;
	WHILE i # 0 DO
		error[6+i] := CHR(48 + err MOD 10);  err := err DIV 10;  DEC(i)
	END;
	nummax := 0
END Err;

(* FindFatPartition - Find the specified FAT partition. Return drive < 0 if not found. *)

PROCEDURE FindFatPartition(letter: CHAR;  VAR drive: SHORTINT;  VAR offset, len: LONGINT);
VAR pt: ARRAY 16 OF Partition;  pn, pi, m: SHORTINT;
BEGIN
	ReadPartitionTable(pt, pn);
	pi := 0;  m := pn;
	WHILE pi # m DO
		IF (pt[pi].letter = letter) & (pt[pi].type < 32) & (pt[pi].type IN {1,4,6}) THEN m := pi
		ELSE INC(pi)
		END
	END;
	IF pi # pn THEN offset := pt[pi].start;  len := pt[pi].size;  drive := pt[pi].drive
	ELSE drive := -1
	END
END FindFatPartition;

PROCEDURE Cap(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "a") & (ch <= "z") THEN RETURN CAP(ch)
	ELSE RETURN ch
	END
END Cap;

(* GetBPB - Read BPB and return parameters. *)

PROCEDURE GetBPB(VAR csize, fatb, rootb, rootsize, datab: LONGINT): BOOLEAN;
VAR b: ARRAY 512 OF CHAR;  x, err, fatsize: LONGINT;  numfat: SHORTINT;
BEGIN
	GetBlocks(ddrive, partitionoffset + 0, 1, b, 0);
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[0BH]), SYSTEM.VAL(INTEGER, x));
	IF x # BS THEN error := "Bad block size"; RETURN FALSE END;
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[0DH]), SYSTEM.VAL(CHAR, x));
	csize := x*BS;	(* bytes per cluster *)
	SYSTEM.GET(SYSTEM.ADR(b[10H]), numfat);	(* FAT copies *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[16H]), SYSTEM.VAL(INTEGER, x));
	fatsize := x;	(* sectors in FAT *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[0EH]), SYSTEM.VAL(INTEGER, x));
	fatb := x;	(* start of FAT *)
	rootb := fatb + numfat*fatsize;
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[11H]), SYSTEM.VAL(INTEGER, x));
	rootsize := (x*32) DIV BS;
	datab := rootb + rootsize;	(* start of data *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[13H]), SYSTEM.VAL(INTEGER, x));
	IF x = 0 THEN
		SYSTEM.GET(SYSTEM.ADR(b[20H]), x)	(* big number of sectors *)
	END;
	x := (x-datab) DIV (csize DIV BS);	(* total clusters *)
	IF x <= 4078 THEN error := "~16-bit FAT"; RETURN FALSE
	ELSE RETURN TRUE
	END
END GetBPB;

(* ParseName - Parse one more component of a path, starting at i. *)

PROCEDURE ParseName(VAR file: ARRAY OF CHAR;  VAR i: LONGINT;  VAR name: ARRAY OF CHAR);
VAR j: LONGINT;
BEGIN
	j := 0;
	IF (file[i] = "/") OR (file[i] = "\") THEN
		INC(i);
		WHILE (file[i] = ".") & (j # 2) DO name[j] := file[i]; INC(i); INC(j) END;	(* allow up to 2 leading dots *)
		WHILE (file[i] # 0X) & (file[i] # ".") & (file[i] # "/") & (file[i] # "\") & (j # 8) DO
			file[i] := Cap(file[i]); name[j] := file[i]; INC(i); INC(j)
		END;
		WHILE j # 8 DO name[j] := " "; INC(j) END;
		IF file[i] = "." THEN INC(i) END;
		WHILE (file[i] # 0X) & (file[i] # "/") & (file[i] # "\") & (j # 11) DO
			file[i] := Cap(file[i]); name[j] := file[i]; INC(i); INC(j)
		END;
		WHILE j # 11 DO name[j] := " "; INC(j) END
	END;
	name[j] := 0X
END ParseName;

(* NextCluster - Return next cluster or 0 if eof or -1 if bad block or error. b is 512 byte buffer and 
	cache is block number loaded in b. *)

PROCEDURE NextCluster(VAR b: ARRAY OF CHAR;  VAR cache: LONGINT;  fatb, cluster: LONGINT): LONGINT;
VAR err, k, x: LONGINT;
BEGIN
	k := cluster DIV (BS DIV 2) + fatb;	(* there are BS DIV 2 next entries per FAT block, indexed by cluster *)
	IF k # cache THEN
		GetBlocks(ddrive, partitionoffset + k, 1, b, 0);
		cache := k
	END;
		(* get next in chain *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[(cluster MOD (BS DIV 2))*2]), SYSTEM.VAL(INTEGER, x));
	IF x >= 0FFF8H THEN RETURN 0	(* was last cluster *)
	ELSIF x >= 0FFF0H THEN error := "Bad cluster"; RETURN -1
	ELSE RETURN x
	END
END NextCluster;

(* Equal - Return TRUE iff str1[i1..i1+len-1] = str2[i2..i2+len-1] *)

PROCEDURE Equal(VAR str1, str2: ARRAY OF CHAR;  i1, i2, len: LONGINT): BOOLEAN;
BEGIN
	WHILE len # 0 DO
		IF str1[i1] # str2[i2] THEN RETURN FALSE END;
		INC(i1);  INC(i2);  DEC(len)
	END;
	RETURN TRUE
END Equal;

(* FindName - Find a name in a directory entry. *)

PROCEDURE FindName(VAR b: ARRAY OF CHAR;  name: ARRAY OF CHAR;  VAR attr: SET;  VAR start, size: LONGINT): BOOLEAN;
VAR j: LONGINT;
BEGIN
	j := 0;
	WHILE j # 16 DO
		IF Equal(b, name, j*32, 0, 11) THEN
			start := 0;  attr := {};
			SYSTEM.GET(SYSTEM.ADR(b[j*32+0BH]), SYSTEM.VAL(CHAR, attr));
			SYSTEM.GET(SYSTEM.ADR(b[j*32+1AH]), SYSTEM.VAL(INTEGER, start));
			SYSTEM.GET(SYSTEM.ADR(b[j*32+1CH]), size);
			RETURN TRUE
		ELSE INC(j)
		END
	END;
	RETURN FALSE
END FindName;

(* FindFile - Find a file and return its position and size. *)

PROCEDURE FindFile(VAR file: ARRAY OF CHAR;  csize, fatb, rootb, rootsize, datab: LONGINT;  VAR start, fsize: LONGINT): BOOLEAN;
VAR
	b: ARRAY BS OF CHAR;  disk: ARRAY 12 OF CHAR;
	err, i, k, m, n, dir: LONGINT;  found: BOOLEAN;  attr: SET;
BEGIN
	k := 2;  ParseName(file, k, disk);
	i := 0;  found := FALSE;  start := -1;
	WHILE (i # rootsize) & ~found DO
		GetBlocks(ddrive, partitionoffset + rootb+i, 1, b, 0);
		found := FindName(b, disk, attr, start, fsize);
		INC(i)
	END;
	WHILE found & (file[k] # 0X) & (4 IN attr) DO	(* more to come *)
		dir := start;  ParseName(file, k, disk);  found := FALSE;
		LOOP
			m := 0;  n := csize DIV BS;
			WHILE (m # n) & ~found DO
				GetBlocks(ddrive, partitionoffset + (dir-2)*n + datab + m, 1, b, 0);
				found := FindName(b, disk, attr, start, fsize);
				INC(m)
			END;
			IF found THEN EXIT END;
			m := -1;  dir := NextCluster(b, m, fatb, dir);
			IF dir <= 0 THEN
				IF dir = 0 THEN EXIT	(* last cluster *)
				ELSE COPY(file, error); RETURN FALSE	(* error *)
				END
			END
		END
	END;
	IF found & (file[k] = 0X) & (attr * {3,4} = {}) THEN RETURN TRUE
	ELSE COPY(file, error); RETURN FALSE
	END
END FindFile;

(* InitMapping - Initialise sector mapping for file system in a file *)

PROCEDURE InitMapping;
VAR
	b: ARRAY 512 OF CHAR;
	i, j, m, csize, fatb, rootb, datab, rootsize, start, fsize, cache: LONGINT;
BEGIN
	file[0] := Cap(file[0]);
	IF (file[0] < "C") OR (file[0] > "Z") OR (file[1] # ":") OR ((file[2] # "\") & (file[2] # "/")) OR (file[3] = 0X) THEN
		error := "Bad drive"; RETURN
	END;
	FindFatPartition(file[0], ddrive, partitionoffset, partitionlen);
	IF ddrive >= 0 THEN
		IF GetBPB(csize, fatb, rootb, rootsize, datab) THEN
			IF FindFile(file, csize, fatb, rootb, rootsize, datab, start, fsize) THEN
				nummax := fsize DIV SS;
				IF (nummax < 8) OR (start = 0) THEN
					error := "File too small"; nummax := 0; RETURN
				END;
				IF csize MOD SS # 0 THEN
					error := "Bad cluster size"; nummax := 0; RETURN
				END;
				NEW(map, nummax+1);
				map[0] := -1;	(* reserve sector 0 (illegal to use) *)
				i := start;  j := 1;  cache := -1;
				LOOP
					FOR m := 0 TO (csize DIV SS)-1 DO	(* the next csize bytes of the file are stored in cluster i *)
						map[j] := (i-2)*(csize DIV BS) + datab + m*BPS;  INC(j);	(* i-2 for 1st 2 FAT entries *)
						IF j > nummax THEN EXIT END	(* done *)
					END;
					i := NextCluster(b, cache, fatb, i);	(* step to next *)
					IF i <= 0 THEN
						IF i = 0 THEN EXIT	(* last cluster *)
						ELSE nummax := 0; RETURN	(* error *)
						END
					END
				END;
				FOR i := 1 TO nummax DO
					ASSERT((map[i] >= datab) & (map[i] < partitionoffset+partitionlen))
				END
			END
		END
	ELSE error := "Drive not found"
	END
END InitMapping;

(* InitTable - Initialise sector reservation table *)

PROCEDURE InitTable;
VAR s, err, x: LONGINT;  b: ARRAY 512 OF CHAR;  pt: ARRAY 16 OF Partition;  pn, pi: SHORTINT;
BEGIN
		(* read partition table, finding first Native Oberon partition *)
	native := TRUE;  ReadPartitionTable(pt, pn);
	pi := 0;  x := pn;
	WHILE pi # x DO
		IF pt[pi].type = parttype THEN x := pi
		ELSE INC(pi)
		END
	END;
	IF pi = pn THEN error := "Partition not found"; RETURN END;
	partitionoffset := pt[pi].start;  partitionlen := pt[pi].size;
	ddrive := pt[pi].drive;
		(* read boot block to get offset *)
	GetBlocks(ddrive, partitionoffset+0, 1, b, 0);
	rootoffset := 1;
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[510]), SYSTEM.VAL(INTEGER, x));
	b[0] := "x"; b[1] := "x"; b[2] := "x";  b[9] := 0X;
	IF (x = 0AA55H) & (b = "xxxOBERON") THEN	(* valid boot block *)
		SYSTEM.GET(SYSTEM.ADR(b[0EH]), SYSTEM.VAL(INTEGER, rootoffset))
	END;
		(* set up sector reservation table *)
	nummax := (partitionlen-rootoffset) DIV BPS;
	s := (nummax+1+31) DIV 32;
	NEW(map, s);
	WHILE s # 0 DO DEC(s); map[s] := 0 END;
	INCL(SYSTEM.VAL(SET, map[0]), 0)	(* reserve sector 0 (illegal to use) *)
END InitTable;

(** ResetDisk - Reset the disk driver *)

PROCEDURE ResetDisk*;
VAR s: ARRAY 20 OF CHAR;  i: SHORTINT;
BEGIN
	IF ~init THEN
		error := "";
		InitCache;
		ddrive := -1;  partitionoffset := 0;  native := FALSE;
		nummax := 0;  numused := 0;  NEW(map, 0);
		Kernel.GetConfig("PartType", s);
		i := 0;  parttype := 0;
		WHILE (s[i] >= "0") & (s[i] <= "9") DO
			parttype := parttype*10 + (ORD(s[i])-48);
			INC(i)
		END;
		IF parttype = 0 THEN parttype := 79 END;
		Kernel.GetConfig("FileSystem", file);
		IF file = "" THEN InitTable	(* native partition *)
		ELSE InitMapping	(* inside FAT file *)
		END;
		IF nummax = 0 THEN
			Kernel.WriteString("Error: ");
			Kernel.WriteString(error);  Kernel.WriteLn	(* error message *)
		ELSE
			init := TRUE
		END
	END
END ResetDisk;

(** Available - Return number of 2k Sectors available (unmarked) on disk *)

PROCEDURE Available*(): LONGINT;
BEGIN
	RETURN nummax - numused
END Available;

(** Size - Return total number of 2k Sectors on disk *)

PROCEDURE Size*(): LONGINT;
BEGIN
	RETURN nummax
END Size;

(** NumDrives - Return number of disk drives available *)

PROCEDURE NumDrives*(): SHORTINT;
BEGIN
	RETURN drives
END NumDrives;

(** GetParams - Return parameters of drive (for Install) *)

PROCEDURE GetParams*(drive: SHORTINT; VAR cyls,hds,spt: LONGINT);
VAR
	cmd: ARRAY 6 OF CHAR;
	data: ARRAY 16 OF CHAR;
BEGIN
	cmd[0]:= 1AX; cmd[1]:= 08X; cmd[2]:= 03X;
	cmd[3]:= 00X; cmd[4]:= 10X; cmd[5]:= 00X;

	requ.target:= tgt[drive]; requ.lun:= 00H; requ.clen:= 6; requ.dlen:= 16;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(data);
	
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status # SCSI.Good) THEN DiskError(); END;
	spt:= SYSTEM.LSH(ORD(data[4+10]),8) + ORD(data[4+11]);

	cmd[2]:= 04X; cmd[4]:= 0AX; requ.dlen:= 10;
	
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status # SCSI.Good) THEN DiskError(); END;

	cyls:= SYSTEM.LSH(LONG(ORD(data[4+2])),16) + SYSTEM.LSH(ORD(data[4+3]),8) + ORD(data[4+4]);
	hds:= ORD(data[4+5]);
END GetParams;

BEGIN
	init:= FALSE; trapped := FALSE; parttype := -1; NEW(requ); Interrogate({0..7});
END Disk.

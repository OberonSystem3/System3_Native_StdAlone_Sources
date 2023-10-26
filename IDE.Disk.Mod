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

MODULE Disk;	(* pjm *)

(* Note: IDE.InstDisk.Mod contains modified copy of disk driver *)

(* IDE Disk driver for native Oberon

	Contains:
	A. Interface for Ceres Files module.
	B. Disk driver for PC BIOS-compatible disks (e.g. IDE, ESDI).
	C. DOS partition table reading (new version)
	D. Mapping to c:\oberon.dsk.


	References:
	1. pmuller, Hybrid Oberon and Gneiss microkernel code *)

IMPORT Kernel, SYSTEM;

TYPE
	Sector* = RECORD END;	(** 2k Oberon Sector *)

CONST
	SectorSize* = 2048;

		(* Values for Params.op *)
	Read = 0;  Write = 1;

	BS = 512;	(* disk block size *)
	SS = SectorSize;	(* Oberon sector size *)
	SS4 = SectorSize DIV 4;
	BPS = SS DIV BS;	(* blocks per sector *)
	
	CS = 100;	(* default sector cache size *)
	Reserved = 32;	(* sectors reserved for trap handling *)

		(* Values for ControllerDesc.state (<32)*)
	Initial0 = 0;  Ready0 = 1;  Busy0 = 2;  Reset0 = 3;  Reset1 = 4;
	Reset2 = 5;  Reset3 = 6;

		(* Timeout values in ms *)
	IOTime = 8000;	(* basic time allowed for an IO operation *)
	IOTimex = 60;	(* time extra per sector for IO *)

	MaxDevices = 2;

TYPE
	DeviceDesc = RECORD
		cylinders, cylinders0: LONGINT;	(* number of cylinders *)
		heads, heads0: LONGINT;	(* number of heads *)
		sectrack: LONGINT;	(* sectors/track *)
		writePreComp: LONGINT
	END;

	Controller = POINTER TO ControllerDesc;
	ControllerDesc = RECORD
		num: SHORTINT;	(* number of devices *)
		state: SHORTINT;	(* see CONST  *)
		device: ARRAY MaxDevices OF DeviceDesc;
		port: LONGINT;	(* Disk controller port *)
		regPort: LONGINT;	(* Disk controller register port *)
		num1: LONGINT	(* # of sectors currently being read (<256) *)
	END;

	Params = POINTER TO ParamsDesc;
	ParamsDesc = RECORD
		controller: Controller;
		drive, sector, num, bufadr: LONGINT;	(* request par. (inc) *)
		op: SHORTINT	(* Read, Write *)
	END;

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
	par: Params;
	interrupt: LONGINT;
	large, native: BOOLEAN;
	ddrive: SHORTINT;
	partitionoffset, partitionlen, rootoffset: LONGINT;
	parttype: INTEGER;
	wstate0, wstate1: SHORTINT;

(* ---- Driver support ---- *)

(* RepInWord - Block port input instruction. *)

PROCEDURE -RepInWord(port, buf, len: LONGINT);
CODE
	POP ECX
	POP EDI
	POP EDX
	CLD
	REP INSW
END RepInWord;

(* RepOutWord - Block port output instruction. *)

PROCEDURE -RepOutWord(port, buf, len: LONGINT);
CODE
	POP ECX
	POP ESI
	POP EDX
	CLD
	REP OUTSW
END RepOutWord;

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

(* ---- Disk driver (GST506 device-specific part) ---- *)

(* WaitFin - Wait for controller to finish (~busy).
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitFin(d: Controller): BOOLEAN;
VAR
	x: SET;
	p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	wstate0 := SYSTEM.VAL(SHORTINT, x);
	REPEAT
		IF ~(7 IN x) THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 15000*Kernel.TimeUnit DIV 1000;	(* 15s, was 250ms *)
	wstate1 := SYSTEM.VAL(SHORTINT, x);
	RETURN FALSE
END WaitFin;

(* WaitDrq - Wait for DRQ.
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitDrq(d: Controller): BOOLEAN;
VAR
	x: SET;
	p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	wstate0 := SYSTEM.VAL(SHORTINT, x);
	REPEAT
		IF 3 IN x THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 250*Kernel.TimeUnit DIV 1000;	(* 250ms *)
	wstate1 := SYSTEM.VAL(SHORTINT, x);
	RETURN FALSE
END WaitDrq;

(* CheckReady - Check if disk is ready.
	{(0 <= drive <= 1) & (0 <= head <= 15)} *)

PROCEDURE CheckReady(d: Controller;  drive, head: LONGINT): LONGINT;
VAR
	x: SET;
	p, t: LONGINT;
BEGIN
	t := Kernel.GetTimer();
	REPEAT
		IF ~WaitFin(d) THEN RETURN 6010 END;
		p := d.port+6;
		SYSTEM.PORTOUT(p, CHR(0A0H+(drive*10H)+head));
		INC(p);  SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
		IF (7 IN x) OR (x * {4,5,6} = {4,6}) THEN
			RETURN 0	(* busy OR (~writeerror & ready & seek) *)
		END
	UNTIL Kernel.GetTimer() - t > 500*Kernel.TimeUnit DIV 1000;	(* 500ms *)
	RETURN 6011
END CheckReady;

(* Command - Send command to controller.  p. 5-111 *)

PROCEDURE Command(cmd: CHAR;  d: Controller;  drive, sector, head,
		cylinder, numsec: LONGINT): LONGINT;
VAR p: LONGINT;  control: CHAR;
BEGIN
	IF (drive < 0) OR (drive > 1) THEN RETURN 6003 END;
	IF (head < 0) OR (head > 15) THEN RETURN 6004 END;
	IF (cylinder < 0) OR (cylinder > 0FFFFH) THEN RETURN 6006 END;
	IF (sector < 0) OR (sector > 255) THEN RETURN 6007 END;
	IF (numsec < 0) OR (numsec > 255) THEN RETURN 6008 END;
	p := CheckReady(d, drive, head);
	IF p # 0 THEN RETURN p END;
	IF d.device[drive].heads > 8 THEN control := 8X ELSE control := 0X END;
	SYSTEM.PORTOUT(d.regPort, control);
	p := d.port+1;
	SYSTEM.PORTOUT(p, CHR(d.device[drive].writePreComp DIV 4));
	INC(p);  SYSTEM.PORTOUT(p, CHR(numsec));
	INC(p);  SYSTEM.PORTOUT(p, CHR(sector));
	INC(p);  SYSTEM.PORTOUT(p, CHR(cylinder MOD 100H));
	INC(p);  SYSTEM.PORTOUT(p, CHR(cylinder DIV 100H));
	INC(p);  SYSTEM.PORTOUT(p, CHR(0A0H+(drive*10H)+head));
	INC(p);  SYSTEM.PORTOUT(p, cmd);
	RETURN 0
END Command;

(* Cleanup - Clean up an aborted operation. *)

PROCEDURE Cleanup(d: Controller;  params: Params): LONGINT;
VAR res: LONGINT;
BEGIN
	WITH d: Controller DO
		CASE d.state OF
			Reset0, Reset1, Reset2, Reset3:
				res := 6012	(* reset timeout *)
			|Busy0:
				res := 6013	(* IO timeout *)
		END; (* CASE *)
		d.state := Initial0
	END;
	RETURN res
END Cleanup;

(* Reset - Reset the disk system.  p. 5-108
	Q: d.ap # NIL
	R: (d.state = Reset0) OR ((d.state = Initial0) & Wakeup)
	If Reset fails, the controller is probably broken. *)

PROCEDURE Reset(d: Controller): LONGINT;
VAR
	x: CHAR;
	p, res, t: LONGINT;
BEGIN
	d.state := Initial0;	(* assume the worst *)
	SYSTEM.PORTOUT(d.regPort, 4X);	(* reset controller *)
	t := Kernel.GetTimer() + 2;	(* assume one GetTimer tick > 4.8us *)
	REPEAT UNTIL Kernel.GetTimer() >= t;	(* wait > 4.8us *)
	SYSTEM.PORTOUT(d.regPort, 8X);
	IF WaitFin(d) THEN
		p := d.port+1;  SYSTEM.PORTIN(p, x);	(* get reset status *)
		IF x = 1X THEN
			res := Command(91X, d, 0, d.device[0].sectrack, d.device[0].heads-1,
					d.device[0].cylinders, d.device[0].sectrack);	(* params. *)
			IF res = 0 THEN d.state := Reset0
			ELSE (* {d.state = Initial0} *)
			END
		ELSE res := 6002	(* bad reset status *)
		END
	ELSE res := 6001	(* controller not responding *)
	END;
	RETURN res
END Reset;

(* Start - Start the IO operation.
	R: d.state IN {Initial0, Busy0} *)

PROCEDURE Start(d: Controller;  params: Params;  VAR time: LONGINT): LONGINT;
VAR
	x, drv, sec, cyl, head, res: LONGINT;
BEGIN
	WITH d: Controller DO
		time := IOTime + params.num * IOTimex;
		CASE d.state OF
			Initial0:
				res := Reset(d)
			|Ready0, Busy0:
				drv := params.drive;
				sec := params.sector MOD d.device[drv].sectrack + 1;
				x := params.sector DIV d.device[drv].sectrack;
				head := x MOD d.device[drv].heads;
				cyl := x DIV d.device[drv].heads;
				IF params.num > 255 THEN d.num1 := 255 ELSE d.num1 := params.num END;
				CASE params.op OF
					Read:
						res := Command(20X, d, drv, sec, head, cyl, d.num1);	(* Read *)
						IF res = 0 THEN d.state := Busy0
						ELSE d.state := Initial0
						END
					|Write:
						res := Command(30X, d, drv, sec, head, cyl, d.num1);	(* Write *)
						IF res = 0 THEN
							IF WaitDrq(d) THEN	(* drq *)
								RepOutWord(d.port, params.bufadr, BS DIV 2);	(* PF *)
								d.state := Busy0	(* {res = 0} *)
							ELSE d.state := Initial0;  res := 6029	(* drq timeout *)
							END
						ELSE d.state := Initial0	(* {res # 0} *)
						END
				END (* CASE *)
		END (* CASE *)
	END;
	RETURN res
END Start;

(* GetResult - Get result of the current operation.  p. 5-112
	p+7:
		bit 7	busy
		bit 6	ready
		bit 5	write fault
		bit 4	seek complete
		bit 3	drq
		bit 2	ecc corrected
		bit 1	index
		bit 0	error
	p+1:
		bit 7	bad block
		bit 6	data ecc
		bit 5	not used
		bit 4	id not found
		bit 3	not used
		bit 2	command aborted
		bit 1	track 0 not found
		bit 0	data address mark not found *)

PROCEDURE GetResult(d: Controller): LONGINT;
VAR
	x: SET;
	p: LONGINT;
	i: SHORTINT;
BEGIN
	p := d.port+7;  SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	IF ~(7 IN x) THEN	(* ~busy *)
		IF 5 IN x THEN RETURN 6014 (* write fault *)
		ELSIF ~(6 IN x) THEN RETURN 6015 (* not ready *)
		ELSIF ~(4 IN x) THEN RETURN 6016 (* seek not complete *)
		(*ELSIF 2 IN x THEN RETURN 6018*) (* ecc corrected *)
		ELSE (* fall through *)
		END
	END;
	IF 0 IN x THEN	(* error *)
		p := d.port+1;  SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
		FOR i := 0 TO 7 DO
			IF i IN x THEN RETURN 6024-LONG(LONG(i)) END	(* 6017-6024 *)
		END;
		RETURN 6025 (* no error code! *)
	ELSE
		RETURN 0
	END
END GetResult;

(* Transfer - Transfer data. *)

PROCEDURE Transfer(d: Controller;  params: Params;  VAR more: BOOLEAN): LONGINT;
VAR x, err: LONGINT;
BEGIN
	WITH d: Controller DO
		more := TRUE; 
		CASE d.state OF
			Ready0:
				err := 6030	(* unexpected interrupt *)

			|Busy0:
				CASE params.op OF
					Read:
						RepInWord(d.port, params.bufadr, BS DIV 2);	(* PF *)
						INC(params.bufadr, BS);  DEC(d.num1);
						DEC(params.num);  INC(params.sector);  err := GetResult(d);
						IF err # 0 THEN d.state := Initial0
						ELSE	(* ~error *)
							IF d.num1 = 0 THEN	(* finished... *)
								IF params.num = 0 THEN	(* ...totally *)
									d.state := Ready0;  more := FALSE
								ELSE	(* ...with partial request *)
									err := Start(d, params, x)	(* next partial request *)
										(* ignore x *)
								END
							ELSE	(* await another interrupt *)
							END
						END
					|Write:
						INC(params.bufadr, BS);  DEC(d.num1);
						DEC(params.num);  INC(params.sector);
						err := GetResult(d);
						IF err # 0 THEN d.state := Initial0
						ELSE	(* ~error *)
							IF d.num1 = 0 THEN	(* finished... *)
								IF params.num = 0 THEN	(* ...totally *)
									d.state := Ready0;  more := FALSE
								ELSE	(* ...with partial request *)
									err := Start(d, params, x)	(* next partial request *)
										(* ignore x *)
								END
							ELSE
								RepOutWord(d.port, params.bufadr, BS DIV 2)	(* PF *)
									(* await another interrupt *)
							END
						END
				END (* CASE *)
	
			|Reset0:
				err := Command(10X, d, 0, d.device[0].sectrack, 0, 0, 0);	(* recal. *)
				IF err # 0 THEN d.state := Initial0
				ELSE
					IF d.num = 2 THEN d.state := Reset1 ELSE d.state := Reset3 END
				END
	
			|Reset1:
				err := Command(91X, d, 1, d.device[1].sectrack, d.device[1].heads-1,
						d.device[1].cylinders, d.device[1].sectrack);	(* params. *)
				IF err # 0 THEN d.state := Initial0
				ELSE d.state := Reset2
				END
	
			|Reset2:
				err := Command(10X, d, 1, d.device[1].sectrack, 0, 0, 0);	(* recal. *)
				IF err # 0 THEN d.state := Initial0
				ELSE d.state := Reset3
				END
	
			|Reset3:
				d.state := Ready0;  err := Start(d, params, x)	(* ignore x *)
	
			|Initial0:
				err := 6031	(* unexpected interrupt *)
		END;
		RETURN err
	END
END Transfer;

PROCEDURE InterruptHandler;
BEGIN
	INC(interrupt)
END InterruptHandler;

(* WaitForInterrupt - Wait for and handle interrupts *)

PROCEDURE WaitForInterrupt(time: LONGINT): LONGINT;
VAR
	start, err: LONGINT;
	more: BOOLEAN;
BEGIN
	start := Kernel.GetTimer();
	LOOP
		REPEAT (* skip *) UNTIL (interrupt # 0) OR (Kernel.GetTimer() - start > time);
		IF interrupt # 0 THEN	(* handle interrupt *)
			SYSTEM.CLI();  DEC(interrupt);  SYSTEM.STI();
			err := Transfer(par.controller, par, more);
			IF (err # 0) OR ~more THEN
				RETURN err
			END
		ELSE	(* timeout *)
			RETURN Cleanup(par.controller, par)
		END
	END
END WaitForInterrupt;

(* ReadBlocks - Read disk blocks *)

PROCEDURE ReadBlocks(drive, sec, num, adr, offset: LONGINT): LONGINT;
VAR err, time: LONGINT;
BEGIN
	par.op := Read;  par.drive := drive;  par.sector := sec + offset;
	par.num := num;  par.bufadr := adr;
	err := Start(par.controller, par, time);
	IF err = 0 THEN err := WaitForInterrupt(time) END;
	RETURN err
END ReadBlocks;

(* WriteBlocks - Write disk blocks *)

PROCEDURE WriteBlocks(drive, sec, num, adr, offset: LONGINT): LONGINT;
VAR err, time: LONGINT;
BEGIN
	par.op := Write;  par.drive := drive;  par.sector := sec + offset;
	par.num := num;  par.bufadr := adr;
	err := Start(par.controller, par, time);
	IF err = 0 THEN err := WaitForInterrupt(time) END;
	RETURN err
END WriteBlocks;

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
	FOR d := 0 TO par.controller.num-1 DO
		e := ReadBlocks(d, 0, 1, SYSTEM.ADR(b[0]), 0);
		IF e # 0 THEN Error(e) END;
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
		e := ReadBlocks(d, sec, 1, SYSTEM.ADR(b[0]), 0);
		IF e # 0 THEN Error(e) END;
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
	err := ReadBlocks(ddrive, 0, 1, SYSTEM.ADR(b[0]), partitionoffset);
	IF err # 0 THEN Err(err); RETURN FALSE END;
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
		err := ReadBlocks(ddrive, k, 1, SYSTEM.ADR(b[0]), partitionoffset);
		IF err # 0 THEN Err(err); RETURN -1 END;
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
		err := ReadBlocks(ddrive, rootb+i, 1, SYSTEM.ADR(b[0]), partitionoffset);
		IF err # 0 THEN Err(err); RETURN FALSE END;
		found := FindName(b, disk, attr, start, fsize);
		INC(i)
	END;
	WHILE found & (file[k] # 0X) & (4 IN attr) DO	(* more to come *)
		dir := start;  ParseName(file, k, disk);  found := FALSE;
		LOOP
			m := 0;  n := csize DIV BS;
			WHILE (m # n) & ~found DO
				err := ReadBlocks(ddrive, (dir-2)*n + datab + m, 1, SYSTEM.ADR(b[0]), partitionoffset);
				IF err # 0 THEN Err(err); RETURN FALSE END;
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
	err := ReadBlocks(ddrive, 0, 1, SYSTEM.ADR(b[0]), partitionoffset);
	IF err # 0 THEN Err(err); RETURN END;
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
			err := ReadBlocks(ddrive, rootoffset+(src-1)*BPS, BPS, SYSTEM.ADR(dest), partitionoffset)
		ELSE
			err := ReadBlocks(ddrive, ABS(map[src]), BPS, SYSTEM.ADR(dest), partitionoffset)
		END;
		IF err # 0 THEN Error(err) (* Disk error (unreadable sector) *) END;
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
		err := WriteBlocks(ddrive, rootoffset+(dest-1)*BPS, BPS, SYSTEM.ADR(src), partitionoffset)
	ELSE
		err := WriteBlocks(ddrive, ABS(map[dest]), BPS, SYSTEM.ADR(src), partitionoffset)
	END;
	IF err # 0 THEN Error(err) (* Disk error *) END
END PutSector;

(** GetBlocks - Read 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to read into
	"ofs" - offset from start of buf in bytes *)

PROCEDURE GetBlocks*(drive: SHORTINT;  start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR err: LONGINT;
BEGIN
	err := ReadBlocks(drive, start, num, SYSTEM.ADR(buf[ofs]), 0);
	IF err # 0 THEN Error(err) END
END GetBlocks;

(** PutBlocks - Write 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to write from
	"ofs" - offset from start of buf in bytes *)

PROCEDURE PutBlocks*(drive: SHORTINT;  start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR err: LONGINT;
BEGIN
	err := WriteBlocks(drive, start, num, SYSTEM.ADR(buf[ofs]), 0);
	IF err # 0 THEN Error(err) END
END PutBlocks;

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
	RETURN par.controller.num
END NumDrives;

(** GetParams - Return parameters of drive (for Install) *)

PROCEDURE GetParams*(drive: SHORTINT;  VAR cyls, hds, spt: LONGINT);
VAR d: DeviceDesc;
BEGIN
	d := par.controller.device[drive];
	cyls := d.cylinders0;  hds := d.heads0;  spt := d.sectrack
END GetParams;

PROCEDURE GetPar(p: LONGINT;  ofs: SHORTINT): LONGINT;
VAR x: LONGINT;
BEGIN
	x := 0;
	SYSTEM.GET(p+12+ofs, SYSTEM.VAL(CHAR, x));
	RETURN x
END GetPar;

PROCEDURE Parse(s: ARRAY OF CHAR;  VAR d: DeviceDesc);
VAR p: LONGINT;
BEGIN
	d.cylinders0 := 0;  d.heads0 := 0;  d.writePreComp := 65535;
	p := 0;  d.cylinders := StrToInt(p, s);
	IF CAP(s[p]) = "M" THEN	(* only size in Mb specified *)
		d.heads := 16;  d.sectrack := 63;  d.cylinders := (d.cylinders*1024*2) DIV (16*63);
		INC(p);  IF CAP(s[p]) = "B" THEN INC(p) END
	ELSE
		IF s[p] # "," THEN Error(6080) END;
		INC(p);  d.heads := StrToInt(p, s);  IF s[p] # "," THEN Error(6081) END;
		INC(p);  d.sectrack := StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p);  d.writePreComp := StrToInt(p, s);
			IF s[p] = "," THEN
				INC(p);  d.cylinders0 := StrToInt(p, s);
				IF s[p] = "," THEN
					INC(p);  d.heads0 := StrToInt(p, s)
				END
			END
		END
	END;
	IF (s[p] # 0X) & (s[p] # 20X) THEN Error(6082) END;
	IF d.cylinders0 = 0 THEN d.cylinders0 := d.cylinders END;
	IF d.heads0 = 0 THEN d.heads0 := d.heads END;
	IF (d.cylinders < 1) OR (d.cylinders > 0FFFFH) OR (d.heads < 1) OR 
			(d.heads > 16) OR (d.sectrack < 1) OR (d.sectrack > 256) THEN
		Error(6083)
	END
END Parse;

(* Adjust - Adjust head and cylinder parameters for controller. *)

PROCEDURE Adjust(d: Controller;  i: LONGINT);
BEGIN
	WHILE (d.device[i].heads > 16) & ~ODD(d.device[i].heads) DO
		large := TRUE;
		d.device[i].heads := d.device[i].heads DIV 2;
		d.device[i].cylinders := d.device[i].cylinders*2
	END;
	IF d.device[i].heads > 16 THEN	(* still too large *)
		large := TRUE;
		d.device[i].cylinders := d.device[i].cylinders * d.device[i].heads DIV 16;
		d.device[i].heads := 16
	END
END Adjust;

(* Detect - Attempt to detect drive parameters for drive d.num-1. *)

PROCEDURE Detect(d: Controller);
VAR err: LONGINT;  buf: ARRAY BS OF CHAR;  drive, i: SHORTINT;  p, hd, sec, cyl, phd, pcyl, psec: LONGINT;
BEGIN
	drive := d.num-1;
	d.device[drive].cylinders := 1023;  d.device[drive].heads := 16;	(* provisional parameters *)
	d.device[drive].sectrack := 63;  d.device[drive].writePreComp := 65535;
	err := ReadBlocks(drive, 0, 1, SYSTEM.ADR(buf[0]), 0);	(* read first block *)
	IF err = 0 THEN
		IF (buf[510] = 055X) & (buf[511] = 0AAX) THEN	(* valid partition table *)
			phd := -1;  pcyl := -1;	(* find end head and sector for each valid primary partition *)
			FOR i := 0 TO 3 DO
				p := 01BEH + 16*i;
				IF buf[p+4] # 0X THEN	(* partition i in use *)
					hd := ORD(buf[p+5]); 	(* end head *)
					sec := ORD(buf[p+6]) MOD 64;	(* end sector *)
					cyl := ASH(ASH(ORD(buf[p+6]), -6), 8) + ORD(buf[p+7]);	(* end cylinder *)
					IF cyl > pcyl THEN pcyl := cyl END;	(* highest cyl so far *)
					IF phd = -1 THEN phd := hd;  psec := sec
					ELSIF (phd = hd) & (psec = sec) THEN (* skip *)
					ELSE err := 6091	(* inconsistent table *)
					END
				END
			END;
			IF err = 0 THEN
				IF (phd # -1) & (pcyl > 0) THEN	(* set parameters *)
					d.device[drive].cylinders := pcyl+1;  d.device[drive].cylinders0 := pcyl+1;
					d.device[drive].heads := phd+1;  d.device[drive].heads0 := phd+1;
					d.device[drive].sectrack := psec;
					Adjust(d, drive)
				ELSE err := 6092	(* no partitions *)
				END
			END
		ELSE err := 6090	(* no partition table *)
		END
	END;
	IF err # 0 THEN
		Kernel.WriteString("HD");  Kernel.WriteInt(drive, 1);
		Kernel.WriteString(": Not detected (");  Kernel.WriteInt(err, 1);  
		Kernel.WriteChar(")");  Kernel.WriteLn;
		DEC(d.num)	(* not detected *)
	END;
	d.state := Initial0	(* reset on next command *)
END Detect;

(* ReadConfig - Read disk device configuration.  Set d.num and d.device as side effect.  Reads boot table. *)

PROCEDURE ReadConfig(d: Controller);
VAR p, t, i: LONGINT;  s: ARRAY 40 OF CHAR;
BEGIN
	d.num := 0;  large := FALSE;
	Kernel.GetConfig("Disk0", s);
	IF s[0] = 0X THEN	(* Disk0 not specified, use table *)
		p := Kernel.bt;	(* get boot table *)
		LOOP
			SYSTEM.GET(p, t);
			IF t = -1 THEN EXIT	(* end *)
			ELSIF t = 5 THEN	(* HD params *)
				i := d.num;  INC(d.num);
				d.device[i].cylinders := GetPar(p, 0) + 100H*GetPar(p, 1);
				d.device[i].heads := GetPar(p, 2);
				d.device[i].cylinders0 := d.device[i].cylinders;
				d.device[i].heads0 := d.device[i].heads;
				Adjust(d, i);
				d.device[i].writePreComp := GetPar(p, 5) + 100H*GetPar(p, 6);
				d.device[i].sectrack := GetPar(p, 14)
			END;
			SYSTEM.GET(p+4, t);  INC(p, t)
		END
	ELSIF CAP(s[0]) = "A" THEN
		d.num := 1;  Detect(d)
	ELSE
		d.num := 1;  Parse(s, d.device[0])
	END;
	IF d.num >= 1 THEN	(* Disk1 may override second drive info *)
		Kernel.GetConfig("Disk1", s);
		IF CAP(s[0]) = "A" THEN
			d.num := 2;  Detect(d)
		ELSIF s[0] # 0X THEN
			d.num := 2;  Parse(s, d.device[1])
		END
	END;
	IF d.num = 0 THEN
		Kernel.WriteString("Disk: no HD configured")
	ELSE
		FOR i := 0 TO d.num-1 DO
			Kernel.WriteString("HD");  Kernel.WriteInt(i, 1);  Kernel.WriteString(": ");
			Kernel.WriteInt(d.device[i].cylinders*d.device[i].heads*d.device[i].sectrack DIV (100000H DIV BS), 1);
			Kernel.WriteString("Mb ");  Kernel.WriteInt(d.device[i].cylinders, 1);
			Kernel.WriteChar(",");  Kernel.WriteInt(d.device[i].heads, 1);
			Kernel.WriteChar(",");  Kernel.WriteInt(d.device[i].sectrack, 1);
			IF d.device[i].writePreComp # 65535 THEN
				Kernel.WriteChar(",");  Kernel.WriteInt(d.device[i].writePreComp, 1)
			END;
			Kernel.WriteLn
		END
	END
END ReadConfig;

PROCEDURE InitDriver(intnum: SHORTINT;  ctrlPort, regPort: LONGINT);
VAR d: Controller;
BEGIN
	interrupt := 0;
	NEW(par);  NEW(d);  par.controller := d;
	d.state := Initial0;  d.num := 0;  d.port := ctrlPort;  d.regPort := regPort;
	Kernel.InstallIP(InterruptHandler, intnum);
	ReadConfig(d)
END InitDriver;

(* Init - Get parameters and initialise driver *)

PROCEDURE Init;
VAR s: ARRAY 32 OF CHAR;  irq: SHORTINT;  p, c, r: LONGINT;
BEGIN
	Kernel.GetConfig("IDE", s);
	p := 0;  c := 0;  r := 0;
	irq := SHORT(SHORT(StrToInt(p, s)));
	IF s[p] = "," THEN
		INC(p);  c := StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p);  r := StrToInt(p, s)
		END
	END;
	IF irq = 0 THEN irq := 14 END;
	IF c = 0 THEN c := 01F0H END;
	IF r = 0 THEN r := 03F6H END;
	Kernel.WriteString("IDE: ");  Kernel.WriteInt(irq, 1);  Kernel.WriteHex(c, 9);  Kernel.WriteHex(r, 9);  Kernel.WriteLn;
	InitDriver(Kernel.IRQ+irq, c, r)
END Init;

BEGIN
	init := FALSE;  trapped := FALSE;  parttype := -1;  Init
END Disk.

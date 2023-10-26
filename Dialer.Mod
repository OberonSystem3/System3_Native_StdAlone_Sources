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

MODULE Dialer;	(* 26.08.96 mg *)

IMPORT
	Oberon, NetSystem, Strings, Texts, Input, V24, NetBase;

CONST
	RI = 5;  DCD = 6;	(* input *)

VAR
	CW, W: Texts.Writer;
	task, script: Oberon.Task;
	host: ARRAY 64 OF CHAR;
	waitStr: ARRAY 32 OF CHAR;
	waitPos: INTEGER;
	waitTime: LONGINT;
	err: BOOLEAN;
	S: Texts.Scanner;
	port: INTEGER;
	dev: NetBase.Device;

PROCEDURE ^ DoScript(me: Oberon.Task);

PROCEDURE Delay (i: LONGINT);
VAR
	t: LONGINT;
BEGIN t := Oberon.Time();
	WHILE (Oberon.Time() - t) < i DO END
END Delay;

PROCEDURE * V24Input (me: Oberon.Task);
VAR
	ch: CHAR;
	any: BOOLEAN;
	res: LONGINT;
BEGIN any := FALSE;
	WHILE V24.Available(port) > 0 DO
		any := TRUE; V24.Receive(port, ch, res);
		IF ch = 0AX THEN (* skip *)
		ELSIF ch = 0DX THEN Texts.Write(CW, " ") 
		ELSE Texts.Write(CW, ch)
		END;
		IF waitPos >= 0 THEN
			IF CAP(ch) = CAP(waitStr[waitPos]) THEN INC(waitPos);
				IF waitStr[waitPos] = 0X THEN
					waitPos := -1
				END
			ELSE waitPos := 0
			END
		END
	END;
	IF (waitPos >= 0) & (Oberon.Time() > waitTime) THEN err := TRUE;
		Texts.WriteLn(W); Texts.WriteString(W, "timed out waiting for ");
		Texts.WriteString(W, waitStr); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		Oberon.Remove(task); task := NIL;
		IF script # NIL THEN Oberon.Remove(script);
			script := NIL
		END;
		dev := NIL
	END;
	IF any THEN Texts.Append(Oberon.Log, CW.buf) END
END V24Input;

PROCEDURE CmdMode;
BEGIN
	IF task # NIL THEN Oberon.Remove(task)
	ELSE NEW(task)
	END;
	waitPos := -1;
	task.safe := FALSE; task.time := 0;
	task.handle := V24Input; Oberon.Install(task);
	Texts.WriteString(W, "Command mode"); Texts.WriteLn(W);
	Texts.Append(Oberon.Log,W.buf)
END CmdMode;

PROCEDURE InitComPort (port: INTEGER; baud: LONGINT);
VAR
	ok: BOOLEAN;
	res: LONGINT;
BEGIN ok := TRUE;
	Texts.WriteString(W, "Initialising Port ");
	Texts.WriteLn(W);
	V24.Start(port, baud, 8, V24.ParNo, 1, res);
	IF res = 1 THEN
		V24.Stop(port);  V24.Start(port, baud, 8, V24.ParNo, 1, res)
	END;
	ok := FALSE;
	IF res = 0 THEN ok := TRUE
	ELSIF res = 3 THEN
		Texts.WriteString(W,"Baudrate not supported"); Texts.WriteLn(W)
	ELSIF res = 1 THEN
		Texts.WriteString(W,"Port already in use"); Texts.WriteLn(W)
	ELSE
		Texts.WriteString(W,"Init error ");  Texts.WriteInt(W, res, 1); Texts.WriteLn(W)
	END;
	CmdMode;
	Texts.Append(Oberon.Log, W.buf);
	IF ~ok THEN err := TRUE END
END InitComPort;

PROCEDURE SendStr(str: ARRAY OF CHAR);
VAR
	ch: CHAR;
	i: INTEGER;
	res: LONGINT;
BEGIN waitPos := -1; i := 0;
	WHILE str[i] # 0X DO ch := str[i];
		IF ch = "~" THEN Delay(300)
		ELSE V24.Send(port, ch, res)
		END;
		INC(i)
	END;
	V24.Send(port, 0DX, res)
END SendStr;

PROCEDURE WaitStr(str: ARRAY OF CHAR; timeOut: LONGINT);
BEGIN COPY(str, waitStr);
	waitPos := 0; waitTime := Oberon.Time() + timeOut
END WaitStr;

PROCEDURE * DoScript (me: Oberon.Task);
VAR
	user, passwd: ARRAY 64 OF CHAR;
	timo: LONGINT;
BEGIN err := FALSE;
	IF waitPos >= 0 THEN RETURN END;
	IF task # NIL THEN task.handle(task) END;
	IF S.class = Texts.Name THEN
		IF S.s = "USER" THEN user := "";
			NetSystem.GetPassword("slip", host, user, passwd);
			Texts.WriteString(W, "Sending [");  Texts.WriteString(W, user);  Texts.Write(W, "]"); 
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			IF user # "" THEN SendStr(user); Texts.Scan(S)
			ELSE err := TRUE
			END
		ELSIF S.s = "PASSWORD" THEN user := "";
			NetSystem.GetPassword("slip", host, user, passwd);
			Texts.WriteString(W, "Sending PASSWORD");  
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			IF passwd # "" THEN SendStr(passwd); Texts.Scan(S)
			ELSE err := TRUE
			END
		ELSIF S.s = "START" THEN
			Texts.WriteString(W, "Enabling ");  Texts.WriteString(W, dev.name);
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			IF (dev # NIL) & (dev.state = NetBase.pending) THEN
				dev.state := NetBase.open
			END;
			dev := NIL; Texts.Scan(S)
		ELSE err := TRUE
		END
	ELSIF S.class = Texts.String THEN
		Texts.WriteString(W, "Sending [");  Texts.WriteString(W, S.s);  Texts.Write(W, "]");
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
		SendStr(S.s); Texts.Scan(S)
	ELSIF S.class = Texts.Int THEN
		timo := S.i * Input.TimeUnit; Texts.Scan(S);
		IF S.class = Texts.String THEN
			Texts.WriteString(W, "Waiting ");  Texts.WriteInt(W, timo DIV Input.TimeUnit, 1);
			Texts.WriteString(W, "s for [");   Texts.WriteString(W, S.s);  Texts.Write(W, "]");
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			WaitStr(S.s, timo); Texts.Scan(S)
		ELSE err := TRUE
		END
	ELSIF S.class = Texts.Char THEN
		IF S.c = "}" THEN
			Texts.WriteString(W, "End of dial script");
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			IF task # NIL THEN
				Oberon.Remove(task); task := NIL
			END;
			Oberon.Remove(script); script := NIL;
			dev := NIL
		ELSE err := TRUE
		END
	ELSE HALT(99)
	END;
	IF err THEN
		IF task # NIL THEN
			Oberon.Remove(task);
			task := NIL
		END;
		Oberon.Remove(script); script := NIL;
		dev := NIL;
		IF err THEN Texts.WriteString(W, "script aborted");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END
END DoScript;

PROCEDURE Dial*;
VAR
	S0: Texts.Scanner;
	prefix, path: ARRAY 64 OF CHAR;
	err: BOOLEAN;
BEGIN err := FALSE;
	Texts.OpenScanner(S0, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S0);
	IF S0.class = Texts.Name THEN COPY(S0.s, prefix);
		COPY(prefix, path); Strings.Append(path, ".Host");
		Oberon.OpenScanner(S, path); COPY(S.s, host);
		Texts.Scan(S0);
		IF S0.class = Texts.Name THEN
			dev := NetBase.FindDevice(S0.s);
			IF dev # NIL THEN
				IF dev.state = NetBase.open THEN
					dev.state := NetBase.pending;
					Texts.WriteString(W, "Warning: ");  Texts.WriteString(W, S0.s);
					Texts.WriteString(W, " device is already open");  Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf)
				END;
				COPY(prefix, path); Strings.Append(path, ".Init");
				Oberon.OpenScanner(S, path);
				IF S.class = Texts.Name THEN
					IF S.s = "COM1" THEN port := 0
					ELSIF S.s = "COM2" THEN port := 1
					ELSE HALT(99)
					END;
					Texts.Scan(S);
					IF S.class = Texts.Int THEN InitComPort(port, S.i);
						COPY(prefix, path); Strings.Append(path, ".Dial");
						Oberon.OpenScanner(S, path);
						IF script # NIL THEN Oberon.Remove(script)
						ELSE NEW(script)
						END;
						waitPos := -1; script.safe := FALSE;
						script.time := 0; script.handle := DoScript;
						Oberon.Install(script)
					ELSE Texts.WriteString(W, "Init syntax error"); err := TRUE
					END
				ELSE Texts.WriteString(W, "Init syntax error"); err := TRUE
				END
			ELSE Texts.WriteString(W, S0.s); Texts.WriteString(W, " device not found"); err := TRUE
			END
		ELSE Texts.WriteString(W, "Dial syntax error"); err := TRUE
		END
	ELSE Texts.WriteString(W, "Dial syntax error"); err := TRUE
	END;
	IF err THEN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf) END
END Dial;

PROCEDURE GetPort(VAR port: INTEGER;  VAR dev: ARRAY OF CHAR);
VAR S, R: Texts.Scanner;  i: LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	COPY("", dev);
	IF S.class = Texts.Name THEN
		Strings.Append(S.s, ".Init");
		Oberon.OpenScanner(R, S.s);
		IF R.s = "COM1" THEN port := 0
		ELSIF R.s = "COM2" THEN port := 1
		ELSE HALT(99)
		END;
		Texts.Scan(S);
		IF S.class = Texts.Name THEN COPY(S.s, dev) END
	ELSE HALT(99)
	END
END GetPort;

PROCEDURE Hangup*;
VAR port: INTEGER;  name: ARRAY 32 OF CHAR;
BEGIN
	GetPort(port, name);
	V24.ClearMC(port, {V24.DTR});
	Delay(Input.TimeUnit DIV 6);
	V24.SetMC(port, {V24.DTR})
END Hangup;

PROCEDURE State*;
VAR port: INTEGER;  name: ARRAY 32 OF CHAR;  s: SET;
BEGIN
	GetPort(port, name);
	V24.GetMC(port, s);
	IF DCD IN s THEN
		Texts.WriteString(W, "Modem connected");  Texts.WriteLn(W)
	ELSE
		Texts.WriteString(W, "Modem not connected");  Texts.WriteLn(W)
	END;
	IF name # "" THEN
		dev := NetBase.FindDevice(name);
		Texts.WriteString(W, name); Texts.WriteString(W, " device ");
		IF dev = NIL THEN
			Texts.WriteString(W, "not installed")
		ELSE
			IF dev.state = NetBase.closed THEN
				Texts.WriteString(W, "closed")
			ELSIF dev.state = NetBase.open THEN
				Texts.WriteString(W, "open")
			ELSIF dev.state = NetBase.pending THEN
				Texts.WriteString(W, "link pending")
			ELSE
				Texts.WriteString(W, "in state"); Texts.WriteInt(W, dev.state, 1)
			END
		END;
		Texts.WriteLn(W)
	END;
	Texts.Append(Oberon.Log, W.buf)
END State;

BEGIN Texts.OpenWriter(W); Texts.OpenWriter(CW); (*Texts.SetColor(CW, 3);*)
	task := NIL; script := NIL; dev := NIL; port := 1
END Dialer.

System.Free Dialer ~

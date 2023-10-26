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

MODULE EmptyNet;

(* Empty network driver *)

IMPORT SYSTEM, NetBase, Texts, Oberon;

TYPE 
	Device = POINTER TO DeviceDesc;
	DeviceDesc = RECORD (NetBase.DeviceDesc)
	END;
	
VAR
	dev: Device;

(* Send - Send a packet. *)

PROCEDURE Send(dev: NetBase.Device; prno: INTEGER; VAR dest: ARRAY OF SYSTEM.BYTE; item: NetBase.Item);
END Send;

(* Avail - Return TRUE iff a packet is available *)

PROCEDURE Avail(dev: NetBase.Device): BOOLEAN;
BEGIN
	RETURN FALSE
END Avail;

(* ReceivePacket - Remove a packet from the input buffer *)

PROCEDURE Receive(dev: NetBase.Device;  VAR prno: INTEGER; VAR src: ARRAY OF SYSTEM.BYTE; VAR item: NetBase.Item);
BEGIN
	item.len := 0
END Receive;

PROCEDURE Install(name: ARRAY OF CHAR);
VAR w: Texts.Writer;
BEGIN
	NEW(dev);  dev.typ := NetBase.broadcast;  dev.state := NetBase.closed;
	dev.sndCnt := 0;  dev.recCnt := 0;
	COPY(name, dev.name);
	dev.Receive := Receive;  dev.Send := Send;  dev.Available := Avail;
	NetBase.InstallDevice(dev, name);
	Texts.OpenWriter(w);
	Texts.WriteString(w, "Null network driver installed");  Texts.WriteLn(w);
	Texts.Append(Oberon.Log, w.buf)
END Install;

(** InstallDevice - Command to install net device.  Device name is parameter. *)

PROCEDURE InstallDevice*;	(* devname *)
VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF S.class = Texts.Name THEN Install(S.s)
	ELSE HALT(99)
	END
END InstallDevice;

END EmptyNet.

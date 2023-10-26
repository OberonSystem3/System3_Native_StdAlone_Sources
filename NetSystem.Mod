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

MODULE NetSystem;	(* mg 16.08.96 *)

IMPORT Oberon, SYSTEM, Input, Texts, DNS, TCP, UDP, Ports, NetBase, Kernel, Strings, Fonts, Ip := IP, TextFrames;

CONST
	anyport* = 0;	(** "NIL" port value *)

(** result values *)
	done* = 0;	(** everything went ok *)
	error* = 1;	(** failure occured *)
	
(** return values of procedure State *)
	closed* = 0;	(** connection is closed (neither sending nor receiving) *)
	listening* = 1;	(** passive connection is listening for a request *)
	in* = 2;	(** receiving only *)
	out* = 3;	(** sending only *)
	inout* = 4;	(** sending and receiving is possible *)
	waitCon * =  5;	(** still waiting to be connected *)
	errorCon* =  6;	(** connecting failed *)

	CR = 0DX;
	LF = 0AX;

TYPE
	Connection* = POINTER TO ConnectionDesc;	(** handle for TCP connections *)
	ConnectionDesc* = RECORD
		port: Ports.Port;
		res*: INTEGER;	(** result of last operation on a connection (error indication) *)
		state: INTEGER;
		Available: PROCEDURE (C: Connection; VAR res: INTEGER): LONGINT;
		Receive: PROCEDURE (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
		Send: PROCEDURE (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
	END;

	IPAdr* = LONGINT; (** IP address in network byte order *)

	Socket* = POINTER TO SocketDesc;	(** handle for UDP "connections" *)
	SocketDesc* = RECORD
		C: UDP.Connection;
		res*: INTEGER;	(** result of last operation on a connection (error indication) *)
		state: INTEGER
	END;

	Password = POINTER TO PasswordDesc;
	PasswordDesc = RECORD
		service, user, host, passwd: ARRAY 64 OF CHAR;
		next: Password
	END;

VAR
	anyIP*: IPAdr;	(** "NIL" ip-number *)
	allIP*: IPAdr;	(** broadcast ip-number *)
	hostIP*: IPAdr;	(** main ip-number of local machine *)
	hostName*: ARRAY 64 OF CHAR;	(** main name of local machine *)
	started: BOOLEAN;
	W: Texts.Writer;
	passwords: Password;

PROCEDURE GetEntry (key, name: ARRAY OF CHAR; VAR arg0, arg1: ARRAY OF CHAR);
VAR
	S: Texts.Scanner;
	key0: ARRAY 64 OF CHAR;
	i, j: INTEGER;
BEGIN COPY(key, key0);
	i := 0; WHILE key0[i] # 0X DO INC(i) END;
	j := 0; WHILE name[j] # 0X DO key0[i] := name[j]; INC(i); INC(j) END;
	key0[i] := 0X; Oberon.OpenScanner(S, key0);
	IF S.class IN {Texts.Name, Texts.String} THEN
		COPY(S.s, arg0); Texts.Scan(S)
	ELSE COPY("", arg0)
	END;
	IF (S.class = Texts.Char) & (S.c = ",") THEN Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, arg1)
		ELSE COPY("", arg1)
		END
	ELSE COPY("", arg1)
	END
END GetEntry;
	
PROCEDURE GetEntry0 (key, name: ARRAY OF CHAR; VAR arg: ARRAY OF CHAR);
VAR
	S: Texts.Scanner;
	key0: ARRAY 64 OF CHAR;
	i, j: INTEGER;
BEGIN COPY(key, key0);
	i := 0; WHILE key0[i] # 0X DO INC(i) END;
	j := 0; WHILE name[j] # 0X DO key0[i] := name[j]; INC(i); INC(j) END;
	key0[i] := 0X; Oberon.OpenScanner(S, key0);
	IF S.class IN {Texts.Name, Texts.String} THEN
		COPY(S.s, arg); Texts.Scan(S)
	ELSE COPY("", arg)
	END
END GetEntry0;
	
PROCEDURE ToNum0 (num: ARRAY OF CHAR; VAR n: INTEGER; VAR done: BOOLEAN);
VAR
	i: INTEGER;
BEGIN n := 0; i := 0;
	WHILE ("0" <= num[i]) & (num[i] <= "9") DO
		n := n * 10 + ORD(num[i]) - ORD("0"); INC(i)
	END;
	done := num[i] = 0X
END ToNum0;

PROCEDURE ToHost0 (num: ARRAY OF CHAR; VAR adr: Ip.Adr; VAR done: BOOLEAN);
VAR
	addr: LONGINT;
	buf: ARRAY 32 OF CHAR;
	i, j, k, n: INTEGER;
BEGIN done := TRUE;
	addr := 0; i := 0; j := 0; 
	WHILE done & (j < 4) & (num[i] # 0X) DO
		k := 0;
		WHILE (num[i] # ".") & (num[i] # 0X) DO
			buf[k] := num[i]; INC(k); INC(i)
		END;
		buf[k] := 0X; ToNum0(buf, n, done);
		addr := ASH(addr, 8) + n; done := done & (n <= 256);
		IF num[i] = "." THEN INC(i) END;
		INC(j)
	END;
	NetBase.Copy(addr, adr, Ip.AdrLen); NetBase.HostLToNet(adr);
	done := done & (j = 4) & (num[i] = 0X)
END ToHost0;

(** -- Adressing/Naming section. *)

(** Convert a dotted IP address string (e.g. "1.2.3.4") to an IPAdr value. *)

PROCEDURE ToHost* (num: ARRAY OF CHAR; VAR adr: IPAdr; VAR done: BOOLEAN);
VAR a: Ip.Adr;
BEGIN
	ToHost0(num, a, done);
	IF done THEN NetBase.Copy(a, adr, Ip.AdrLen)
	ELSE NetBase.Copy(anyIP, adr, Ip.AdrLen)
	END
END ToHost;

(** Convert an IPAdr value to a dotted IP address string *)

PROCEDURE ToNum*(adr: IPAdr; VAR num: ARRAY OF CHAR);
	VAR i, j, n: LONGINT;
	PROCEDURE Digit(d: LONGINT);
	BEGIN
		num[j] := CHR(ORD("0")+d); INC(j)
	END Digit;
BEGIN
	j := 0;
	FOR i := 0 TO 3 DO
		n := adr MOD 256; adr := adr DIV 256;
		IF n >= 100 THEN
			Digit(n DIV 100); Digit((n DIV 10) MOD 10)
		ELSIF n >= 10 THEN
			Digit(n DIV 10)
		END;
		Digit(n MOD 10);
		num[j] := "."; INC(j)
	END;
	num[j-1] := 0X
END ToNum;

(** Procedure delivers the ip-number of a named host. If a symbolic name is given, it will be resolved by use of domain name
	servers. *)

PROCEDURE GetIP* (name: ARRAY OF CHAR; VAR IP: IPAdr);
VAR
	hostName, hostIP: ARRAY 64 OF CHAR;
	adr: Ip.Adr;
	res: INTEGER;
	done: BOOLEAN;
BEGIN
	IF (CAP(name[0]) >= "A") & (CAP(name[0]) <= "Z") THEN
		GetEntry("NetSystem.Hosts.", name, hostName, hostIP);
		IF hostIP # "" THEN
			ToHost0(hostIP, adr, done)
		ELSE
			IF started THEN
				IF hostName # "" THEN
					DNS.HostByName(hostName, adr, res)
				ELSE DNS.HostByName(name, adr, res)
				END;
				done := (res = DNS.Done)
			ELSE
				done := FALSE
			END
		END
	ELSIF (name[0] >= "0") & (name[0] <= "9") THEN
		ToHost0(name, adr, done)
	ELSE done := FALSE
	END;
	IF ~done THEN IP := anyIP
	ELSE NetBase.Copy(adr, IP, Ip.AdrLen)
	END
END GetIP;

(** GetName is the reverse of GetIP. Given an ip-number, it delivers the name of a host. *)

PROCEDURE GetName* (IP: IPAdr; VAR name: ARRAY OF CHAR);
VAR
	adr: Ip.Adr;
	res: INTEGER;
BEGIN
	IF started THEN
		NetBase.Copy(IP, adr, Ip.AdrLen);
		DNS.HostByNumber(adr, name, res)
	END;
	IF ~started OR (res # DNS.Done) THEN COPY("", name) END
END GetName;

(** -- TCP section. *)

(* Stream oriented communication *)

PROCEDURE TCPSetState (C: Connection);
BEGIN
	IF ~TCP.Connected(C.port(TCP.Connection)) THEN
		IF C.state = inout THEN C.state := out
		ELSIF C.state = in THEN C.state := closed
		END
	END
END TCPSetState;

PROCEDURE TCPAvailable (C: Connection; VAR res: INTEGER): LONGINT;
VAR
	len: LONGINT;
BEGIN len := TCP.Available(C.port(TCP.Connection));
	IF len < 0 THEN len := 0; res := error ELSE res := done END;
	TCPSetState(C); RETURN len
END TCPAvailable;

PROCEDURE TCPReceive (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
VAR
	l: LONGINT;
BEGIN l := 0;
	REPEAT l := len;
		TCP.Receive(C.port(TCP.Connection), buf, beg, l);
		IF l > 0 THEN beg := beg + l; len := len - l END
	UNTIL (len = 0) OR (l < 0);
	IF l < 0 THEN res := error ELSE res := done END;
	TCPSetState(C)
END TCPReceive;

PROCEDURE TCPSend (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
BEGIN TCP.Send(C.port(TCP.Connection), buf, beg, len);
	IF len < 0 THEN res := error ELSE res := done END;
	TCPSetState(C)
END TCPSend;

PROCEDURE DmyAvailable (C: Connection; VAR res: INTEGER): LONGINT;
BEGIN res := error; RETURN 0
END DmyAvailable;

PROCEDURE DmyReceive (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
BEGIN res := error
END DmyReceive;

PROCEDURE DmySend (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
BEGIN res := error
END DmySend;

PROCEDURE ^Cleanup(c: SYSTEM.PTR);

(** Procedure opens a connection. locPort, remPort, remIP are contained in the quadrupel <locIP, remIP, locPort, remPort>
	which determines a connection uniquely. As locIP is always the current machine, it is omitted. If remPort is equal to
	anyport or remIP is equal to anyIP, a passive connection will be opened. After execution, C is a brand new connection.
	res indicates any error. *)

PROCEDURE OpenConnection* (VAR C: Connection; locPort: INTEGER; remIP: IPAdr; remPort: INTEGER; VAR res: INTEGER);
VAR
	conC: TCP.Connection;
	listC: TCP.Listener;
	remAdr: Ip.Adr;
BEGIN
	IF started THEN
		NetBase.Copy(remIP, remAdr, Ip.AdrLen); NEW(C);
		IF NetBase.Equal(remIP, Ip.IPany, Ip.AdrLen) OR (remPort = Ports.anyport) THEN
			TCP.Listen(listC, locPort, remAdr, remPort, C.res);
			IF C.res = TCP.Done THEN C.port := listC;
				C.state := listening; C.Available := DmyAvailable;
				C.Send := DmySend; C.Receive := DmyReceive;
				Kernel.RegisterObject(C, Cleanup, FALSE)
			ELSIF C.res # TCP.Timeout THEN C.res := error
			END;
			res := C.res
		ELSIF ~Ip.Broadcast(remAdr) THEN
			TCP.Connect(conC, locPort, remAdr, remPort, C.res);
			IF C.res = TCP.Done THEN C.port := conC;
				C.state := inout; C.Available := TCPAvailable;
				C.Send := TCPSend; C.Receive := TCPReceive;
				Kernel.RegisterObject(C, Cleanup, FALSE)
			ELSIF C.res # TCP.Timeout THEN C.res := error
			END;
			res := C.res
		ELSE res := error
		END
	ELSE res := error
	END
END OpenConnection;

(** Like OpenConnection, but this procedure may return immediately and delay the actual opening of the connection.  
	In this case State() should be checked to wait for the connection status to change from waitCon. *)

PROCEDURE AsyncOpenConnection*(VAR C: Connection; locPort: INTEGER; remIP: IPAdr; remPort:INTEGER; VAR res: INTEGER);
BEGIN
	OpenConnection(C, locPort, remIP, remPort, res)	(* currently implemented synchronously *)
END AsyncOpenConnection;

(** Procedure closes the connection. Connection can not be used for send operations afterwards. *)

PROCEDURE CloseConnection* (C: Connection);
BEGIN
	IF C # NIL THEN
		IF C.port IS TCP.Listener THEN C.state := closed;
			TCP.Close(C.port(TCP.Listener))
		ELSIF C.port IS TCP.Connection THEN
			IF C.state = inout THEN C.state := in
			ELSIF C.state = out THEN C.state := closed
			END;
			TCP.Disconnect(C.port(TCP.Connection))
		ELSE HALT(99)
		END;
		C.res := done
	END
END CloseConnection;

PROCEDURE Cleanup(c: SYSTEM.PTR);
BEGIN
	WITH c: Connection DO
		IF c.state # closed THEN
			CloseConnection(c)
		END
	END
END Cleanup;

(** Indicates whether there exists a remote machine which wants to connect to the local one. This Procedure is only usefully
	defined on passive connections. For active connections (State(C) # listen), it always delivers FALSE. *)

PROCEDURE Requested* (C: Connection): BOOLEAN;
BEGIN RETURN (C.port IS TCP.Listener) & TCP.Requested(C.port(TCP.Listener))
END Requested;

(** Procedure accepts a new waiting, active connection (newC) on a passive one (State(C) = listen). If no connection is 
	waiting, accept blocks until there is one or an error occurs. If C is not a passive connection, Accept does nothing
	but res is set to Done. *)

PROCEDURE Accept* (C: Connection; VAR newC: Connection; VAR res: INTEGER);
VAR
	conC: TCP.Connection;
BEGIN res := TCP.NotDone;
	IF C.port IS TCP.Listener THEN
		TCP.Accept(C.port(TCP.Listener), conC, res);
		IF res = TCP.Done THEN NEW(newC);
			newC.port := conC; newC.state := inout;
			newC.Available := TCPAvailable;
			newC.Send := TCPSend; newC.Receive := TCPReceive
		END
	END;
	C.res := res
END Accept;

(** Procedure returns the state of a connection (see constant section). *)

PROCEDURE State* (C: Connection): INTEGER;
BEGIN RETURN C.state
END State;

(** Returns the number of bytes which may be read without blocking. *)

PROCEDURE Available* (C: Connection): LONGINT;
BEGIN RETURN C.Available(C, C.res)
END Available;

(** Blocking read a single byte. *)

PROCEDURE Read* (C: Connection; VAR ch: CHAR);
BEGIN C.Receive(C, ch, 0, 1, C.res)
END Read;

(** Blocking read len bytes of data (beginning at pos in buf) to buf. *)

PROCEDURE ReadBytes* (C: Connection; pos, len: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE);
BEGIN C.Receive(C, buf, pos, len, C.res);
END ReadBytes;

(** Blocking read two bytes in network byte ordering. *)

PROCEDURE ReadInt* (C: Connection; VAR x: INTEGER);
BEGIN C.Receive(C, x, 0, 2, C.res); NetBase.NetToHost(x)
END ReadInt;

(** Blocking read four bytes in network byte ordering. *)

PROCEDURE ReadLInt* (C: Connection; VAR x: LONGINT);
BEGIN C.Receive(C, x, 0, 4, C.res); NetBase.NetLToHost(x);
END ReadLInt;

(** Blocking read a string terminated by ( [CR]LF | 0X ). *)

PROCEDURE ReadString* (C: Connection; VAR s: ARRAY OF CHAR);
VAR
	ch, ch0: CHAR;
	i: INTEGER;
BEGIN i := -1; ch := 0X;
	REPEAT INC(i);
		ch0 := ch; C.Receive(C, ch, 0, 1, C.res); s[i] := ch;
	UNTIL (C.res = error) OR (ch = 0X) OR (ch = LF);
	IF (ch = LF) & (ch0 = CR) THEN
		s[i - 1] := 0X ELSE s[i] := 0X
	END
END ReadString;

(** Blocking write a single byte to C. *)

PROCEDURE Write* (C: Connection; ch: CHAR);
BEGIN C.Send(C, ch, 0, 1, C.res)
END Write;

(** Blocking write len bytes of data (beginning at pos in buf) to C. *)

PROCEDURE WriteBytes* (C: Connection; pos, len: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE);
BEGIN C.Send(C, buf, pos, len, C.res)
END WriteBytes;

(** Blocking write two bytes in network byte ordering to C. *)

PROCEDURE WriteInt* (C: Connection; x: INTEGER);
BEGIN NetBase.HostToNet(x); C.Send(C, x, 0, 2, C.res)
END WriteInt;

(** Blocking write four bytes in network byte ordering to C. *)

PROCEDURE WriteLInt* (C: Connection; x: LONGINT);
BEGIN NetBase.HostLToNet(x); C.Send(C, x, 0, 4, C.res)
END WriteLInt;

(** Blocking write a string without "0X" and terminated by "CRLF" to C. *)

PROCEDURE WriteString* (C: Connection; s: ARRAY OF CHAR);
VAR
	cs: ARRAY 2 OF CHAR;
	i: INTEGER;
BEGIN  i := 0;
	WHILE s[i] # 0X DO INC(i) END;
	C.Send(C, s, 0, i, C.res);
	cs[0] := CR; cs[1] := LF;
	C.Send(C, cs, 0, 2, C.res)
END WriteString;

(** Procedure delivers the ip-number and port number of a connection's remote partner. *)

PROCEDURE GetPartner* (C: Connection; VAR remIP: IPAdr; VAR remPort: INTEGER);
BEGIN remPort := C.port.rport; NetBase.Copy(C.port.rip, remIP, Ip.AdrLen)
END GetPartner;

(** -- UDP section. *)

(* Datagram oriented communication *)

(** Opens a socket which is dedicated to datagram services. locPort is registered to receive datagrams
	from any port and any host. *)

PROCEDURE OpenSocket* (VAR S: Socket; locPort: INTEGER; VAR res: INTEGER);
BEGIN
	IF started THEN NEW(S);
		UDP.Open(S.C, locPort, Ip.IPany, Ports.anyport, S.res);
		IF S.res = UDP.Done THEN S.state := inout
		ELSE S.C := NIL; S.res := error
		END;
		res := S.res
	ELSE res := error
	END
END OpenSocket;

(** Closes the socket. You can not receive datagrams anymore. *)

PROCEDURE CloseSocket* (S: Socket);
BEGIN S.state := closed; UDP.Close(S.C); S.C := NIL; S.res := done
END CloseSocket;

(** Sends len bytes of data (beginning at pos in buf) to the host specified by remIP and remPort. *)

PROCEDURE SendDG* (S: Socket; remIP: IPAdr; remPort: INTEGER; pos, len: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE);
VAR
	radr: Ip.Adr;
BEGIN NetBase.Copy(remIP, radr, Ip.AdrLen);
	UDP.Send(S.C, radr, remPort, buf, pos, len); S.res := done
END SendDG;

(** Stores an entire datagram in buf beginning at pos. On success (S.res = done), remIP and remPort indicate the sender,
	len indicate the length of valid data. *)

PROCEDURE ReceiveDG*(S: Socket; VAR remIP: IPAdr; VAR remPort: INTEGER; pos: LONGINT; VAR len: LONGINT;
	VAR buf: ARRAY OF SYSTEM.BYTE);
VAR
	radr: Ip.Adr;
BEGIN UDP.Receive(S.C, radr, remPort, buf, pos, len);
	IF len >= 0 THEN NetBase.Copy(radr, remIP, Ip.AdrLen); S.res := done ELSE S.res := error END
END ReceiveDG;

(** Returns the number of available datagrams, that were received on the socket. *)

PROCEDURE AvailableDG* (S: Socket): LONGINT;
BEGIN RETURN UDP.Available(S.C)
END AvailableDG;

(* Conversions *)

(** Write 2 bytes in network byte ordering to buf[pos]. *)

PROCEDURE PutInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; x: INTEGER);
BEGIN NetBase.HostToNet(x);
	SYSTEM.PUT(SYSTEM.ADR(buf[pos]), x)
END PutInt;

(** Write 4 bytes in network byte ordering to buf[pos]. *)

PROCEDURE PutLInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; x: LONGINT);
BEGIN NetBase.HostLToNet(x);
	SYSTEM.PUT(SYSTEM.ADR(buf[pos]), x)
END PutLInt;

(** Read 2 bytes in network byte ordering from buf[pos]. *)

PROCEDURE GetInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; VAR x: INTEGER);
BEGIN SYSTEM.GET(SYSTEM.ADR(buf[pos]), x);
	NetBase.NetToHost(x)
END GetInt;

(** Read 4 bytes in network byte ordering from buf[pos]. *)

PROCEDURE GetLInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; VAR x: LONGINT);
BEGIN SYSTEM.GET(SYSTEM.ADR(buf[pos]), x);
	NetBase.NetLToHost(x)
END GetLInt;

(** -- Passwords section. *)

(** Retrieve the password for user using service on host.  Parameters service, host and user must be specified. 
Parameter user is in/out.  If empty, it returns the first (user,password) pair found, otherwise it returns the
specified user's password. *)

PROCEDURE GetPassword*(service, host: ARRAY OF CHAR;  VAR user, password: ARRAY OF CHAR);
VAR pass: Password;  r: Texts.Reader;  ch: CHAR;
BEGIN
	Strings.Lower(service, service);  Strings.Lower(host, host);
	pass := passwords;
	WHILE (pass # NIL) & ~((pass.service = service) & (pass.host = host) & ((user = "") OR (pass.user = user))) DO
		pass := pass.next
	END;
	IF pass # NIL THEN
		COPY(pass.user, user);  COPY(pass.passwd, password)
	ELSE
		IF (service # "") & (user # "") THEN
			IF Oberon.Log.len > 0 THEN
				Texts.OpenReader(r, Oberon.Log, Oberon.Log.len-1);
				Texts.Read(r, ch);
				IF ch # CHR(13) THEN Texts.WriteLn(W) END
			END;
			Texts.WriteString(W, "NetSystem.SetUser ");
			IF service # "" THEN Texts.WriteString(W, service) ELSE Texts.WriteString(W, "<service>") END;
			Texts.Write(W, ":");
			IF user # "" THEN Texts.WriteString(W, user) ELSE Texts.WriteString(W, "<user>") END;
			Texts.Write(W, "@");
			Texts.WriteString(W, host);  Texts.WriteString(W, " ~"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
		COPY("", user); COPY("", password)
	END
END GetPassword;

(** Remove password for user using service on host. *)

PROCEDURE DelPassword*(service, user, host: ARRAY OF CHAR);
	VAR ppass, pass: Password;
BEGIN
	Strings.Lower(service, service);  Strings.Lower(host, host);
	ppass := NIL; pass := passwords;
	WHILE (pass # NIL) & ((pass.service # service) & (pass.host # host) & (pass.user # user)) DO
		ppass := pass; pass := pass.next
	END;
	IF pass # NIL THEN
		IF ppass # NIL THEN
			ppass.next := pass.next
		ELSE
			passwords := pass.next
		END
	END
END DelPassword;

(** Command NetSystem.SetUser { service ":" ["//"] user [ ":" password ] "@" host [ "/" ] } "~" <enter password>
		If password is not specified in-line, prompts for the password for the (service, host, user) triple. 
		The (service, host, user, password) 4-tuple is stored in memory for retrieval with GetPassword. 
		Multiple identical passwords may be set with one command. *)
		
PROCEDURE SetUser*;
	VAR
		R: Texts.Reader;
		service, usr, host, pwd: ARRAY 64 OF CHAR;
		pass, list: Password;
		ok, verbose: BOOLEAN;
		ch: CHAR;

	PROCEDURE Next(VAR str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		Texts.Read(R, ch);
		WHILE ~R.eot & ((ch <= " ") OR (ch = ":") OR (ch = "@") OR (ch = "/") OR ~(R.lib IS Fonts.Font)) DO
			Texts.Read(R, ch)
		END;
		i := 0;
		WHILE ~R.eot & (ch > " ") & (ch # ":") & (ch # "@") & (ch # "/") & (ch # "~") & (R.lib IS Fonts.Font) DO
			str[i] := ch; INC(i); Texts.Read(R, ch)
		END;
		str[i] := 0X
	END Next;
	
	PROCEDURE ReadPwd;
		VAR i: LONGINT;
	BEGIN
		Texts.WriteString(W, "Password: ");  Texts.Append(Oberon.Log, W.buf);
		Input.Read(ch); i := 0;
		WHILE ch > " " DO
			IF ch = 7FX THEN
				IF i > 0 THEN
					Texts.Delete(Oberon.Log, Oberon.Log.len-1, Oberon.Log.len);
					DEC(i)
				END
			ELSE
				Texts.Write(W, "*");  Texts.Append(Oberon.Log, W.buf);
				pwd[i] := ch;  INC(i)
			END;
			Input.Read(ch)
		END;
		pwd[i] := 0X;
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
	END ReadPwd;
		
	PROCEDURE Replace(p: Password);
	VAR q: Password;
	BEGIN
		q := passwords;
		WHILE (q # NIL) & ~((q.service = p.service) & (q.host = p.host) & (q.user = p.user)) DO
			q := q.next
		END;
		IF verbose THEN
			Texts.WriteString(W, p.service);  Texts.Write(W, ":");  
			Texts.WriteString(W, p.user);  Texts.Write(W, "@");  Texts.WriteString(W, p.host)
		END;
		IF q = NIL THEN
			p.next := passwords;  passwords := p;
			IF verbose THEN Texts.WriteString(W, " password set") END
		ELSE
			COPY(p.passwd, q.passwd);
			IF verbose THEN Texts.WriteString(W, " password replaced") END
		END;
		IF verbose THEN Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf) END
	END Replace;
	
BEGIN
	Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
	ok := TRUE;  verbose := FALSE;  list := NIL;
	WHILE ~R.eot & ok DO
		ok := FALSE;  Next(service);
		IF service = "\v" THEN verbose := TRUE; Next(service) END;
		Strings.Lower(service, service);
		IF ch = ":" THEN
			Next(usr);
			IF ch = "@" THEN	(* no password specified, prompt for password later *)
				Next(host);  Strings.Lower(host, host);
				IF host # "" THEN
					NEW(pass);  pass.next := list;  list := pass;	(* add to temp list *)
					COPY(service, pass.service); COPY(host, pass.host); COPY(usr, pass.user);
					ok := TRUE
				END
			ELSIF ch = ":" THEN	(* password specified in-line *)
				Next(pwd);
				IF ch = "@" THEN
					Next(host);
					IF host # "" THEN
						NEW(pass);  COPY(service, pass.service); COPY(host, pass.host); 
						COPY(usr, pass.user);  COPY(pwd, pass.passwd);
						Replace(pass);  ok := TRUE
					END
				END
			END
		END
	END;
	IF list # NIL THEN
		ReadPwd;
		IF ch = 0DX THEN	(* password entered *)
			WHILE list # NIL DO
				pass := list;  list := list.next;  COPY(pwd, pass.passwd);  Replace(pass)
			END
		END
	END
END SetUser;

(** Command NetSystem.ClearUser ~  Clear all passwords from memory. *)

PROCEDURE ClearUser*;
BEGIN
	passwords := NIL
END ClearUser;

(** -- Initialisation section. *)

PROCEDURE SetDevices;
VAR
	T: Texts.Text;
	device, name, arg: ARRAY 32 OF CHAR;
	i, res: INTEGER;
	par: Oberon.ParList;
	F: TextFrames.Frame;
BEGIN NEW(T);
	i := 0; device := "Device0"; GetEntry("NetSystem.Hosts.", device, name, arg);
	WHILE (i < NetBase.MaxDevices) & (name # "") DO Texts.Open(T, "");
		Texts.WriteString(W, name);  Texts.Write(W, " ");
		Texts.WriteString(W, arg); Texts.WriteLn(W); Texts.Append(T, W.buf);
		IF Oberon.Par = NIL THEN par := NIL
		ELSE NEW(par); par^ := Oberon.Par^
		END;
		F := TextFrames.NewText(T, 0);  TextFrames.Call(F, 0, FALSE);
		IF (par # NIL) & (Oberon.Par # NIL) THEN Oberon.Par^ := par^ END;
		INC(i); device[6] := CHR(i+ORD("0"));
		GetEntry("NetSystem.Hosts.", device, name, arg)
	END
END SetDevices;

PROCEDURE SetRoutes;
VAR
	route: Ip.Route;
	key, rname: ARRAY 64 OF CHAR;
	hostname, num, device, arp, dmy, gateway: ARRAY 64 OF CHAR;
	i: INTEGER;
	done: BOOLEAN;
BEGIN key := "NetSystem.Hosts.Route0.";
	COPY("Route0", rname); GetEntry0(key, "Device", device); i := 0;
	WHILE (i < Ip.MaxRoutes) & (device # "") DO NEW(route);
		route.dev := NetBase.FindDevice(device);
		IF route.dev # NIL THEN GetEntry0(key, "Mode", arp);
			IF arp = "arp" THEN INCL(route.options, Ip.arpopt) END;
			GetEntry(key, "Host", hostname, num); ToHost0(num, route.adr, done);
			IF ~done THEN (*Texts.WriteString(W, "Host not found");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)*)
			ELSE
				IF i = 0 THEN
					COPY(hostname, hostName);
					NetBase.Copy(route.adr, hostIP, Ip.AdrLen)
				END
			END;
			GetEntry(key, "Gateway", gateway, num); ToHost0(num, route.gway, done);
			IF ~done THEN (*Texts.WriteString(W, "Gateway not found");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)*)
			END;
			GetEntry(key, "Netmask", dmy, num); ToHost0(num, route.subnet, done);
			IF done THEN Ip.InstallRoute(route, rname, device);
				(*Texts.WriteString(W, "Route installed"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)*)
			ELSE (*Texts.WriteString(W, "Netmask not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)*)
			END
		ELSE Texts.WriteString(W, "Device not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		INC(i); key[21] := CHR(i+ORD("0"));
		rname[5] := CHR(i+ORD("0"));
		GetEntry0(key, "Device", device)
	END
END SetRoutes;

PROCEDURE SetDns;
VAR
	name, num, dns: ARRAY 64 OF CHAR;
	i, nodns: INTEGER;
	adr: Ip.Adr;
	done: BOOLEAN;
BEGIN nodns := 0;
	i := 1; dns := "DNS1"; GetEntry("NetSystem.Hosts.", dns, name, num);
	WHILE num # "" DO ToHost0(num, adr, done);
		IF done THEN
			DNS.InstallDNS(name, adr); INC(nodns)
		ELSE (*Texts.WriteString(W, dns);
			Texts.Write(W, " "); Texts.WriteString(W, name);
			Texts.WriteString(W, " no ip-number");  Texts.WriteLn(W)*)
		END;
		INC(i); dns[3] := CHR(i + ORD("0"));
		GetEntry("NetSystem.Hosts.", dns, name, num)
	END;
	IF nodns = 0 THEN
		ToHost0("129.132.1.11", adr, done); DNS.InstallDNS("dns1.ethz.ch", adr);
		ToHost0("129.132.98.12", adr, done); DNS.InstallDNS("dns2.ethz.ch", adr)
	END;
END SetDns;

(** Command NetSystem.Start ~  Start up NetSystem. *)

PROCEDURE Start*;
VAR
	name, num: ARRAY 64 OF CHAR;
BEGIN
	IF ~started THEN
		SetDevices;
		SetRoutes; DNS.Init; GetEntry("NetSystem.Hosts.", "Domain", name, num);
		IF name # "" THEN DNS.InstallDom(name) ELSE DNS.InstallDom("ethz.ch") END;
		SetDns; started := Ip.nofRoutes > 0;
		IF started THEN Ip.SetDirectedCast(Ip.routes[0]);
			Texts.WriteString(W, "NetSystem started / mg");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		ELSE
			Texts.WriteString(W, "Oberon.Text - NetSystem not configured");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		NetBase.Start; Ip.StartTimer; Ip.StartIP; Ports.Init; UDP.Start; TCP.Start
	END
END Start;

(** Command NetSystem.Stop ~  Shut down NetSystem. *)

PROCEDURE Stop*;
BEGIN TCP.Stop; UDP.Stop; Ip.StopIP; Ip.StopTimer; NetBase.Stop;
	started := FALSE; Texts.WriteString(W, "NetSystem stopped");
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Stop;

BEGIN NetBase.Copy(Ip.IPany, anyIP, Ip.AdrLen);
	NetBase.Copy(Ip.IPall, allIP, Ip.AdrLen);
	Texts.OpenWriter(W); started := FALSE; passwords := NIL;
	Start;  Kernel.InstallTermHandler(Stop)
END NetSystem.

Dialer.Dial
Dialer.Hangup

NetSystem.Start 
NetSystem.Stop

System.Free NetSystem SLIP TCP DNS UDP Ports IP NetBase ~

System.ShowModules

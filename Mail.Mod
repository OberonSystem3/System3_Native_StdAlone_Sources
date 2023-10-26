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

MODULE Mail; (* ejz,  , with some help from pm *)
	IMPORT 
		Modules, Strings, Files, BTrees, Objects, Display, Fonts, Texts, NetSystem, Oberon, NetTools, AsciiCoder, Attributes, 
		MIME, Streams, TextStreams, Out, Links, Gadgets, TextGadgets, TextDocs, Documents, Desktops, Input, HyperDocs, 
		Dates, ListRiders, ListModels, ListGadgets, Display3;

(** The Mail-module implements an API-interface and the commands used by Mail.Panel. Mail is sent according to the
		SMTP (RFC 821) protocol and received via POP3 (RFC 1725). Content-Types may either be text/plain
		(oberon-ascii, us-ascii or iso-8859-1) or in application/compressed/oberon. Later allows to transmit any oberon
		TextDoc via e-mail.
		Additionally the Mail-modul supports mailto and mailserver urls. If they should be used the following
		lines should be added to the LinkSchemes section of the Registry:
			mailto = Mail.NewMailToLinkScheme
			mailserver = Mail.NewMailServerLinkScheme
		And the following lines to the Documents section:
			mailto = Mail.NewDoc
			mailserver = Mail.NewDoc
		All POP3 operations require a valid username and password for the pop-server used. Sending mail with SMTP
		requires that the senders e-mail address is known. The e-mail address can be defined in the NetSystem section
		of the Registry.
			e.g.: EMail = "anonymous@host.nowhere" *)

	CONST
		jg = TRUE;
		DefSnoopDelay = 60;
		DefPOPPort* = 110; DefSMTPPort* = 25;
		LocalBoxTag = 987654321; LocalBoxTTag = LocalBoxTag+MAX(INTEGER);
		LocalMailTag = 876543219; LocalMailTTag = LocalMailTag+MAX(INTEGER);
		DefTopic = "Misc";
		OberonStart* = "--- start of oberon mail ---";
		read* = 0; delete* = 1; in* = 2; out* = 3; remote* = 4; header* = 5;
		Mailer = "Mail for Oberon (ejz)";
		(* op *)
		eq = 1; leq = 2; le = 3; geq = 4; ge = 5; neq = 6; or = 7; and = 8;
		(* field *)
		from = 20; subject = 21; date = 22; time = 23; text = 24; topic = 25; readFlag = 26; netFlag = 27;
		Menu = "Desktops.Copy[Copy] Mail.Reply[Reply] TextDocs.Search[Search] TextDocs.Replace[Rep] Desktops.StoreDoc[Store]";
		SysMenu = "Desktops.Copy[Copy] Mail.Reply[Reply] Desktops.StoreDoc[Store]";

	TYPE
		LocalBox = POINTER TO LocalBoxDesc;
		LocalMail* = RECORD
			replyTo*, topic*: ARRAY 64 OF CHAR;
			date*, time*: LONGINT; (* universal time (GMT) in oberon format *)
			subject*: ARRAY 256 OF CHAR;
			state*: SET; (** read, delete, in, out, remote *)
			key*, org: LONGINT;
			text*: Texts.Text;
			box: LocalBox
		END;
		LocalBoxDesc = RECORD
			ind: BTrees.Tree;
			name: ARRAY 64 OF CHAR;
			time, date: LONGINT
		END;
		Alias = POINTER TO AliasDesc;
		AliasDesc = RECORD
			org: LONGINT;
			k: INTEGER;
			next: Alias
		END;
		RemoteBox = POINTER TO RemoteBoxDesc;
		RemoteBoxDesc = RECORD (LocalBoxDesc)
			host, user: ARRAY 64 OF CHAR;
			aliases: Alias;
			next: RemoteBox
		END;
		Cond = POINTER TO CondDesc;
		CondDesc = RECORD
			val: ARRAY 64 OF CHAR;
			date, time, op, field: LONGINT;
			value, eval: BOOLEAN;
			next: Cond
		END;
		Node = POINTER TO NodeDesc;
		NodeDesc = RECORD (CondDesc)
			left, right: Cond
		END;
		Query = RECORD
			query: ARRAY 128 OF CHAR;
			conds, root: Cond;
			error: BOOLEAN
		END;
(** The connection to an pop host is controlled by a session handle. *)
		POPSession* = POINTER TO POPSessionDesc;
		POPSessionDesc* = RECORD (NetTools.SessionDesc)
		END;
(** The connection to an smtp host is controlled by a session handle. *)
		SMTPSession* = POINTER TO SMTPSessionDesc;
		SMTPSessionDesc* = RECORD (NetTools.SessionDesc)
			from: ARRAY 64 OF CHAR
		END;
		Snooper = POINTER TO SnooperDesc;
		SnooperDesc = RECORD (Oberon.TaskDesc)
			hostIP: NetSystem.IPAdr;
			host, user, passwd: ARRAY 64 OF CHAR;
			S: POPSession;
			state, delay: LONGINT;
			lastMails: INTEGER;
			nextS: Snooper
		END;
		Item = POINTER TO ItemDesc;
		ItemDesc = RECORD (ListRiders.DataDesc)
			key: LONGINT; box: LocalBox
		END;

	VAR
		buffer: ARRAY NetTools.BufLen OF CHAR;
		remBoxes: RemoteBox;
		snoopers: Snooper;
		W: Texts.Writer;
		mullerBox: ARRAY 16 OF CHAR;
		mailListMethod: ListGadgets.Method;
		cacheBoxName: ARRAY 64 OF CHAR;
		cacheBox: LocalBox;

	PROCEDURE InitBox(box: LocalBox; F: Files.File);
		VAR R: Files.Rider;
	BEGIN
		box.time := 0; box.date := 0;
		Files.Set(R, F, 0);
		Files.WriteLInt(R, LocalBoxTTag); Files.WriteLInt(R, 16);
		Files.WriteLInt(R, box.time); Files.WriteLInt(R, box.date);
		box.ind := BTrees.NewLInt(F, 16, 512);
		BTrees.Flush(box.ind);
		box.name := ""
	END InitBox;

	PROCEDURE OpenLocalBox(name: ARRAY OF CHAR): LocalBox;
		VAR
			F: Files.File;
			R: Files.Rider;
			org: LONGINT;
			ind: LocalBox;
	BEGIN
		IF name = cacheBoxName THEN
			RETURN cacheBox
		END;
		NEW(ind); F := Files.Old(name);
		IF F # NIL THEN
			Files.Set(R, F, 0);
			Files.ReadLInt(R, org);
			IF org = LocalBoxTag THEN
				Files.ReadLInt(R, org);
				ind.time := 0; ind.date := 0
			ELSIF org = LocalBoxTTag THEN
				Files.ReadLInt(R, org);
				Files.ReadLInt(R, ind.time); Files.ReadLInt(R, ind.date)
			ELSE
				HALT(99)
			END;
			ind.ind := BTrees.Old(F, org)
		ELSE
			F := Files.New(name);
			InitBox(ind, F);
			IF name # "" THEN
				Files.Register(F)
			END
		END;
		COPY(name, ind.name);
		COPY(name, cacheBoxName);
		cacheBox := ind;
		RETURN ind
	END OpenLocalBox;

	PROCEDURE KeyByOrg(box: LocalBox; org: LONGINT): LONGINT;
		VAR
			R: Files.Rider;
			key: LONGINT;
	BEGIN
		Files.Set(R, BTrees.Base(box.ind), org+4+64+64+4+4+256+4);
		Files.ReadLInt(R, key);
		RETURN key
	END KeyByOrg;

	PROCEDURE OrgByKey(box: LocalBox; key: LONGINT): LONGINT;
		VAR
			org: LONGINT;
			res: INTEGER;
	BEGIN
		BTrees.SearchLInt(box.ind, key, org, res);
		IF res # BTrees.Done THEN
			org := -1
		END;
		RETURN org
	END OrgByKey;

	PROCEDURE NewKey(box: LocalBox): LONGINT;
		VAR
			key: LONGINT;
			res: INTEGER;
	BEGIN
		BTrees.MaxLIntKey(box.ind, key, res);
		IF res = BTrees.Done THEN
			INC(key)
		ELSE
			key := 1
		END;
		RETURN key
	END NewKey;

	PROCEDURE GetLocalMail(box: LocalBox; key: LONGINT; VAR mail: LocalMail; text, topic: BOOLEAN);
		VAR
			R: Files.Rider;
			org, len: LONGINT;
			res: INTEGER;
			ch: CHAR;
	BEGIN
		BTrees.SearchLInt(box.ind, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, BTrees.Base(box.ind), org);
			mail.text := NIL; mail.box := box;
			Files.ReadLInt(R, mail.key); ASSERT((mail.key = LocalMailTag) OR (mail.key = LocalMailTTag));
			Files.ReadBytes(R, mail.replyTo, LEN(mail.replyTo)); Files.ReadBytes(R, mail.topic, LEN(mail.topic));
			Files.ReadLInt(R, mail.date);
			IF mail.key = LocalMailTTag THEN
				Files.ReadLInt(R, mail.time)
			ELSE
				mail.time := 0
			END;
			Files.ReadBytes(R, mail.subject, LEN(mail.subject));
			Files.ReadSet(R, mail.state); Files.ReadLInt(R, mail.key);
			Files.ReadLInt(R, mail.org);
			IF text & (mail.key = key) THEN
				IF mail.org > 0 THEN
					Files.Set(R, BTrees.Base(box.ind), mail.org); len := 0;
					Files.Read(R, ch); ASSERT(ch = Texts.TextBlockId);
					NEW(mail.text); Texts.Open(mail.text, "");
					Texts.Load(mail.text, BTrees.Base(box.ind), mail.org+1, len);
					IF topic THEN
						Texts.WriteString(W, "Topic: "); Texts.WriteString(W, mail.topic); Texts.WriteLn(W);
						Texts.Insert(mail.text, 0, W.buf)
					END
				END
			END
		ELSE
			mail.key := -1; mail.org := -1; mail.box := NIL
		END
	END GetLocalMail;

	PROCEDURE PutLocalMail(box: LocalBox; VAR mail: LocalMail; new, sort: BOOLEAN);
		VAR
			R: Files.Rider;
			org, org2, len, key, key2: LONGINT;
			mail2: LocalMail;
			res: INTEGER;
	BEGIN
		IF new THEN
			BTrees.InsertLInt(box.ind, mail.key, -1, res);
			org := Files.Length(BTrees.Base(box.ind));
			BTrees.InsertLInt(box.ind, mail.key, org, res);
			mail.org := -1
		ELSE
			BTrees.SearchLInt(box.ind, mail.key, org, res);
			ASSERT(res = BTrees.Done)
		END;
		Files.Set(R, BTrees.Base(box.ind), org);
		Files.WriteLInt(R, LocalMailTTag);
		Files.WriteBytes(R, mail.replyTo, LEN(mail.replyTo)); Files.WriteBytes(R, mail.topic, LEN(mail.topic));
		Files.WriteLInt(R, mail.date); Files.WriteLInt(R, mail.time);
		Files.WriteBytes(R, mail.subject, LEN(mail.subject));
		Files.WriteSet(R, mail.state); Files.WriteLInt(R, mail.key);
		Files.WriteLInt(R, mail.org);
		IF new THEN
			IF mail.text # NIL THEN
				mail.org := Files.Length(BTrees.Base(box.ind)); len := 0;
				Texts.Store(mail.text, BTrees.Base(box.ind), mail.org, len)
			ELSE
				mail.org := -1
			END;
			Files.Set(R, BTrees.Base(box.ind), Files.Pos(R)-4);
			Files.WriteLInt(R, mail.org);
			IF sort & ((mail.date < box.date) OR ((mail.date = box.date) & (mail.time < box.time))) THEN
				key2 := mail.key; mail2.date := mail.date+1;
				WHILE (key2 > 0) & ((mail.date < mail2.date) OR ((mail.date = mail2.date) & (mail.time < mail2.time))) DO
					DEC(key2);
					GetLocalMail(box, key2, mail2, FALSE, TRUE);
					IF mail2.key # key2 THEN
						mail2.date := mail.date+1
					END
				END;
				FOR key := mail.key-1 TO key2+1 BY -1 DO
					GetLocalMail(box, key, mail2, FALSE, TRUE);
					IF mail2.key = key THEN
						INC(mail2.key);
						BTrees.SearchLInt(box.ind, key, org2, res);
						BTrees.InsertLInt(box.ind, mail2.key, org2, res);
						PutLocalMail(box, mail2, FALSE, FALSE)
					END
				END;
				mail.key := key2+1;
				BTrees.InsertLInt(box.ind, mail.key, org, res);
				PutLocalMail(box, mail, FALSE, FALSE)
			ELSE
				box.date := mail.date; box.time := mail.time;
				Files.Set(R, BTrees.Base(box.ind), 0);
				Files.ReadLInt(R, len);
				IF len = LocalBoxTTag THEN
					Files.Set(R, BTrees.Base(box.ind), 8);
					Files.WriteLInt(R, box.time); Files.WriteLInt(R, box.date)
				END
			END
		END;
		BTrees.Flush(box.ind); Files.Close(BTrees.Base(box.ind))
	END PutLocalMail;

	PROCEDURE DeleteLocalMail(box: LocalBox; key: LONGINT);
		VAR
			org: LONGINT;
			R: Files.Rider;
			state: SET;
			p, a: Alias;
			res: INTEGER;
	BEGIN
		BTrees.SearchLInt(box.ind, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, BTrees.Base(box.ind), org+4+64+64+4+4+256);
			Files.ReadSet(R, state);
			INCL(state, delete);
			Files.Set(R, BTrees.Base(box.ind), org+4+64+64+4+4+256);
			Files.WriteSet(R, state)
		END;
		BTrees.DeleteLInt(box.ind, key, res);
		IF box IS RemoteBox THEN
			p := NIL; a := box(RemoteBox).aliases;
			WHILE (a # NIL) & (a.org # org) DO
				p := a; a := a.next
			END;
			IF a # NIL THEN
				IF p # NIL THEN
					p.next := a.next
				ELSE
					box(RemoteBox).aliases := a.next
				END;
				p := box(RemoteBox).aliases;
				WHILE p # NIL DO
					IF p.k > a.k THEN
						DEC(p.k)
					END;
					p := p.next
				END
			END
		END
	END DeleteLocalMail;

	PROCEDURE SendCmd(S: NetTools.Session; cmd, arg: ARRAY OF CHAR);
		VAR i, j: LONGINT;
	BEGIN
		i := 0;
		WHILE cmd[i] # 0X DO
			buffer[i] := cmd[i]; INC(i)
		END;
		IF arg[0] # 0X THEN
			buffer[i] := " "; INC(i); j := 0;
			WHILE arg[j] # 0X DO
				buffer[i] := arg[j]; INC(i); INC(j)
			END
		END;
		buffer[i] := Strings.CR; buffer[i+1] := Strings.LF; buffer[i+2] := 0X;
		NetSystem.WriteBytes(S.C, 0, i+2, buffer);
	END SendCmd;

	PROCEDURE ReadString(VAR R: Texts.Reader; VAR s: ARRAY OF CHAR; dot: BOOLEAN);
		VAR
			l, i: LONGINT;
			ch: CHAR;
	BEGIN
		l := LEN(s)-1; i := 0;
		Texts.Read(R, ch);
		IF dot & ~R.eot & (ch = ".") THEN
			s[0] := "."; INC(i)
		END;
		WHILE ~R.eot & (ch # Strings.CR) & (i < l) DO
			IF R.lib IS Fonts.Font THEN
				s[i] := ch; INC(i)
			END;
			Texts.Read(R, ch)
		END;
		s[i] := 0X
	END ReadString;

	PROCEDURE NrToArg(nr: INTEGER; VAR arg: ARRAY OF CHAR);
	BEGIN
		IF nr > 9 THEN
			Strings.IntToStr(nr, arg)
		ELSE
			arg[0] := " "; arg[1] := CHR(nr+ORD("0")); arg[2] := 0X
		END
	END NrToArg;

	PROCEDURE ReadState(S: POPSession): BOOLEAN;
	BEGIN
		NetSystem.ReadString(S.C, S.reply);
		IF S.reply[0] = "+" THEN
			S.status := NetTools.Done; S.res := NetTools.Done
		ELSE
			S.status := NetTools.Failed; S.res := NetTools.Failed
		END;
		RETURN S.status = NetTools.Done
	END ReadState;

(** Close the connection for session S. *)
	PROCEDURE ClosePOP*(S: POPSession);
	BEGIN
		IF S.C # NIL THEN
			SendCmd(S, "QUIT", "");
			(*NetSystem.ReadString(S.C, S.reply);*)
			S.res := NetTools.Done;
			NetTools.Disconnect(S.C); S.C := NIL; S.S := NIL
		ELSE
			S.res := NetTools.Failed
		END
	END ClosePOP;

	PROCEDURE openPOP(S: POPSession; host, user, passwd: ARRAY OF CHAR): BOOLEAN;
	VAR pos: LONGINT;
	BEGIN
		IF ReadState(S) THEN
			SendCmd(S, "USER", user);
			IF ReadState(S) THEN
				SendCmd(S, "PASS", passwd);
				IF ReadState(S) THEN
					S.reply := "connected"; S.res := NetTools.Done;
					RETURN TRUE
				END
			END;
			pos := 0;
			Strings.Search("assword", S.reply, pos);
			IF pos > 0 THEN
				NetSystem.DelPassword("pop", host, user)
			END
		ELSIF S.reply[0] = 0X THEN
			S.reply := "timed out"
		END;
		ClosePOP(S);
		RETURN FALSE
	END openPOP;

(** Open a new pop-session S to host. *)
	PROCEDURE OpenPOP*(VAR S: POPSession; host, user, passwd: ARRAY OF CHAR; port: INTEGER);
		VAR
			hostIP: NetSystem.IPAdr;
			snoop: Snooper;
	BEGIN
		IF (port <= 0) OR (port >= 10000) THEN
			port := DefPOPPort
		END;
		NEW(S);
		IF (host[0] # "<") & (host[0] # 0X) THEN
			NetSystem.GetIP(host, hostIP);
			snoop := snoopers;
			WHILE (snoop # NIL) & (snoop.hostIP # hostIP) DO
				snoop := snoop.nextS
			END;
			IF (snoop # NIL) & (snoop.S # NIL) THEN
				ClosePOP(snoop.S); snoop.S := NIL; snoop.state := 0
			END;
			IF NetTools.Connect(S.C, port, host, FALSE) THEN
				S.S := NetTools.OpenStream(S.C);
				IF openPOP(S, host, user, passwd) THEN
					RETURN
				END
			ELSE
				S.reply := "no connection"
			END
		ELSE
			S.reply := "no pop-host specified"
		END;
		S.res := NetTools.Failed; S.C := NIL; S.S := NIL
	END OpenPOP;

(** Returns the number of mails available. *)
	PROCEDURE NrOfMails*(S: POPSession; VAR mails: INTEGER);
		VAR i: LONGINT;
	BEGIN
		mails := 0;
		SendCmd(S, "STAT", "");
		IF ReadState(S) THEN
			i := 4;
			WHILE (S.reply[i] # 0X) & ((S.reply[i] < "0") OR (S.reply[i] > "9")) DO
				INC(i)
			END;
			WHILE (S.reply[i] >= "0") & (S.reply[i] <= "9") DO
				mails := 10*mails + ORD(S.reply[i])-ORD("0"); INC(i)
			END
		END
	END NrOfMails;

(** Delete0 mail no (1 .. NrOfMails). *)
	PROCEDURE DeleteMail*(S: POPSession; no: INTEGER);
		VAR arg: ARRAY 4 OF CHAR;
	BEGIN
		NrToArg(no, arg);
		SendCmd(S, "DELE", arg);
		IF ReadState(S) THEN
		END
	END DeleteMail;

	PROCEDURE ParseContent*(h: MIME.Header; VAR cont: MIME.Content);
		VAR
			val: ARRAY 32 OF CHAR;
			pos: LONGINT;
	BEGIN
		cont := NIL;
		pos := MIME.FindField(h, "X-Content-Type");
		IF pos > 0 THEN
			MIME.ExtractContentType(h, pos, cont);
			IF cont.typ.typ = "application" THEN
				COPY(cont.typ.subTyp, val);
				IF Strings.CAPPrefix("oberon", val) THEN
					cont.encoding := MIME.EncAsciiCoder
				ELSIF Strings.CAPPrefix("compressed/oberon", val) THEN
					cont.encoding := MIME.EncAsciiCoderC
				ELSE
					cont := NIL
				END
			ELSE
				cont := NIL
			END
		END;
		IF cont = NIL THEN
			pos := MIME.FindField(h, "Content-Type");
			IF pos < 0 THEN
				pos := MIME.FindField(h, "X-Content-Type")
			END;
			IF pos > 0 THEN
				MIME.ExtractContentType(h, pos, cont);
				IF cont.typ.typ = "text" THEN
					pos := MIME.FindField(h, "Content-Transfer-Encoding");
					MIME.TextEncoding(h, pos, cont)
				END
			ELSE
				NEW(cont); cont.typ := MIME.GetContentType("text/plain");
				IF MIME.FindField(h, "X-Sun-Charset") > 0 THEN
					cont.encoding := MIME.Enc8Bit
				ELSE
					cont.encoding := MIME.EncBin
				END
			END
		END
	END ParseContent;

	PROCEDURE GetClock(VAR time, date: LONGINT);
	BEGIN
		Oberon.GetClock(time, date);
		Dates.AddTime(time, date, -Dates.TimeDiff * 60)	(* convert to GMT *)
	END GetClock;

	PROCEDURE RecHead(S: POPSession; VAR mail: LocalMail; VAR cont: MIME.Content);
		VAR
			h: MIME.Header;
			sout: Streams.Stream;
			pos: LONGINT;
	BEGIN
		mail.replyTo := ""; COPY(DefTopic, mail.topic); mail.subject := "";
		GetClock(mail.time, mail.date); mail.state := {in, header}; mail.key := -1; mail.org := -1;
		NEW(mail.text); Texts.Open(mail.text, "");
		IF ReadState(S) THEN
			sout := TextStreams.OpenWriter(mail.text);
			MIME.ReadHeader(S.S, sout, h, pos);
			sout.Flush(sout);
			pos := MIME.FindField(h, "Reply-To");
			IF pos < 0 THEN
				pos := MIME.FindField(h, "From")
			END;
			MIME.ExtractEMail(h, pos, mail.replyTo);
			pos := MIME.FindField(h, "Subject");
			MIME.ExtractValue(h, pos, mail.subject);
			pos := MIME.FindField(h, "Date");
			MIME.ExtractGMTDate(h, pos, mail.time, mail.date);
			ParseContent(h, cont)
		END;
		Texts.WriteLn(W); Texts.Append(mail.text, W.buf)
	END RecHead;

	PROCEDURE RecBody(S: POPSession; VAR mail: LocalMail; cont: MIME.Content; head: BOOLEAN);
		VAR mT: Texts.Text;
	BEGIN
		IF (cont.typ.typ # "multipart") OR head THEN
			cont.len := MAX(LONGINT); MIME.ReadText(S.S, W, cont, TRUE)
		ELSE
			Texts.Append(mail.text, W.buf);
			cont.len := MAX(LONGINT); MIME.ReadMultipartText(S.S, mT, cont, TRUE);
			Texts.Save(mT, 0, mT.len, W.buf)
		END;
		IF ~head THEN
			EXCL(mail.state, header)
		END;
		Texts.Append(mail.text, W.buf)
	END RecBody;

	PROCEDURE ReceiveHead*(S: POPSession; no: INTEGER; VAR mail: LocalMail);
		VAR
			arg: ARRAY 8 OF CHAR;
			cont: MIME.Content;
	BEGIN
		NrToArg(no, arg); Strings.Append(arg, " 0");
		SendCmd(S, "TOP", arg);
		RecHead(S, mail, cont);
		IF S.res = NetTools.Done THEN
			RecBody(S, mail, cont, TRUE)
		END
	END ReceiveHead;

	PROCEDURE DecodeMessage*(VAR text: Texts.Text; cont: MIME.Content);
		VAR
			R: Texts.Reader;
			ok: BOOLEAN;
			pos, len: LONGINT;
			F, Fc: Files.File;
	BEGIN
		pos := 0; Texts.OpenReader(R, text, pos);
		ok := TRUE; ReadString(R, buffer, FALSE);
		WHILE ~R.eot & (buffer # OberonStart) DO
			IF (buffer # "") & ok  THEN
				pos := Texts.Pos(R)
			ELSE
				ok := FALSE
			END;
			ReadString(R, buffer, FALSE)
		END;
		IF buffer = OberonStart THEN
			F := Files.New(""); len := Texts.Pos(R);
			AsciiCoder.Decode(text, len, F, ok);
			IF ok THEN
				IF cont.encoding = MIME.EncAsciiCoderC THEN
					Fc := Files.New(""); AsciiCoder.Expand(F, Fc)
				ELSE
					Fc := F
				END;
				Texts.Save(text, 0, pos+1, W.buf);
				NEW(text); Texts.Load(text, Fc, 1, len);
				Texts.Insert(text, 0, W.buf)
			END
		END
	END DecodeMessage;

	PROCEDURE ReceiveMail*(S: POPSession; no: INTEGER; VAR mail: LocalMail);
		VAR
			arg: ARRAY 8 OF CHAR;
			cont: MIME.Content;
	BEGIN (* with decoding *)
		NrToArg(no, arg); SendCmd(S, "RETR", arg);
		RecHead(S, mail, cont);
		IF S.res = NetTools.Done THEN
			RecBody(S, mail, cont, FALSE);
			IF (S.res = NetTools.Done) & (cont.typ.typ = "application") & (cont.encoding IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC}) THEN
				DecodeMessage(mail.text, cont)
			END
		END
	END ReceiveMail;

	PROCEDURE ReadResponse(S: SMTPSession);
		VAR l: LONGINT;
	BEGIN
		NetSystem.ReadString(S.C, S.reply);
		Strings.StrToInt(S.reply, l); S.status := SHORT(l);
		COPY(S.reply, buffer);
		WHILE buffer[3] = "-" DO
			NetSystem.ReadString(S.C, buffer)
		END
	END ReadResponse;

(** Close the connection for session S. *)
	PROCEDURE CloseSMTP*(S: SMTPSession);
	BEGIN
		IF S.C # NIL THEN
			SendCmd(S, "QUIT", "");
			(*NetSystem.ReadString(S.C, S.reply);*)
			S.res := NetTools.Done;
			NetTools.Disconnect(S.C); S.C := NIL; S.S := NIL
		ELSE
			S.res := NetTools.Failed
		END
	END CloseSMTP;

(** Open a new smtp-session S to host. *)
	PROCEDURE OpenSMTP*(VAR S: SMTPSession; host, from: ARRAY OF CHAR; port: INTEGER);
	BEGIN
		IF (port <= 0) OR (port >= 10000) THEN
			port := DefSMTPPort
		END;
		NEW(S);
		IF (host[0] # "<") & (host[0] # 0X) THEN
			IF NetTools.Connect(S.C, port, host, FALSE) THEN
				S.S := NetTools.OpenStream(S.C);
				ReadResponse(S);
				IF S.reply[0] = "2" THEN
					SendCmd(S, "HELO", NetSystem.hostName);
					ReadResponse(S);
					IF S.reply[0] = "2" THEN
						COPY(from, S.from); S.res := NetTools.Done;
						RETURN
					END
				END;
				CloseSMTP(S)
			ELSE
				S.reply := "no connection"
			END
		ELSE
			S.reply := "no smtp-host specified"
		END;
		S.res := NetTools.Failed; S.C := NIL; S.S := NIL
	END OpenSMTP;

	PROCEDURE Recipient(VAR i: LONGINT; VAR s, rcpt: ARRAY OF CHAR);
		VAR j: LONGINT;
	BEGIN
		WHILE (s[i] # 0X) & (s[i] <= " ") DO
			INC(i)
		END;
		IF s[i] = "," THEN
			INC(i);
			WHILE (s[i] # 0X) & (s[i] <= " ") DO
				INC(i)
			END
		END;
		j := 0;
		WHILE (s[i] > " ") & (s[i] # ",") DO
			rcpt[j] := s[i];
			INC(j); INC(i)
		END;
		rcpt[j] := 0X
	END Recipient;

(*
	PROCEDURE Recipient(VAR i: LONGINT; VAR s, rcpt: ARRAY OF CHAR);
		VAR
			j, k, end, dom: LONGINT;
			candidate: ARRAY 128 OF CHAR;
			special: BOOLEAN;
			ch, old, close: CHAR;
	BEGIN
		j := i; ch := s[j]; old := 01X; close := 02X;
		WHILE (ch # 0X) & ~( ((ch = ",") & (close = 02X)) OR (old = close) ) DO
			IF ch = "(" THEN
				close := ")"
			ELSIF ch = "<" THEN
				close := ">"
			ELSIF ch = "{" THEN
				close := "}"
			ELSIF ch = "[" THEN
				close := "]"
			ELSIF ch = 22X THEN
				close := 22X
			END;
			INC(j); old := ch; ch := s[j]
		END;
		IF old # close THEN
			end := j
		ELSE
			end := j-1
		END;
		WHILE (j >= i) & (s[j] <= " ") DO
			DEC(j)
		END;
		WHILE (j >= i) & (s[j] > " ") DO
			DEC(j)
		END; INC(j);
		k := 0; dom := -1; special := FALSE; ch := s[j];
		IF ch = "(" THEN
			close := ")"; INC(j)
		ELSIF ch = "<" THEN
			close := ">"; INC(j)
		ELSIF ch = "{" THEN
			close := "}"; INC(j)
		ELSIF ch = "[" THEN
			close := "]"; INC(j)
		ELSE
			close := 02X
		END;
		ch := s[j];
		WHILE (ch > " ") & (j < end) & (ch # close) DO
			IF ch = "@" THEN
				dom := j
			ELSIF (dom < 0) & ((ch = "(") OR (ch = ")") OR (ch = "<") OR (ch = ">") OR (ch = ",") OR (ch = ";") OR (ch = ":") OR
				(ch = "\") OR (ch = 22X) OR (*(ch = ".") OR*) (ch = "[") OR (ch = "]") OR (ch = "/")) THEN
				special := TRUE
			END;
			candidate[k] := ch; INC(k); INC(j); ch := s[j]
		END;
		candidate[k] := 0X;
		IF special THEN
			IF candidate[0] # 22X THEN
				rcpt[0] := 22X; k := 1
			ELSE
				k := 0
			END; j := 0;
			WHILE (candidate[j] # 0X) & (candidate[j] # "@") DO
				rcpt[k] := candidate[j]; INC(k); INC(j)
			END;
			rcpt[k] := 22X; INC(k);
			WHILE candidate[j] # 0X DO
				rcpt[k] := candidate[j]; INC(k); INC(j)
			END;
			IF candidate[j-1] = 22X THEN
				DEC(k)
			END;
			rcpt[k] := 0X
		ELSE
			COPY(candidate, rcpt)
		END;
		WHILE (s[end] # 0X) & (s[end] # ",") DO
			INC(end)
		END;
		IF s[end] = "," THEN
			i := end+1
		ELSE
			i := end
		END
	END Recipient;
*)

	PROCEDURE QueryContType*(T: Texts.Text; beg: LONGINT; cont: MIME.Content);
		VAR
			R: Texts.Reader;
			deflib: Objects.Library;
			defcol: INTEGER;
			ch: CHAR;
	BEGIN
		cont.typ := MIME.GetContentType("text/plain"); cont.encoding := MIME.EncBin;
		Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
		deflib := R.lib; defcol := R.col;
		WHILE ~R.eot DO
			IF R.lib # deflib THEN
				cont.typ := MIME.GetContentType(MIME.OberonMime);
				cont.encoding := MIME.EncAsciiCoderC; RETURN
			ELSIF R.col # defcol THEN
				cont.typ := MIME.GetContentType(MIME.OberonMime);
				cont.encoding := MIME.EncAsciiCoderC; RETURN
			ELSIF ch > CHR(127) THEN
				cont.encoding := MIME.Enc8Bit
			END;
			Texts.Read(R, ch)
		END
	END QueryContType;

	PROCEDURE MakeAscii*(T: Texts.Text; VAR atext: Texts.Text; pos: LONGINT; VAR end: LONGINT; text: BOOLEAN);
		VAR
			R: Texts.Reader;
			len: LONGINT;
			B: Texts.Buffer;
			F, Fc: Files.File;
			ch: CHAR;
			colon: BOOLEAN;
	BEGIN
		colon := FALSE; ch := 0X;
		Texts.OpenReader(R, T, pos);
		REPEAT
			IF ch = Strings.CR THEN
				pos := Texts.Pos(R); colon := FALSE
			ELSIF ch = ":" THEN
				colon := TRUE
			END;
			Texts.Read(R, ch)
		UNTIL R.eot OR ((ch = Strings.CR) & ~colon);
		IF R.eot & colon THEN
			pos := T.len
		END;
		NEW(B); Texts.OpenBuf(B);
		end := pos; Texts.Save(T, pos, T.len, B);
		IF text THEN
			end := T.len
		END;
		NEW(atext); Texts.Open(atext, "");
		Texts.Append(atext, B); len := 0;
		F := Files.New(""); Texts.Store(atext, F, 0, len);
		Fc := Files.New(""); AsciiCoder.Compress(F, Fc);
		Texts.Delete(atext, 0, atext.len);
		AsciiCoder.Code(Fc, atext)
	END MakeAscii;

	PROCEDURE SendText(S: SMTPSession; VAR mail: LocalMail; head, text, coded: Texts.Text; beg, end: LONGINT; cont: MIME.Content);
		VAR enc: LONGINT;
	BEGIN
		cont.len := MAX(LONGINT);
		buffer := "From: "; Strings.Append(buffer, S.from);
		SendCmd(S, buffer, "");
		buffer := "X-Mailer: "; Strings.Append(buffer, Mailer);
		SendCmd(S, buffer, ""); enc := cont.encoding;
		IF head # NIL THEN
			NetTools.curLen := end-beg+head.len+128;
			cont.encoding := MIME.EncBin;
			MIME.WriteText(head, 0, head.len, S.S, cont, TRUE, FALSE);
			cont.encoding := enc
		ELSE
			NetTools.curLen := end-beg+128
		END;
		NetSystem.WriteString(S.C, "");
		IF cont.encoding = MIME.EncAsciiCoderC THEN
			cont.encoding := MIME.Enc8Bit;
			MIME.WriteISOMime(S.S, cont);
			cont.encoding := enc;
			buffer := "X-Content-Type: "; Strings.Append(buffer, MIME.OberonMime);
			SendCmd(S, buffer, "")
		ELSIF cont.encoding # MIME.EncBin THEN
			MIME.WriteISOMime(S.S, cont)
		END;
		NetSystem.WriteString(S.C, "");
		IF coded # NIL THEN
			cont.encoding := MIME.Enc8Bit;
			MIME.WriteText(text, beg, end, S.S, cont, TRUE, TRUE);
			SendCmd(S, OberonStart, "");
			cont.encoding := MIME.EncBin;
			MIME.WriteText(coded, 0, coded.len, S.S, cont, TRUE, TRUE);
			cont.encoding := enc
		ELSE
			MIME.WriteText(text, beg, end, S.S, cont, TRUE, TRUE)
		END;
		SendCmd(S, ".", "")
	END SendText;

	PROCEDURE GetSetting*(name: ARRAY OF CHAR; VAR host: ARRAY OF CHAR; local: BOOLEAN);
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.FindObj(Gadgets.context, name);
		IF obj # NIL THEN
			Attributes.GetString(obj, "Value", host)
		ELSE
			COPY("", host)
		END;
		IF (host = "") & ~local THEN
			IF ~NetTools.QueryString(name, host) THEN
				COPY("", host)
			END
		END
	END GetSetting;

	PROCEDURE SendReplyLine*(S: NetTools.Session; cont: MIME.Content);
	BEGIN
		S.reply := "Done ";
		CASE cont.encoding OF
			MIME.EncBin: Strings.Append(S.reply, "ASCII (Oberon)")
			|MIME.Enc8Bit: Strings.Append(S.reply, "ASCII (ISO 8bit)")
			|MIME.Enc7Bit: Strings.Append(S.reply, "ASCII (ISO 7bit)")
			|MIME.EncQuoted: Strings.Append(S.reply, "ASCII (ISO quoted)")
			|MIME.EncAsciiCoderC: Strings.Append(S.reply, "Oberon + Text")
			|MIME.EncAsciiCoderCPlain: Strings.Append(S.reply, "Oberon")
		ELSE
			Strings.Append(S.reply, "???")
		END
	END SendReplyLine;

(** Send T encoded as conttype (NetTools.ascii (oberon, plain ascii), NetTools.iso (iso-8859-1, quoted),
	iso8 (iso-8859-1, 8 bit), oberon (oberon document, asciicoded) or auto). The recipient(s) must be contained in the
		mail text itself. *)
	PROCEDURE SendMail*(S: SMTPSession; T: Texts.Text; cont: MIME.Content; sendBox: ARRAY OF CHAR);
		VAR
			R: Texts.Reader;
			t: ARRAY 2048 OF CHAR;
			pos, beg, end: LONGINT;
			coded, head: Texts.Text;
			box: LocalBox;
			mail: LocalMail;
			h: MIME.Header;
			sin: Streams.Stream;
			ch: CHAR;
		PROCEDURE Recipients(text: Texts.Text; VAR pos: LONGINT);
			VAR
				R: Texts.Reader;
				t: ARRAY 2048 OF CHAR;
				i: LONGINT;
				rcpt: ARRAY 64 OF CHAR;
				first: BOOLEAN;
		BEGIN
			Texts.OpenReader(R, text, pos); ReadString(R, t, FALSE); first := TRUE;
			WHILE (Strings.CAPPrefix("TO:", t) OR Strings.CAPPrefix("CC:", t) OR Strings.CAPPrefix("BCC:", t)) OR
				(~first & (t[0] = " ") OR (t[0] = 09X)) DO
				Texts.WriteString(W, t); Texts.WriteLn(W);
				IF (t[0] = " ") OR (t[0] = 09X) THEN
					i := 1
				ELSE
					i := 3
				END;
				Recipient(i, t, rcpt);
				WHILE rcpt # "" DO
					Out.String("To: "); Out.String(rcpt); Out.Ln();
					SendCmd(S, "RCPT TO:", rcpt); ReadResponse(S);
					IF S.reply[0] # "2" THEN
						S.res := NetTools.Failed; Texts.Append(head, W.buf); RETURN
					END;
					Recipient(i, t, rcpt); first := FALSE
				END;
				pos := Texts.Pos(R); ReadString(R, t, FALSE)
			END;
			Texts.Append(head, W.buf)
		END Recipients;
	BEGIN
		IF sendBox # "" THEN
			box := OpenLocalBox(sendBox)
		ELSE
			box := NIL
		END;
		COPY(S.from, mail.replyTo); COPY(DefTopic, mail.topic);
		mail.text := T; mail.state := {out}; mail.key := -1;
		Texts.OpenReader(R, T, 0);
		REPEAT
			pos := Texts.Pos(R); ReadString(R, t, FALSE)
		UNTIL R.eot OR Strings.CAPPrefix("TO:", t) OR Strings.CAPPrefix("CC:", t) OR Strings.CAPPrefix("BCC:", t);
		IF ~R.eot THEN
			Strings.GetPar(t, mail.replyTo);
			SendCmd(S, "MAIL FROM:", S.from); ReadResponse(S);
			IF S.reply[0] = "2" THEN
				S.res := NetTools.Done;
				GetClock(mail.time, mail.date);
				beg := pos;
				IF cont.encoding = MIME.EncAsciiCoderC THEN
					MakeAscii(T, coded, pos, end, TRUE)
				ELSIF cont.encoding = MIME.EncAsciiCoderCPlain THEN
					MakeAscii(T, coded, pos, end, FALSE)
				ELSE
					coded := NIL; end := T.len
				END;
				NEW(head); Texts.Open(head, ""); Recipients(T, pos);
				IF S.res # NetTools.Done THEN
					RETURN
				END;
				sin := TextStreams.OpenReader(T, pos); 
				MIME.ReadHeader(sin, NIL, h, beg);
				INC(beg, pos);
				Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
				IF (ch = Strings.CR) OR (ch = Strings.LF) THEN
					WHILE (beg > 0) & ((ch = Strings.CR) OR (ch = Strings.LF)) DO
						DEC(beg);
						Texts.OpenReader(R, T, beg); Texts.Read(R, ch)
					END;
					INC(beg); IF beg > T.len THEN beg := T.len END
				END;
				Texts.Save(T, pos, beg, W.buf);
				Texts.Append(head, W.buf);
				Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
				WHILE ~R.eot & ((ch = Strings.CR) OR (ch = Strings.LF)) & (R.lib IS Fonts.Font) DO
					Texts.Read(R, ch); INC(beg)
				END;
				pos := MIME.FindField(h, "Subject");
				MIME.ExtractValue(h, pos, mail.subject);
				SendCmd(S, "DATA", ""); ReadResponse(S);
				IF S.reply[0] = "3" THEN
					SendText(S, mail, head, T, coded, beg, end, cont); ReadResponse(S);
					IF S.reply[0] = "2" THEN
						SendReplyLine(S, cont);
						IF box # NIL THEN
							mail.key := NewKey(box);
							INCL(mail.state, read); PutLocalMail(box, mail, TRUE, FALSE)
						END;
						S.res := NetTools.Done; RETURN
					END
				END
			END
		ELSE
			S.reply := "no recipient"
		END;
		S.res := NetTools.Failed
	END SendMail;

	PROCEDURE ShowStatus(msg: ARRAY OF CHAR);
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.FindObj(Gadgets.context, "StatusBar");
		IF obj # NIL THEN
			Attributes.SetString(obj, "Value", msg);
			Gadgets.Update(obj)
		ELSE
			Out.String(msg); Out.Ln()
		END
	END ShowStatus;

	PROCEDURE OpenPop(VAR S: POPSession; host: ARRAY OF CHAR; VAR user: ARRAY OF CHAR; VAR mails: INTEGER; connect: BOOLEAN): BOOLEAN;
		VAR passwd: ARRAY 32 OF CHAR;
	BEGIN
		NEW(S); passwd := "";
		IF (host[0] # "<") & (host[0] # 0X) THEN
			NetSystem.GetPassword("pop", host, user, passwd);
			IF passwd # "" THEN
				IF connect THEN
					ShowStatus("connecting ...");
					OpenPOP(S, host, user, passwd, DefPOPPort);
					IF S.res = NetTools.Done THEN
						NrOfMails(S, mails);
						IF S.res # NetTools.Done THEN
							ClosePOP(S)
						END
					END
				ELSE
					S.C := NIL; S.res := NetTools.Done
				END
			ELSE
				S.res := NetTools.Failed; S.status := 401;
				S.reply := "no password found"
			END
		ELSE
			S.reply := "no pop-host specified"; S.res := NetTools.Failed
		END;
		ShowStatus(S.reply);
		RETURN S.res = NetTools.Done
	END OpenPop;

	PROCEDURE InsertMailItem(R: ListRiders.Rider; VAR mail: LocalMail);
		VAR item: Item;
	BEGIN
		NEW(item); item.key := mail.key; item.box := mail.box;
		R.do.Set(R, 0); R.do.Write(R, item)
	END InsertMailItem;

	PROCEDURE GetRemoteBox(VAR server, user: ARRAY OF CHAR): RemoteBox;
		VAR remBox: RemoteBox;
	BEGIN
		remBox := remBoxes;
		WHILE (remBox # NIL) & ~((remBox.host = server) & (remBox.user = user)) DO
			remBox := remBox.next
		END;
		IF remBox = NIL THEN
			NEW(remBox); remBox.next := remBoxes; remBoxes := remBox;
			InitBox(remBox, Files.New("")); remBox.aliases := NIL;
			COPY(user, remBox.user); COPY(server, remBox.host)
		END;
		RETURN remBox
	END GetRemoteBox;

	PROCEDURE FindAlias(remBox: RemoteBox; k: INTEGER; org: LONGINT): Alias;
		VAR a: Alias;
	BEGIN
		a := remBox.aliases;
		WHILE (a # NIL) & ~((a.k = k) OR (a.org = org)) DO
			a := a.next
		END;
		RETURN a
	END FindAlias;

	PROCEDURE DefineAlias(remBox: RemoteBox; k: INTEGER; org: LONGINT);
		VAR a: Alias;
	BEGIN
		NEW(a); a.next := remBox.aliases; remBox.aliases := a;
		a.k := k; a.org := org
	END DefineAlias;

	PROCEDURE POPDirectory(VAR remBox: RemoteBox): BOOLEAN;
		VAR
			S: POPSession;
			server, user: ARRAY 64 OF CHAR;
			msg: ARRAY 32 OF CHAR;
			arg: ARRAY 8 OF CHAR;
			mail: LocalMail;
			alias: Alias;
			k, mails: INTEGER;
	BEGIN
		GetSetting("User", user, FALSE); GetSetting("POP", server, FALSE);
		IF OpenPop(S, server, user, mails, TRUE) THEN
			remBox := GetRemoteBox(server, user);
			IF mails > 0 THEN
				k := 1;
				WHILE k <= mails DO
					mail.key := -1; alias := FindAlias(remBox, k, -1);
					IF alias # NIL THEN
						mail.key := KeyByOrg(remBox, alias.org); GetLocalMail(remBox, mail.key, mail, FALSE, TRUE)
					END;
					IF alias = NIL THEN
						NrToArg(k, arg); Strings.Append(arg, " 0");
						msg := "TOP "; Strings.Append(msg, arg); ShowStatus(msg);
						ReceiveHead(S, k, mail); INCL(mail.state, remote);
						mail.key := NewKey(remBox);
						PutLocalMail(remBox, mail, TRUE, TRUE);
						DefineAlias(remBox, k, OrgByKey(remBox, mail.key))
					END;
					INC(k)
				END;
			END;
			ClosePOP(S);
			ShowStatus(S.reply);
			RETURN TRUE
		ELSE
			remBox := NIL;
			RETURN FALSE
		END
	END POPDirectory;

	PROCEDURE ReceiveAll(box: LocalBox): BOOLEAN;
		VAR
			S: POPSession;
			server, user: ARRAY 64 OF CHAR;
			msg: ARRAY 32 OF CHAR;
			arg: ARRAY 8 OF CHAR;
			mail, rmail: LocalMail;
			remBox: RemoteBox;
			alias: Alias;
			k, mails: INTEGER;
	BEGIN
		GetSetting("User", user, FALSE); GetSetting("POP", server, FALSE);
		IF OpenPop(S, server, user, mails, TRUE) THEN
			IF mails > 0 THEN
				remBox := GetRemoteBox(server, user);
				k := 1; mail.key := -1;
				WHILE (k <= mails) & (S.res = NetTools.Done) DO
					mail.key := -1; alias := FindAlias(remBox, k, -1);
					IF alias # NIL THEN
						mail.key := KeyByOrg(remBox, alias.org); GetLocalMail(remBox, mail.key, mail, FALSE, TRUE)
					END;
					NrToArg(k, arg);
					IF jg THEN msg := "GET " ELSE msg := "RETR " END;
					Strings.Append(msg, arg); ShowStatus(msg);
					ReceiveMail(S, k, rmail);
					IF S.res = NetTools.Done THEN
						IF alias # NIL THEN
							COPY(mail.topic, rmail.topic);
							IF read IN mail.state THEN
								INCL(rmail.state, read)
							END
						END;
						rmail.key := NewKey(box); INC(k);
						PutLocalMail(box, rmail, TRUE, TRUE)
					END
				END;
				IF S.res = NetTools.Done THEN
					k := 1;
					WHILE (k <= mails) & (S.res = NetTools.Done) DO
						IF ~jg THEN
							NrToArg(k, arg); msg := "DELE "; Strings.Append(msg, arg); ShowStatus(msg)
						END;
						DeleteMail(S, k);
						IF S.res = NetTools.Done THEN
							alias := FindAlias(remBox, k, -1);
							IF alias # NIL THEN
								DeleteLocalMail(remBox, KeyByOrg(remBox, alias.org))
							END
						END;
						INC(k)
					END
				END;
				BTrees.Flush(remBox.ind)
			END;
			ClosePOP(S); ShowStatus(S.reply);
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReceiveAll;

	PROCEDURE SearchText(text: Texts.Text; pat: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
		CONST
			MaxPatLen = 128;
		VAR
			i, l, sPatLen: LONGINT;
			R: Texts.Reader;
			sPat: ARRAY MaxPatLen OF CHAR;
			sDv: ARRAY MaxPatLen + 1 OF INTEGER;
			ch: CHAR;
		PROCEDURE CalcDispVec();
			VAR i, j, d: INTEGER;
		BEGIN
			i := 1;
			d := 1;
			WHILE i <= sPatLen DO
				j := 0; 
				WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO
					INC(j)
				END;
				WHILE i <= j + d DO
					sDv[i] := d;
					INC(i)
				END;
				INC(d)
			END
		END CalcDispVec;
	BEGIN
		COPY(pat, sPat);
		sPatLen := SHORT(Strings.Length(sPat));
		CalcDispVec();
		IF sPatLen > 0 THEN
			Texts.OpenReader(R, text, pos);
			Texts.Read(R, ch);
			INC(pos);
			l := text.len;
			i := 0;
			WHILE (i # sPatLen) & (pos <= l) DO
				IF ch = sPat[i] THEN
					INC(i);
					IF i < sPatLen THEN
						Texts.Read(R, ch);
						INC(pos)
					END
				ELSIF i = 0 THEN
					Texts.Read(R, ch);
					INC(pos)
				ELSE
					i := i - sDv[i]
				END
			END
		ELSE
			i := -1
		END;
		RETURN i = sPatLen
	END SearchText;

	PROCEDURE MatchQuery(box: LocalBox; VAR Q: Query; VAR mail: LocalMail): BOOLEAN;
		VAR
			cond: Cond;
			pos, i: LONGINT;
			txt: BOOLEAN;
	BEGIN
		cond := Q.conds; txt := FALSE;
		WHILE cond # NIL DO (* evaluate simple conditions *)
			cond.eval := TRUE;
			CASE cond.field OF
				from: pos := 0;
						Strings.Search(cond.val, mail.replyTo, pos);
						cond.value := ((cond.op = eq) & (pos >= 0)) OR ((cond.op = neq) & (pos < 0))
				|subject: pos := 0;
							Strings.Search(cond.val, mail.subject, pos);
							cond.value := ((cond.op = eq) & (pos >= 0)) OR ((cond.op = neq) & (pos < 0))
				|topic: pos := 0;
							Strings.Search(cond.val, mail.topic, pos);
							cond.value := ((cond.op = eq) & (pos >= 0)) OR ((cond.op = neq) & (pos < 0))
				|date: CASE cond.op OF
								eq: cond.value := mail.date = cond.date
								|leq: cond.value := mail.date <= cond.date
								|le: cond.value := mail.date < cond.date
								|geq: cond.value := mail.date >= cond.date
								|ge: cond.value := mail.date > cond.date
								|neq: cond.value :=  mail.date # cond.date
							END
				|time: CASE cond.op OF
								eq: cond.value := mail.time = cond.time
								|leq: cond.value := mail.time <= cond.time
								|le: cond.value := mail.time < cond.time
								|geq: cond.value := mail.time >= cond.time
								|ge: cond.value := mail.time > cond.time
								|neq: cond.value :=  mail.time # cond.time
							END
				|readFlag: cond.value := (read IN mail.state) = (cond.val[0] = "R")
				|netFlag: cond.value := (remote IN mail.state) = (cond.val[0] = "R")
				|text: txt := TRUE; mail.text := NIL; cond.value := FALSE; cond.eval := FALSE
			ELSE (* or, and *)
				cond.value := FALSE; cond.eval := FALSE
			END;
			cond := cond.next
		END;
		LOOP
			REPEAT
				i := 0; cond := Q.conds; (* evaluate logical ops *)
				WHILE cond # NIL DO
					IF cond IS Node THEN
						WITH cond: Node DO
							IF ~cond.eval THEN
								IF cond.left.eval & cond.right.eval THEN
									IF cond.op = or THEN (* OR *)
										cond.value := cond.left.value OR cond.right.value
									ELSIF cond.op = and THEN (* AND *)
										cond.value := cond.left.value & cond.right.value
									ELSE
										HALT(99)
									END;
									cond.eval := TRUE; INC(i)
								ELSIF (cond.op = or) & ((cond.left.eval & cond.left.value) OR (cond.right.eval & cond.right.value)) THEN
									cond.value := TRUE; cond.eval := TRUE; cond.left.eval := TRUE; cond.right.eval := TRUE; INC(i)
								ELSIF (cond.op = and) & ((cond.left.eval & ~cond.left.value) OR (cond.right.eval & ~cond.right.value)) THEN
									cond.value := FALSE; cond.eval := TRUE; cond.left.eval := TRUE; cond.right.eval := TRUE; INC(i)
								END
							END
						END
					END;
					cond := cond.next
				END
			UNTIL Q.root.eval OR (i <= 0);
			IF Q.root.eval THEN
				RETURN Q.root.value
			ELSIF txt THEN (* evaluate full-text conditions *)
				cond := Q.conds;
				WHILE cond # NIL DO
					IF (cond.field = text) & ~cond.eval THEN
						IF mail.text = NIL THEN
							GetLocalMail(box, mail.key, mail, TRUE, TRUE)
						END;
						IF mail.text # NIL THEN
							pos := 0; cond.value := SearchText(mail.text, cond.val, pos)
						ELSE
							cond.value := TRUE
						END;
						cond.eval := TRUE
					END;
					cond := cond.next
				END
			END
		END
	END MatchQuery;

	PROCEDURE getLocalMail(box: LocalBox; key: LONGINT; VAR mail: LocalMail; query: BOOLEAN);
		VAR
			F: Files.File;
			R: Files.Rider;
			org: LONGINT;
			res: INTEGER;
	BEGIN
		IF query THEN
			GetLocalMail(box, key, mail, FALSE, TRUE)
		ELSE
			BTrees.SearchLInt(box.ind, key, org, res);
			IF res = BTrees.Done THEN
				F := BTrees.Base(box.ind);
				Files.Set(R, F, org);
				Files.ReadLInt(R, mail.key); ASSERT((mail.key = LocalMailTag) OR (mail.key = LocalMailTTag));
				Files.Set(R, F, org+4+LEN(mail.replyTo)+LEN(mail.topic));
				Files.ReadLInt(R, mail.date);
				IF mail.key = LocalMailTTag THEN
					Files.ReadLInt(R, mail.time)
				ELSE
					mail.time := 0
				END;
				mail.box := box; mail.key := key
			ELSE
				mail.box := NIL; mail.key := -1
			END;
			mail.text := NIL; mail.org := -1
		END
	END getLocalMail;

	PROCEDURE LocalDirectory(R: ListRiders.Rider; box, box1: LocalBox; VAR Q: Query); 
		VAR
			maxKey, maxKey1, key, key1: LONGINT;
			mail, mail1: LocalMail;
			msg: ARRAY 32 OF CHAR;
			res: INTEGER;
			query: BOOLEAN;
	BEGIN
		query := Q.conds # NIL;
		msg := "searching "; ShowStatus(msg);
		IF box1 # NIL THEN
			BTrees.MaxLIntKey(box1.ind, maxKey1, res);
			IF res # BTrees.Done THEN
				maxKey1 := -1
			END
		ELSE
			maxKey1 := -1
		END;
		BTrees.MaxLIntKey(box.ind, maxKey, res);
		IF res # BTrees.Done THEN
			maxKey := -1
		END;
		IF box1 = NIL THEN
			FOR key := 0 TO maxKey DO
				getLocalMail(box, key, mail, query);
				IF mail.key = key THEN
					IF ~query OR MatchQuery(box, Q, mail) THEN
						InsertMailItem(R, mail)
					END;
					IF (key MOD 100) = 0 THEN
						Strings.AppendCh(msg, "."); ShowStatus(msg)
					END
				END
			END
		ELSE
			key := 0; mail.date := MAX(LONGINT); mail.time := MAX(LONGINT);
			getLocalMail(box, key, mail, query);
			WHILE (key <= maxKey) & (mail.key # key) DO
				INC(key); getLocalMail(box, key, mail, query)
			END;
			key1 := 0; mail1.date := MAX(LONGINT); mail1.time := MAX(LONGINT);
			getLocalMail(box1, key1, mail1, query);
			WHILE (key1 <= maxKey1) & (mail1.key # key1) DO
				INC(key1); getLocalMail(box1, key1, mail1, query)
			END;
			WHILE (key <= maxKey) OR (key1 <= maxKey1) DO
				IF (mail.date < mail1.date) OR ((mail.date = mail1.date) & (mail.time <= mail1.time)) THEN
					IF mail.key = key THEN
						IF ~query OR MatchQuery(box, Q, mail) THEN
							InsertMailItem(R, mail)
						END;
						INC(key); getLocalMail(box, key, mail, query)
					ELSE
						mail.date := MAX(LONGINT);
						WHILE (key <= maxKey) & (mail.key # key) DO
							INC(key); getLocalMail(box, key, mail, query)
						END
					END
				ELSIF key1 <= maxKey1 THEN
					IF mail1.key = key1 THEN
						IF ~query OR MatchQuery(box1, Q, mail1) THEN
							InsertMailItem(R, mail1)
						END;
						INC(key1); getLocalMail(box1, key1, mail1, query)
					ELSE
						mail1.date := MAX(LONGINT);
						WHILE (key1 <= maxKey1) & (mail1.key # key1) DO
							INC(key1); getLocalMail(box1, key1, mail1, query)
						END
					END
				ELSE
					key1 := maxKey1+1; mail.date := 0; mail1.date := MAX(LONGINT)
				END;
				IF ((key1+key) MOD 100) = 0 THEN
					Strings.AppendCh(msg, "."); ShowStatus(msg)
				END
			END
		END
	END LocalDirectory;

	PROCEDURE CompileQuery(VAR Q: Query);
		CONST
			eof = 0; colon = 9; name = 10; string = 11; number = 12; dot = 13; today = 14; now = 15;
			read = 16; unread = 17; local = 18; remote = 19;
		VAR
			str, keyw: ARRAY 64 OF CHAR;
			pos, num, d, m, y, h, s, sym: LONGINT;
			ch: CHAR;
		PROCEDURE GetName();
			VAR j: LONGINT;
		BEGIN
			j := 0;
			WHILE (ch # 0X) & (Strings.IsAlpha(ch) OR (ch = ".") OR (ch = "@") OR Strings.IsDigit(ch)) DO
				str[j] := ch; INC(j); ch := Q.query[pos]; INC(pos)
			END;
			str[j] := 0X
		END GetName;
		PROCEDURE GetString();
			VAR j: LONGINT;
		BEGIN
			j := 0;
			WHILE (ch # 0X) & (ch # 022X) DO
				str[j] := ch; INC(j); ch := Q.query[pos]; INC(pos)
			END;
			IF ch = 022X THEN
				ch := Q.query[pos]; INC(pos)
			END;
			str[j] := 0X
		END GetString;
		PROCEDURE GetNumber();
		BEGIN
			num := 0;
			WHILE (ch # 0X) & Strings.IsDigit(ch) DO
				num := 10*num+ORD(ch)-ORD("0"); ch := Q.query[pos]; INC(pos)
			END
		END GetNumber;
		PROCEDURE Next();
		BEGIN
			WHILE (ch # 0X) & (ch <= " ")  DO
				ch := Q.query[pos]; INC(pos)
			END;
			CASE ch OF
				"=": sym := eq; ch := Q.query[pos]; INC(pos)
				|":": sym := colon; ch := Q.query[pos]; INC(pos)
				|"<": ch := Q.query[pos]; INC(pos);
						IF ch = "=" THEN
							ch := Q.query[pos]; INC(pos); sym := leq
						ELSE
							sym := le
						END
				|">": ch := Q.query[pos]; INC(pos);
						IF ch = "=" THEN
							ch := Q.query[pos]; INC(pos); sym := geq
						ELSE
							sym := ge
						END
				|"&": sym := and; ch := Q.query[pos]; INC(pos)
				|".": sym := dot; ch := Q.query[pos]; INC(pos)
				|"#": sym := neq; ch := Q.query[pos]; INC(pos)
				|"A" .. "Z", "a" .. "z": GetName(); Strings.Upper(str, keyw);
								IF keyw = "FROM" THEN
									sym := from
								ELSIF keyw = "SUBJECT" THEN
									sym := subject
								ELSIF keyw = "DATE" THEN
									sym := date
								ELSIF keyw = "NOW" THEN
									sym := now
								ELSIF keyw = "TEXT" THEN
									sym := text
								ELSIF keyw = "TIME" THEN
									sym := time
								ELSIF keyw = "TOPIC" THEN
									sym := topic
								ELSIF keyw = "TODAY" THEN
									sym := today
								ELSIF keyw = "OR" THEN
									sym := or
								ELSIF keyw = "READ" THEN
									sym := read
								ELSIF keyw = "UNREAD" THEN
									sym := unread
								ELSIF keyw = "LOCAL" THEN
									sym := local
								ELSIF keyw = "REMOTE" THEN
									sym := remote
								ELSE
									sym := name
								END
				|"0" .. "9": sym := number; GetNumber()
				|022X: sym := string; ch := Q.query[pos]; INC(pos); GetString()
			ELSE
				sym := eof
			END
		END Next;
		PROCEDURE Check(sy: LONGINT);
		BEGIN
			IF sy = sym THEN
				Next()
			ELSE
				Q.error := TRUE
			END
		END Check;
		PROCEDURE Factor(): Cond;
			VAR cond: Cond;
		BEGIN
			NEW(cond); cond.field := sym;
			IF sym IN {from, subject, topic, text} THEN
				Next();
				IF sym IN {eq, neq} THEN
					cond.op := sym
				ELSE
					Q.error := TRUE
				END;
				Next();
				IF sym IN {name, string} THEN
					COPY(str, cond.val); Next()
				ELSE
					Q.error := TRUE
				END
			ELSIF sym = date THEN
				Next();
				IF sym IN {eq, leq, le, geq, ge, neq} THEN
					cond.op := sym
				ELSE
					Q.error := TRUE
				END;
				Next();
				IF sym = today THEN
					GetClock(num, cond.date); Next()
				ELSE
					Check(number);
					d := num;
					Check(dot);
					Check(number);
					m := num;
					Check(dot);
					Check(number);
					y := num;
					cond.date := ((y MOD 100)*16+m)*32+d
				END
			ELSIF sym = time THEN
				Next();
				IF sym IN {eq, leq, le, geq, ge, neq} THEN
					cond.op := sym
				ELSE
					Q.error := TRUE
				END;
				Next();
				IF sym = now THEN
					GetClock(cond.time, num); Next()
				ELSE
					Check(number);
					h := num;
					Check(colon);
					Check(number);
					m := num;
					IF sym = colon THEN
						Check(colon);
						Check(number);
						s := num
					ELSE
						s := 0
					END;
					cond.time := h*1000H + m*40H + s
				END;
				cond.time := Dates.AddMinute(cond.time, -SHORT(Dates.TimeDiff))
			ELSIF sym IN {read, unread} THEN
				cond.field := readFlag; cond.op := eq;
				COPY(keyw, cond.val); Next()
			ELSIF sym IN {local, remote} THEN
				cond.field := netFlag; cond.op := eq;
				COPY(keyw, cond.val); Next()
			ELSIF sym IN {name, string} THEN
				cond.field := text; cond.op := eq;
				COPY(str, cond.val); Next()
			ELSE
				Q.error := TRUE
			END;
			IF ~Q.error THEN
				cond.next := Q.conds; Q.conds := cond
			END;
			RETURN cond		
		END Factor;
		PROCEDURE Term(): Cond;
			VAR
				factor: Cond;
				term: Node;
		BEGIN
			factor := Factor();
			WHILE (sym = and) & ~Q.error DO
				NEW(term); term.field := MAX(INTEGER); term.op := and;
				term.next := Q.conds; Q.conds := term; term.left := factor;
				Next(); term.right := Factor(); factor := term
			END;
			RETURN factor
		END Term;
		PROCEDURE Expr(): Cond;
			VAR
				term: Cond;
				expr: Node;
		BEGIN
			term := Term();
			WHILE (sym = or) & ~Q.error DO
				NEW(expr); expr.field := MAX(INTEGER); expr.op := or;
				expr.next := Q.conds; Q.conds := expr; expr.left := term;
				Next(); expr.right := Expr(); term := expr
			END;
			RETURN term
		END Expr;
	BEGIN
		Q.conds := NIL; Q.root := NIL; Q.error := FALSE;
		ch := Q.query[0]; pos := 1;
		Next(); Q.root := Expr();
		IF (sym # eof) OR Q.error THEN
			Q.conds := NIL; Q.root := NIL;
			Q.error := TRUE
		END
	END CompileQuery;

	PROCEDURE directory(box: LocalBox; remBox: RemoteBox; pop, all, keepPos: BOOLEAN);
		VAR
			R: ListRiders.Rider;
			list: Objects.Object;
			Q: Query;
			server, user, outbox, listbox, str: ARRAY 64 OF CHAR;
			ok, useQuery: BOOLEAN;
		PROCEDURE BeginDir();
			VAR C: ListRiders.ConnectMsg;
		BEGIN
			list := Gadgets.FindObj(Gadgets.context, "MailList");
			ListModels.InitList(list(ListModels.List), TRUE);
			C.R := NIL; Objects.Stamp(C); list.handle(list, C); R := C.R
		END BeginDir;
		PROCEDURE EndDir();
			VAR N: Oberon.ControlMsg;
		BEGIN
			list := Gadgets.FindObj(Gadgets.context, "MailListF");
			WITH list: ListGadgets.Frame DO
				list.do := mailListMethod;
				IF list.sel THEN
					N.F := list; N.id := Oberon.neutralize; Display.Broadcast(N)
				END
			END;
			IF ~keepPos THEN
				Links.GetLink(list, "VPos", list);
				Attributes.SetInt(list, "Value", 0);
				Gadgets.Update(list);
				list := Gadgets.FindObj(Gadgets.context, "MailList");
				Gadgets.Update(list);
				list := Gadgets.FindObj(Gadgets.context, "MailListF");
				Links.GetLink(list, "VPos", list);
				Attributes.SetInt(list, "Value", 0);
				Gadgets.Update(list)
			ELSE
				list := Gadgets.FindObj(Gadgets.context, "MailList");
				Gadgets.Update(list);
				list := Gadgets.FindObj(Gadgets.context, "MailListF");
				Gadgets.Update(list)
			END
		END EndDir;
	BEGIN
		GetSetting("OutBox", outbox, FALSE); GetSetting("ListBox", listbox, TRUE);
		IF Strings.CAPCompare(outbox, mullerBox) THEN outbox := "" END;
		IF Gadgets.executorObj # NIL THEN
			Attributes.GetString(Gadgets.executorObj, "UseQuery", Q.query);
			useQuery := Q.query # ""
		ELSE
			useQuery := FALSE
		END;
		IF useQuery THEN
			IF Q.query # "Topic" THEN
				GetSetting(Q.query, Q.query, TRUE)
			ELSE
				Q.query := 'topic = "';
				GetSetting("Topic", str, TRUE);
				Strings.Append(Q.query, str);
				Strings.AppendCh(Q.query, '"')
			END
		ELSE
			Q.query := ""
		END;
		Q.conds := NIL; Q.root := NIL;
		BeginDir(); ok := TRUE;
		IF pop & (outbox # listbox) & ~useQuery THEN
			IF all THEN
				ok := ReceiveAll(box); remBox := NIL
			ELSE
				ok := POPDirectory(remBox)
			END
		ELSIF outbox # listbox THEN
			IF remBox = NIL THEN
				GetSetting("User", user, FALSE); GetSetting("POP", server, FALSE);
				IF user = "" THEN
					NetSystem.GetPassword("pop", server, user, str)
				END;
				remBox := GetRemoteBox(server, user)
			END
		ELSE
			remBox := NIL
		END;
		IF ok THEN
			IF Q.query # "" THEN
				CompileQuery(Q);
				IF Q.error THEN
					ShowStatus("error in query");
					RETURN
				END
			END;
			LocalDirectory(R, box, remBox, Q)
		END;
		EndDir();
		list := Gadgets.FindObj(Gadgets.context, "MailListF");
		IF list(ListGadgets.Frame).lines = list(ListGadgets.Frame).lines.next THEN
			IF useQuery & (Q.query # "") THEN
				ShowStatus("nothing found")
			ELSIF ok THEN
				ShowStatus("empty box")
			END
		ELSIF ok THEN
			ShowStatus("done")
		END
	END directory;

	PROCEDURE Directory*;
		VAR
			listbox: ARRAY 64 OF CHAR;
			rec: ARRAY 8 OF CHAR;
			box: LocalBox;
	BEGIN
		GetSetting("ListBox", listbox, TRUE); box := OpenLocalBox(listbox);
		GetSetting("RecMode", rec, TRUE);
		directory(box, NIL, TRUE, rec[0] = "0", FALSE)
	END Directory;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "DeskMenu" THEN
							M.obj :=  Gadgets.CopyPublicObject("NetDocs.MailDeskMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "SystemMenu" THEN
							M.obj :=  Gadgets.CopyPublicObject("NetDocs.MailSystemMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(SysMenu) END;
							M.res := 0
						ELSIF M.name = "UserMenu" THEN
							M.obj :=  Gadgets.CopyPublicObject("NetDosc.MailUserMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSE
							TextDocs.DocHandler(D, M)
						END
					ELSE
						TextDocs.DocHandler(D, M)
					END
				END
			ELSE
				TextDocs.DocHandler(D, M)
			END
		END
	END DocHandler;

	PROCEDURE ShowText(title: ARRAY OF CHAR; T: Texts.Text; reply: BOOLEAN);
		VAR
			D: Documents.Document;
			F: TextGadgets.Frame;
	BEGIN
		NEW(D); TextDocs.InitDoc(D);
		NEW(F); TextGadgets.Init(F, T, FALSE);
		Documents.Init(D, F); COPY(title, D.name);
		IF reply THEN D.handle := DocHandler END;
		D.W := HyperDocs.docW; D.H := HyperDocs.docH;
		Desktops.ShowDoc(D)
	END ShowText;

	PROCEDURE GetMail(item: Item; VAR mail: LocalMail);
	BEGIN
		IF ~(item.box IS RemoteBox) THEN
			item.box := OpenLocalBox(item.box.name)
		END;
		GetLocalMail(item.box, item.key, mail, FALSE, FALSE)
	END GetMail;

	PROCEDURE Show*;
		VAR
			list: Objects.Object;
			S: POPSession;
			server, user, listbox, outbox: ARRAY 64 OF CHAR;
			rec: ARRAY 8 OF CHAR;
			remBox: RemoteBox;
			box: LocalBox;
			mail, rmail: LocalMail;
			key: LONGINT;
			C: ListRiders.ConnectMsg;
			R: ListRiders.Rider;
			A: Objects.AttrMsg;
			item: Item;
			alias: Alias;
			mails, k: INTEGER;
			modify: BOOLEAN;
	BEGIN
		list := Gadgets.FindObj(Gadgets.context, "MailListF");
		WITH list: ListGadgets.Frame DO
			A.id := Objects.get; A.name := "PointKey"; A.class := Objects.Inval; A.res := -1;
			list.handle(list, A);
			IF (A.res = 0) & (A.class = Objects.Int) THEN
				Gadgets.context := Gadgets.context.dlink; modify := FALSE;
				C.R := NIL; Objects.Stamp(C); list.obj.handle(list.obj, C); R := C.R;
				R.do.Seek(R, A.i); item := R.d(Item);
				GetSetting("RecMode", rec, TRUE);
				GetSetting("ListBox", listbox, TRUE); box := OpenLocalBox(listbox);
				GetSetting("OutBox", outbox, FALSE);
				IF Strings.CAPCompare(outbox, mullerBox) THEN outbox := "" END;
				IF item.key >= 0 THEN
					key := item.key; GetMail(item, mail);
					IF remote IN mail.state THEN
						IF listbox = outbox THEN
							ShowStatus("can not receive mail into out-box");
							RETURN
						END;
						GetSetting("User", user, FALSE); GetSetting("POP", server, FALSE);
						IF OpenPop(S, server, user, mails, TRUE) THEN
							remBox := GetRemoteBox(server, user);
							alias := FindAlias(remBox, -1, OrgByKey(remBox, key));
							IF alias # NIL THEN
								mail.key := -1; GetLocalMail(remBox, key, mail, FALSE, TRUE);
								k := alias.k; ReceiveMail(S, k, rmail);
								IF S.res = NetTools.Done THEN
									COPY(mail.topic, rmail.topic);
									IF rec[0] # "2" THEN
										rmail.key := NewKey(box);
										PutLocalMail(box, rmail, TRUE, TRUE); DeleteMail(S, k);
										IF S.res = NetTools.Done THEN
											DeleteLocalMail(remBox, key);
											BTrees.Flush(remBox.ind)
										END;
										modify := TRUE
									ELSE
										INCL(rmail.state, remote); rmail.key := mail.key
									END
								END
							END;
							ClosePOP(S);
							mail := rmail;
							ShowStatus(S.reply)
						END
					ELSE
						rec := 0X; remBox := NIL; GetLocalMail(box, key, mail, TRUE, TRUE)
					END
				END;
				IF (mail.key >= 0) & (mail.text # NIL) THEN
					IF mail.org <= 0 THEN
						Texts.WriteString(W, "Topic: "); Texts.WriteString(W, mail.topic); Texts.WriteLn(W);
						Texts.Insert(mail.text, 0, W.buf)
					END;
					ShowText("Mail.Text", mail.text, TRUE);
					IF ~(read IN mail.state) THEN
						INCL(mail.state, read);
						IF rec[0] # "2" THEN
							PutLocalMail(box, mail, FALSE, TRUE)
						ELSE
							PutLocalMail(remBox, mail, FALSE, TRUE)
						END;
						Gadgets.Update(list)
					END;
					IF modify THEN
						directory(box, remBox, FALSE, FALSE, TRUE)
					END
				END
			END
		END
	END Show;

	PROCEDURE HandleSel(op: INTEGER);
		VAR
			list: Objects.Object;
			server, user, listbox, topic: ARRAY 64 OF CHAR;
			S: POPSession;
			box: LocalBox;
			remBox: RemoteBox;
			mail: LocalMail;
			item: Item;
			line: ListGadgets.Line;
			key: LONGINT;
			C: ListRiders.ConnectMsg;
			R: ListRiders.Rider;
			msg: ARRAY 32 OF CHAR;
			arg: ARRAY 8 OF CHAR;
			alias: Alias;
			mails, k: INTEGER;
			rem, ok, hasread: BOOLEAN;
	BEGIN
		list := Gadgets.FindObj(Gadgets.context, "MailListF");
		WITH list: ListGadgets.Frame DO
			IF op # 0 THEN GetSetting("Topic", topic, TRUE) END;
			GetSetting("ListBox", listbox, TRUE); box := OpenLocalBox(listbox);
			GetSetting("User", user, FALSE); GetSetting("POP", server, FALSE);
			IF user = "" THEN
				NetSystem.GetPassword("pop", server, user, msg)
			END;
			remBox := NIL; S := NIL; ok := TRUE;
			C.R := NIL; Objects.Stamp(C); list.obj.handle(list.obj, C); R := C.R;
			line := list.lines;
			REPEAT
				IF line.sel THEN
					R.do.Seek(R, line.key); item := R.d(Item);
					key := item.key; GetMail(item, mail);
					IF remote IN mail.state THEN
						IF remBox = NIL THEN
							IF OpenPop(S, server, user, mails, op # 1) THEN
								remBox := GetRemoteBox(server, user)
							ELSE
								ok := FALSE
							END
						END;
						IF ok THEN
							rem := TRUE; GetLocalMail(remBox, key, mail, FALSE, TRUE)
						END
					ELSE
						rem := FALSE; GetLocalMail(box, key, mail, FALSE, TRUE)
					END;
					IF (mail.key >= 0) & ok THEN
						IF op # 1 THEN
							IF rem THEN
								alias := FindAlias(remBox, -1, OrgByKey(remBox, key)); k := alias.k;
								IF op = 2 THEN
									COPY(mail.topic, topic); hasread := read IN mail.state;
									ReceiveMail(S, k, mail);
									COPY(topic, mail.topic);
									IF hasread THEN INCL(mail.state, read) END;
									ok := S.res = NetTools.Done;
									IF ok THEN
										mail.key := NewKey(box);
										PutLocalMail(box, mail, TRUE, TRUE);
										BTrees.Flush(box.ind)
									END
								END;
								IF ok THEN
									DeleteLocalMail(remBox, key);
									IF ~jg THEN
										NrToArg(k, arg); msg := "DELE "; Strings.Append(msg, arg); ShowStatus(msg)
									END;
									DeleteMail(S, k);
									BTrees.Flush(remBox.ind);
									ok := S.res = NetTools.Done
								END
							ELSIF op = 0 THEN
								DeleteLocalMail(box, mail.key);
								BTrees.Flush(box.ind)
							END
						ELSE
							COPY(topic, mail.topic);
							IF rem THEN
								PutLocalMail(remBox, mail, FALSE, TRUE)
							ELSE
								PutLocalMail(box, mail, FALSE, TRUE)
							END
						END
					END
				END;
				line := line.next
			UNTIL (line = list.lines) OR ~ok;
			IF S # NIL THEN
				ClosePOP(S)
			END;
			IF (op # 1) & ((remBox # NIL) OR (op = 0)) & ok THEN
				directory(box, remBox, FALSE, FALSE, TRUE)
			END
		END
	END HandleSel;

	PROCEDURE Delete*;
	BEGIN
		HandleSel(0)	
	END Delete;

	PROCEDURE Classify*;
	BEGIN
		HandleSel(1)	
	END Classify;

	PROCEDURE Receive*;
	BEGIN
		HandleSel(2)
	END Receive;

	PROCEDURE Send*;
		VAR
			text, sig: Texts.Text;
			email, server, outbox, val: ARRAY 64 OF CHAR;
			S: SMTPSession;
			Sc: Attributes.Scanner;
			obj: Objects.Object;
			beg, i: LONGINT;
			cont: MIME.Content;
			F: Texts.Finder;
	BEGIN
		GetSetting("EMail", email, FALSE);
		IF email = "" THEN
			ShowStatus("no return address set"); RETURN
		ELSE
			i := 0; Recipient(i, email, val);
			IF val # email THEN
				ShowStatus("invalid return address"); RETURN
			END
		END;
		GetSetting("SMTP", server, FALSE); GetSetting("OutBox", outbox, FALSE);
		IF Strings.CAPCompare(outbox, mullerBox) THEN
			GetSetting("ListBox", outbox, TRUE)
		END;
		GetSetting("ContType", val, TRUE);
		NEW(cont); cont.typ := MIME.GetContentType("text/plain");
		IF val[0] = "0" THEN
			cont.encoding := MIME.EncBin
		ELSIF val[0] = "1" THEN
			cont.encoding := MIME.Enc8Bit
		ELSIF val[0] = "2" THEN
			cont.typ := MIME.GetContentType(MIME.OberonMime); cont.encoding := MIME.EncAsciiCoderC
		ELSE
			beg := 0;
			IF Gadgets.executorObj # NIL THEN
				Gadgets.GetObjName(Gadgets.executorObj, val);
				IF val = "mailto" THEN
					Links.GetLink(Gadgets.context, "Model", obj);
					IF (obj # NIL) & (obj IS Texts.Text) THEN
						Texts.OpenFinder(F, obj(Texts.Text), beg);
						beg := F.pos; Texts.FindObj(F, obj);
						WHILE ~F.eot & (obj # Gadgets.executorObj) DO
							beg := F.pos; Texts.FindObj(F, obj)
						END;
						INC(beg)
					END
				END
			END;
			cont.encoding := MIME.EncAuto
		END;
		Attributes.OpenScanner(Sc, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(Sc); Links.GetLink(Gadgets.context, "Model", obj);
		IF (Sc.class = Attributes.Char) & (Sc.c = "@") & (obj # NIL) & (obj IS Texts.Text) THEN
			text := obj(Texts.Text)
		ELSE
			text := Oberon.MarkedText()
		END;
		IF text # NIL THEN
			IF cont.encoding = MIME.EncAuto THEN
				QueryContType(text, beg, cont)
			END;
			GetSetting("Signature", val, FALSE);
			IF val # "" THEN
				NEW(sig); Texts.Open(sig, val);
				IF sig.len > 0 THEN
					Texts.Save(text, 0, text.len, W.buf);
					NEW(text); Texts.Open(text, "");
					Texts.Append(text, W.buf);
					Texts.WriteLn(W); Texts.Append(text, W.buf);
					Texts.Save(sig, 0, sig.len, W.buf);
					Texts.Append(text, W.buf)
				END
			END;
			OpenSMTP(S, server, email, DefSMTPPort);
			IF S.res = NetTools.Done THEN
				ShowStatus("mailing ");
				SendMail(S, text, cont, outbox);
				CloseSMTP(S)
			END;
			ShowStatus(S.reply)
		ELSE
			ShowStatus("no text")
		END
	END Send;

	PROCEDURE CiteText*(VAR W: Texts.Writer; T: Texts.Text; beg, end: LONGINT);
		VAR
			R: Texts.Reader;
			lib: Objects.Library;
			col, voff: SHORTINT;
			ch: CHAR;
	BEGIN
		lib := W.lib;  col := W.col;  voff := W.voff;
		Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
		Texts.WriteString(W, "> ");
		WHILE ~R.eot & (Texts.Pos(R) <= end) DO
			Texts.SetFont(W, R.lib); Texts.SetColor(W, R.col); Texts.SetOffset(W, R.voff);
			Texts.Write(W, ch);
			IF (R.lib IS Fonts.Font) & (ch = Strings.CR) & (Texts.Pos(R) < end) THEN
				Texts.SetFont(W, lib); Texts.SetColor(W, col); Texts.SetOffset(W, voff);
				Texts.WriteString(W, "> ")
			END;
			Texts.Read(R, ch)
		END;
		Texts.SetFont(W, lib); Texts.SetColor(W, col); Texts.SetOffset(W, voff)
	END CiteText;

(** Mail.Cite (selection & caret)
		Copy the selection to the caret with an left indent "> ". *)
	PROCEDURE Cite*;
		VAR
			text: Texts.Text;
			beg, end, time: LONGINT;
			C: Oberon.CaretMsg;
	BEGIN
		text := NIL; time := -1;
		Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time > 0) THEN
			C.id := Oberon.get; C.car := NIL; C.text := NIL; C.pos := -1; C.F := NIL;
			Objects.Stamp(C); Display.Broadcast(C);
			IF C.text # NIL THEN
				CiteText(W, text, beg, end);
				Texts.Insert(C.text, C.pos, W.buf)
			END
		END
	END Cite;

	PROCEDURE Re*(VAR W: Texts.Writer; VAR t: ARRAY OF CHAR);
		VAR
			i, j, re, oldre: LONGINT;
			p: INTEGER;
			end: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (t[i] # 0X) & (t[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		re := 1; i := 0;
		REPEAT
			end := TRUE; Blanks(); j := i;
			IF CAP(t[i]) = "R" THEN
				IF t[i+1] = "e" THEN
					INC(i, 2); Blanks();
					IF t[i] = ":" THEN
						INC(i); INC(re); end := FALSE
					ELSIF t[i] = "(" THEN
						INC(i); p := SHORT(i); oldre := re;
						Strings.StrToIntPos(t, re, p);
						IF re > 0 THEN
							i := p; Blanks();
							IF t[i] = ")" THEN
								INC(i); Blanks();
								IF t[i] = ":" THEN
									INC(i)
								END;
								INC(re); end := FALSE
							END
						ELSE
							re := oldre
						END
					END
				END
			END
		UNTIL end;
		IF t[j] = 0X THEN
			RETURN
		ELSIF re > 1 THEN
			Texts.WriteString(W, "Re ("); Texts.WriteInt(W, re, 0); Texts.WriteString(W, "): ")
		ELSE
			Texts.WriteString(W, "Re: ")
		END;
		WHILE t[j] # 0X DO
			Texts.Write(W, t[j]); INC(j)
		END
	END Re;

(** Mail.Reply (selection)
		Opens a new TextDoc with the two lines "To: user@host" and "Subject: Re: subject"
		taken from the current selection. *)
	PROCEDURE Reply*;
		VAR
			text: Texts.Text;
			obj: Objects.Object;
			D: Documents.Document;
			listbox, user, server: ARRAY 64 OF CHAR;
			remBox: RemoteBox;
			box: LocalBox;
			mail: LocalMail;
			beg, end, time, key: LONGINT;
			M: Oberon.SelectMsg;
			S: POPSession;
			item: Item;
			C: ListRiders.ConnectMsg;
			R: ListRiders.Rider;
			line: ListGadgets.Line;
			i: INTEGER;
			ln: BOOLEAN;
		PROCEDURE ReplyText(T: Texts.Text; pos: LONGINT);
			VAR
				S: Streams.Stream;
				h: MIME.Header;
				t: ARRAY 512 OF CHAR;
		BEGIN
			Texts.WriteString(W, "To: ");
			S := TextStreams.OpenReader(T, pos);
			MIME.ReadHeader(S, NIL, h, pos);
			pos := MIME.FindField(h, "Reply-To");
			IF pos < 0 THEN
				pos := MIME.FindField(h, "From")
			END;
			MIME.ExtractEMail(h, pos, t);
			Texts.WriteString(W, t); Texts.WriteLn(W);
			pos := MIME.FindField(h, "Subject");
			MIME.ExtractValue(h, pos, t);
			Texts.WriteString(W, "Subject: "); Re(W, t)
		END ReplyText;
	BEGIN
		ln := TRUE;
		IF Desktops.IsInMenu(Gadgets.context) THEN
			D := Desktops.CurDoc(Gadgets.context);
			Links.GetLink(D.dsc, "Model", obj);
			IF (obj # NIL) & (obj IS Texts.Text) THEN
				ReplyText(obj(Texts.Text), 0);
				Texts.WriteLn(W); Texts.WriteLn(W);
				text := NIL; time := -1;
				Oberon.GetSelection(text, beg, end, time);
				IF text = obj THEN
					CiteText(W, text, beg, end)
				ELSE
					ln := FALSE
				END
			END
		ELSE
			M.id := Oberon.get; M.F := NIL; M.time := -1; M.text := NIL; M.sel := NIL;
			Display.Broadcast(M);
			IF (M.text # NIL) & (M.time > 0) THEN
				IF (M.sel # NIL) & (M.sel IS ListGadgets.Frame) THEN
					line := M.sel(ListGadgets.Frame).lines;
					REPEAT
						line := line.next
					UNTIL (line = M.sel(ListGadgets.Frame).lines) OR line.sel;
					IF line.sel THEN
						C.R := NIL; Objects.Stamp(C); M.sel(ListGadgets.Frame).obj.handle(M.sel(ListGadgets.Frame).obj, C); R := C.R;
						R.do.Seek(R, line.key); item := R.d(Item)
					ELSE
						item := NIL
					END;					
					IF item # NIL THEN
						GetSetting("ListBox", listbox, TRUE);
						IF listbox # "" THEN
							box := OpenLocalBox(listbox);
							key := item.key; GetMail(item, mail);
							IF remote IN mail.state THEN
								GetSetting("User", user, FALSE); GetSetting("POP", server, FALSE);
								IF OpenPop(S, server, user, i, FALSE) THEN
									remBox := GetRemoteBox(server, user);
									GetLocalMail(remBox, key, mail, FALSE, TRUE)
								ELSE
									mail.key := -1; key := 0
								END
							ELSE
								GetLocalMail(box, key, mail, FALSE, TRUE)
							END;
							IF mail.key = key THEN
								Texts.WriteString(W, "To: "); Texts.WriteString(W, mail.replyTo); Texts.WriteLn(W);
								Texts.WriteString(W, "Subject: "); Re(W, mail.subject)
							END
						END
					END
				ELSE
					ReplyText(M.text, M.beg)
				END
			END
		END;
		IF W.buf.len = 0 THEN
			Texts.WriteString(W, "To: "); Texts.WriteLn(W);
			Texts.WriteString(W, "Subject: ")
		END;
		IF ln THEN
			Texts.WriteLn(W); Texts.WriteLn(W)
		END;
		NEW(text); Texts.Open(text, ""); Texts.Append(text, W.buf);
		ShowText("Mail.Out.Text", text, FALSE)
	END Reply;

(** Mail.CutLines [width] (marked text)
		Break all lines in the marked viewer after a maximum of width characters.
		The default width is 80. *)
	PROCEDURE CutLines*;
		VAR
			S: Attributes.Scanner;
			T: Texts.Text;
			R: Texts.Reader;
			pos, n, l: LONGINT;
			ch: CHAR;
	BEGIN
		T := Oberon.MarkedText();
		IF T = NIL THEN
			RETURN
		END;
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF S.class = Attributes.Int THEN
			IF S.i < 40 THEN
				n := 40
			ELSIF S.i > 132 THEN
				n := 132
			ELSE
				n := S.i
			END 
		ELSE
			n := 80
		END;
		Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
		pos := 0; l := 1;
		WHILE ~R.eot DO
			IF R.lib IS Fonts.Font THEN
				IF ch = Strings.CR THEN
					l := 0
				ELSIF l >= n THEN
					Texts.WriteLn(W); Texts.Insert(T, pos, W.buf);
					Texts.OpenReader(R, T, Texts.Pos(R)+1);
					l := 0
				ELSIF ch <= " " THEN
					pos := Texts.Pos(R)
				END
			ELSE
				pos := Texts.Pos(R)
			END;
			Texts.Read(R, ch); INC(l)
		END
	END CutLines;

	PROCEDURE *DoSnoop(me: Oberon.Task);
		VAR res: INTEGER;
	BEGIN
		WITH me: Snooper DO
			CASE me.state OF
				0: NEW(me.S); 
					NetSystem.AsyncOpenConnection(me.S.C, NetSystem.anyport, me.hostIP, DefPOPPort, res);
					IF res = NetSystem.done THEN
						me.state := 1
					ELSE
						me.S := NIL;  Oberon.Remove(me)
					END;
					me.time := Input.Time() + 3*Input.TimeUnit
				|1:
					res := NetSystem.State(me.S.C);
					IF res = NetSystem.inout THEN
						me.state := 2
					ELSIF res # NetSystem.waitCon THEN
						NetSystem.CloseConnection(me.S.C); me.S := NIL; me.state := 0;
						me.time := me.time + Input.TimeUnit
					END
				|2: IF openPOP(me.S, me.host, me.user, me.passwd) THEN
						me.state := 3
					ELSE
						me.state := 4
					END;
					me.time := Input.Time() + Input.TimeUnit
				|3: NrOfMails(me.S, res);
					IF (me.S.res = NetTools.Done) & (res # me.lastMails) THEN
						IF res > 0 THEN
							Texts.WriteString(W, "New mail "); Texts.WriteInt(W, res, 0);
							Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
						END;
						me.lastMails := res
					END;
					me.state := 4;  me.time := Input.Time() + Input.TimeUnit
				|4: ClosePOP(me.S); me.S := NIL; me.state := 0; me.time := Input.Time() + me.delay*Input.TimeUnit
			END;
			(*me.time := me.time + Input.TimeUnit*)
		END
	END DoSnoop;

(** Mail.StartSnoop user@pop-host
	Polls pop-host for incoming mail. *)
	PROCEDURE StartSnoop*;
		VAR
			S: Attributes.Scanner;
			snooper, snoop: Snooper;
			i, j: LONGINT;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			NEW(snooper); snooper.passwd := ""; snooper.S := NIL; snooper.lastMails := 0;
			i := 0;
			WHILE (S.s[i] # 0X) & (S.s[i] # "@") DO
				snooper.user[i] := S.s[i]; INC(i)
			END;
			snooper.user[i] := 0X;
			IF S.s[i] = "@" THEN
				j := i+1; i := 0;
				WHILE S.s[j] # 0X DO
					snooper.host[i] := S.s[j]; INC(i); INC(j)
				END;
				snooper.host[i] := 0X
			ELSE
				COPY(snooper.user, snooper.host); snooper.user := ""
			END;
			NetSystem.GetPassword("pop", snooper.host, snooper.user, snooper.passwd);
			Texts.WriteString(W, snooper.user); Texts.Write(W, "@"); Texts.WriteString(W, snooper.host);
			IF snooper.passwd # "" THEN
				NetSystem.GetIP(snooper.host, snooper.hostIP);
				IF snooper.hostIP # NetSystem.anyIP THEN
					snoop := snoopers;
					WHILE (snoop # NIL) & (snoop.hostIP # snooper.hostIP) DO
						snoop := snoop.nextS
					END;
					IF snoop = NIL THEN
						Attributes.Scan(S);
						IF (S.class = Attributes.Int) & (S.i > 0) THEN
							snooper.delay := S.i
						ELSE
							snooper.delay := DefSnoopDelay
						END;
						Texts.Write(W, " "); Texts.WriteInt(W, snooper.delay, 0);
						snooper.state := 0; snooper.time := Oberon.Time();
						snooper.nextS := snoopers; snoopers := snooper;
						snooper.safe := FALSE; snooper.handle := DoSnoop;
						Oberon.Install(snooper)
					END
				ELSE
					Texts.WriteString(W, " invalid address")
				END
			ELSE
				Texts.WriteString(W, " no password found")
			END;
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END StartSnoop;

(** Mail.StopSnoop user@pop-host
		see Mail.StartSnoop *)
	PROCEDURE StopSnoop*;
		VAR
			S: Attributes.Scanner;
			user, host, passwd: ARRAY 64 OF CHAR;
			hostIP: NetSystem.IPAdr;
			snoop, psnoop: Snooper;
			i, j: LONGINT;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			i := 0;
			WHILE (S.s[i] # 0X) & (S.s[i] # "@") DO
				user[i] := S.s[i]; INC(i)
			END;
			user[i] := 0X;
			IF S.s[i] = "@" THEN
				j := i+1; i := 0;
				WHILE S.s[j] # 0X DO
					host[i] := S.s[j]; INC(i); INC(j)
				END;
				host[i] := 0X
			ELSE
				COPY(user, host); user := ""
			END;
			NetSystem.GetPassword("pop", host, user, passwd);
			IF passwd # "" THEN
				Texts.WriteString(W, user); Texts.Write(W, "@"); Texts.WriteString(W, host);
				NetSystem.GetIP(host, hostIP);
				psnoop := NIL; snoop := snoopers;
				WHILE (snoop # NIL) & (snoop.hostIP # hostIP) DO
					psnoop := snoop; snoop := snoop.nextS
				END;
				IF snoop # NIL THEN
					IF snoop.S # NIL THEN
						ClosePOP(snoop.S)
					END;
					Oberon.Remove(snoop);
					IF psnoop # NIL THEN
						psnoop.nextS := snoop.nextS
					ELSE
						snoopers := snoop.nextS
					END
				ELSE
					Texts.WriteString(W, " not found")
				END;
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END StopSnoop;

(** Parsing of a mailto url. *)
	PROCEDURE SplitMailTo*(VAR url, mailadr: ARRAY OF CHAR): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		HyperDocs.UnESC(url);
		i := 0; Blanks();
		(* skip mailto *)
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			INC(i)
		END;
		(* skip : *)
		WHILE (url[i] # 0X) & ((url[i] = ":") OR (url[i] = "/")) DO
			INC(i)
		END;
		Blanks();
		(* get mailadr *)
		iskey := TRUE;
		l := LEN(mailadr); j := 0;
		WHILE url[i] # 0X DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				mailadr[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		mailadr[j] := 0X; DEC(j);
		WHILE (j >= 0) & (mailadr[j] <= " ") DO
			mailadr[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF mailadr # "" THEN
				Strings.StrToInt(mailadr, key);
				HyperDocs.RetrieveLink(key, buffer);
				key := SplitMailTo(buffer, mailadr)
			ELSE
				key := HyperDocs.UndefKey
			END
		ELSE
			COPY("mailto:", url);
			Strings.Append(url, mailadr);
			key := HyperDocs.RegisterLink(url)
		END;
		RETURN key
	END SplitMailTo;

	PROCEDURE *MailToSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR mailadr: ARRAY NetTools.PathStrLen OF CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitMailTo(M.link, mailadr);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Mail.NewMailToLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END MailToSchemeHandler;

	PROCEDURE NewMailToLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.usePath := FALSE;
		L.handle := MailToSchemeHandler; Objects.NewObj := L
	END NewMailToLinkScheme;

(** Parsing of a mailserver url. *)
	PROCEDURE SplitMailServer*(VAR url, mailadr, subject, body: ARRAY OF CHAR): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		HyperDocs.UnESC(url);
		i := 0; Blanks();
		(* skip mailserver *)
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			INC(i)
		END;
		(* skip : *)
		WHILE (url[i] # 0X) & ((url[i] = ":") OR (url[i] = "/")) DO
			INC(i)
		END;
		Blanks();
		(* get mailadr *)
		iskey := TRUE;
		l := LEN(mailadr); j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				mailadr[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		mailadr[j] := 0X; DEC(j);
		WHILE (j >= 0) & (mailadr[j] <= " ") DO
			mailadr[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF mailadr # "" THEN
				Strings.StrToInt(mailadr, key);
				HyperDocs.RetrieveLink(key, buffer);
				key := SplitMailServer(buffer, mailadr, subject, body)
			ELSE
				key := HyperDocs.UndefKey
			END;
			RETURN key
		END;
		IF url[i] = "/" THEN
			INC(i)
		END;
		l := LEN(subject); j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			IF j < l THEN
				subject[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		subject[j] := 0X; DEC(j);
		WHILE (j >= 0) & (subject[j] <= " ") DO
			subject[j] := 0X; DEC(j)
		END;
		IF url[i] = "/" THEN
			INC(i)
		END;
		l := LEN(body); j := 0;
		WHILE url[i] # 0X DO
			IF j < l THEN
				body[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		body[j] := 0X;
		COPY("mailserver:", url);
		Strings.Append(url, mailadr);
		Strings.AppendCh(url, "/");
		Strings.Append(url, subject);
		Strings.AppendCh(url, "/");
		Strings.Append(url, body);
		key := HyperDocs.RegisterLink(url);
		RETURN key
	END SplitMailServer;

	PROCEDURE *MailServerSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR mailadr, subject, body: ARRAY NetTools.PathStrLen OF CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitMailServer(M.link, mailadr, subject, body);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Mail.NewMailServerLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END MailServerSchemeHandler;

	PROCEDURE NewMailServerLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.usePath := FALSE;
		L.handle := MailServerSchemeHandler; Objects.NewObj := L
	END NewMailServerLinkScheme;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			T, text: Texts.Text;
			objb: Objects.Object;
			mailadr, subject, body: ARRAY NetTools.PathStrLen OF CHAR;
			key, beg, end, time, i: LONGINT;
			node: HyperDocs.Node;
	BEGIN
		IF Strings.CAPPrefix("mailto", D.name) THEN
			key := SplitMailTo(D.name, mailadr); subject := ""; body := ""
		ELSIF Strings.CAPPrefix("mailserver", D.name) THEN
			key := SplitMailServer(D.name, mailadr, subject, body)
		ELSE
			key := HyperDocs.UndefKey
		END;
		IF key = HyperDocs.UndefKey THEN
			D.dsc := NIL; RETURN
		END;
		NEW(T); Texts.Open(T, "");
		objb := Gadgets.CreateObject("BasicGadgets.NewButton");
		Attributes.SetString(objb, "Caption", "Send"); Attributes.SetString(objb, "Cmd", "Mail.Send  @ ~");
		Gadgets.NameObj(objb, "mailto");
		Texts.WriteObj(W, objb); Texts.WriteLn(W); Texts.WriteLn(W);
		Texts.WriteString(W, "To: "); Texts.WriteString(W, mailadr); Texts.WriteLn(W);
		IF subject # "" THEN
			Texts.WriteString(W, "Subject: "); Texts.WriteString(W, subject); Texts.WriteLn(W)
		END;
		IF (HyperDocs.context # NIL) & (HyperDocs.context.old # NIL) THEN
			node := HyperDocs.context.old
		ELSE
			node := HyperDocs.NodeByDoc(Desktops.CurDoc(Gadgets.context))
		END;
		IF node # NIL THEN
			Texts.WriteString(W, "X-URL: "); HyperDocs.RetrieveLink(node.key, buffer); Texts.WriteString(W, buffer); Texts.WriteLn(W)
		END;
		IF body # "" THEN
			Texts.WriteLn(W); i := 0;
			WHILE body[i] # 0X DO
				IF body[i] = "/" THEN
					Texts.WriteLn(W)
				ELSE
					Texts.Write(W, body[i])
				END;
				INC(i)
			END;
			Texts.WriteLn(W)
		ELSE
			text := NIL; time := -1;
			Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time > 0) THEN
				Texts.WriteLn(W); Texts.Append(T, W.buf); CiteText(W, text, beg, end)
			END
		END;
		Texts.Append(T, W.buf);
		COPY(mailadr, D.name); Links.SetLink(D.dsc, "Model", T);
		IF HyperDocs.context # NIL THEN
			HyperDocs.context.replace := FALSE; HyperDocs.context.history := FALSE
		END
	END LoadDoc;

(** Mail.NewDoc
		Document new-procedure for "mailto:" & "mailserver:" documents.
		E.g. Use Desktops.OpenDoc "mailto:zeller@inf.ethz.ch" to send me a mail. *)
	PROCEDURE NewDoc*;
		VAR D: Objects.Object;
	BEGIN
		D := Gadgets.CreateObject("TextDocs.NewDoc");
		WITH D: Documents.Document DO
			D.Load := LoadDoc
		END
	END NewDoc;

(** Mail.Convert from to ~
	Converts a mailbox-file from the old version to the new version *)
	PROCEDURE Convert*;
		VAR
			S: Attributes.Scanner;
			F: Files.File;
			R: Files.Rider;
			box: LocalBox;
			mail: LocalMail;
			org, pos, len: LONGINT;
			state: SET;
			nrmails, nr, i, res: INTEGER;
			new: BOOLEAN;
			tag: CHAR;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			F := Files.Old(S.s); Texts.WriteString(W, S.s); Texts.Write(W, " ");
			IF F # NIL THEN
				Attributes.Scan(S);
				IF S.class IN {Attributes.Name, Attributes.String} THEN
					Texts.WriteString(W, "=> "); Texts.WriteString(W, S.s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
					box := OpenLocalBox(S.s);
					Files.Set(R, F, 0); Files.ReadLInt(R, org);
					IF org < 0 THEN
						Files.ReadLInt(R, len); org := -org; new := TRUE
					ELSE
						new := FALSE				
					END;
					Files.Set(R, F, org); Files.ReadInt(R, nrmails);
					FOR i := 1 TO nrmails DO
						Files.ReadInt(R, nr);
						Files.ReadString(R, mail.replyTo);
						IF new THEN
							Files.ReadString(R, mail.topic)
						ELSE
							COPY(DefTopic, mail.topic)
						END;
						Files.ReadString(R, mail.subject);
						Files.ReadLInt(R, mail.date); mail.time := 0;
						Files.ReadSet(R, state); mail.state := {};
						IF read IN state THEN
							INCL(mail.state, read)
						END;
						IF delete IN state THEN
							INCL(mail.state, delete)
						END;
						Files.ReadLInt(R, org); mail.org := -1;
						pos := Files.Pos(R); Files.Set(R, F, org);
						Files.Read(R, tag);
						IF tag = Texts.TextBlockId THEN
							NEW(mail.text); Texts.Open(mail.text, "");
							Texts.Load(mail.text, F, Files.Pos(R), len);
							BTrees.SearchLInt(box.ind, nr, org, res);
							IF res = BTrees.Done THEN
								Texts.WriteInt(W, nr, 0); Texts.WriteString(W, " number allready used, allocating a new one"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
								mail.key := NewKey(box)
							ELSE
								mail.key := nr
							END;
							PutLocalMail(box, mail, TRUE, FALSE)
						ELSE
							Texts.WriteInt(W, nr, 0); Texts.WriteString(W, " no text"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
							mail.text := NIL
						END;
						Files.Set(R, F, pos)
					END;
					BTrees.Flush(box.ind)
				END
			ELSE
				Texts.WriteString(W, "not found")
			END;
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END Convert;

(** Mail.Mono (marked text)
		Change the font of the marked viewer into Courier10. *)
	PROCEDURE Mono*;
		VAR T: Texts.Text;
	BEGIN
		T := Oberon.MarkedText();
		IF T # NIL THEN
			Texts.ChangeLooks(T, 0, T.len, {0, 1}, Fonts.This("Courier10.Scn.Fnt"), Display.FG, 0)
		END
	END Mono;

(*
	check out file name
	\C collect
	\U undelete
*)
	PROCEDURE Recover*;
		VAR
			S: Attributes.Scanner;
			F: Files.File;
			R: Files.Rider;
			key, i, org, org2, len, pos: LONGINT;
			box: LocalBox;
			mail: LocalMail;
			h: MIME.Header;
			sin: Streams.Stream;
			tR: Texts.Reader;
			collect, undelete: BOOLEAN;
			ch: CHAR;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		collect := FALSE; undelete := FALSE;
		WHILE ~S.eot & (S.class = Attributes.Char) & (S.c = Oberon.OptionChar) DO
			Attributes.Scan(S);
			IF S.class = Attributes.Name THEN
				IF CAP(S.s[0]) = "C" THEN
					collect := TRUE
				ELSIF CAP(S.s[0]) = "U" THEN
					undelete := TRUE
				END;
				Attributes.Scan(S)
			END
		END;
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			F := Files.Old(S.s); Files.Set(R, F, 0);
			Attributes.Scan(S);
			IF (F # NIL) & (S.class IN {Attributes.Name, Attributes.String}) THEN
				IF Files.Old(S.s) # NIL THEN
					RETURN
				END;
				box := OpenLocalBox(S.s);
				key := 0; org := 0; Files.ReadLInt(R, i);
				WHILE ~R.eof DO
					IF (i = LocalMailTag) OR (i = LocalMailTTag) THEN
						org := Files.Pos(R);
						Files.ReadBytes(R, mail.replyTo, LEN(mail.replyTo)); Files.ReadBytes(R, mail.topic, LEN(mail.topic));
						Files.ReadLInt(R, mail.date);
						IF i = LocalMailTTag THEN
							Files.ReadLInt(R, mail.time)
						ELSE
							mail.time := 0
						END;
						Files.ReadBytes(R, mail.subject, LEN(mail.subject));
						Files.ReadSet(R, mail.state); Files.ReadLInt(R, mail.key);
						Files.ReadLInt(R, mail.org);
						IF (mail.key >= 0) & (mail.org < Files.Length(F)) THEN
							org2 := Files.Pos(R); mail.text := NIL;
							Texts.WriteInt(W, mail.key, 0); Texts.Append(Oberon.Log, W.buf);
							IF mail.org >  0 THEN
								Files.Set(R, F, mail.org); Files.Read(R, ch);
								IF ch = Texts.TextBlockId THEN
									NEW(mail.text); Texts.Open(mail.text, "");
									len := 0; Texts.Load(mail.text, F, mail.org+1, len)
								END
							END;
							IF mail.text # NIL THEN
								Texts.OpenReader(tR, mail.text, 0);
								Texts.Read(tR, ch);
								WHILE ~tR.eot & (ch <= " ") DO
									Texts.Read(tR, ch)
								END;
								sin := TextStreams.OpenReader(mail.text, Texts.Pos(tR)-1);
								MIME.ReadHeader(sin, NIL, h, len);
								pos := MIME.FindField(h, "Reply-To");
								IF pos < 0 THEN
									pos := MIME.FindField(h, "From")
								END;
								IF pos > 0 THEN (* incomming message *)
									INCL(mail.state, in); EXCL(mail.state, out);
									MIME.ExtractEMail(h, pos, mail.replyTo)
								ELSE (* outgoing message *)
									EXCL(mail.state, in); INCL(mail.state, out);
									pos := MIME.FindField(h, "To");
									MIME.ExtractValue(h, pos, mail.replyTo)
								END;
								pos := MIME.FindField(h, "Subject");
								MIME.ExtractValue(h, pos, mail.subject);
								IF in IN mail.state THEN
									pos := MIME.FindField(h, "Date");
									IF pos > 0 THEN
										MIME.ExtractGMTDate(h, pos, mail.time, mail.date)
									END
								END;
								pos := MIME.FindField(h, "Topic");
								WHILE pos > 0 DO
									Texts.OpenReader(tR, mail.text, 0);
									Texts.Read(tR, ch);
									WHILE ~tR.eot & (ch # Strings.CR) DO
										Texts.Read(tR, ch)
									END;
									Texts.Delete(mail.text, 0, Texts.Pos(tR));
									sin := TextStreams.OpenReader(mail.text, 0);
									MIME.ReadHeader(sin, NIL, h, len);
									pos := MIME.FindField(h, "Topic")
								END;
								IF undelete THEN
									EXCL(mail.state, delete)
								END;
								IF ~collect OR ~(delete IN mail.state) THEN
									INC(key); mail.key := key;
									Texts.WriteString(W, " => "); Texts.WriteInt(W, mail.key, 0);
									org := org2;
									Texts.WriteString(W, " ok");
									PutLocalMail(box, mail, TRUE, TRUE)
								ELSE
									Texts.WriteString(W, " deleted")
								END
							ELSE
								Texts.WriteString(W, " no text")
							END;
							Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
						END
					ELSE
						INC(org)
					END;
					Files.Set(R, F, org); Files.ReadLInt(R, i)
				END;
				BTrees.Flush(box.ind); Files.Close(BTrees.Base(box.ind))
			END
		END
	END Recover;

(** Mail.Append box1 box2
	adds all messages in box2 to box1. *)
	PROCEDURE Append*;
		VAR
			S: Attributes.Scanner;
			new, old: LocalBox;
			mail: LocalMail;
			key, maxKey: LONGINT;
			res: INTEGER;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			new := OpenLocalBox(S.s);
			Attributes.Scan(S);
			IF S.class IN {Attributes.Name, Attributes.String} THEN
				old := OpenLocalBox(S.s);
				BTrees.MaxLIntKey(old.ind, maxKey, res);
				IF res # BTrees.Done THEN
					maxKey := -1
				END;
				key := 0;
				WHILE key <= maxKey DO
					mail.key := -1; GetLocalMail(old, key, mail, TRUE, FALSE);
					IF mail.key = key THEN
						mail.key := NewKey(new);
						PutLocalMail(new, mail, TRUE, TRUE)
					END;
					INC(key)
				END 
			END
		END
	END Append;
	
	PROCEDURE *Cleanup();
	BEGIN
		WHILE snoopers # NIL DO
			Oberon.Remove(snoopers);
			IF snoopers.S # NIL THEN ClosePOP(snoopers.S) END;
			snoopers := snoopers.nextS
		END
	END Cleanup;

	PROCEDURE *MailListDisplay(F: ListGadgets.Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: ListGadgets.Line);
		VAR
			item: Item;
			mail: LocalMail;
			str: ARRAY 16 OF CHAR;
			i: LONGINT;
			textC: INTEGER;
			font: Fonts.Font;
			ch: CHAR;
	BEGIN
		IF R.d = NIL THEN RETURN END;
		item := R.d(Item); 
		GetMail(item, mail);
		IF remote IN mail.state THEN
			font := Fonts.This("Oberon10b.Scn.Fnt")
		ELSE
			font := F.fnt
		END;
		IF read IN mail.state THEN
			textC := F.textC
		ELSE
			textC := Display3.red
		END;
		Display3.ReplConst(Q, F.backC, x, y, 58, h, Display.replace);
		i := 0;
		WHILE (mail.replyTo[i] # "@") & (mail.replyTo[i] # 0X) DO
			INC(i)
		END;
		ch := mail.replyTo[i]; mail.replyTo[i] := 0X;
		Display3.String(Q, textC, x, y + L.dsr, font, mail.replyTo, Display.paint);
		mail.replyTo[i] := ch;
		Display3.ReplConst(Q, F.backC, x+58, y, 224, h, Display.replace);
		Display3.String(Q, textC, x+64, y + L.dsr, font, mail.subject, Display.paint);
		Strings.DateToStr(mail.date, str);
		Display3.ReplConst(Q, F.backC, x+64+218, y, w-64-218, h, Display.replace);
		Display3.String(Q, textC, x+64+224, y + L.dsr, font, str, Display.paint)
	END MailListDisplay;

	PROCEDURE *MailListFormat(F: ListGadgets.Frame; R: ListRiders.Rider; L: ListGadgets.Line);
	BEGIN
		L.w := F.W; L.h := F.fnt.height;
		L.dsr := -F.fnt.minY; L.dx := 0
	END MailListFormat;

BEGIN
	Modules.InstallTermHandler(Cleanup);
	Texts.OpenWriter(W); mullerBox := "CURRENT";
	remBoxes := NIL; snoopers := NIL;
	NEW(mailListMethod);
	mailListMethod^ := ListGadgets.methods^;
	mailListMethod.Display := MailListDisplay;
	mailListMethod.Format := MailListFormat
END Mail.

Mail.Panel	Mail.Sig.Text

Mail.StartSnoop zeller@lillian.inf.ethz.ch ~

Mail.StopSnoop zeller@lillian.inf.ethz.ch ~

System.Directory Mail*.DB*\d ~

Mail.Convert MailBox.DB OldMail.DB ~
Mail.Recover \C MailInFeb2.DB MailIn.DB  ~
Mail.Recover \C MailOut.DB MailOutRec.DB ~
Mail.Append MailTest.DB MailIn.DB

System.Free Mail ~ NetTools HyperDocs ~

System.DeleteFiles MailBox.DB MailIn.DB ~

Mail.StartSnoop muller@lillian 120
Mail.StopSnoop muller@lillian 120

System.Free Mail ~

telnet:lillian:110
NetSystem.ClearUser

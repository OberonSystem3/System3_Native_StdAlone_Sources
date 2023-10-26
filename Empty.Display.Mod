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

(**
 Module Display provides the display drawing primitives and the base type of the visual objects, called Frames.
*)

(* Native Oberon empty display driver, pmuller 28.09.95 *)

	IMPORT SYSTEM, Objects;
	
	CONST
		BG* = 0; FG* = 15; (** Background, foreground colors. *)
		
		(** Drawing operation modes. *)
		replace* = 0;	(** replace destination. *)
		paint* = 1;	(** paint over destination.  *)
		invert* = 2;	(** invert destination. *)
		
		remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (** ControlMsg id. *)
		reduce* = 0; extend* = 1; move* = 2; (** ModifyMsg id. *)
		display* = 0; state* = 1; (** ModifyMsg mode. *)
		screen* = 0; printer* = 1; (** DisplayMsg device *)
		full* = 0; area* = 1; contents* = 2; (** DisplayMsg id. *)
		get* = 0; set* = 1; reset* = 2; (** SelectMsg id. *)
		drop* = 0; integrate* = 1; (** ConsumeMsg id. *)
		
	TYPE Pattern* = LONGINT;
			PatternPtr = POINTER TO RECORD w, h, pixmap: SHORTINT END;
			List = POINTER TO ListDesc;
			ListDesc = RECORD
				next: List;
				pat: PatternPtr
			END;

			Frame* = POINTER TO FrameDesc;	(** Base type of all displayable objects. *)
			FrameDesc* = RECORD (Objects.ObjDesc)
				next*, dsc*: Frame;	(** Sibling, child pointers. *)
				X*, Y*, W*, H*: INTEGER	(** Coordinates. *)
			END;
  
			FrameMsg* = RECORD (Objects.ObjMsg)	(** Base type of messages sent to frames. *)
				F*: Frame; (*target*)	(** Message target, NIL for broadcast. *)
				x*, y*: INTEGER;	(** Message origin. *)
				res*: INTEGER	(** Result code: <0 = error or no response, >=0 response. *)
			END;
		
			ControlMsg* = RECORD (FrameMsg)
				id*: INTEGER	(** remove, suspend, restore. *)
			END;
		
			ModifyMsg* = RECORD (FrameMsg)	(** Change coordinates in container frame. *)
				id*: INTEGER;	(** reduce, extend, move. *)
				mode*: INTEGER;	(** Modes display, state. *)
				dX*, dY*, dW*, dH*: INTEGER;	(** Change from old coordinates (delta). *)
				X*, Y*, W*, H*: INTEGER	(** New coordinates. *)
			END;
		
			DisplayMsg* = RECORD (FrameMsg)	(** Display a frame, a part of it or its contents. *)
				device*: INTEGER;	(** screen, printer *)
				id*: INTEGER;	(** full, area, contents. *)
				u*, v*, w*, h*: INTEGER	(** Area to be restored. *)
			END;
		
			LocateMsg* = RECORD (FrameMsg)	(** Locate frame in display space. *)
				loc*: Frame;	(** Result. *)
				X*, Y*: INTEGER;	(** Absolute location. *)
				u*, v*: INTEGER	(** Relative coordinates in loc. *)
			END;
		
			SelectMsg* = RECORD (FrameMsg)	(** Selection control. *)
				id*: INTEGER;	(** get, set, reset. *)
				time*: LONGINT;	(** Time of selection. *)
				sel*: Frame;	(** Parent of selection. *)
				obj*: Objects.Object	(** List of objects involved, linked with slink. *)
			END;
		
			ConsumeMsg* = RECORD (FrameMsg)	(** Drop, integrate frames. *)
				id*: INTEGER;	(** drop, integrate. *)
				u*, v*: INTEGER;	(** Relative coordinates in destination when drop. *)
				obj*: Objects.Object	(** List of objects to be consumed, linked with slink. *)
			END;
		
			MsgProc* = PROCEDURE (VAR M: FrameMsg);

	VAR
		Unit*: LONGINT; (** RasterUnit = Unit/36000 mm *)
		Left*, (** Left margin of black-and-white screen. *)
		ColLeft*, (** Left margin of color screen, often same as Left. *)
		Bottom*, (** Bottom of primary map. *)
		UBottom*, (** Bottom of secondary map. *)
		Width*, (** Screen width. *)
		Height*: INTEGER; (** Screen height. *)
		arrow*, 	(** Oberon cursor. *)
    	star*, 	(** Star marker to mark documents and viewers. *)
    	cross*, 	(** Insertion marker. *)
    	downArrow*, 	(** Marker to indicate disk operation. *)
    	hook*: Pattern;	(** Text caret pattern. *)
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;	(** Simulated grey levels. *)
		Broadcast*: MsgProc;	(** Message broadcast to all frames in the display space. *)
		Pat: List;

(** Intersect with current clip rectangle resulting in a new clip rectangle. *)
	PROCEDURE AdjustClip*(X, Y, W, H: INTEGER);
	BEGIN
	END AdjustClip;

(** Returns the dimensions of a pattern. *)
	PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
	VAR s: SHORTINT;
	BEGIN SYSTEM.GET(pat, s); w := s; SYSTEM.GET(pat+1, s); h := s;
	END GetDim;

(** Reset the current clipping rectangle to the whole display. *)
	PROCEDURE ResetClip*;
	BEGIN 
	END ResetClip;
	
(** Set the new clipping rectangle. *)
	PROCEDURE SetClip*(x, y, w, h: INTEGER);
	BEGIN
	END SetClip;
	
(** Get the current clip rectangle. *)
	PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
	BEGIN
		x := 0;  y := 0;  w := Width;  h := Height
	END GetClip;
	
(** Change color palette entry. 0 <= col, red, green, blue < 256. *)
	PROCEDURE SetColor*(col, red, green, blue: INTEGER);	(* 0 <= col, red, green, blue < 256 *)
	BEGIN
	END SetColor;

(** Retrieve color paletter entry. 0 <= col, red, green, blue < 256. *)
	PROCEDURE GetColor*(col: INTEGER; VAR red, green, blue: INTEGER);
	BEGIN
		red := 0;  green := 0;  blue := 0
	END GetColor;

(** Place a dot of color col in operation mode at x, y. Effect equivalent to ReplConst with a block of size 1, 1. *)
	PROCEDURE Dot*(col, x, y, mode: INTEGER);
	BEGIN
	END Dot;
	
(** Copy source block SX, SY, W, H to destination DX, DY using operation mode. A block is given by its lower left corner X, Y and its dimension W, H. Some drivers only implement mode = replace. *)
	PROCEDURE CopyBlock*(SX, SY, W, H, DX, DY, mode: INTEGER);
	BEGIN 
	END CopyBlock;
	
(** Change screen mode. *)
	PROCEDURE SetMode*(X: INTEGER; s: SET);
	BEGIN
	END SetMode;
	
(** Copy pattern pat in color col to X, Y using operation mode. *)
	PROCEDURE CopyPattern*(col: INTEGER; pat: Pattern; X, Y, mode: INTEGER);
	BEGIN
	END CopyPattern;
	
(** Block fill in color col and operation mode. Some drivers do not implement mode = paint. *)
	PROCEDURE ReplConst*(col, X, Y, W, H, mode: INTEGER);	(* col not used if mode is invert *)
	BEGIN
	END ReplConst;
	
(** Replicate pattern pat in color col into block X, Y, W, H using operation mode, proceeding from left to right and from bottom to top, starting at lower left corner. The pattern origin is placed at pX, pY. Some drivers do not implement mode = paint. *)
	PROCEDURE FillPattern*(col: INTEGER; pat: Pattern; pX, pY, X, Y, W, H, mode: INTEGER);
	BEGIN
	END FillPattern;

(** Replicate pattern pat in color col into block X, Y, W, H using operation mode, proceeding from left to right and from bottom to top, starting at lower left corner. The pattern pin-point is at 0, 0. Some drivers do not implement mode = paint. *)
	PROCEDURE ReplPattern*(col: INTEGER; pat: Pattern; X, Y, W, H, mode: INTEGER);
	BEGIN
	END ReplPattern;
	
(** Define a new pattern. *)
	PROCEDURE NewPattern*(width, height: INTEGER; VAR image: ARRAY OF SET): Pattern;
	VAR len, src, dest: LONGINT; i: INTEGER; p: PatternPtr; pl: List;
	BEGIN
		len := (width+7) DIV 8;
		SYSTEM.NEW(p, 4+len*height); p.w := SHORT(width); p.h := SHORT(height);
		src := SYSTEM.ADR(image); dest := SYSTEM.ADR(p.pixmap);
		i := 0;
		WHILE i < height DO SYSTEM.MOVE(src, dest, len); INC(src, 4); INC(dest, len); INC(i) END;
		NEW(pl);  pl.pat := p;  pl.next := Pat;  Pat := pl;	(* put in list to avoid GC *)
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
		downArrow := NewPattern(11, 15, image);
		
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
	
(** Returns the number of bits per pixel for the given X coordinate. Typical values are 1, 4 and 8. *)
	PROCEDURE Depth*(X: INTEGER): INTEGER;
	BEGIN
		RETURN 8
	END Depth; 

(** Display a picture.  Used internally by Pictures module. *)
	PROCEDURE DisplayBlock*(B:LONGINT; DX, DY, W, H, SX, SY, mode:INTEGER);
	BEGIN
	END DisplayBlock;

(** Return address of display screen located at X coordinate.  Returns 0 if not supported. *)
	PROCEDURE Map*(X: INTEGER): LONGINT;
	BEGIN
		RETURN 0
	END Map;
	
BEGIN
	Width := 1024;
	Height := 768;
	Left:= 0;
	ColLeft:= 0;
	Bottom:= 0;
	UBottom:= -255; 
	Pat := NIL;
	CreatePatterns;
	Unit := 10000
END Display.

(** Remarks:

1. Background and Foreground colors
Oberon can either be used with white text on a black background, or inverted with black text on a white background (the so-called paper model). To reduce confusion you should use the FG and BG constants in your code. The black and white constants are only there for compatibility with older applications and do not reflect true white and black. It is recommended to use the paper model for all Oberon applications. Oberon uses color palettes and does not directly support true color displays (although it might be possible to use Oberon on such a display).

2. Screen Organization and Depth
Oberon supports multiple displays that are placed next to each other in increasing X coordinates. The X coordinate thus uniquely determines the screen, hence the single parameter of the Depth procedure. Each screen contains a set of nested frames. Historically, the first screen (at Left) is the black and white screen, and the second screen is the color screen (at ColLeft). Today Left and ColLeft are typically set to 0, as only a few computers still use black and white displays. The screen origin is located at the bottom-left corner of the display (i.e. Y decrease from the top to the bottom of the display).

3. The Frames and the Frame messages
Frames are the visual entities of Oberon. The frames are placed in the display space to make them visible. This involves inserting frames using the dsc and next fields into a container already located in the display space. All frames of a container are linked together in priority sequence using the next field. The dsc field points to the first child frame of a container. Note that this is only a convention and certain frames might decide to manage their contents in different ways. The frame messages are used to manipulate Frames (remember that frames also respond to the object message defined in module Objects).

4. Target or Destination frames
The Frame messages are often broadcasted into the display space rather than sending them directly to a frame. This is useful when many frames are to be informed of an event. It is also a means to determine the exact location (in coordinates and nesting) of a frame in the display space by following the message thread from the display root object to the frame itself (see module Objects). It is also possible to address a broadcasted message to a certain frame. This is called a directed broadcast. The target or destination of a broadcasted message is identified by the F field in the FrameMsg. It is set to NIL when all frames are to receive the message (true broadcast) and to a specific frame if only that frame is interested in the message (directed broadcast).

5. Frame Coordinates and Message origin
The coordinates of a frame are specified relative to its container or parent frame. The frame messages pass the absolute position of the top-left corner of the parent frame to their children in the x and y fields (called the message origin). Thus the absolute display position of a frame F is determined when it receives a frame message M:

	M.x + F.X, M.y + F.Y, F.W, F.H
	
6. Invalidating Messages
Often a frame knows that a message broadcast need not pass through the remainder of display space because it has already been handled. In such cases the res field of the frame message is set to zero or positive to indicate an action has been completed and that the message should be regarded as invalidated. Setting the res field in this way is called invalidating a message and will terminate the message broadcast.

7. Broadcasting Frame Messages
The Broadcast procedure broadcasts a message through the display space. The procedure initializes fields in the frame message. The message origin is set to (0, 0), the message is time stamped, the res field is set to a negative value, and the dlink field is initialized to NIL. In addition, the clipping rectangle is set to the whole display area.

8. Clipping
To prevent the clipping rectangle clipping the wrong display primitives, it is reset on each message broadcast or when a trap occurs. Clipping does not affect the drawing of cursors. The Gadget system uses "display masks" that hide the management of the clipping rectangle from the programmer.

9. NewPattern
The NewPattern procedure allows you to define patterns in a machine portable way. The sets contain 32 bits, each specifying a single pixel, with {0} the left-most pixel of the pattern. Each pattern line must be filled with empty bits so that it is a multiple of 32 pixels long. The first SET of the array contains the bottom line of the pattern.

10. ControlMsg
The ControlMsg is primarily used to remove a frame from the display space. When id is set to remove, the destination frame should be removed from its current location. This done by the container the frame is contained in (and is thus a slight misinterpretation of F as a destination frame). More than one frame are removed if the destination is a list of frames (connected by the slink field). In this case, they should at all belong to the same parent. This message should always be broadcast.
When the message id is set to suspend or restore it indicates that all frames from the destination downwards in the display space will be temporarily removed from the display space, or will be restored to the display space. This allow frames to update their internal data structures as they may have missed messages while suspended (this is because only those frames located in the display space receive message broadcasts). This message is sent to the top-most frame of that part of the display space involved (with the destination set to NIL).

11. ModifyMsg
The ModifyMsg broadcasts resize request to the destination frame. This allows you to move the relative position or change the size of a child in a container. When the mode is set to state, the frame should not display itself immediately but only update its size and position (possibly indicating changes to its children in turn). It is then the task of the sender to send a follow up Display message to the frame. The latter way of using the ModifyMsg allows a container to influence its children without having them draw themselves for each change made. This message must never be invalidated (i.e. it must travel throughout the whole display space). The dX, dY, dW, dH coordinates should always be set correctly to indicate the change in position and size from the original position and size. The id field of the ModifyMsg is ignored by most frames in the system.

12. DisplayMsg
The DisplayMsg sends either a redraw request or a print request to a destination frame, depending on the value of device (screen or printer). When the destination is NIL, a whole DAG of gadgets are implied. When id is set to area, the area u, v, w, h inside the destination frame should be redrawn. Gadgets assume that these coordinates are relative to the top left-most corner of the destination gadget (thus v is negative).
When printing, the x, y coordinates indicate the absolute printer coordinates of the left-bottom corner of the frame on paper (and not the left-bottom corner of the container). When the id is set to full, the frame has to print itself in the form it looks on the display. When the id is set to contents it should print its complete contents (for example a multi-page text that it is displaying). The frame may assume that the printer driver has been initialized already. Readying the printer is the task of the sender, and is done by calling Printer.Open.

13. LocateMsg
This message is broadcast to locate the frame positioned at the absolute coordinates X, Y on the display. The result, if any, is found in the loc field. The frame should return the relative position u, v of X, Y inside itself. Gadgets return these coordinates relative to their top-left corner (i.e. v is typically negative). By convention, the message is invalidated when the loc field is set.

14. SelectMsg
When id is set to get, the message is used to return the current object selection (a list) in obj. The parent of the selected objects is returned in the sel field. This message is broadcast with the destination set to NIL. The time of the selection is returned in the time field. Each container frame in the display space typically compares the time of its selection with the time field in the message, updating the returned selection when it is after the time set in the message field. When id is set to set or reset, the destination frame should select or unselect itself. It should never draw itself at this point. This is the task of the message sender.

15. ConsumeMsg
When the id is set to drop, the destination frame is requested to consume the list of objects found in the obj field. This is the way how objects can be added dynamically to a container. The relative u, v coordinates indicate where inside of this gadget (note that v is typically negative). When id is set to integrate, the message is broadcast to all and indicates that the frame owning the focus (caret) should consume the list of objects.

16. The Broadcast procedure is installed by module Viewers to the default message broadcasting procedure found it that module.


*)

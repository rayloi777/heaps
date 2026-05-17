package hxd;
import hxd.Key in K;
import hxd.impl.MouseMode;

#if (hlsdl && hldx)
#error "You shouldn't use both -lib hlsdl and -lib hldx"
#end

#if hlsdl
typedef DisplayMode = sdl.Window.DisplayMode;
#elseif hldx
typedef DisplayMode = dx.Window.DisplayMode;
#else
enum DisplayMode {
	Windowed;
	Borderless;
	Fullscreen;
}
#end

typedef Monitor = {
	name : String,
	width : Int,
	height : Int
}

typedef DisplaySetting = {
	width : Int,
	height : Int,
	framerate : Int
}

private class NativeDroppedFile extends hxd.DropFileEvent.DroppedFile {
	public function getBytes( callback : ( data : haxe.io.Bytes ) -> Void ) {
		haxe.Timer.delay(() -> callback(sys.io.File.getBytes(file)), 1);
	}
}

//@:coreApi
class Window {

	static var WINDOWS : Array<Window> = [];

	var resizeEvents : List<Void -> Void>;
	var eventTargets : List<Event -> Void>;
	var dropTargets : List<DropFileEvent -> Void>;
	var dropFiles : Array<hxd.DropFileEvent.DroppedFile>;

	public var id : Int;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var mouseX(get, never) : Int;
	public var mouseY(get, never) : Int;
	@:deprecated("Use mouseMode = AbsoluteUnbound(true)")
	public var mouseLock(get, set) : Bool;
	/**
		If set, will restrain the mouse cursor within the window boundaries.
	**/
	public var mouseClip(get, set) : Bool;
	/**
		Set the mouse movement input handling mode.

		@see `hxd.impl.MouseMode` for more details on each mode.
	**/
	public var mouseMode(default, set): MouseMode = Absolute;
	public var monitor : Null<Int> = null;
	public var framerate : Null<Int> = null;
	public var vsync(get, set) : Bool;
	public var isFocused(get, never) : Bool;

	public var title(get, set) : String;
	public var displayMode(get, set) : DisplayMode;
	#if (hl_ver >= version("1.12.0"))
	public var currentMonitorIndex(get,never) : Int;
	#end

	#if hlsdl
	var window : sdl.Window;
	#elseif hldx
	var window : dx.Window;
	var _mouseClip : Bool;
	#end
	var windowWidth = 800;
	var windowHeight = 600;
	var curMouseX = 0;
	var curMouseY = 0;
	var startMouseX = 0;
	var startMouseY = 0;
	var savedSize : { x : Int, y : Int, width : Int, height : Int };
	var flags : { fixed: Bool, hidden: Bool };

	static var CODEMAP = [for( i in 0...2048 ) i];
	static var MIN_HEIGHT = 720;
	static var MIN_FRAMERATE = 60; // 30 and 60 are always allowed
	#if hlsdl
	static inline var TOUCH_SCALE = #if (hl_ver >= version("1.12.0")) 10000 #else 100 #end;
	#if heaps_vulkan
	public static var USE_VULKAN = false;
	#end
	#end

	public function new(title:String, width:Int, height:Int, ?flags: { ?fixed:Bool, ?hidden:Bool }) {
		this.windowWidth = width;
		this.windowHeight = height;
		eventTargets = new List();
		resizeEvents = new List();
		dropTargets = new List();
		this.flags = flags;
		var fixed = flags != null && flags.fixed != null ? flags.fixed : false;
		var hidden = flags != null && flags.hidden != null ? flags.hidden : false;
		#if hlsdl
		var sdlFlags = 0;
		if (!fixed) sdlFlags |= sdl.Window.SDL_WINDOW_RESIZABLE;
		if (!hidden) sdlFlags |= sdl.Window.SDL_WINDOW_SHOWN;
		#if heaps_vulkan
		if( USE_VULKAN ) sdlFlags |= sdl.Window.SDL_WINDOW_VULKAN;
		#end
		window = new sdl.Window(title, width, height, sdl.Window.SDL_WINDOWPOS_CENTERED, sdl.Window.SDL_WINDOWPOS_CENTERED, sdlFlags);
		this.windowWidth = window.width;
		this.windowHeight = window.height;
		#elseif hldx
		var dxFlags = 0;
		if (!fixed) dxFlags |= dx.Window.RESIZABLE;
		if (hidden) dxFlags |= dx.Window.HIDDEN;
		window = new dx.Window(title, width, height, dx.Window.CW_USEDEFAULT, dx.Window.CW_USEDEFAULT, dxFlags);
		#end
		WINDOWS.push(this);
		#if multidriver
		id = window.id;
		#end
	}

	public dynamic function onClose() : Bool {
		return true;
	}

	public dynamic function onMove() : Void {
	}

	public dynamic function onMouseModeChange( from : MouseMode, to : MouseMode ) : Null<MouseMode> {
		return null;
	}

	public function close() {
		if( !WINDOWS.remove(this) )
			return;
		#if (multidriver && (hlsdl || hldx))
		window.destroy();
		#end
	}

	public function event( e : hxd.Event ) : Void {
		for( et in eventTargets )
			et(e);
	}

	public function addEventTarget(et : Event -> Void) : Void {
		eventTargets.add(et);
	}

	public function removeEventTarget(et : Event -> Void) : Void {
		for( e in eventTargets )
			if( Reflect.compareMethods(e,et) ) {
				eventTargets.remove(e);
				break;
			}
	}

	public function addResizeEvent( f : Void -> Void ) : Void {
		resizeEvents.push(f);
	}

	public function removeResizeEvent( f : Void -> Void ) : Void {
		for( e in resizeEvents )
			if( Reflect.compareMethods(e,f) ) {
				resizeEvents.remove(f);
				break;
			}
	}

	function onResize(e:Dynamic) : Void {
		for( r in resizeEvents )
			r();
	}

	public function resize( width : Int, height : Int ) : Void {
		#if (hldx || hlsdl)
		if( window.displayMode == Fullscreen ) {
			#if (hlsdl && hl_ver >= version("1.12.0") )
			var cds = getCurrentDisplaySetting();
			var mode = getBestDisplayMode(width, height, framerate != null ? framerate : cds.framerate);
			if(mode != null) {
				@:privateAccess sdl.Window.winSetDisplayMode(window.win, mode.mode.width, mode.mode.height, mode.mode.framerate);
				width = mode.mode.width;
				height = mode.mode.height;
			}
			#end
		}
		window.resize(width, height);
		#end
		windowWidth = width;
		windowHeight = height;
		for( f in resizeEvents ) f();
	}

	public function addDragAndDropTarget( f : ( event : DropFileEvent ) -> Void ) : Void {
		if (dropTargets.length == 0) {
			#if (hlsdl >= version("1.14.0"))
			sdl.Sdl.setDragAndDropEnabled(true);
			#elseif (hldx >= version("1.14.0"))
			window.dragAndDropEnabled = true;
			#end
		}
		dropTargets.push(f);
	}

	public function removeDragAndDropTarget( f : ( event : DropFileEvent ) -> Void ) : Void {
		for( e in dropTargets )
			if( Reflect.compareMethods(e, f) ) {
				dropTargets.remove(f);
				break;
			}
		if ( dropTargets.length == 0 ) {
			#if (hlsdl >= version("1.14.0"))
			sdl.Sdl.setDragAndDropEnabled(false);
			#elseif (hldx >= version("1.14.0"))
			window.dragAndDropEnabled = false;
			#end
		}
	}

	public function setCursorPos( x : Int, y : Int, emitEvent : Bool = false ) : Void {
		#if hldx
		if (mouseMode == Absolute) window.setCursorPosition(x, y);
		#elseif hlsdl
		if (mouseMode == Absolute) window.warpMouse(x, y);
		#else
		throw "Not implemented";
		#end
		curMouseX = x;
		curMouseY = y;
		if (emitEvent) event(new hxd.Event(EMove, x, y));
	}

	public function captureMouseEvents(enable: Bool) : Void {
		#if (hldx >= version("1.16.0") || hlsdl >= version("1.16.0"))
		window.captureMouseEvents(enable);
		#end
	}

	@:deprecated("Use the displayMode property instead")
	public function setFullScreen( v : Bool ) : Void {
		#if (hldx || hlsdl)
		window.displayMode = v ? Borderless : Windowed;
		#end
	}

	function get_mouseX() : Int {
		return curMouseX;
	}

	function get_mouseY() : Int {
		return curMouseY;
	}

	function get_width() : Int {
		return windowWidth;
	}

	function get_height() : Int {
		return windowHeight;
	}

	function get_mouseLock() : Bool {
		return switch (mouseMode) { case AbsoluteUnbound(_): true; default: false; };
	}

	function set_mouseLock(v:Bool) : Bool {
		return set_mouseMode(v ? AbsoluteUnbound(true) : Absolute).equals(AbsoluteUnbound(true));
	}

	function get_mouseClip() : Bool {
		#if hldx
		return _mouseClip;
		#elseif hlsdl
		return window.grab;
		#else
		return false;
		#end
	}

	function set_mouseClip( v : Bool ) : Bool {
		#if hldx
		window.clipCursor(v);
		return _mouseClip = v;
		#elseif hlsdl
		return window.grab = v;
		#else
		if( v ) throw "Not implemented";
		return false;
		#end
	}

	function set_mouseMode( v : MouseMode ) : MouseMode {
		if ( v.equals(mouseMode) ) return v;

		var forced = onMouseModeChange(mouseMode, v);
		if (forced != null) v = forced;

		#if hldx
		window.setRelativeMouseMode(v != Absolute);
		return mouseMode = v;
		#elseif hlsdl
		sdl.Sdl.setRelativeMouseMode(v != Absolute);
		#else
		if ( v != Absolute ) throw "Not implemented";
		#end

		if ( v == Absolute ) {
			switch ( mouseMode ) {
				case Relative(_, restorePos) | AbsoluteUnbound(restorePos):
					if ( restorePos ) {
						curMouseX = startMouseX;
						curMouseY = startMouseY;
					} else {
						curMouseX = hxd.Math.iclamp(curMouseX, 0, width);
						curMouseY = hxd.Math.iclamp(curMouseY, 0, height);
					}
					#if hldx
					window.setCursorPosition(curMouseX, curMouseY);
					#elseif hlsdl
					window.warpMouse(curMouseX, curMouseY);
					#end
				default:
			}
		}

		startMouseX = curMouseX;
		startMouseY = curMouseY;

		return mouseMode = v;
	}

	#if usesys

		function get_vsync() : Bool return haxe.System.vsync;

		function set_vsync( b : Bool ) : Bool {
			return haxe.System.vsync = b;
		}

		function get_isFocused() : Bool return true;

		function onEvent( e : Event ) : Bool {
			event(e);
			return true;
		}

		#elseif hlmetal

		static var MAC_KEYMAP = [for( i in 0...128 ) i];

		static function initMacKeys() {
			var k = hxd.Key;
			inline function addKey(mac, keyCode) {
				if( mac < 128 ) MAC_KEYMAP[mac] = keyCode;
			}
			// Letters (macOS virtual key codes -> hxd.Key ASCII codes)
			addKey(0x00, k.A); addKey(0x01, k.S); addKey(0x02, k.D); addKey(0x03, k.F);
			addKey(0x04, k.H); addKey(0x05, k.G); addKey(0x06, k.Z); addKey(0x07, k.X);
			addKey(0x08, k.C); addKey(0x09, k.V); addKey(0x0B, k.B); addKey(0x0C, k.Q);
			addKey(0x0D, k.W); addKey(0x0E, k.E); addKey(0x0F, k.R); addKey(0x10, k.Y);
			addKey(0x11, k.T); addKey(0x1F, k.O); addKey(0x20, k.U); addKey(0x22, k.I);
			addKey(0x23, k.P); addKey(0x25, k.L); addKey(0x26, k.J); addKey(0x28, k.K);
			addKey(0x2D, k.N); addKey(0x2E, k.M);
			// Number row
			addKey(0x12, k.NUMBER_1); addKey(0x13, k.NUMBER_2); addKey(0x14, k.NUMBER_3);
			addKey(0x15, k.NUMBER_4); addKey(0x17, k.NUMBER_5); addKey(0x16, k.NUMBER_6);
			addKey(0x1A, k.NUMBER_7); addKey(0x1C, k.NUMBER_8); addKey(0x19, k.NUMBER_9);
			addKey(0x1D, k.NUMBER_0);
			// Special keys
			addKey(0x24, k.ENTER);     // kVK_Return
			addKey(0x30, k.TAB);       // kVK_Tab
			addKey(0x31, k.SPACE);     // kVK_Space
			addKey(0x33, k.BACKSPACE); // kVK_Delete (backspace)
			addKey(0x35, k.ESCAPE);    // kVK_Escape
			addKey(0x75, k.DELETE);    // kVK_ForwardDelete
			// Modifiers
			addKey(0x38, k.LSHIFT);    // kVK_Shift
			addKey(0x3C, k.RSHIFT);    // kVK_RightShift
			addKey(0x3B, k.LCTRL);     // kVK_Control
			addKey(0x3E, k.RCTRL);     // kVK_RightControl
			addKey(0x3A, k.LALT);      // kVK_Option
			addKey(0x3D, k.RALT);      // kVK_RightOption
			addKey(0x37, k.LEFT_WINDOW_KEY);  // kVK_Command
			addKey(0x36, k.RIGHT_WINDOW_KEY); // kVK_RightCommand
			// Navigation
			addKey(0x7E, k.UP);    // kVK_UpArrow
			addKey(0x7D, k.DOWN);  // kVK_DownArrow
			addKey(0x7B, k.LEFT);  // kVK_LeftArrow
			addKey(0x7C, k.RIGHT); // kVK_RightArrow
			addKey(0x73, k.HOME);  // kVK_Home
			addKey(0x77, k.END);   // kVK_End
			addKey(0x74, k.PGUP);  // kVK_PageUp
			addKey(0x79, k.PGDOWN);// kVK_PageDown
			// F keys
			addKey(0x7A, k.F1);  addKey(0x78, k.F2);  addKey(0x63, k.F3);  addKey(0x76, k.F4);
			addKey(0x60, k.F5);  addKey(0x61, k.F6);  addKey(0x62, k.F7);  addKey(0x64, k.F8);
			addKey(0x65, k.F9);  addKey(0x6D, k.F10); addKey(0x67, k.F11); addKey(0x6F, k.F12);
			// Numpad
			addKey(0x52, k.NUMPAD_0); addKey(0x53, k.NUMPAD_1); addKey(0x54, k.NUMPAD_2);
			addKey(0x55, k.NUMPAD_3); addKey(0x56, k.NUMPAD_4); addKey(0x57, k.NUMPAD_5);
			addKey(0x58, k.NUMPAD_6); addKey(0x59, k.NUMPAD_7); addKey(0x5B, k.NUMPAD_8);
			addKey(0x5C, k.NUMPAD_9);
			addKey(0x4B, k.NUMPAD_DIV);   // kVK_ANSI_KeypadDivide
			addKey(0x43, k.NUMPAD_MULT);  // kVK_ANSI_KeypadMultiply
			addKey(0x4E, k.NUMPAD_SUB);   // kVK_ANSI_KeypadMinus
			addKey(0x45, k.NUMPAD_ADD);   // kVK_ANSI_KeypadPlus
			addKey(0x4C, k.NUMPAD_ENTER); // kVK_ANSI_KeypadEnter
			addKey(0x41, k.NUMPAD_DOT);   // kVK_ANSI_KeypadDecimal
			// Punctuation
			addKey(0x18, k.QWERTY_EQUALS);        // kVK_ANSI_Equal
			addKey(0x1B, k.QWERTY_MINUS);         // kVK_ANSI_Minus
			addKey(0x21, k.QWERTY_BRACKET_LEFT);  // kVK_ANSI_LeftBracket
			addKey(0x1E, k.QWERTY_BRACKET_RIGHT); // kVK_ANSI_RightBracket
			addKey(0x2A, k.QWERTY_BACKSLASH);     // kVK_ANSI_Backslash
			addKey(0x27, k.QWERTY_QUOTE);         // kVK_ANSI_Quote
			addKey(0x2B, k.QWERTY_COMMA);         // kVK_ANSI_Comma
			addKey(0x2F, k.QWERTY_PERIOD);        // kVK_ANSI_Period
			addKey(0x2C, k.QWERTY_SLASH);         // kVK_ANSI_Slash
			addKey(0x29, k.QWERTY_SEMICOLON);     // kVK_ANSI_Semicolon
			addKey(0x0A, k.INTL_BACKSLASH);       // kVK_ISO_Section
			addKey(0x32, k.QWERTY_TILDE);         // kVK_ANSI_Grave
			// Lock / misc
			addKey(0x39, k.CAPS_LOCK);   // kVK_CapsLock
			addKey(0x47, k.NUM_LOCK);    // kVK_ANSI_KeypadClear
			addKey(0x71, k.SCROLL_LOCK); // kVK_F15 (used as ScrollLock)
			addKey(0x6A, k.PAUSE_BREAK); // kVK_F16 (used as Pause/Break)
			addKey(0x6E, k.CONTEXT_MENU);// kVK_ContextualMenu
		}

		function get_vsync() : Bool return true;

		function set_vsync( b : Bool ) : Bool {
			return true;
		}

		function get_isFocused() : Bool return true;

		static function processMetalEvents() : Void {
			var w = inst;
			if( w == null ) return;
			var count = metal.Window.eventCount();
			for( i in 0...count ) {
				var etype = metal.Window.eventType(i);
				var mx = metal.Window.eventMouseX(i);
				var my = metal.Window.eventMouseY(i);
				var btn = metal.Window.eventButton(i);
				var wheel = metal.Window.eventWheel(i);
				var kc = metal.Window.eventKeyCode(i);
				var sc = metal.Window.eventScanCode(i);
				var eh : Event = null;
				switch( etype ) {
				case 5: // Quit
					if( w.onClose() )
						w.close();
				case 8: // MouseDown
					w.curMouseX = mx;
					w.curMouseY = my;
					eh = new Event(EPush, mx, my);
					eh.button = switch( btn ) {
					case 0: 0;
					case 1: 2;
					case 2: 1;
					case x: x;
					}
				case 9: // MouseUp
					w.curMouseX = mx;
					w.curMouseY = my;
					eh = new Event(ERelease, mx, my);
					eh.button = switch( btn ) {
					case 0: 0;
					case 1: 2;
					case 2: 1;
					case x: x;
					}
				case 10: // MouseMove
					w.curMouseX = mx;
					w.curMouseY = my;
					eh = new Event(EMove, mx, my);
				case 11: // MouseWheel
					eh = new Event(EWheel, w.curMouseX, w.curMouseY);
					eh.wheelDelta = -wheel;
				case 12: // KeyDown
					eh = new Event(EKeyDown, w.curMouseX, w.curMouseY);
					eh.keyCode = kc < 128 ? MAC_KEYMAP[kc] : kc;
				case 13: // KeyUp
					eh = new Event(EKeyUp, w.curMouseX, w.curMouseY);
					eh.keyCode = kc < 128 ? MAC_KEYMAP[kc] : kc;
				default:
				}
				if( eh != null ) w.event(eh);
			}
		}

		function onEvent( e : Event ) : Bool {
			event(e);
			return true;
		}

		#elseif (hldx||hlsdl)

	function get_vsync() : Bool return window.vsync;

	function set_vsync( b : Bool ) : Bool {
		window.vsync = b;
		return b;
	}

	function get_isFocused() : Bool return !wasBlurred;

	var wasBlurred : Bool;

	function onEvent( e : #if hldx dx.Event #else sdl.Event #end ) : Bool {
		var eh = null;
		switch( e.type ) {
		case WindowState:
			switch( e.state ) {
			case Resize:
				windowWidth = window.width;
				windowHeight = window.height;
				onResize(null);
			case Focus:
				#if hldx
				// return to exclusive mode
				if( window.displayMode == Fullscreen && wasBlurred ) {
					window.displayMode = Borderless;
					window.displayMode = Fullscreen;
				}
				#end
				wasBlurred = false;
				event(new Event(EFocus));
			case Blur:
				wasBlurred = true;
				event(new Event(EFocusLost));
				#if hldx
				// release all keys
				var ev = new Event(EKeyUp);
				for( i in 0...@:privateAccess hxd.Key.keyPressed.length )
					if( hxd.Key.isDown(i) ) {
						ev.keyCode = i;
						event(ev);
					}
				#end
			case Enter:
				#if hldx
				// Restore cursor
				var cur = @:privateAccess hxd.System.currentNativeCursor;
				@:privateAccess hxd.System.currentNativeCursor = null;
				hxd.System.setNativeCursor(cur);
				#end
				event(new Event(EOver));
			case Leave:
				event(new Event(EOut));
			case Close:
				return onCloseEvent();
			case Move:
				if( onMove != null )
					onMove();
			default:
			}
		case MouseDown if (!hxd.System.getValue(IsTouch)):
			if (mouseMode == Absolute) {
				curMouseX = e.mouseX;
				curMouseY = e.mouseY;
			}
			eh = new Event(EPush, curMouseX, curMouseY);
			// middle button -> 2 / right button -> 1
			eh.button = switch( e.button - 1 ) {
			case 0: 0;
			case 1: 2;
			case 2: 1;
			case x: x;
			}
		case MouseUp if (!hxd.System.getValue(IsTouch)):
			if (mouseMode == Absolute) {
				curMouseX = e.mouseX;
				curMouseY = e.mouseY;
			}
			eh = new Event(ERelease, curMouseX, curMouseY);
			eh.button = switch( e.button - 1 ) {
			case 0: 0;
			case 1: 2;
			case 2: 1;
			case x: x;
			};
		case MouseMove if (!hxd.System.getValue(IsTouch)):
			switch (mouseMode) {
				case Absolute:
					curMouseX = e.mouseX;
					curMouseY = e.mouseY;
					eh = new Event(EMove, e.mouseX, e.mouseY);
				case Relative(callback, _):
					#if (hldx || hlsdl)
					var ev = new Event(EMove, e.mouseXRel, e.mouseYRel);
					#else
					var ev = new Event(EMove, e.mouseX - curMouseX, e.mouseY - curMouseY);
					#end
					callback(ev);
					if (!ev.cancel && ev.propagate) {
						ev.cancel = false;
						ev.propagate = false;
						ev.relX = curMouseX;
						ev.relY = curMouseY;
						eh = ev;
					}
				case AbsoluteUnbound(_):
					#if (hldx || hlsdl)
					curMouseX += e.mouseXRel;
					curMouseY += e.mouseYRel;
					#else
					curMouseX += e.mouseX - curMouseX;
					curMouseY += e.mouseY - curMouseY;
					#end
					eh = new Event(EMove, curMouseX, curMouseY);
			}
		case MouseWheel:
			eh = new Event(EWheel, mouseX, mouseY);
			eh.wheelDelta = -e.wheelDelta;
		#if hlsdl
		case GControllerAdded, GControllerRemoved, GControllerUp, GControllerDown, GControllerAxis:
			@:privateAccess hxd.Pad.onEvent( e );
		case KeyDown:
			eh = new Event(EKeyDown, curMouseX, curMouseY);
			if( e.keyCode & (1 << 30) != 0 ) e.keyCode = (e.keyCode & ((1 << 30) - 1)) + 1000;
			eh.keyCode = CODEMAP[e.keyCode];
			if( eh.keyCode & (K.LOC_LEFT | K.LOC_RIGHT) != 0 ) {
				e.keyCode = eh.keyCode & 0xFF;
				onEvent(e);
			}
		case KeyUp:
			eh = new Event(EKeyUp, curMouseX, curMouseY);
			if( e.keyCode & (1 << 30) != 0 ) e.keyCode = (e.keyCode & ((1 << 30) - 1)) + 1000;
			eh.keyCode = CODEMAP[e.keyCode];
			if( eh.keyCode & (K.LOC_LEFT | K.LOC_RIGHT) != 0 ) {
				e.keyCode = eh.keyCode & 0xFF;
				onEvent(e);
			}
		case TextInput:
			eh = new Event(ETextInput, mouseX, mouseY);
			var c = e.keyCode & 0xFF;
			eh.charCode = if( c < 0x7F )
				c;
			else if( c < 0xE0 )
				((c & 0x3F) << 6) | ((e.keyCode >> 8) & 0x7F);
			else if( c < 0xF0 )
				((c & 0x1F) << 12) | (((e.keyCode >> 8) & 0x7F) << 6) | ((e.keyCode >> 16) & 0x7F);
			else
				((c & 0x0F) << 18) | (((e.keyCode >> 8) & 0x7F) << 12) | (((e.keyCode >> 16) & 0x7F) << 6) | ((e.keyCode >> 24) & 0x7F);
		case TouchDown if (hxd.System.getValue(IsTouch)):
			#if hlsdl
				e.mouseX = Std.int(windowWidth * e.mouseX / TOUCH_SCALE);
				e.mouseY = Std.int(windowHeight * e.mouseY / TOUCH_SCALE);
			#end
			eh = new Event(EPush, e.mouseX, e.mouseY);
			eh.touchId = e.fingerId;
		case TouchMove if (hxd.System.getValue(IsTouch)):
			#if hlsdl
				e.mouseX = Std.int(windowWidth * e.mouseX / TOUCH_SCALE);
				e.mouseY = Std.int(windowHeight * e.mouseY / TOUCH_SCALE);
			#end
			eh = new Event(EMove, e.mouseX, e.mouseY);
			eh.touchId = e.fingerId;
		case TouchUp if (hxd.System.getValue(IsTouch)):
			#if hlsdl
				e.mouseX = Std.int(windowWidth * e.mouseX / TOUCH_SCALE);
				e.mouseY = Std.int(windowHeight * e.mouseY / TOUCH_SCALE);
			#end
			eh = new Event(ERelease, e.mouseX, e.mouseY);
			eh.touchId = e.fingerId;

		#elseif hldx
		case KeyDown:
			eh = new Event(EKeyDown, curMouseX, curMouseY);
			eh.keyCode = e.keyCode;
			if( eh.keyCode & (K.LOC_LEFT | K.LOC_RIGHT) != 0 ) {
				e.keyCode = eh.keyCode & 0xFF;
				onEvent(e);
			}
		case KeyUp:
			eh = new Event(EKeyUp, curMouseX, curMouseY);
			eh.keyCode = CODEMAP[e.keyCode];
			if( eh.keyCode & (K.LOC_LEFT | K.LOC_RIGHT) != 0 ) {
				e.keyCode = eh.keyCode & 0xFF;
				onEvent(e);
			}
		case TextInput:
			eh = new Event(ETextInput, mouseX, mouseY);
			eh.charCode = e.keyCode;
		#end
		#if (hlsdl >= version("1.14.0") || hldx >= version("1.14.0"))
		case DropStart:
			dropFiles = [];
		case DropFile:
			#if hlsdl
			dropFiles.push(new NativeDroppedFile(@:privateAccess String.fromUTF8(e.dropFile)));
			#else
			dropFiles.push(new NativeDroppedFile(@:privateAccess String.fromUCS2(e.dropFile)));
			#end
		case DropEnd:
			var event = new DropFileEvent(
				dropFiles,
				#if hldx
				e.mouseX, e.mouseY
				#else
				mouseX, mouseY
				#end
			);
			for ( dt in dropTargets ) dt(event);
			dropFiles = null;
		#end
		#if (hlsdl >= version("1.16.0") || hldx >= version("1.16.0"))
		case KeyMapChanged:
			hxd.System.onKeyboardLayoutChange();
		#end
		#if !hlsdl // hlsdl post both Close+Quit
		case Quit:
			return onCloseEvent();
		#end
		default:
		}
		if( eh != null ) event(eh);
		return true;
	}

	function onCloseEvent() {
		var ret = onClose();
		if( ret )
			close();
		return ret;
	}

	static function initChars() : Void {

		inline function addKey(sdl, keyCode) {
			CODEMAP[sdl] = keyCode;
		}

		// ASCII
		for( i in 0...26 )
			addKey(97 + i, K.A + i);
		for( i in 0...12 )
			addKey(1058 + i, K.F1 + i);
		for( i in 0...12 )
			addKey(1104 + i, K.F13 + i);

		// NUMPAD
		addKey(1084, K.NUMPAD_DIV);
		addKey(1085, K.NUMPAD_MULT);
		addKey(1086, K.NUMPAD_SUB);
		addKey(1087, K.NUMPAD_ADD);
		addKey(1088, K.NUMPAD_ENTER);
		for( i in 0...9 )
			addKey(1089 + i, K.NUMPAD_1 + i);
		addKey(1098, K.NUMPAD_0);
		addKey(1099, K.NUMPAD_DOT);

		// EXTRA
		var keys = [
			//K.BACKSPACE
			//K.TAB
			//K.ENTER
			1225 => K.LSHIFT,
			1229 => K.RSHIFT,
			1224 => K.LCTRL,
			1228 => K.RCTRL,
			1226 => K.LALT,
			1230 => K.RALT,
			1227 => K.LEFT_WINDOW_KEY,
			1231 => K.RIGHT_WINDOW_KEY,
			// K.ESCAPE
			// K.SPACE
			1075 => K.PGUP,
			1078 => K.PGDOWN,
			1077 => K.END,
			1074 => K.HOME,
			1080 => K.LEFT,
			1082 => K.UP,
			1079 => K.RIGHT,
			1081 => K.DOWN,
			1073 => K.INSERT,
			127 => K.DELETE,
			//K.NUMPAD_0-9
			//K.A-Z
			//K.F1-F12
			1085 => K.NUMPAD_MULT,
			1087 => K.NUMPAD_ADD,
			1088 => K.NUMPAD_ENTER,
			1086 => K.NUMPAD_SUB,
			1099 => K.NUMPAD_DOT,
			1084 => K.NUMPAD_DIV,

			39 => K.QWERTY_QUOTE,
			44 => K.QWERTY_COMMA,
			45 => K.QWERTY_MINUS,
			46 => K.QWERTY_PERIOD,
			47 => K.QWERTY_SLASH,
			59 => K.QWERTY_SEMICOLON,
			61 => K.QWERTY_EQUALS,
			91 => K.QWERTY_BRACKET_LEFT,
			92 => K.QWERTY_BACKSLASH,
			93 => K.QWERTY_BRACKET_RIGHT,
			96 => K.QWERTY_TILDE,
			167 => K.QWERTY_BACKSLASH,

			// AZERTY
			41 => K.QWERTY_BRACKET_LEFT, // degree
			94 => K.QWERTY_BRACKET_RIGHT, // caret
			249 => K.QWERTY_TILDE, // percent
			58 => K.QWERTY_SLASH, // slash
			33 => K.AZERTY_EXCLAM,
			36 => K.QWERTY_SEMICOLON, // dollar

			1101 => K.CONTEXT_MENU,
			1057 => K.CAPS_LOCK,
			1071 => K.SCROLL_LOCK,
			1072 => K.PAUSE_BREAK,
			1083 => K.NUM_LOCK,
			// LowerThan on AZERTY, none on QWERTY because hlsdl uses sym code, instead of scancode - INTL_BACKSLASH always reports 0x5C, e.g. regular slash.
			60 => K.INTL_BACKSLASH,

			//1070 => K.PRINT_SCREEN
		];
		for( sdl in keys.keys() )
			addKey(sdl, keys.get(sdl));
	}

	#else

	function get_vsync() : Bool return true;

	function set_vsync( b : Bool ) : Bool {
		return true;
	}

	function get_isFocused() : Bool return false;

	function onEvent( e : Event ) : Bool {
		event(e);
		return true;
	}

	#end

	function get_displayMode() : DisplayMode {
		#if (hldx || hlsdl)
		return window.displayMode;
		#end
		return Windowed;
	}

	function set_displayMode( m : DisplayMode ) : DisplayMode {
		#if (hldx || hlsdl)
		var oldMode = window.displayMode;
		#if (hl_ver >= version("1.12.0"))
		var oldMode = window.displayMode;
		if( window.displayMode != m ) {
			if(window.displayMode == Windowed) {
				if( savedSize == null ) {
					savedSize = { x: window.x, y: window.y, width: window.width, height: window.height };
				}
			}
		}

		if(flags != null && flags.hidden)
			return displayMode;

		// No way to choose the screen in SDL, need to fit the window in the right screen before.
		if(m != Windowed) {
			window.displayMode = Windowed;
			var mon = selectedMonitor();
			if(mon != null) {
				window.setPosition(mon.left, mon.top);
				window.resize(mon.right-mon.left, mon.bottom-mon.top);
			}
		}
		if( m == Fullscreen ) {
			var cds = getCurrentDisplaySetting();
			var dm = getBestDisplayMode(windowWidth, windowHeight, framerate != null ? framerate : cds.framerate);
			if(dm == null)
				return oldMode;
			window.displaySetting = dm.mode;
			#if hldx
			var mon = selectedMonitor();
			window.selectedMonitor = mon != null ? mon.name : null;
			#end
			window.displayMode = m;
			window.resize(dm.mode.width, dm.mode.height);
		}
		else {
			window.displayMode = m;
			if( oldMode != m && m == Windowed && savedSize != null) {
				window.setPosition(savedSize.x, savedSize.y);
				window.resize(savedSize.width, savedSize.height);
				savedSize = null;
			}
		}
		#else
		window.displayMode = m;
		#end
		#end
		return displayMode;
	}

	public function applyDisplay() {
		displayMode = displayMode;
	}

	public function setIcon(icon: hxd.BitmapData) : Void {
		#if (hlsdl >= version("1.16.0") || hldx >= version("1.16.0"))
		var pixels = icon.getPixels();
		pixels.convert(BGRA);
		#if hlsdl
		var surf = sdl.Surface.fromBGRA(pixels.bytes, pixels.width, pixels.height);
		window.setIcon(surf);
		surf.free();
		#elseif hldx
		window.setIcon(pixels.width, pixels.height, pixels.bytes);
		#end
		pixels.dispose();
		#end
	}

	#if (hl_ver >= version("1.12.0"))
	public static function getMonitors() : Array<Monitor> {
		return [for(m in #if hldx dx.Window.getMonitors() #elseif hlsdl sdl.Sdl.getDisplays() #else [] #end) { name: m.name, width: m.right-m.left, height: m.bottom-m.top}];
	}

	// If registry is set, return the default DisplaySetting when it's currently modified by the application.
	public function getCurrentDisplaySetting(?monitorId : Int, registry : Bool = false) : DisplaySetting {
		#if hldx
		var mon = monitorId != null ? getMonitors()[monitorId] : null;
		return dx.Window.getCurrentDisplaySetting(mon == null ? null : mon.name, registry);
		#elseif hlsdl
		return sdl.Sdl.getCurrentDisplayMode(monitorId == null ? 0 : monitorId, true);
		#else
		return null;
		#end
	}

	public function getDisplaySettings(?monitorId : Int) : Array<DisplaySetting> {
		var map = new Map<String,DisplaySetting>();
		var f = [];
		if(monitorId == null)
			monitorId = monitor;
		#if hldx
		var m = dx.Window.getMonitors()[monitorId];
		var l = m != null ? dx.Window.getDisplaySettings(m.name) : [];
		#elseif hlsdl
		var l = sdl.Sdl.getDisplayModes( monitorId == null ? window.currentMonitor : monitorId );
		#else
		var l = [];
		#end
		for(d in l) {
			if(d.height >= MIN_HEIGHT && (d.framerate >= MIN_FRAMERATE || d.framerate == 30 || d.framerate == 60)) {
				f.push(d);
			}
		}
		if(f.length > 0)
			return f;
		else
			return l;
	}

	function selectedMonitor() : Dynamic {
		var m = if(monitor == null) currentMonitorIndex else monitor;
		#if hldx
		return dx.Window.getMonitors()[m];
		#elseif hlsdl
		return sdl.Sdl.getDisplays()[m];
		#else
		return null;
		#end
	}

	function getBestDisplayMode(width, height, framerate) {
		var m : {idx: Int, mode: DisplaySetting } = {
			idx: -1,
			mode: null
		}
		var defaultId = -1;
		var def = getCurrentDisplaySetting(currentMonitorIndex, true);
		for( i => s in getDisplaySettings(currentMonitorIndex) ) {
			if(s.width == def.width && s.height == def.height && s.framerate == def.framerate)
				defaultId = i;
			if(s.width == width && s.height == height) {
				if(s.framerate == framerate)
					return { idx: i, mode: s };
				else if(s.framerate == def.framerate)
					m = {idx : i, mode : s };
				else if(m.idx == -1)
					m = {idx: i, mode : s };
			}
		}
		return m.idx == -1 ? { idx: defaultId, mode: def } : m;
	}

	function get_currentMonitorIndex() : Int {
		#if hldx
		var current = window.getCurrentMonitor();
		for(i => m in getMonitors()) {
			if(m.name == current)
				return i;
		}
		return 0;
		#elseif hlsdl
		return window.currentMonitor;
		#else
		return 0;
		#end
	}

	#end
	function get_title() : String {
		#if (hldx || hlsdl)
		return window.title;
		#end
		return "";
	}
	function set_title( t : String ) : String {
		#if (hldx || hlsdl)
		return window.title = t;
		#end
		return "";
	}

	public function setCurrent() {
		inst = this;
		#if hlsdl
		window.renderTo();
		#end
	}

	static var inst : Window = null;
	public static function getInstance() : Window {
		return inst;
	}

	public static function hasWindow() {
		return WINDOWS.length > 0;
	}

	static function dispatchEvent( e ) {
		#if multidriver
		if( false ) @:privateAccess WINDOWS[0].onEvent(e); // typing
		for( w in WINDOWS )
			if( e.windowId == w.id )
				return w.onEvent(e);
		return true;
		#else
		return inst.onEvent(e);
		#end
	}

}

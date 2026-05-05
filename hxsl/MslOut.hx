package hxsl;
using hxsl.Ast;
import hxsl.HlslOut.Samplers;

class MslOut {

	static var KWD_LIST = [
		"auto", "break", "case", "char", "const", "continue", "default", "do",
		"double", "else", "enum", "extern", "float", "for", "goto", "if",
		"inline", "int", "long", "register", "return", "short", "signed",
		"sizeof", "static", "struct", "switch", "typedef", "union",
		"unsigned", "void", "volatile", "while",
		// C++ keywords
		"bool", "class", "constexpr", "decltype", "delete", "dynamic_cast",
		"explicit", "false", "friend", "inline", "mutable", "namespace",
		"new", "noexcept", "nullptr", "operator", "private", "protected",
		"public", "reinterpret_cast", "static_assert", "static_cast",
		"template", "this", "thread_local", "throw", "true", "try",
		"typeid", "typename", "using", "virtual",
		// Metal keywords
		"atomic", "attribute", "bool2", "bool3", "bool4",
		"catch", "char2", "char3", "char4",
		"constant", "device", "half", "half2", "half3", "half4",
		"kernel", "main0", "metal", "packed", "ray_data", "rayhit_data",
		"short2", "short3", "short4", "texture", "thread", "uchar", "uchar2",
		"uchar3", "uchar4", "uint", "uint2", "uint3", "uint4",
		"ushort", "ushort2", "ushort3", "ushort4",
		"vertex", "fragment",
		// MSL built-in types / functions
		"float2", "float3", "float4",
		"float2x2", "float3x3", "float4x4",
		"half2x2", "half3x3", "half4x4",
		"int2", "int3", "int4",
		"sampler", "sampler2d", "texture2d", "texture3d", "texturecube",
		"depth2d", "array2d",
		"access", "sample", "read", "write",
		// hxsl output names
		"_in", "_out", "s_input", "s_output", "mul", "matrix", "vector",
		"sample"
	];
	static var KWDS = [for( k in KWD_LIST ) k => true];
	static var GLOBALS = {
		var m = new Map();
		for( g in hxsl.Ast.TGlobal.createAll() ) {
			var n = "" + g;
			n = n.charAt(0).toLowerCase() + n.substr(1);
			m.set(g, n);
		}
		// Type conversions - Metal uses explicit constructors
		m.set(ToInt, "int");
		m.set(ToFloat, "float");
		m.set(ToBool, "bool");
		// Vector constructors - Metal uses float2/3/4 like HLSL
		m.set(Vec2, "float2");
		m.set(Vec3, "float3");
		m.set(Vec4, "float4");
		m.set(IVec2, "int2");
		m.set(IVec3, "int3");
		m.set(IVec4, "int4");
		m.set(BVec2, "bool2");
		m.set(BVec3, "bool3");
		m.set(BVec4, "bool4");
		// Matrix constructors - Metal uses floatNxM like HLSL
		m.set(Mat2, "float2x2");
		m.set(Mat3, "float3x3");
		m.set(Mat4, "mat4");
		m.set(Mat3x4, "mat3x4");
		// Functions with different names in Metal
		m.set(LReflect, "reflect");
		m.set(Fract, "fract"); // Metal uses fract (same as GLSL), not frac (HLSL)
		m.set(Mix, "mix"); // Metal uses mix (same as GLSL), not lerp (HLSL)
		m.set(Inversesqrt, "rsqrt"); // Metal uses rsqrt like HLSL
		m.set(Step, "step");
		m.set(Smoothstep, "smoothstep");
		m.set(Saturate, "saturate"); // Metal has saturate built-in
		m.set(Transpose, "transpose");
		m.set(RoundEven, "rint"); // Metal uses rint for round-to-even
		// Bit casting
		m.set(FloatBitsToInt, "as_type<int>");
		m.set(FloatBitsToUint, "as_type<uint>");
		m.set(IntBitsToFloat, "as_type<float>");
		m.set(UintBitsToFloat, "as_type<float>");
		// Derivatives - Metal uses dfdx/dfdy
		m.set(DFdx, "dfdx");
		m.set(DFdy, "dfdy");
		m.set(Fwidth, "fwidth");
		// Compute thread variables - Metal uses thread_position_in_*
		m.set(ComputeVar_GlobalInvocation, "_in.__globalInvocation");
		m.set(ComputeVar_LocalInvocation, "_in.__localInvocation");
		m.set(ComputeVar_WorkGroup, "_in.__workGroup");
		m.set(ComputeVar_LocalInvocationIndex, "_in.__localInvocationIndex");
		// Vertex/instance ID - Metal uses metal::vertex_id etc.
		m.set(VertexID, "_in.__vertexId");
		m.set(InstanceID, "_in.__instanceId");
		// Fragment inputs
		m.set(FragCoord, "_in.__pos");
		m.set(FrontFacing, "_in.__frontFacing");
		m.set(Barycentrics, "_in.__bary");
		// Group memory barrier
		m.set(GroupMemoryBarrier, "threadgroup_barrier(mem_flags::mem_threadgroup)");
		// Texture ops - these need special handling in addExpr
		m.set(Texture, "tex2D");
		m.set(TextureLod, "tex2DLevel");
		m.set(Texel, "tex2DFetch");
		m.set(TexelLod, "tex2DFetchLevel");
		m.set(TextureSize, "textureSize");
		// Pack/unpack
		m.set(Pack, "pack");
		m.set(Unpack, "unpack");
		m.set(PackNormal, "packNormal");
		m.set(UnpackNormal, "unpackNormal");
		// Screen <-> UV
		m.set(ScreenToUv, "screenToUv");
		m.set(UvToScreen, "uvToScreen");
		// Channel ops
		m.set(ChannelRead, "channelRead");
		m.set(ChannelReadLod, "channelReadLod");
		m.set(ChannelFetch, "channelFetch");
		m.set(ChannelTextureSize, "channelTextureSize");
		// Misc
		m.set(Trace, "trace");
		m.set(VertexAt, "vertexAt");
		m.set(InvLerp, "invLerp");
		m.set(ImageStore, "imageStore");
		m.set(AtomicAdd, "atomicAdd");
		m.set(UnpackSnorm4x8, "unpackSnorm4x8");
		m.set(UnpackUnorm4x8, "unpackUnorm4x8");
		m.set(ResolveSampler, "resolveSampler");
		m.set(SetLayout, "setLayout");

		for( g in m )
			KWDS.set(g, true);
		m;
	};

	var buf : StringBuf;
	var decls : Array<String>;
	var exprIds = 0;
	var exprValues : Array<String>;
	var locals : Map<Int,TVar>;
	public var varNames : Map<Int,String>;
	var allNames : Map<String,Int>;
	var samplers : Map<Int,Array<Int>>;
	var isVertex : Bool;
	var isCompute : Bool;
	var computeLayout = [1,1,1];
	var hasBinormal : Bool;
	var varAccess : Map<Int,String>;
	var kind : FunctionKind;
	var stagePrefix : String;
	var hasGlobals : Bool;
	var hasParams : Bool;
	var inputIndex : Int;
	var paramBuffers : Array<{ v : TVar, index : Int, addrSpace : String }>;
	var paramTextures : Array<{ decl : String, index : Int, varId : Null<Int> }>;
	var paramSamplerCount : Int;
	var vertexParamGlobals : Array<{ g : TGlobal, name : String }>;

	public function new() {
		varNames = new Map();
		allNames = new Map();
	}

	inline function add( v : Dynamic ) {
		buf.add(v);
	}

	inline function addIdent( v : TVar ) {
		add(varName(v, varNames, allNames));
	}

	function decl( s : String ) {
		for( d in decls )
			if( d == s ) return;
		if( s.charCodeAt(0) == '#'.code )
			decls.unshift(s);
		else
			decls.push(s);
	}

	function getTexType( t : Type ) {
		return switch( t ) {
		case TSampler(dim, arr):
			"texture" + dim.getName().substr(1).toLowerCase() + (arr ? "_array" : "") + "<float, access::sample>";
		case TRWTexture(dim, arr, chans):
			"texture" + dim.getName().substr(1).toLowerCase() + (arr ? "_array" : "") + "<float, access::write>";
		default:
			throw "assert";
		}
	}

	function addType( t : Type ) {
		switch( t ) {
		case TVoid:
			add("void");
		case TInt:
			add("int");
		case TBytes(n):
			add("uint" + n);
		case TBool:
			add("bool");
		case TFloat:
			add("float");
		case TString:
			add("string");
		case TVec(size, k):
			switch( k ) {
			case VFloat: add("float");
			case VInt: add("int");
			case VBool: add("bool");
			}
			add(size);
		case TMat2:
			add("float2x2");
		case TMat3:
			add("float3x3");
		case TMat4:
			add("float4x4");
		case TMat3x4:
			add("float4x3");
		case TSampler(_), TRWTexture(_):
			add(getTexType(t));
		case TStruct(vl):
			add("struct { ");
			for( v in vl ) {
				addVar(v);
				add(";");
			}
			add(" }");
		case TFun(_):
			add("function");
		case TArray(t, size), TBuffer(t, size, _):
			switch( t ) {
			case TBuffer(_, _, Storage | StoragePartial):
				add("device ");
				addType(t);
				add("*");
			case TBuffer(_, _, RW | RWPartial):
				add("device ");
				addType(t);
				add("*");
			default:
				addType(t);
			}
			addArraySize(size);
		case TChannel(n):
			add("channel" + n);
		case TTextureHandle:
			add("uint2");
		}
	}

	function addArraySize( size : SizeDecl ) {
		add("[");
		switch( size ) {
		case SVar(v): addIdent(v);
		case SConst(0):
		case SConst(n): add(n);
		}
		add("]");
	}

	function addVar( v : TVar ) {
		switch( v.type ) {
		case TArray(t, size), TBuffer(t, size, Uniform | Partial):
			addVar({
				id : v.id,
				name : v.name,
				type : t,
				kind : v.kind,
			});
			addArraySize(size);
		case TBuffer(t, size, Storage | StoragePartial):
			add("device ");
			addType(t);
			add("* ");
			addIdent(v);
		case TBuffer(t, size, RW | RWPartial):
			add("device ");
			addType(t);
			add("* ");
			addIdent(v);
		default:
			if( v.type == TBool && v.kind == Param && !Tools.isConst(v) )
				add("float");
			else
				addType(v.type);
			add(" ");
			addIdent(v);
		}
	}

	function declMods() {
		// unsigned mod like GLSL
		decl("float mod(float x, float y) { return x - y * floor(x/y); }");
		decl("float2 mod(float2 x, float2 y) { return x - y * floor(x/y); }");
		decl("float3 mod(float3 x, float3 y) { return x - y * floor(x/y); }");
		decl("float4 mod(float4 x, float4 y) { return x - y * floor(x/y); }");
	}

	function declGlobal( g : TGlobal, args : Array<TExpr> ) {
		switch( g ) {
		case Mat3x4:
			decl("float4x3 mat3x4( float4 a, float4 b, float4 c ) { return float4x3(float3(a.x, b.x, c.x), float3(a.y, b.y, c.y), float3(a.z, b.z, c.z), float3(a.w, b.w, c.w)); }");
			decl("float4x3 mat3x4( float4x4 m ) { return float4x3(float3(m[0].x, m[1].x, m[2].x), float3(m[0].y, m[1].y, m[2].y), float3(m[0].z, m[1].z, m[2].z), float3(m[0].w, m[1].w, m[2].w)); }");
		case Mat4:
			decl("float4x4 mat4( float4 a, float4 b, float4 c, float4 d ) { return float4x4(float4(a.x, b.x, c.x, d.x), float4(a.y, b.y, c.y, d.y), float4(a.z, b.z, c.z, d.z), float4(a.w, b.w, c.w, d.w)); }");
		case Mat3:
			decl("float3x3 mat3( float4x4 m ) { return float3x3(m[0].xyz, m[1].xyz, m[2].xyz); }");
			decl("float3x3 mat3( float4x3 m ) { return float3x3(float3(m[0].x,m[1].x,m[2].x), float3(m[0].y,m[1].y,m[2].y), float3(m[0].z,m[1].z,m[2].z)); }");
			decl("float3x3 mat3( float3 a, float3 b, float3 c ) { return float3x3(a,b,c); }");
			decl("float3x3 mat3( float c00, float c01, float c02, float c10, float c11, float c12, float c20, float c21, float c22 ) { return float3x3(c00,c10,c20,c01,c11,c21,c02,c12,c22); }");
		case Mat2:
			decl("float2x2 mat2( float4x4 m ) { return float2x2(m[0].xy, m[1].xy); }");
			decl("float2x2 mat2( float3x3 m ) { return float2x2(m[0].xy, m[1].xy); }");
			decl("float2x2 mat2( float4x3 m ) { return float2x2(float2(m[0].x,m[1].x), float2(m[0].y,m[1].y)); }");
			decl("float2x2 mat2( float2 a, float2 b ) { return float2x2(a,b); }");
			decl("float2x2 mat2( float c00, float c01, float c10, float c11 ) { return float2x2(c00,c10,c01,c11); }");
		case Mod:
			declMods();
		case Pack:
			decl("float4 pack( float v ) { float4 color = fract(v * float4(1, 255, 255.*255., 255.*255.*255.)); return color - color.yzww * float4(1. / 255., 1. / 255., 1. / 255., 0.); }");
		case Unpack:
			decl("float unpack( float4 color ) { return dot(color,float4(1., 1. / 255., 1. / (255. * 255.), 1. / (255. * 255. * 255.))); }");
		case PackNormal:
			decl("float4 packNormal( float3 n ) { return float4((n + 1.) * 0.5,1.); }");
		case UnpackNormal:
			decl("float3 unpackNormal( float4 p ) { return normalize(p.xyz * 2. - 1.); }");
		case Atan:
			// Metal already has atan2 built-in
		case ScreenToUv:
			decl("float2 screenToUv( float2 v ) { return v * float2(0.5, -0.5) + float2(0.5,0.5); }");
		case UvToScreen:
			decl("float2 uvToScreen( float2 v ) { return v * float2(2.,-2.) + float2(-1., 1.); }");
		case TextureSize:
			var tt = args[0].t;
			var tstr = getTexType(tt);
			switch( tt ) {
			case TSampler(dim, arr) if( args.length > 1 ):
				var size = Tools.getDimSize(dim, arr);
				switch( size ) {
				case 1:
					decl('float textureSize($tstr tex, int lod) { return float(tex.get_width((uint)lod)); }');
				case 2:
					decl('float2 textureSize($tstr tex, int lod) { return float2(float(tex.get_width((uint)lod)), float(tex.get_height((uint)lod))); }');
				case 3:
					decl('float3 textureSize($tstr tex, int lod) { return float3(float(tex.get_width((uint)lod)), float(tex.get_height((uint)lod)), float(tex.get_depth((uint)lod))); }');
				}
			case TSampler(dim, arr), TRWTexture(dim, arr, _):
				var size = Tools.getDimSize(dim, arr);
				switch( size ) {
				case 1:
					decl('float textureSize($tstr tex) { return float(tex.get_width()); }');
				case 2:
					decl('float2 textureSize($tstr tex) { return float2(float(tex.get_width()), float(tex.get_height())); }');
				case 3:
					decl('float3 textureSize($tstr tex) { return float3(float(tex.get_width()), float(tex.get_height()), float(tex.get_depth())); }');
				}
			default:
				throw "assert";
			}
		case Vec2 if( args.length == 1 && args[0].t == TFloat ):
			decl("float2 vec2( float v ) { return float2(v,v); }");
		case Vec3 if( args.length == 1 && args[0].t == TFloat ):
			decl("float3 vec3( float v ) { return float3(v,v,v); }");
		case Vec4 if( args.length == 1 && args[0].t == TFloat ):
			decl("float4 vec4( float v ) { return float4(v,v,v,v); }");
		case IVec2 if( args.length == 1 && args[0].t.match(TInt | TFloat) ):
			decl("int2 ivec2( int v ) { return int2(v,v); }");
		case IVec3 if( args.length == 1 && args[0].t.match(TInt | TFloat) ):
			decl("int3 ivec3( int v ) { return int3(v,v,v); }");
		case IVec4 if( args.length == 1 && args[0].t.match(TInt | TFloat) ):
			decl("int4 ivec4( int v ) { return int4(v,v,v,v); }");
		case AtomicAdd:
			decl("int atomicAdd( device int* buf, int index, int data ) { return atomic_fetch_add_explicit(&buf[index], data, memory_order_relaxed); }");
		case InvLerp:
			decl("float invLerp(float v, float a, float b) { return saturate((v - a) / (b - a)); }");
		case UnpackSnorm4x8:
			decl("float4 unpackSnorm4x8( int v ) {
				float4 unpack;
				unpack.x = clamp(((as_type<uint>(v) & as_type<uint>(0xff000000)) >> 24) / 127.0, -1.0, 1.0);
				unpack.y = clamp(((as_type<uint>(v) & as_type<uint>(0x00ff0000)) >> 16) / 127.0, -1.0, 1.0);
				unpack.z = clamp(((as_type<uint>(v) & as_type<uint>(0x0000ff00)) >> 8) / 127.0, -1.0, 1.0);
				unpack.w = clamp(((as_type<uint>(v) & as_type<uint>(0x000000ff)) >> 0) / 127.0, -1.0, 1.0);
				return unpack;
			 }");
		case UnpackUnorm4x8:
			decl("float4 unpackUnorm4x8( int v ) {
				float4 unpack;
				unpack.x = ((as_type<uint>(v) & as_type<uint>(0xff000000)) >> 24) / 255.0;
				unpack.y = ((as_type<uint>(v) & as_type<uint>(0x00ff0000)) >> 16) / 255.0;
				unpack.z = ((as_type<uint>(v) & as_type<uint>(0x0000ff00)) >> 8) / 255.0;
				unpack.w = ((as_type<uint>(v) & as_type<uint>(0x000000ff)) >> 0) / 255.0;
				return unpack;
			 }");
		default:
		}
	}

	function addBlock( e : TExpr, tabs : String ) {
		if( e.e.match(TBlock(_)) )
			addExpr(e, tabs);
		else {
			add("{");
			addExpr(e, tabs);
			if( !isBlock(e) )
				add(";");
			add("}");
		}
	}

	function getIdent( v : TVar ) : String {
		var n = varNames.get(v.id);
		if( n != null ) return n;
		n = v.name;
		if( KWDS.get(n) ) n = "_" + n;
		return n;
	}

	function collectFreeVars( e : TExpr, declared : Map<Int,Bool>, free : Map<Int,TVar> ) {
		switch( e.e ) {
		case TConst(_):
		case TVar(v):
			if( !declared.exists(v.id) ) free.set(v.id, v);
		case TGlobal(_):
		case TParenthesis(e2):
			collectFreeVars(e2, declared, free);
		case TBlock(el):
			for( e2 in el ) collectFreeVars(e2, declared, free);
		case TVarDecl(v, init):
			declared.set(v.id, true);
			if( init != null ) {
				switch( init.e ) {
				case TArrayDecl(el):
					for( e2 in el ) collectFreeVars(e2, declared, free);
				default:
					collectFreeVars(init, declared, free);
				}
			}
		case TBinop(_, e1, e2):
			collectFreeVars(e1, declared, free);
			collectFreeVars(e2, declared, free);
		case TUnop(_, e1):
			collectFreeVars(e1, declared, free);
		case TIf(econd, eif, eelse):
			collectFreeVars(econd, declared, free);
			collectFreeVars(eif, declared, free);
			if( eelse != null ) collectFreeVars(eelse, declared, free);
		case TCall(e2, args):
			collectFreeVars(e2, declared, free);
			for( a in args ) collectFreeVars(a, declared, free);
		case TSwiz(e2, _):
			collectFreeVars(e2, declared, free);
		case TSwitch(e2, cases, def):
			collectFreeVars(e2, declared, free);
			for( c in cases ) {
				for( v in c.values ) collectFreeVars(v, declared, free);
				collectFreeVars(c.expr, declared, free);
			}
			if( def != null ) collectFreeVars(def, declared, free);
		case TFor(v, it, loop):
			declared.set(v.id, true);
			collectFreeVars(it, declared, free);
			collectFreeVars(loop, declared, free);
		case TWhile(it, loop, _):
			collectFreeVars(it, declared, free);
			collectFreeVars(loop, declared, free);
		case TReturn(e2):
			if( e2 != null ) collectFreeVars(e2, declared, free);
		case TContinue:
		case TBreak:
		case TDiscard:
		case TArray(e1, e2):
			collectFreeVars(e1, declared, free);
			collectFreeVars(e2, declared, free);
		case TArrayDecl(el):
			for( e2 in el ) collectFreeVars(e2, declared, free);
		case TMeta(_, _, e2):
			collectFreeVars(e2, declared, free);
		case TField(e2, _):
			collectFreeVars(e2, declared, free);
		case TSyntax(_, _, _):
		}
	}

	function addValue( e : TExpr, tabs : String ) {
		switch( e.e ) {
		case TBlock(el):
			var name = "_val" + (exprIds++);
			// Collect free variables from the block (referenced but not declared within)
			var declared = new Map<Int, Bool>();
			var freeVarMap = new Map<Int, TVar>();
			var el2 = el.copy();
			var last = el2[el2.length - 1];
			el2[el2.length - 1] = { e : TReturn(last), t : e.t, p : last.p };
			for( ex in el2 ) collectFreeVars(ex, declared, freeVarMap);
			// Build parameter list, grouping shared resources (__params, __globals, _in)
			var paramDecls = [];
			var callArgs = [];
			var addedShared = new Map<String, Bool>();
			// Helper: add texture params for a variable (handles both direct and TArray textures)
			function addTextureParams(v:TVar) {
				var sams = samplers.get(v.id);
				if( sams == null ) return;
				// Determine the base texture type
				var texType = switch( v.type ) {
				case TArray(t, _): getTexType(t);
				default: getTexType(v.type);
				}
				for( idx in sams ) {
					paramDecls.push(texType + " tex" + idx);
					callArgs.push("tex" + idx);
				}
				// Also pass sampler array if not already added
				if( !addedShared.exists("__Samplers") && paramSamplerCount > 0 ) {
					paramDecls.push("array<sampler," + paramSamplerCount + "> __Samplers");
					callArgs.push("__Samplers");
					addedShared.set("__Samplers", true);
				}
			}
			// Helper: check if a type is or contains textures
			function isTextureType(t:Type) {
				return t.isTexture() || switch(t) { case TArray(st, _): st.isTexture(); default: false; };
			}
			for( vid in freeVarMap.keys() ) {
				var v = freeVarMap.get(vid);
				var acc = varAccess.get(v.id);
				if( acc != null && !isTextureType(v.type) ) {
					if( acc == "__params." && !addedShared.exists("__params") ) {
						paramDecls.push("constant " + stagePrefix + "Params& __params");
						callArgs.push("__params");
						addedShared.set("__params", true);
					} else if( acc == "__globals." && !addedShared.exists("__globals") ) {
						paramDecls.push("constant " + stagePrefix + "Globals& __globals");
						callArgs.push("__globals");
						addedShared.set("__globals", true);
					} else if( acc == "_in." && !addedShared.exists("_in") ) {
						paramDecls.push(stagePrefix + "input _in");
						callArgs.push("_in");
						addedShared.set("_in", true);
					}
				} else if( isTextureType(v.type) ) {
					// Texture variable - look up sampler indices to get texN names
					addTextureParams(v);
				} else {
					// Local variable - pass by value
					var typeBuf = new StringBuf();
					var oldBuf = buf;
					buf = typeBuf;
					addType(v.type);
					buf = oldBuf;
					paramDecls.push(typeBuf.toString() + " " + getIdent(v));
					callArgs.push(getIdent(v));
				}
			}
			// Generate helper function with parameters
			var tmp = buf;
			buf = new StringBuf();
			addType(e.t);
			add(" ");
			add(name);
			add("(");
			add(paramDecls.join(", "));
			add(")");
			var e2 : TExpr = {
				t : TVoid,
				e : TBlock(el2),
				p : e.p,
			};
			addExpr(e2, "");
			exprValues.push(buf.toString());
			buf = tmp;
			// Generate call with arguments
			add(name);
			add("(");
			add(callArgs.join(", "));
			add(")");
		case TIf(econd, eif, eelse):
			add("( ");
			addValue(econd, tabs);
			add(" ) ? ");
			addValue(eif, tabs);
			add(" : ");
			addValue(eelse, tabs);
		case TMeta(_, _, e2):
			addValue(e2, tabs);
		default:
			addExpr(e, tabs);
		}
	}

	function addExpr( e : TExpr, tabs : String ) {
		switch( e.e ) {
		case TConst(c):
			switch( c ) {
			case CInt(v): add(v);
			case CFloat(f):
				var str = "" + f;
				add(str);
				if( str.indexOf(".") == -1 && str.indexOf("e") == -1 )
					add(".");
			case CString(v): add('"' + v + '"');
			case CNull: add("null");
			case CBool(b): add(b);
			}
		case TVar(v):
			var acc = varAccess.get(v.id);
			if( acc != null ) add(acc);
			addIdent(v);
		case TGlobal(g):
			add(GLOBALS.get(g));
		case TParenthesis(e2):
			add("(");
			addValue(e2, tabs);
			add(")");
		case TBlock(el):
			add("{\n");
			var t2 = tabs + "\t";
			for( e2 in el ) {
				add(t2);
				addExpr(e2, t2);
				newLine(e2);
			}
			add(tabs);
			add("}");
		case TVarDecl(v, { e : TArrayDecl(el) }):
			locals.set(v.id, v);
			for( i in 0...el.length ) {
				addIdent(v);
				add("[");
				add(i);
				add("] = ");
				addExpr(el[i], tabs);
				if( i < el.length - 1 ) {
					newLine(el[i]);
					add(tabs);
				}
			}
		case TBinop(OpAssign, evar = { e : TVar(_) }, { e : TArrayDecl(el) }):
			for( i in 0...el.length ) {
				addExpr(evar, tabs);
				add("[");
				add(i);
				add("] = ");
				addExpr(el[i], tabs);
				if( i < el.length - 1 ) {
					newLine(el[i]);
					add(tabs);
				}
			}
		case TArrayDecl(el):
			add("{");
			var first = true;
			for( e2 in el ) {
				if( first ) first = false else add(", ");
				addValue(e2, tabs);
			}
			add("}");
		case TBinop(op, e1, e2):
			switch( [op, e1.t, e2.t] ) {
			case [OpAssignOp(OpMod) | OpMod, _, _]:
				if( op.match(OpAssignOp(_)) ) {
					addValue(e1, tabs);
					add(" = ");
				}
				declMods();
				add("mod(");
				addValue(e1, tabs);
				add(",");
				addValue(e2, tabs);
				add(")");
			case [OpAssignOp(op2), TVec(_), TMat3x4 | TMat3 | TMat4]:
				addValue(e1, tabs);
				add(" = ");
				addValue({ e : TBinop(op2, e1, e2), t : e.t, p : e.p }, tabs);
			case [OpMult, TVec(_), TMat3x4]:
				// vec * mat3x4: extend vec to vec4, multiply, take xyz
				add("(");
				addValue(e2, tabs);
				add(" * float4(");
				addValue(e1, tabs);
				add(",1.)).xyz");
			case [OpMult, TVec(_), TMat2 | TMat3 | TMat4]:
				// Metal column-major: result = matrix * vector
				add("(");
				addValue(e2, tabs);
				add(" * ");
				addValue(e1, tabs);
				add(")");
			case [OpMult, TMat3 | TMat3x4 | TMat4 | TMat2, TMat3 | TMat3x4 | TMat4 | TMat2]:
				add("(");
				addValue(e1, tabs);
				add(" * ");
				addValue(e2, tabs);
				add(")");
			case [OpUShr, _, _]:
				decl("int _ushr( int a, int b) { return (int)(((uint)a) >> b); }");
				add("_ushr(");
				addValue(e1, tabs);
				add(",");
				addValue(e2, tabs);
				add(")");
			case [_, TVec(size, VFloat), TVec(_, VFloat)] if( switch(op) { case OpGt, OpLt, OpGte, OpLte, OpEq, OpNotEq: true; default: false; } ):
				// Metal comparison on float vectors returns bool vector, not float.
				// HLSL returns float vector (0.0/1.0), so convert using select().
				var zero = "float" + size + "(0.)";
				var one = "float" + size + "(1.)";
				add("select(" + zero + ", " + one + ", ");
				addValue(e1, tabs);
				add(" ");
				add(Printer.opStr(op));
				add(" ");
				addValue(e2, tabs);
				add(")");
			case [_, TVec(size, VInt), TVec(_, VInt)] if( switch(op) { case OpGt, OpLt, OpGte, OpLte, OpEq, OpNotEq: true; default: false; } ):
				var zero = "int" + size + "(0)";
				var one = "int" + size + "(1)";
				add("select(" + zero + ", " + one + ", ");
				addValue(e1, tabs);
				add(" ");
				add(Printer.opStr(op));
				add(" ");
				addValue(e2, tabs);
				add(")");
			default:
				addValue(e1, tabs);
				add(" ");
				add(Printer.opStr(op));
				add(" ");
				addValue(e2, tabs);
			}
		case TUnop(op, e1):
			add(switch(op) {
			case OpNot: "!";
			case OpNeg: "-";
			case OpIncrement: "++";
			case OpDecrement: "--";
			case OpNegBits: "~";
			default: throw "assert";
			});
			addValue(e1, tabs);
		case TVarDecl(v, init):
			locals.set(v.id, v);
			if( init != null ) {
				addVar(v);
				add(" = ");
				addValue(init, tabs);
			} else {
				addVar(v);
			}
		case TCall({ e : TGlobal(SetLayout) }, _):
			// ignore
		case TCall({ e : TGlobal(g = (Texture | TextureLod)) }, args):
			// Metal: tex.sample(sampler, uv) or tex.sample(sampler, uv, level(lod))
			// Determine texture parameter and sampler
			var offset = 0;
			var dynOffset = null;
			var texName = switch( args[0].e ) {
			case TArray(e, { e : TConst(CInt(i)) }): offset = i; e;
			case TArray(e, idx): dynOffset = idx; e;
			default: args[0];
			}

			switch( texName.e ) {
			case TVar(v):
				var sams = samplers.get(v.id);
				if( sams == null ) throw "assert: no sampler for " + v.name;
				// Use texture parameter name (tex0, tex1, etc.) directly
				add("tex" + sams[offset]);
				add(".sample(");
				if( dynOffset != null ) {
					add("__Samplers[");
					add(sams[0]);
					add("+");
					addValue(dynOffset, tabs);
					add("]");
				} else
					add("__Samplers[" + sams[offset] + "]");
			default:
				addValue(args[0], tabs);
				add(".sample(");
				add("__Samplers[0]");
			}
			add(", ");
			addValue(args[1], tabs);
			if( g == TextureLod ) {
				add(", level(");
				addValue(args[2], tabs);
				add(")");
			} else if( isVertex ) {
				// vertex shader: force lod 0
				add(", level(0)");
			}
			// Pass extra arguments (offset, etc.)
			for( i in 2...args.length ) {
				if( g == TextureLod && i == 2 ) continue;
				add(", ");
				addValue(args[i], tabs);
			}
			add(")");
		case TCall({ e : TGlobal(Texel) }, args):
			// Metal: tex.read(coord, lod)
			addValue(args[0], tabs);
			add(".read(");
			switch( args[0].t ) {
			case TSampler(dim, arr):
				var size = Tools.getDimSize(dim, arr) + 1;
				add("int" + size + "(");
			default:
				throw "assert";
			}
			addValue(args[1], tabs);
			add(", 0))");
		case TCall({ e : TGlobal(TexelLod) }, args):
			// Metal: tex.read(coord, lod)
			addValue(args[0], tabs);
			add(".read(");
			switch( args[0].t ) {
			case TSampler(dim, arr):
				var size = Tools.getDimSize(dim, arr) + 1;
				add("int" + size + "(");
			default:
				throw "assert";
			}
			addValue(args[1], tabs);
			add(", ");
			addValue(args[2], tabs);
			add("))");
		case TCall({ e : TGlobal(ImageStore) }, [tex, uv, color]):
			// Metal: tex.write(color, uv)
			addValue(tex, tabs);
			add(".write(");
			addValue(color, tabs);
			add(", ");
			addValue(uv, tabs);
			add(")");
		case TCall({ e : TGlobal(VertexAt) }, [{ e : TVar(v) }, index]):
			add("GetAttributeAtVertex(");
			var acc = varAccess.get(v.id);
			if( acc != null ) add(acc);
			addIdent(v);
			add(", ");
			addValue(index, tabs);
			add(")");
		case TCall({ e : TGlobal(TextureSize) }, args):
			// Need to resolve texture variable from flattened expression
			declGlobal(TextureSize, args);
			var offset = 0;
			var texName = switch( args[0].e ) {
			case TArray(e, { e : TConst(CInt(i)) }): offset = i; e;
			default: args[0];
			}
			add("textureSize(");
			switch( texName.e ) {
			case TVar(v):
				var sams = samplers.get(v.id);
				if( sams != null )
					add("tex" + sams[offset]);
				else
					addIdent(v);
			default:
				addValue(args[0], tabs);
			}
			add(")");
		case TCall(e2 = { e : TGlobal(g) }, args):
			declGlobal(g, args);
			switch( [g, args] ) {
			case [Vec2 | Vec3 | Vec4, [{ t : TFloat }]]:
				add(g.getName().toLowerCase());
			case [IVec2 | IVec3 | IVec4, [{ t : TInt }] | [{ t : TFloat }]]:
				add(g.getName().toLowerCase());
			case [Mat3, [{ t : TMat4 }]]:
				add("mat3");
			case [Mat3, [{ t : TMat3x4 }]]:
				add("mat3");
			case [Mat2, [{ t : TMat4 }]]:
				add("mat2");
			default:
				addValue(e2, tabs);
			}
			add("(");
			var first = true;
			for( a in args ) {
				if( first ) first = false else add(", ");
				addValue(a, tabs);
			}
			add(")");
		case TCall(e2, args):
			addValue(e2, tabs);
			add("(");
			var first = true;
			for( a in args ) {
				if( first ) first = false else add(", ");
				addValue(a, tabs);
			}
			add(")");
		case TSwiz(e2, regs):
			switch( e2.t ) {
			case TFloat, TInt, TBool:
				// HLSL scalar swizzle - Metal doesn't support this
				// Use constructor: scalar.xxxx -> float4(scalar)
				addType(e.t);
				add("(");
				addValue(e2, tabs);
				add(")");
			default:
				addValue(e2, tabs);
				add(".");
				for( r in regs )
					add(switch(r) {
					case X: "x";
					case Y: "y";
					case Z: "z";
					case W: "w";
					});
			}
		case TIf(econd, eif, eelse):
			add("if( ");
			addValue(econd, tabs);
			add(") ");
			addBlock(eif, tabs);
			if( eelse != null ) {
				add(" else ");
				addBlock(eelse, tabs);
			}
		case TDiscard:
			// Metal uses discard_fragment() instead of discard
			add("discard_fragment()");
		case TReturn(e2):
			if( e2 == null ) {
				if( isCompute )
					add("return");
				else
					add("return _out");
			} else {
				add("return ");
				addValue(e2, tabs);
			}
		case TFor(v, it, loop):
			locals.set(v.id, v);
			switch( it.e ) {
			case TBinop(OpInterval, e1, e2):
				add("for(int ");
				add(v.name + "=");
				addValue(e1, tabs);
				add(";" + v.name + "<");
				addValue(e2, tabs);
				add(";" + v.name + "++) ");
				addBlock(loop, tabs);
			default:
				throw "assert";
			}
		case TWhile(e2, loop, false):
			var old = tabs;
			tabs += "\t";
			add("do ");
			addBlock(loop, tabs);
			add(" while( ");
			addValue(e2, tabs);
			add(" )");
		case TWhile(e2, loop, _):
			add("while( ");
			addValue(e2, tabs);
			add(" ) ");
			addBlock(loop, tabs);
		case TSwitch(_):
			add("switch(...)");
		case TContinue:
			add("continue");
		case TBreak:
			add("break");
		case TArray(e2, index):
			switch( e2.t ) {
			case TMat2, TMat3, TMat3x4, TMat4:
				switch( e2.t ) {
				case TMat2:
					decl("float2 _matarr( float2x2 m, int idx ) { return float2(m[0][idx],m[1][idx]); }");
				case TMat3:
					decl("float3 _matarr( float3x3 m, int idx ) { return float3(m[0][idx],m[1][idx],m[2][idx]); }");
				case TMat3x4:
					decl("float4 _matarr( float4x3 m, int idx ) { return float4(m[0][idx],m[1][idx],m[2][idx],m[3][idx]); }");
				case TMat4:
					decl("float4 _matarr( float4x4 m, int idx ) { return float4(m[0][idx],m[1][idx],m[2][idx],m[3][idx]); }");
				default:
				}
				add("_matarr(");
				addValue(e2, tabs);
				add(",");
				addValue(index, tabs);
				add(")");
			default:
				addValue(e2, tabs);
				add("[");
				addValue(index, tabs);
				add("]");
			}
		case TMeta(_, _, e2):
			addExpr(e2, tabs);
		case TField(e2, f):
			switch( e2.t ) {
			case TFloat, TInt, TBool:
				// HLSL scalar swizzle (e.g. scalar.xxxx) - Metal doesn't support this
				// Use constructor instead: scalar.xxxx -> float4(scalar)
				addType(e.t);
				add("(");
				addValue(e2, tabs);
				add(")");
			default:
				addValue(e2, tabs);
				add(".");
				add(f);
			}
		case TSyntax("code" | "msl", code, args):
			var pos = 0;
			var argRegex = ~/{(\d+)}/g;
			while( argRegex.matchSub(code, pos) ) {
				var matchPos = argRegex.matchedPos();
				add(code.substring(pos, matchPos.pos));
				var index = Std.parseInt(argRegex.matched(1));
				if( index < args.length )
					addValue(args[index].e, tabs);
				pos = matchPos.pos + matchPos.len;
			}
			add(code.substr(pos));
		case TSyntax(_, _, _):
			// Do nothing: Code for other language
		}
	}

	function newLine( e : TExpr ) {
		if( isBlock(e) )
			add("\n");
		else
			add(";\n");
	}

	function isBlock( e : TExpr ) {
		switch( e.e ) {
		case TFor(_, _, loop), TWhile(_, loop, true):
			return isBlock(loop);
		case TIf(_, eif, eelse):
			return isBlock(eelse == null ? eif : eelse);
		case TBlock(_):
			return true;
		default:
			return false;
		}
	}

	public static function varName( v : TVar, varNames : Map<Int,String>, allNames : Map<String,Int> ) : String {
		var n = varNames.get(v.id);
		if( n != null )
			return n;
		n = v.name;
		while( KWDS.exists(n) )
			n = "_" + n;
		if( allNames.exists(n) ) {
			var k = 2;
			n += "_";
			while( allNames.exists(n + k) )
				k++;
			n += k;
		}
		varNames.set(v.id, n);
		allNames.set(n, v.id);
		return n;
	}

	function collectGlobals( m : Map<TGlobal,Type>, e : TExpr ) {
		switch( e.e ) {
		case TGlobal(g): m.set(g, e.t);
		case TCall({ e : TGlobal(SetLayout) }, [{ e : TConst(CInt(x)) }, { e : TConst(CInt(y)) }, { e : TConst(CInt(z)) }]):
			computeLayout = [x, y, z];
		case TCall({ e : TGlobal(SetLayout) }, [{ e : TConst(CInt(x)) }, { e : TConst(CInt(y)) }]):
			computeLayout = [x, y, 1];
		case TCall({ e : TGlobal(SetLayout) }, [{ e : TConst(CInt(x)) }]):
			computeLayout = [x, 1, 1];
		default: e.iter(collectGlobals.bind(m));
		}
	}

	function getSVName( g : TGlobal ) {
		return switch( g ) {
		case VertexID: "vertex_id";
		case InstanceID: "instance_id";
		case ComputeVar_GlobalInvocation: "thread_position_in_grid";
		case ComputeVar_LocalInvocation: "thread_position_in_threadgroup";
		case ComputeVar_WorkGroup: "threadgroup_position_in_grid";
		case ComputeVar_LocalInvocationIndex: "thread_index_in_threadgroup";
		default: null;
		}
	}

	function initVars( s : ShaderData ) {
		var outIndex = 0;
		var varyingIndex = 0;
		inputIndex = 0;

		function declInputVar(v : TVar) {
			add("\t");
			if( Tools.hasQualifier(v, Flat) )
				add("flat ");
			addVar(v);
			// Fragment shader varyings use [[user(locN)]], vertex inputs use [[attribute(N)]]
			if( !isVertex && v.kind == Var )
				add(" [[user(loc" + (inputIndex++) + ")]];\n");
			else
				add(" [[attribute(" + (inputIndex++) + ")]];\n");
			varAccess.set(v.id, "_in.");
		}

		function declOutputVar(v : TVar) {
			add("\t");
			if( Tools.hasQualifier(v, Flat) )
				add("flat ");
			addVar(v);
			// For fragment shaders, use [[color(n)]] for render target outputs.
			if( v.kind == Output ) {
				if( isVertex && outIndex == 0 )
					add(" [[position]]");
				else if( !isVertex )
					add(" [[color(" + outIndex + ")]]");
			} else if( v.kind == Var && isVertex ) {
				// Vertex shader varyings use [[user(locN)]] to match fragment input
				add(" [[user(loc" + varyingIndex + ")]]");
			}
			add(";\n");
			varAccess.set(v.id, "_out.");
			if( v.kind == Output )
				outIndex++;
			else if( v.kind == Var && isVertex )
				varyingIndex++;
		}

		var foundGlobals = new Map();
		for( f in s.funs )
			collectGlobals(foundGlobals, f.expr);

		// Build stage input struct
		var oldAllNames = allNames;
		allNames = new Map();
		add("struct " + stagePrefix + "input {\n");
		if( kind == Fragment ) {
			add("\tfloat4 __pos [[position]];\n");
			GLOBALS.set(FragCoord, "_in.__pos");
		}
		if( kind == Fragment ) {
			add("\tbool __frontFacing [[front_facing]];\n");
			GLOBALS.set(FrontFacing, "_in.__frontFacing");
		}
		if( kind == Fragment ) {
			for( g in foundGlobals.keys() ) {
				if( g == Barycentrics ) {
					add("\tfloat3 __bary [[barycentric_coord]];\n");
					GLOBALS.set(Barycentrics, "_in.__bary");
					break;
				}
			}
		}
		for( v in s.vars )
			if( v.kind == Input || (v.kind == Var && !isVertex) )
				declInputVar(v);
		for( g in foundGlobals.keys() ) {
			var sv = getSVName(g);
			if( sv == null ) continue;
			switch( g ) {
			case InstanceID, VertexID:
				// Metal requires vertex_id/instance_id as function parameters,
				// not struct members with [[stage_in]]
				var name = g.getName();
				name = name.charAt(0).toLowerCase() + name.substr(1);
				if( vertexParamGlobals == null ) vertexParamGlobals = [];
				vertexParamGlobals.push({ g : g, name : name });
				GLOBALS.set(g, name);
			default:
				add("\t");
				addType(foundGlobals.get(g));
				var name = g.getName().split("_").pop();
				name = name.charAt(0).toLowerCase() + name.substr(1);
				add(" " + name);
				add(" [[" + sv + "]];\n");
				GLOBALS.set(g, "_in." + name);
			}
		}
		add("};\n\n");

		// Build s_output struct (not for compute)
		if( !isCompute ) {
			allNames = new Map();
			outIndex = 0;
			add("struct " + stagePrefix + "output {\n");
			for( v in s.vars )
				if( v.kind == Output )
					declOutputVar(v);
			for( v in s.vars )
				if( v.kind == Var && isVertex )
					declOutputVar(v);
			add("};\n\n");
		}

		allNames = oldAllNames;
	}

	function initGlobals( s : ShaderData ) {
		hasGlobals = false;
		for( v in s.vars )
			if( v.kind == Global ) { hasGlobals = true; break; }
		if( !hasGlobals ) return;

		add("struct " + stagePrefix + "Globals {\n");
		for( v in s.vars )
			if( v.kind == Global ) {
				add("\t");
				addVar(v);
				add(";\n");
			}
		add("};\n\n");
	}

	function initParams( s : ShaderData ) {
		var textures = [];
		var buffers = [];
		hasParams = false;

		for( v in s.vars )
			if( v.kind == Param ) {
				switch( v.type ) {
				case TArray(TRWTexture(_), _):
					textures.push(v);
					continue;
				case TArray(t, _) if( t.isTexture() ):
					textures.push(v);
					continue;
				case TBuffer(_, _, Storage | StoragePartial):
					buffers.push(v);
					continue;
				case TBuffer(_, _, RW | RWPartial):
					buffers.push(v);
					continue;
				case TBuffer(_, _, _):
					buffers.push(v);
					continue;
				default:
					if( v.type.isTexture() ) {
						textures.push(v);
						continue;
					}
				}
				hasParams = true;
			}

		if( hasParams ) {
			add("struct " + stagePrefix + "Params {\n");
			for( v in s.vars )
				if( v.kind == Param ) {
					switch( v.type ) {
					case TArray(TRWTexture(_), _):
						continue;
					case TArray(t, _) if( t.isTexture() ):
						continue;
					case TBuffer(_, _, _):
						continue;
					default:
						if( v.type.isTexture() ) continue;
					}
					add("\t");
					addVar(v);
					add(";\n");
				}
			add("};\n\n");
		}

		var bufIndex = 2;
		paramBuffers = [];
		for( b in buffers ) {
			switch( b.type ) {
			case TBuffer(t, size, Storage | StoragePartial):
				paramBuffers.push({ v : b, index : bufIndex++, addrSpace : "device " });
			case TBuffer(t, size, RW | RWPartial):
				paramBuffers.push({ v : b, index : bufIndex++, addrSpace : "device " });
			case TBuffer(t, size, Uniform | Partial):
				paramBuffers.push({ v : b, index : bufIndex++, addrSpace : "constant " });
			default:
			}
		}

		// Collect texture bindings and build sampler map
		var texIndex = 0;
		var ctx = new Samplers();
		paramTextures = [];
		for( v in textures ) {
			switch( v.type ) {
			case TArray(TRWTexture(dim, arr, chans), SConst(n)):
				for( i in 0...n ) {
					paramTextures.push({ decl : getTexType(TRWTexture(dim, arr, chans)) + " tex" + texIndex, index : texIndex, varId : null });
					texIndex++;
				}
				samplers.set(v.id, ctx.make(v, []));
			case TRWTexture(_, _, _):
				var tmp = new StringBuf();
				var oldBuf = buf;
				buf = tmp;
				add(getTexType(v.type));
				add(" ");
				addIdent(v);
				buf = oldBuf;
				paramTextures.push({ decl : tmp.toString(), index : texIndex, varId : v.id });
				texIndex++;
				samplers.set(v.id, ctx.make(v, []));
			case TArray(t, SConst(n)) if( t.isTexture() ):
				for( i in 0...n ) {
					paramTextures.push({ decl : getTexType(t) + " tex" + texIndex, index : texIndex, varId : null });
					texIndex++;
				}
				samplers.set(v.id, ctx.make(v, []));
			default:
				if( v.type.isTexture() ) {
					var tmp = new StringBuf();
					var oldBuf = buf;
					buf = tmp;
					add(getTexType(v.type));
					add(" ");
					addIdent(v);
					buf = oldBuf;
					paramTextures.push({ decl : tmp.toString(), index : texIndex, varId : v.id });
					texIndex++;
					samplers.set(v.id, ctx.make(v, []));
				}
			}
		}

		paramSamplerCount = ctx.count;
	}

	function emitMain( expr : TExpr ) {
		if( isCompute )
			add("kernel ");
		else if( isVertex )
			add("vertex ");
		else
			add("fragment ");

		if( isCompute )
			add("void ");
		else
			add(stagePrefix + "output ");

		add("main(\n");

		// Stage-in input
		add("\t" + stagePrefix + "input _in [[stage_in]]\n");

		// Vertex/instance ID as function parameters (Metal requirement)
		if( vertexParamGlobals != null ) {
			for( vg in vertexParamGlobals ) {
				add("\t, uint ");
				add(vg.name);
				add(" [[" + getSVName(vg.g) + "]]\n");
			}
		}

		// Globals buffer
		if( hasGlobals ) add("\t, constant " + stagePrefix + "Globals& __globals [[buffer(0)]]\n");

		// Params buffer
		if( hasParams ) add("\t, constant " + stagePrefix + "Params& __params [[buffer(1)]]\n");

		for( pb in paramBuffers ) {
			add("\t, " + pb.addrSpace);
			// Need to use a temp buf to get the var declaration
			var tmp = new StringBuf();
			var oldBuf = buf;
			buf = tmp;
			switch( pb.v.type ) {
			case TBuffer(t, size, _):
				addType(t);
				add("* ");
				addIdent(pb.v);
			default:
			}
			buf = oldBuf;
			add(tmp.toString());
			add(" [[buffer(" + pb.index + ")]]\n");
		}

		for( pt in paramTextures ) {
			add("\t, " + pt.decl + " [[texture(" + pt.index + ")]]\n");
		}

		if( paramSamplerCount > 0 )
			add("\t, array<sampler," + paramSamplerCount + "> __Samplers [[sampler(0)]]\n");

		add(") {\n");

		// Declare output struct for non-compute shaders
		if( !isCompute )
			add("\t" + stagePrefix + "output _out = {};\n");


		// Emit body
		switch( expr.e ) {
		case TBlock(el):
			for( e in el ) {
				switch( e.e ) {
				case TBinop(OpAssign, { e : TVar(v) }, _) if( v.qualifiers != null && v.qualifiers.indexOf(Final) >= 0 ):
					// ignore (is a static const)
					continue;
				default:
				}
				add("\t");
				addExpr(e, "\t");
				newLine(e);
			}
		default:
			addExpr(expr, "");
		}

		if( !isCompute )
			add("\treturn _out;\n");
		add("}\n");
	}

	function initLocals(s : ShaderData) {
		// Forward-declare Local variables that have NO TVarDecl in the IR.
		// Variables with TVarDecl get inline type declarations via addVar().
		// Only inject into the main function body, not _val helpers.
		var fwdBuf = new StringBuf();
		var fwdSet = new Map();
		for( v in s.vars ) {
			if( v.kind == Local && !locals.exists(v.id) && !fwdSet.exists(v.id) ) {
				fwdSet.set(v.id, true);
				fwdBuf.add("\t");
				var oldBuf = buf;
				buf = fwdBuf;
				addVar(v);
				buf = oldBuf;
				fwdBuf.add(";\n");
			}
		}
		var fwdDecl = fwdBuf.toString();
		// Only inject forward declarations into the LAST exprValue (main function body).
		for( i in 0...exprValues.length ) {
			var e = exprValues[i];
			if( i == exprValues.length - 1 && fwdDecl.length > 0 ) {
				var braceIdx = e.indexOf("{\n");
				if( braceIdx >= 0 )
					e = e.substr(0, braceIdx + 2) + fwdDecl + e.substr(braceIdx + 2);
			}
			add(e);
			add("\n\n");
		}
	}

	public function run( s : ShaderData ) {
		locals = new Map();
		decls = [];
		buf = new StringBuf();
		exprValues = [];
		samplers = new Map();
		varAccess = new Map();
		paramBuffers = [];
		paramTextures = [];
		paramSamplerCount = 0;
		vertexParamGlobals = null;

		if( s.funs.length != 1 ) throw "assert";
		var f = s.funs[0];
		kind = f.kind;
		isVertex = kind == Vertex;
		isCompute = kind == Main;
		stagePrefix = switch( kind ) { case Vertex: "vs_"; case Fragment: "fs_"; case Main: "cs_"; default: "x_"; };
		hasBinormal = false;

		// Metal header is added by MetalDriver when combining shaders

		// Initialize variable name map first
		for( v in s.vars )
			varName(v, varNames, allNames);

		initVars(s);
		initGlobals(s);
		initParams(s);

		// Set up var access for Global kind variables
		for( v in s.vars )
			if( v.kind == Global && varAccess.get(v.id) == null )
				varAccess.set(v.id, "__globals.");

		// Set up var access for Param kind variables (non-texture, non-buffer)
		for( v in s.vars )
			if( v.kind == Param ) {
				if( varAccess.get(v.id) != null ) continue;
				switch( v.type ) {
				case TSampler(_), TRWTexture(_), TBuffer(_, _, _):
					// textures and buffers are accessed directly
				default:
					if( v.type.isTexture() ) continue;
					varAccess.set(v.id, "__params.");
				}
			}

		var tmp = buf;
		buf = new StringBuf();
		emitMain(f.expr);
		exprValues.push(buf.toString());
		buf = tmp;

		initLocals(s);

		decls.push(buf.toString());
		buf = null;
		return decls.join("\n");
	}

	public static function compile( s : ShaderData ) {
		var out = new MslOut();
		return out.run(s);
	}

}

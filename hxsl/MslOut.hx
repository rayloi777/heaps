package hxsl;
using hxsl.Ast;

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
		m.set(Mat4, "float4x4");
		m.set(Mat3x4, "float3x4");
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
			"texture" + dim.getName().substr(1) + (arr ? "Array" : "") + "<float, access::sample>";
		case TRWTexture(dim, arr, chans):
			"texture" + dim.getName().substr(1) + (arr ? "Array" : "") + "<float, access::write>";
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
			add("float3x4");
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
		case TArray(t, size), TBuffer(t, size, Uniform):
			addVar({
				id : v.id,
				name : v.name,
				type : t,
				kind : v.kind,
			});
			addArraySize(size);
		case TBuffer(t, size, Storage):
			add("device ");
			addType(t);
			add("* ");
			addIdent(v);
		case TBuffer(t, size, RW):
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
			decl("float3x4 mat3x4( float4 a, float4 b, float4 c ) { return float3x4(a.xyz, b.xyz, c.xyz); }");
			decl("float3x4 mat3x4( float4x4 m ) { return float3x4(m[0].xyz, m[1].xyz, m[2].xyz); }");
		case Mat4:
			decl("float4x4 mat4( float4 a, float4 b, float4 c, float4 d ) { return float4x4(a,b,c,d); }");
		case Mat3:
			decl("float3x3 mat3( float4x4 m ) { return float3x3(m[0].xyz, m[1].xyz, m[2].xyz); }");
			decl("float3x3 mat3( float3x4 m ) { return float3x3(m[0].xyz, m[1].xyz, m[2].xyz); }");
			decl("float3x3 mat3( float3 a, float3 b, float3 c ) { return float3x3(a,b,c); }");
			decl("float3x3 mat3( float c00, float c01, float c02, float c10, float c11, float c12, float c20, float c21, float c22 ) { return float3x3(c00,c10,c20,c01,c11,c21,c02,c12,c22); }");
		case Mat2:
			decl("float2x2 mat2( float4x4 m ) { return float2x2(m[0].xy, m[1].xy); }");
			decl("float2x2 mat2( float3x3 m ) { return float2x2(m[0].xy, m[1].xy); }");
			decl("float2x2 mat2( float3x4 m ) { return float2x2(m[0].xy, m[1].xy); }");
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

	function addValue( e : TExpr, tabs : String ) {
		switch( e.e ) {
		case TBlock(el):
			var name = "_val" + (exprIds++);
			var tmp = buf;
			buf = new StringBuf();
			addType(e.t);
			add(" ");
			add(name);
			add("(void)");
			var el2 = el.copy();
			var last = el2[el2.length - 1];
			el2[el2.length - 1] = { e : TReturn(last), t : e.t, p : last.p };
			var e2 : TExpr = {
				t : TVoid,
				e : TBlock(el2),
				p : e.p,
			};
			addExpr(e2, "");
			exprValues.push(buf.toString());
			buf = tmp;
			add(name);
			add("()");
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
				addIdent(v);
				add(" = ");
				addValue(init, tabs);
			} else {
				add("/*var*/");
			}
		case TCall({ e : TGlobal(SetLayout) }, _):
			// ignore
		case TCall({ e : TGlobal(g = (Texture | TextureLod)) }, args):
			// Metal: tex.sample(sampler, uv) or tex.sample(sampler, uv, level(lod))
			addValue(args[0], tabs);
			add(".sample(");
			// sampler argument
			var offset = 0;
			var dynOffset = null;
			var expr = switch( args[0].e ) {
			case TArray(e, { e : TConst(CInt(i)) }): offset = i; e;
			case TArray(e, idx): dynOffset = idx; e;
			default: args[0];
			}
			switch( expr.e ) {
			case TVar(v):
				var sams = samplers.get(v.id);
				if( sams == null ) throw "assert: no sampler for " + v.name;
				if( dynOffset != null ) {
					add("__Samplers[");
					add(sams[0]);
					add("+");
					addValue(dynOffset, tabs);
					add("]");
				} else
					add("__Samplers[" + sams[offset] + "]");
			default: throw "assert";
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
			addIdent(v);
			add(", ");
			addValue(index, tabs);
			add(")");
		case TCall(e2 = { e : TGlobal(g) }, args):
			declGlobal(g, args);
			switch( [g, args] ) {
			case [Vec2 | Vec3 | Vec4, [{ t : TFloat }]]:
				add(g.getName().toLowerCase());
			case [IVec2 | IVec3 | IVec4, [{ t : TInt }] | [{ t : TFloat }]]:
				add(g.getName().toLowerCase());
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
			addValue(e2, tabs);
			add(".");
			for( r in regs )
				add(switch(r) {
				case X: "x";
				case Y: "y";
				case Z: "z";
				case W: "w";
				});
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
				add("for(");
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
					decl("float4 _matarr( float3x4 m, int idx ) { return float4(m[0][idx],m[1][idx],m[2][idx],m[3][idx]); }");
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
			addValue(e2, tabs);
			add(".");
			add(f);
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

}

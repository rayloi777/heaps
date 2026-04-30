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

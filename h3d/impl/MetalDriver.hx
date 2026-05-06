package h3d.impl;

#if hlmetal

import h3d.impl.Driver;
import h3d.mat.Pass;
import h3d.mat.Stencil;
import metal.Driver as MtlDrv;
import metal.Driver.Buffer;
import metal.Driver.DepthStencilState;
import metal.Driver.SamplerState;
import metal.Driver.PipelineState;
import metal.Driver.Library;
import metal.Driver.BlendDesc;
import metal.Driver.LayoutElement;
import metal.Format;

private class ShaderContext {
	public var globalsSize : Int;
	public var paramsSize : Int;
	public var texturesCount : Int;
	public var bufferCount : Int;
	public var globals : Buffer;
	public var params : Buffer;
	public var paramsContent : hl.Bytes;
	public var texturesTypes : Array<hxsl.Ast.Type>;
	#if debug
	public var debugSource : String;
	#end
	public function new() {
	}
}

private class CompiledShader {
	public var vertex : ShaderContext;
	public var fragment : ShaderContext;
	public var format : hxd.BufferFormat;
	public var perInst : Array<Int>;
	public var pipeline : PipelineState;
	public var library : Library;
	public var shader : hxsl.RuntimeShader;
	public function new() {
	}
}

class MetalDriver extends h3d.impl.Driver {

	static inline var NTARGETS = 8;

	var metalWindow : metal.Window.WindowHandle;
	var shaders : Map<Int,CompiledShader>;
	var currentShader : CompiledShader;
	var currentIndex : h3d.Buffer;
	var frame : Int;
	var currentMaterialBits : Int = -1;
	var currentStencilOpBits : Int = -1;
	var currentStencilMaskBits : Int = -1;
	var currentStencilRef : Int = 0;
	var currentCullMode : Int = -1;
	var pipelineDirty : Bool = true;
	// Texture/sampler binding cache
	static inline var MAX_TEXTURES = 16;
	var currentFragmentTextures : Array<metal.Driver.Texture>;
	var currentFragmentSamplers : Array<metal.Driver.SamplerState>;
	var currentVertexTextures : Array<metal.Driver.Texture>;
	var currentVertexSamplers : Array<metal.Driver.SamplerState>;
	// Viewport cache
	var curVPX : Float = -1;
	var curVPY : Float = -1;
	var curVPW : Float = -1;
	var curVPH : Float = -1;
	var curVPZN : Float = -1;
	var curVPZF : Float = -1;
	var outputWidth : Int;
	var outputHeight : Int;
	var defaultDepthTex : metal.Driver.Texture;
	var curTexture : h3d.mat.Texture;
	var allowDraw : Bool = false;

	// Render pass state
	var inRenderPass : Bool = false;
	var passHasColor : Bool = false;
	var passHasDepth : Bool = false;

	// Depth-only pass tracking (shadow maps)
	var curDepthOnlyTex : metal.Driver.Texture;
	var curDepthOnlyW : Int = 0;
	var curDepthOnlyH : Int = 0;

	// Depth/stencil state cache
	var depthStencilStates : Map<Int, DepthStencilState>;
	var currentDepthStencilState : DepthStencilState;

	// Sampler state cache
	var samplerStates : Map<Int, SamplerState>;
	// Pipeline cache keyed by (shader.id, materialBits)
	var pipelineCache : Map<Int, PipelineState>;

	// Per-draw params buffer pool to avoid shared buffer overwrites between draws
	var paramsPool : Array<{buf:Buffer, size:Int}>;
	var paramsPoolIdx : Int;
	var curColorFormat : Int = cast PixelFormat.BGRA8Unorm;

	var defaultDepthInst : h3d.mat.Texture;

	public function new() {
		reset();
	}

	static function pipelineKey( shaderId : Int, bits : Int, mask : Int, colorFmt : Int, depthFmt : Int ) : Int {
		var h = shaderId;
		h = (h << 5) - h + bits;
		h = (h << 5) - h + mask;
		h = (h << 5) - h + colorFmt;
		h = (h << 5) - h + (depthFmt > 0 ? 1 : 0);
		return h;
	}

	function reset() {
		allowDraw = false;
		currentMaterialBits = -1;
		if( shaders != null ) {
			for( s in shaders ) {
				if( s.vertex != null ) {
					if( s.vertex.globals != null ) s.vertex.globals = null;
					if( s.vertex.params != null ) s.vertex.params = null;
				}
				if( s.fragment != null ) {
					if( s.fragment.globals != null ) s.fragment.globals = null;
					if( s.fragment.params != null ) s.fragment.params = null;
				}
			}
		}
		shaders = new Map();
		depthStencilStates = new Map();
		samplerStates = new Map();
		pipelineCache = new Map();
		currentDepthStencilState = null;
		paramsPool = new Array();
		paramsPoolIdx = 0;
		inRenderPass = false;
		curDepthOnlyTex = null;
		curDepthOnlyW = 0;
		curDepthOnlyH = 0;
		currentFragmentTextures = [for(i in 0...MAX_TEXTURES) null];
		currentFragmentSamplers = [for(i in 0...MAX_TEXTURES) null];
		currentVertexTextures = [for(i in 0...MAX_TEXTURES) null];
		currentVertexSamplers = [for(i in 0...MAX_TEXTURES) null];
	}

	override function dispose() {
		MtlDrv.disposeDriver(null);
		if( metalWindow != null ) {
			metal.Window.destroy(metalWindow);
			metalWindow = null;
		}
	}

	override function isDisposed() {
		return false;
	}

	override function init( onCreate : Bool -> Void, forceSoftware = false ) {
		metalWindow = metal.Window.create("Heaps", 800, 600);
		var layer = metal.Window.getMetalLayer(metalWindow);
		MtlDrv.create(layer, 800, 600, 0);
		outputWidth = 800;
		outputHeight = 600;
		defaultDepthTex = MtlDrv.createTexture2D(800, 600, cast PixelFormat.Depth32Float, 1, cast(TextureUsage.RenderTarget | TextureUsage.ShaderRead), cast StorageMode.Private);
		// Wrap onCreate to fix engine dimensions — hxd.Window returns 0 for Metal backend,
		// causing Engine.onCreate to resize(0,0)→(32,32) which creates drawable/depth size mismatch
		haxe.Timer.delay(function() {
			onCreate(false);
			var engine = h3d.Engine.getCurrent();
			if( engine != null ) engine.resize(outputWidth, outputHeight);
		}, 1);
	}

	override function begin( frame : Int ) {
		paramsPoolIdx = 0;
		this.frame = frame;
		MtlDrv.beginFrame();
		inRenderPass = false;
		curTexture = null;
		curDepthOnlyTex = null;
		// Reset currentShader so selectShader re-sets the pipeline on the
		// new render encoder. Metal does not inherit pipeline state between
		// render encoders, so the pipeline must always be re-set after a pass switch.
		currentShader = null;
		currentMaterialBits = -1;
		// Begin default render pass with clear
		beginDefaultPass(0, 0, 0, 0, 1.0, 0);
	}

	override function present() {
		if( inRenderPass ) {
			MtlDrv.endRenderPass();
			inRenderPass = false;
		}
		MtlDrv.present();
		if( metalWindow != null )
			metal.Window.pollEvents(metalWindow);
	}

	override function end() {
		if( inRenderPass ) {
			MtlDrv.endRenderPass();
			inRenderPass = false;
		}
		MtlDrv.present();
		if( metalWindow != null )
			metal.Window.pollEvents(metalWindow);
	}

	override function getDriverName( details : Bool ) {
		var name = "Metal";
		if( details )
			name += " " + MtlDrv.getDeviceName();
		return name;
	}

	override function hasFeature( f : Feature ) {
		return switch( f ) {
		case Queries, BottomLeftCoords, Bindless:
			false;
		default:
			true;
		};
	}

	override function isSupportedFormat( fmt : hxd.PixelFormat ) {
		return switch( fmt ) {
		case RGB8, RGB16F, ARGB, BGRA, SRGB, RGB16U:
			false;
		default:
			true;
		};
	}

	// ---- Shader Compilation ----

	function compileShaderContext( shader : hxsl.RuntimeShader.RuntimeShaderData ) : ShaderContext {
		var ctx = new ShaderContext();
		ctx.globalsSize = shader.globalsSize;
		ctx.paramsSize = shader.paramsSize;
		ctx.texturesCount = shader.texturesCount;
		ctx.bufferCount = shader.bufferCount;
		ctx.texturesTypes = [];

		// Collect texture types
		var p = shader.textures;
		while( p != null ) {
			switch( p.type ) {
			case TArray( t = TSampler(_) | TRWTexture(_) | TChannel(_), SConst(n) ):
				for( i in 0...n )
					ctx.texturesTypes.push(t);
			case TSampler(_), TRWTexture(_), TChannel(_):
				ctx.texturesTypes.push(p.type);
			default:
			}
			p = p.next;
		}

		// Create constant buffers (Metal: Shared storage for CPU-write)
		if( ctx.globalsSize > 0 )
			ctx.globals = MtlDrv.createBuffer(ctx.globalsSize * 16, ResourceOptions.StorageModeShared);
		if( ctx.paramsSize > 0 ) {
			ctx.params = MtlDrv.createBuffer(ctx.paramsSize * 16, ResourceOptions.StorageModeShared);
			ctx.paramsContent = new hl.Bytes(ctx.paramsSize * 16);
			ctx.paramsContent.fill(0, ctx.paramsSize * 16, 0xDD);
		}

		#if debug
		ctx.debugSource = shader.code;
		#end

		return ctx;
	}

	function compileShader( shader : hxsl.RuntimeShader ) : CompiledShader {
		var s = new CompiledShader();
		s.shader = shader;

		// Generate MSL source via MslOut
		if( shader.vertex.code == null ) {
			shader.vertex.code = hxsl.MslOut.compile(shader.vertex.data);
			#if !heaps_compact_mem
			shader.vertex.data.funs = null;
			#end
		}
		if( shader.fragment.code == null ) {
			shader.fragment.code = hxsl.MslOut.compile(shader.fragment.data);
			#if !heaps_compact_mem
			shader.fragment.data.funs = null;
			#end
		}

		// Compile MSL source into a library
		// MslOut generates a function named "main" for each shader stage.
		// We must rename them to avoid duplicate symbols when combining into one library.
		var vsSource = shader.vertex.code;
		var fsSource = shader.fragment.code;
		// Rename "vertex " prefix + "main(" -> "vertex_main("
		vsSource = renameMain(vsSource, "vertex_main");
		fsSource = renameMain(fsSource, "fragment_main");
		// Deduplicate helper function declarations between VS and FS.
		// MslOut's decl() deduplicates within one shader, but when combining
		// VS + FS into one source, shared helpers (mat3x4, mod, etc.) appear
		// twice. Remove FS declarations that already exist in VS.
		var vsDecls = new Map<String,Bool>();
		for( line in vsSource.split("\n") ) {
			var t = StringTools.trim(line);
			if( t.charCodeAt(0) == 'f'.code || t.charCodeAt(0) == 'i'.code || t.charCodeAt(0) == 'u'.code )
				vsDecls.set(t, true);
		}
		var fsLines = fsSource.split("\n");
		var dedupBuf = new StringBuf();
		for( line in fsLines ) {
			var t = StringTools.trim(line);
			if( vsDecls.exists(t) && (t.charCodeAt(0) == 'f'.code || t.charCodeAt(0) == 'i'.code || t.charCodeAt(0) == 'u'.code) )
				continue; // skip duplicate declaration
			dedupBuf.add(line);
			dedupBuf.addChar("\n".code);
		}
		fsSource = dedupBuf.toString();
		// Inject VS output varyings into FS input struct.
		// MslOut compiles VS and FS independently. VS outputs varyings via
		// [[user(locN)]] but the FS input struct may already have some.
		// We extract varyings from VS output struct and inject into FS input,
		// skipping any that already exist in the FS input struct.
		{
			var varyings = [];
			var inOutput = false;
			var braceDepth = 0;
			for( line in vsSource.split("\n") ) {
				var t = StringTools.trim(line);
				if( t == "struct vs_output {" ) {
					inOutput = true;
					braceDepth = 1;
					continue;
				}
				if( inOutput ) {
					if( t.indexOf("{") >= 0 ) braceDepth++;
					if( t.indexOf("}") >= 0 ) braceDepth--;
					if( braceDepth <= 0 ) break;
					if( t.indexOf("[[position]]") >= 0 ) continue;
					if( t.indexOf("[[user(") < 0 ) continue;
					varyings.push(t);
				}
			}
			if( varyings.length > 0 ) {
				// Collect existing [[user(locN)]] bindings in FS input
				var fsLocs = new Map<String,Bool>();
				var fsInputStart = fsSource.indexOf("struct fs_input {");
				if( fsInputStart >= 0 ) {
					var fsInputEnd = fsSource.indexOf("};", fsInputStart);
					if( fsInputEnd >= 0 ) {
						var fsInputBlock = fsSource.substr(fsInputStart, fsInputEnd - fsInputStart);
						for( line in fsInputBlock.split("\n") ) {
							var m = line.indexOf("[[user(");
							if( m >= 0 ) {
								var loc = line.substr(m, line.indexOf(")", m) - m + 1);
								fsLocs.set(loc, true);
							}
						}
						// Inject only varyings not already in FS input
						var inject = new StringBuf();
						for( v in varyings ) {
							var m = v.indexOf("[[user(");
							var loc = v.substr(m, v.indexOf(")", m) - m + 1);
							if( fsLocs.exists(loc) ) continue;
							inject.addChar("\t".code);
							inject.add(v);
							inject.addChar("\n".code);
						}
						var injectStr = inject.toString();
						if( injectStr.length > 0 )
							fsSource = fsSource.substr(0, fsInputEnd) + injectStr + fsSource.substr(fsInputEnd);
					}
				}
			}
		}
		// Add Metal header once, then combine vertex + fragment
		var combinedSource = "#include <metal_stdlib>\nusing namespace metal;\n" + vsSource + "\n" + fsSource;

		s.library = MtlDrv.compileShader(combinedSource, "vertex_main");

		// Build shader contexts (constant buffers, texture info)
		s.vertex = compileShaderContext(shader.vertex);
		s.fragment = compileShaderContext(shader.fragment);

		// Extract vertex input format
		s.perInst = [];
		var format : Array<hxd.BufferFormat.BufferInput> = [];
		for( v in shader.vertex.data.vars )
			if( v.kind == Input ) {
				var perInst = 0;
				if( v.qualifiers != null )
					for( q in v.qualifiers )
						switch( q ) {
						case PerInstance(k): perInst = k;
						default:
						}
				s.perInst.push(perInst);
				var t = hxd.BufferFormat.InputFormat.fromHXSL(v.type);
				format.push({ name : v.name, type : t });
			}
		s.format = hxd.BufferFormat.make(format);

		// Store vertex layout for later pipeline creation (color format varies per render target)
		var layout = buildVertexLayout(s);
		return s;
	}

	function buildVertexLayout( s : CompiledShader ) : hl.NativeArray<LayoutElement> {
		var inputs = @:privateAccess s.format.inputs;
		var layout = new hl.NativeArray<LayoutElement>(inputs.length);
		var offset = 0;
		for( i in 0...inputs.length ) {
			var e = new LayoutElement();
			e.attributeIndex = i;
			e.bufferIndex = 2;
			e.offset = offset;
			var input = inputs[i];
			e.format = vertexFormatFromInput(input.type);
			offset += input.getBytesSize();
			layout[i] = e;
		}
		return layout;
	}

	function vertexFormatFromInput( t : hxd.BufferFormat.InputFormat ) : Int {
		return switch( t ) {
		case DFloat: metal.Format.VertexFormat.Float;
		case DVec2: metal.Format.VertexFormat.Float2;
		case DVec3: metal.Format.VertexFormat.Float3;
		case DVec4: metal.Format.VertexFormat.Float4;
		case DBytes4: metal.Format.VertexFormat.UChar4Normalized;
		case DMat4: metal.Format.VertexFormat.Float4; // mat4 is split into 4 float4s
		default: metal.Format.VertexFormat.Float4;
		}
	}

	/**
		Renames the MSL entry function from "main" to newName.
		MslOut generates "vertex s_output main(" or "fragment s_output main(" or "kernel void main("
		We rename by replacing the last occurrence of " main(" with " newName(".
	**/
	function renameMain( source : String, newName : String ) : String {
		// Find " main(" pattern (with preceding space) and replace with the new name
		var idx = source.lastIndexOf(" main(");
		if( idx < 0 )
			throw "Could not find 'main(' in generated MSL source";
		return source.substr(0, idx) + " " + newName + "(" + source.substr(idx + 6);
	}

	function makePipelineWithBlend( s : CompiledShader, blendDesc : BlendDesc, colorFormat : Int, depthFormat : Int, stride : Int ) : PipelineState {
		var layout = buildVertexLayout(s);
		return MtlDrv.createRenderPipeline(
			s.library, "vertex_main", "fragment_main",
			layout, layout.length,
			stride,
			blendDesc,
			colorFormat,
			depthFormat
		);
	}

	override function getNativeShaderCode( shader : hxsl.RuntimeShader ) : String {
		var vsCode = shader.vertex.code;
		if( vsCode == null )
			vsCode = hxsl.MslOut.compile(shader.vertex.data);
		var fsCode = shader.fragment.code;
		if( fsCode == null )
			fsCode = hxsl.MslOut.compile(shader.fragment.data);
		return vsCode + "\n\n" + fsCode;
	}

	override function selectShader( shader : hxsl.RuntimeShader ) : Bool {
		var s = shaders.get(shader.id);
		if( s == null ) {
			s = compileShader(shader);
			shaders.set(shader.id, s);
		}
		if( s == currentShader )
			return false;
		currentShader = s;
		pipelineDirty = true;
		// Build pipeline with current material blend state (if material was selected)
		var bits = currentMaterialBits;
		var mask = 15; // default color mask when no material selected
		var blendDesc = new BlendDesc();
		if( bits >= 0 ) {
			blendDesc.sourceRGBBlendFactor = BLEND[Pass.getBlendSrc(bits)];
			blendDesc.destinationRGBBlendFactor = BLEND[Pass.getBlendDst(bits)];
			blendDesc.rgbBlendOperation = BLEND_OP[Pass.getBlendOp(bits)];
			blendDesc.sourceAlphaBlendFactor = BLEND[Pass.getBlendAlphaSrc(bits)];
			blendDesc.destinationAlphaBlendFactor = BLEND[Pass.getBlendAlphaDst(bits)];
			blendDesc.alphaBlendOperation = BLEND_OP[Pass.getBlendAlphaOp(bits)];
		}
		var pipeColorFmt = passHasColor ? curColorFormat : 0;
		var pipeDepthFmt = passHasDepth ? cast PixelFormat.Depth32Float : 0;
		var cacheKey = pipelineKey(s.shader.id, bits, mask, pipeColorFmt, pipeDepthFmt);
		var pipeline = pipelineCache.get(cacheKey);
		if( pipeline == null ) {
			pipeline = makePipelineWithBlend(s, blendDesc, pipeColorFmt, pipeDepthFmt, s.format.strideBytes);
			pipelineCache.set(cacheKey, pipeline);
		}
		MtlDrv.setRenderPipeline(pipeline);
		pipelineDirty = false;
		return true;
	}

	// ---- Buffer Management ----

	override function allocBuffer( b : h3d.Buffer ) : GPUBuffer {
		var size = b.getMemSize();
		var options = b.flags.has(UniformBuffer) ? ResourceOptions.StorageModeShared : ResourceOptions.StorageModeShared;
		var buf = MtlDrv.createBuffer(size, options);
		return buf;
	}

	override function disposeBuffer( b : h3d.Buffer ) {
		// Metal buffer disposal handled by GC for now
		b.vbuf = null;
	}

	override function uploadBufferData( b : h3d.Buffer, startVertex : Int, vertexCount : Int, buf : hxd.FloatBuffer, bufPos : Int ) {
		var src = hl.Bytes.getArray(buf.getNative()).offset(bufPos << 2);
		var dstOffset = startVertex * b.format.strideBytes;
		var bytes = vertexCount * b.format.strideBytes;
		var contents = b.vbuf.contents();
		contents.blit(dstOffset, src, 0, bytes);
	}

	override function uploadBufferBytes( b : h3d.Buffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
		var dstOffset = startVertex * b.format.strideBytes;
		var bytes = vertexCount * b.format.strideBytes;
		var contents = b.vbuf.contents();
		contents.blit(dstOffset, @:privateAccess buf.b, bufPos, bytes);
	}

	override function uploadIndexData( i : h3d.Buffer, startIndice : Int, indiceCount : Int, buf : hxd.IndexBuffer, bufPos : Int ) {
		var bits = i.format.strideBytes >> 1;
		var src = hl.Bytes.getArray(buf.getNative()).offset(bufPos << bits);
		var dstOffset = startIndice << bits;
		var bytes = indiceCount << bits;
		var contents = i.vbuf.contents();
		contents.blit(dstOffset, src, 0, bytes);
	}

	override function readBufferBytes( b : h3d.Buffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
		var stride = b.format.strideBytes;
		var contents = b.vbuf.contents();
		@:privateAccess buf.b.blit(bufPos, contents, startVertex * stride, vertexCount * stride);
	}

	// ---- Texture Management ----

	function getPixelFormat( t : h3d.mat.Texture ) : Int {
		return switch( t.format ) {
		case RGBA: PixelFormat.RGBA8Unorm;
		case RGBA16F: PixelFormat.RGBA16Float;
		case RGBA32F: PixelFormat.RGBA32Float;
		case R32F: PixelFormat.R32Float;
		case R16F: PixelFormat.R16Float;
		case R8: PixelFormat.R8Unorm;
		case RG8: PixelFormat.RG8Unorm;
		case RG16F: PixelFormat.RG16Float;
		case RG32F: PixelFormat.RG32Float;
		case SRGB_ALPHA: PixelFormat.RGBA8Unorm_sRGB;
		case Depth16: PixelFormat.Depth16Unorm;
		case Depth24, Depth24Stencil8: PixelFormat.Depth24Unorm_Stencil8;
		case Depth32: PixelFormat.Depth32Float;
		case Depth32Stencil8: PixelFormat.Depth32Float_Stencil8;
		default: PixelFormat.BGRA8Unorm;
		}
	}

	override function allocTexture( t : h3d.mat.Texture ) : Texture {
		var mips = 1;
		if( t.flags.has(MipMapped) )
			mips = t.mipLevels;

		var rt = t.flags.has(Target);
		var usage : TextureUsage = ShaderRead;
		if( rt )
			usage = usage | TextureUsage.RenderTarget;

		var pixelFormat = getPixelFormat(t);
		// Use Shared storage for non-RT textures so CPU can upload directly.
		// Private storage requires blit encoder which can have sync issues.
		var storage = rt ? StorageMode.Private : StorageMode.Shared;
		var tex = MtlDrv.createTexture2D(t.width, t.height, pixelFormat, mips, cast usage, storage);
		if( tex == null )
			return null;

		t.lastFrame = frame;
		t.flags.unset(WasCleared);

		return { res : tex, rt : rt ? new Array() : null };
	}

	override function disposeTexture( t : h3d.mat.Texture ) {
		var tt = t.t;
		if( tt == null ) return;
		t.t = null;
		// Metal textures are managed; native resources will be freed by GC
	}

	override function uploadTextureBitmap( t : h3d.mat.Texture, bmp : hxd.BitmapData, mipLevel : Int, side : Int ) {
		var pixels = bmp.getPixels();
		uploadTexturePixels(t, pixels, mipLevel, side);
		pixels.dispose();
	}

	override function uploadTexturePixels( t : h3d.mat.Texture, pixels : hxd.Pixels, mipLevel : Int, side : Int ) {
		pixels.convert(t.format);
		var stride = @:privateAccess pixels.stride;
		var tex = t.t;
		if( tex == null ) return;
		MtlDrv.textureReplaceRegion(tex.res, mipLevel, 0, 0, pixels.width, pixels.height,
			@:privateAccess (pixels.bytes : hl.Bytes).offset(pixels.offset), stride);
		t.flags.set(WasCleared);
	}

	override function allocDepthBuffer( b : h3d.mat.Texture ) : Texture {
		var pixelFormat = PixelFormat.Depth32Float;
		var usage : TextureUsage = TextureUsage.RenderTarget | TextureUsage.ShaderRead;
		var tex = MtlDrv.createTexture2D(b.width, b.height, pixelFormat, 1, cast usage, StorageMode.Private);
		if( tex == null )
			return null;
		return { res : tex, rt : null };
	}

	override function disposeDepthBuffer( b : h3d.mat.Texture ) {
		@:privateAccess {
			var d = b.t;
			b.t = null;
		}
	}

	override function getDefaultDepthBuffer() : h3d.mat.Texture {
		if( defaultDepthInst == null ) {
			defaultDepthInst = new h3d.mat.Texture(-1, -1, Depth24Stencil8);
			defaultDepthInst.name = "defaultDepth";
		}
		return defaultDepthInst;
	}

	// ---- Material / State Management ----

	static var COMPARE : Array<Int> = [
		metal.Format.CompareFunction.Always,   // 0
		metal.Format.CompareFunction.Never,    // 1
		metal.Format.CompareFunction.Equal,    // 2
		metal.Format.CompareFunction.NotEqual, // 3
		metal.Format.CompareFunction.Greater,  // 4
		metal.Format.CompareFunction.GreaterEqual, // 5
		metal.Format.CompareFunction.Less,     // 6
		metal.Format.CompareFunction.LessEqual // 7
	];

	static var STENCIL_OP : Array<Int> = [
		metal.Format.StencilOperation.Keep,           // 0 Keep
		metal.Format.StencilOperation.Zero,           // 1 Zero
		metal.Format.StencilOperation.Replace,        // 2 Replace
		metal.Format.StencilOperation.IncrementClamp, // 3 Increment
		metal.Format.StencilOperation.IncrementWrap,  // 4 IncrementWrap
		metal.Format.StencilOperation.DecrementClamp, // 5 Decrement
		metal.Format.StencilOperation.DecrementWrap,  // 6 DecrementWrap
		metal.Format.StencilOperation.Invert,         // 7 Invert
	];

	static var BLEND : Array<Int> = [
		metal.Format.BlendFactor.One,                      // 0 One
		metal.Format.BlendFactor.Zero,                     // 1 Zero
		metal.Format.BlendFactor.SourceAlpha,              // 2 SrcAlpha
		metal.Format.BlendFactor.SourceColor,              // 3 SrcColor
		metal.Format.BlendFactor.DestinationAlpha,         // 4 DstAlpha
		metal.Format.BlendFactor.DestinationColor,         // 5 DstColor
		metal.Format.BlendFactor.OneMinusSourceAlpha,      // 6 OneMinusSrcAlpha
		metal.Format.BlendFactor.OneMinusSourceColor,      // 7 OneMinusSrcColor
		metal.Format.BlendFactor.OneMinusDestinationAlpha, // 8 OneMinusDstAlpha
		metal.Format.BlendFactor.OneMinusDestinationColor, // 9 OneMinusDstColor
		metal.Format.BlendFactor.SourceAlpha,              // 10 ConstantColor -> approximate with SrcAlpha
		metal.Format.BlendFactor.SourceAlpha,              // 11 ConstantAlpha -> approximate with SrcAlpha
		metal.Format.BlendFactor.OneMinusSourceAlpha,      // 12 OneMinusConstantColor -> approximate
		metal.Format.BlendFactor.OneMinusSourceAlpha,      // 13 OneMinusConstantAlpha -> approximate
		metal.Format.BlendFactor.SourceAlphaSaturated,     // 14 SrcAlphaSaturate
	];

	static var BLEND_OP : Array<Int> = [
		metal.Format.BlendOperation.Add,             // 0 Add
		metal.Format.BlendOperation.Subtract,        // 1 Sub
		metal.Format.BlendOperation.ReverseSubtract, // 2 ReverseSub
		metal.Format.BlendOperation.Min,             // 3 Min
		metal.Format.BlendOperation.Max,             // 4 Max
	];

	static inline var SCISSOR_BIT = Pass.reserved_mask;

	override function selectMaterial( pass : h3d.mat.Pass ) {
		var bits = @:privateAccess pass.bits;
		var mask = pass.colorMask;
		var st = pass.stencil;

		var stOpBits = st != null ? @:privateAccess st.opBits : -1;
		var stMaskBits = st != null ? @:privateAccess st.maskBits : -1;

		if( !pipelineDirty && bits == currentMaterialBits && stOpBits == currentStencilOpBits && stMaskBits == currentStencilMaskBits )
			return;

		currentMaterialBits = bits;
		currentStencilOpBits = stOpBits;
		currentStencilMaskBits = stMaskBits;

		allowDraw = pass.culling != Both;

		// Cull mode
		var cull = pass.culling;
		var cullInt = switch(cull) {
			case None: 0;
			case Back: 1;
			case Front: 2;
			case Both: 3;
		}
		if( cullInt != currentCullMode ) {
			currentCullMode = cullInt;
			if( cull == Both ) {
				MtlDrv.setCullMode(metal.Format.CullMode.None); // draw skipped by allowDraw
			} else {
				MtlDrv.setCullMode(switch(cull) {
					case None: metal.Format.CullMode.None;
					case Front: metal.Format.CullMode.Front;
					case Back: metal.Format.CullMode.Back;
					case Both: metal.Format.CullMode.None;
				});
			}
			MtlDrv.setFrontFacingWinding(metal.Format.Winding.CounterClockwise);
		}

		// Depth/stencil state — only when current render pass has a depth attachment
		if( passHasDepth ) {
			var depthBits = bits & (Pass.depthWrite_mask | Pass.depthTest_mask);
			var stencilKey = depthBits | (stOpBits << 16) | (stMaskBits << 24);
			var depthStencil = depthStencilStates.get(stencilKey);
			if( depthStencil == null ) {
				var cmp = Pass.getDepthTest(bits);
				var depthWrite = Pass.getDepthWrite(bits) != 0;
				var stencilCompare = st != null ? COMPARE[st.frontTest.getIndex()] : 0;
				var stencilFailOp = st != null ? STENCIL_OP[st.frontSTfail.getIndex()] : metal.Format.StencilOperation.Keep;
				var stencilDepthFailOp = st != null ? STENCIL_OP[st.frontDPfail.getIndex()] : metal.Format.StencilOperation.Keep;
				var stencilPassOp = st != null ? STENCIL_OP[st.frontPass.getIndex()] : metal.Format.StencilOperation.Keep;
				var readMask = st != null ? st.readMask : 0xFF;
				var writeMask = st != null ? st.writeMask : 0xFF;

				depthStencil = MtlDrv.createDepthStencilState(
					cmp != 0 ? COMPARE[cmp] : metal.Format.CompareFunction.Always,
					depthWrite,
					stencilCompare, stencilFailOp, stencilDepthFailOp, stencilPassOp,
					readMask, writeMask
				);
				depthStencilStates.set(stencilKey, depthStencil);
			}
			if( depthStencil != currentDepthStencilState || (st != null && st.reference != currentStencilRef) ) {
				currentDepthStencilState = depthStencil;
				currentStencilRef = st != null ? st.reference : 0;
				MtlDrv.setDepthStencilState(depthStencil);
				MtlDrv.setStencilRef(currentStencilRef);
			}
		}

		// Rebuild pipeline with blend state if shader is selected
		if( currentShader != null ) {
			var blendDesc = new BlendDesc();
			blendDesc.sourceRGBBlendFactor = BLEND[Pass.getBlendSrc(bits)];
			blendDesc.destinationRGBBlendFactor = BLEND[Pass.getBlendDst(bits)];
			blendDesc.rgbBlendOperation = BLEND_OP[Pass.getBlendOp(bits)];
			blendDesc.sourceAlphaBlendFactor = BLEND[Pass.getBlendAlphaSrc(bits)];
			blendDesc.destinationAlphaBlendFactor = BLEND[Pass.getBlendAlphaDst(bits)];
			blendDesc.alphaBlendOperation = BLEND_OP[Pass.getBlendAlphaOp(bits)];
			blendDesc.writeMask = mask & 15;

			var pipeColorFmt = passHasColor ? curColorFormat : 0;
			var pipeDepthFmt = passHasDepth ? cast PixelFormat.Depth32Float : 0;
			var cacheKey = pipelineKey(currentShader.shader.id, bits, mask, pipeColorFmt, pipeDepthFmt);
			var pipeline = pipelineCache.get(cacheKey);
			if( pipeline == null ) {
				var stride = currentShader.format.strideBytes;
				pipeline = makePipelineWithBlend(currentShader, blendDesc, pipeColorFmt, pipeDepthFmt, stride);
				pipelineCache.set(cacheKey, pipeline);
			}
			MtlDrv.setRenderPipeline(pipeline);
		}
		pipelineDirty = false;
	}

	// ---- Shader Buffer Upload ----

	function uploadShaderBuffer( gpuBuffer : Buffer, buffer : haxe.ds.Vector<hxd.impl.Float32>, size : Int, prevContent : hl.Bytes ) {
		if( size == 0 ) return;
		var data = hl.Bytes.getArray(buffer.toData());
		var bytes = size << 4;
		if( prevContent != null ) {
			if( prevContent.compare(0, data, 0, bytes) == 0 )
				return;
			prevContent.blit(0, data, 0, bytes);
		}
		var contents = gpuBuffer.contents();
		contents.blit(0, data, 0, bytes);
	}

	override function uploadShaderBuffers( buffers : h3d.shader.Buffers, which : h3d.shader.Buffers.BufferKind ) {
		if( currentShader == null ) return;
		uploadBuffers(buffers, currentShader.vertex, buffers.vertex, which, true);
		uploadBuffers(buffers, currentShader.fragment, buffers.fragment, which, false);
	}

	function uploadBuffers( buf : h3d.shader.Buffers, shader : ShaderContext, buffers : h3d.shader.Buffers.ShaderBuffers, which : h3d.shader.Buffers.BufferKind, isVertex : Bool ) {
		switch( which ) {
		case Globals:
			if( shader.globalsSize > 0 && shader.globals != null ) {
				uploadShaderBuffer(shader.globals, buffers.globals, shader.globalsSize, null);
				if( isVertex )
					MtlDrv.setVertexBuffer(shader.globals, 0, 0);
				else
					MtlDrv.setFragmentBuffer(shader.globals, 0, 0);
			}
		case Params:
			if( shader.paramsSize > 0 && shader.params != null ) {
				// Use per-draw buffer from pool to avoid overwriting params between draws
				var bytes = shader.paramsSize << 4;
				var pbuf;
				if( paramsPoolIdx < paramsPool.length && paramsPool[paramsPoolIdx].size >= bytes ) {
					pbuf = paramsPool[paramsPoolIdx].buf;
				} else {
					pbuf = MtlDrv.createBuffer(bytes, ResourceOptions.StorageModeShared);
					if( paramsPoolIdx < paramsPool.length )
						paramsPool[paramsPoolIdx] = { buf : pbuf, size : bytes };
					else
						paramsPool.push({ buf : pbuf, size : bytes });
				}
				paramsPoolIdx++;
				var data = hl.Bytes.getArray(buffers.params.toData());
				var contents = pbuf.contents();
				contents.blit(0, data, 0, bytes);
				if( isVertex )
					MtlDrv.setVertexBuffer(pbuf, 0, 1);
				else
					MtlDrv.setFragmentBuffer(pbuf, 0, 1);
			}
		case Textures:
			for( i in 0...shader.texturesCount ) {
				var t = buffers.tex[i];
				var tt = shader.texturesTypes[i];
				if( t == null || t.isDisposed() ) {
					switch( tt ) {
					case TSampler(T2D, _):
						var color = h3d.mat.Defaults.loadingTextureColor;
						t = h3d.mat.Texture.fromColor(color, (color >>> 24) / 255);
					case TSampler(TCube, _):
						t = h3d.mat.Texture.defaultCubeTexture();
					default:
						throw "Missing texture";
					}
				}
				if( t != null && t.t == null && t.realloc != null ) {
					t.alloc();
					t.realloc();
				}
				t.lastFrame = frame;
				if( t.t != null ) {
					var tex = t.t.res;
					if( isVertex ) {
						if( currentVertexTextures[i] != tex ) {
							currentVertexTextures[i] = tex;
							MtlDrv.setVertexTexture(tex, i);
						}
					} else {
						if( currentFragmentTextures[i] != tex ) {
							currentFragmentTextures[i] = tex;
							MtlDrv.setFragmentTexture(tex, i);
						}
					}

					// Sampler
					var samplerBits = @:privateAccess t.bits & ~h3d.mat.Texture.__startingMip_mask;
					var sampler = samplerStates.get(samplerBits);
					if( sampler == null ) {
						var minFilter = switch( [t.mipMap, t.filter] ) {
						case [None, Nearest]: SamplerMinMagFilter.Nearest;
						case [None, Linear]: SamplerMinMagFilter.Linear;
						case [Nearest, Nearest]: SamplerMinMagFilter.Nearest;
						case [Nearest, Linear]: SamplerMinMagFilter.Linear;
						case [Linear, Nearest]: SamplerMinMagFilter.Nearest;
						case [Linear, Linear]: SamplerMinMagFilter.Linear;
						default: SamplerMinMagFilter.Linear;
						};
						var magFilter = t.filter == Nearest ? SamplerMinMagFilter.Nearest : SamplerMinMagFilter.Linear;
						var mipFilter = t.mipMap == None ? SamplerMinMagFilter.Nearest : SamplerMinMagFilter.Linear;
						var addressMode = switch( t.wrap ) {
						case Clamp: SamplerAddressMode.ClampToEdge;
						case Repeat: SamplerAddressMode.Repeat;
						case Mirror: SamplerAddressMode.MirrorRepeat;
						};
						sampler = MtlDrv.createSamplerState(minFilter, magFilter, mipFilter,
							addressMode, addressMode, addressMode,
							0, 1e30, t.anisotropicMaxLevel, 0);
						samplerStates.set(samplerBits, sampler);
					}
					if( isVertex ) {
						if( currentVertexSamplers[i] != sampler ) {
							currentVertexSamplers[i] = sampler;
							MtlDrv.setVertexSampler(sampler, i);
						}
					} else {
						if( currentFragmentSamplers[i] != sampler ) {
							currentFragmentSamplers[i] = sampler;
							MtlDrv.setFragmentSampler(sampler, i);
						}
					}
				}
			}
		case Buffers:
			for( i in 0...shader.bufferCount ) {
				var buf = buffers.buffers[i];
				if( buf != null && buf.vbuf != null ) {
					var idx = i + 2; // after globals(0) and params(1)
					if( isVertex )
						MtlDrv.setVertexBuffer(buf.vbuf, 0, idx);
					else
						MtlDrv.setFragmentBuffer(buf.vbuf, 0, idx);
				}
			}
		}
	}

	override function flushShaderBuffers() {
		// No-op for Metal; buffers are uploaded immediately
	}

	// ---- Drawing ----

	override function selectBuffer( buffer : h3d.Buffer ) {
		if( currentShader == null ) return;
		// Buffer 0=globals, 1=params, 2=vertex data
		MtlDrv.setVertexBuffer(buffer.vbuf, 0, 2);
	}

	override function selectMultiBuffers( format : hxd.BufferFormat.MultiFormat, buffers : Array<h3d.Buffer> ) {
		if( currentShader == null ) return;
		var map = format.resolveMapping(currentShader.format);
		for( i in 0...map.length ) {
			var inf = map[i];
			var buf = buffers[inf.bufferIndex];
			MtlDrv.setVertexBuffer(buf.vbuf, inf.offset, i + 2);
		}
	}

	override function draw( ibuf : h3d.Buffer, startIndex : Int, ntriangles : Int ) {
		if( !allowDraw ) return;
		if( currentIndex != ibuf ) {
			currentIndex = ibuf;
		}
		if( ibuf.vbuf == null ) return;
		var indexType = ibuf.format.strideBytes == 4 ? IndexType.UInt32 : IndexType.UInt16;
		MtlDrv.drawIndexedPrimitives(
			PrimitiveType.Triangle,
			ntriangles * 3,
			indexType,
			ibuf.vbuf,
			startIndex * ibuf.format.strideBytes,
			1, 0, 0
		);
	}
	override function drawInstanced( ibuf : h3d.Buffer, commands : h3d.impl.InstanceBuffer ) {
		if( !allowDraw ) return;
		if( currentIndex != ibuf ) {
			currentIndex = ibuf;
		}
		var indexType = ibuf.format.strideBytes == 4 ? IndexType.UInt32 : IndexType.UInt16;
		MtlDrv.drawIndexedPrimitives(
			PrimitiveType.Triangle,
			commands.indexCount,
			indexType,
			ibuf.vbuf,
			commands.startIndex * ibuf.format.strideBytes,
			commands.commandCount, 0, 0
		);
	}

	// ---- Render Targets ----

	function resetRenderState() {
		// Metal does not inherit state between render encoders.
		// Reset cached state so it gets re-applied on first draw.
		currentDepthStencilState = null;
		currentMaterialBits = -1;
		currentShader = null;
		currentCullMode = -1;
		pipelineDirty = true;
		for( i in 0...MAX_TEXTURES ) {
			currentFragmentTextures[i] = null;
			currentFragmentSamplers[i] = null;
			currentVertexTextures[i] = null;
			currentVertexSamplers[i] = null;
		}
		curVPX = -1;
		curVPY = -1;
		curVPW = -1;
		curVPH = -1;
		curVPZN = -1;
		curVPZF = -1;
	}

	function setViewportCached(x:Float, y:Float, w:Float, h:Float, zn:Float, zf:Float) {
		if( x == curVPX && y == curVPY && w == curVPW && h == curVPH && zn == curVPZN && zf == curVPZF )
			return;
		curVPX = x; curVPY = y; curVPW = w; curVPH = h; curVPZN = zn; curVPZF = zf;
		MtlDrv.setViewport(x, y, w, h, zn, zf);
	}

	function beginDefaultPass( r : Float, g : Float, b : Float, a : Float, depth : Float, stencil : Int ) {
		MtlDrv.beginRenderPass(r, g, b, a, depth, stencil, defaultDepthTex);
		inRenderPass = true;
		passHasColor = true;
		passHasDepth = true;
		curColorFormat = cast PixelFormat.BGRA8Unorm;
		resetRenderState();
		setViewportCached(0, 0, outputWidth, outputHeight, 0, 1);
	}

	var tmpTextures = new Array<h3d.mat.Texture>();

	override function setRenderTarget( tex : Null<h3d.mat.Texture>, layer = 0, mipLevel = 0, depthBinding : h3d.Engine.DepthBinding = ReadWrite ) {
		if( tex == null ) {
			if( curTexture != null || curDepthOnlyTex != null ) {
				// Switching from texture/depth target back to backbuffer — end current pass
				if( inRenderPass ) {
					MtlDrv.endRenderPass();
					inRenderPass = false;
				}
				curTexture = null;
				curDepthOnlyTex = null;
				// Begin new default render pass for backbuffer
				beginDefaultPass(0, 0, 0, 0, 1.0, 0);
			}
			setViewportCached(0, 0, outputWidth, outputHeight, 0, 1);
			return;
		}
		tmpTextures[0] = tex;
		_setRenderTargets(tmpTextures, layer, mipLevel, depthBinding);
	}

	override function setRenderTargets( textures : Array<h3d.mat.Texture>, depthBinding : h3d.Engine.DepthBinding = ReadWrite ) {
		_setRenderTargets(textures, 0, 0, depthBinding);
	}

	function _setRenderTargets( textures : Array<h3d.mat.Texture>, layer : Int, mipLevel : Int, depthBinding : h3d.Engine.DepthBinding = ReadWrite ) {
		if( textures.length == 0 ) {
			setRenderTarget(null, depthBinding);
			return;
		}

		var tex = textures[0];
		curTexture = tex;

		// End current render pass if any
		if( inRenderPass ) {
			MtlDrv.endRenderPass();
			inRenderPass = false;
		}

		// Ensure textures are allocated
		for( t in textures ) {
			if( t.t == null ) t.alloc();
			t.lastFrame = frame;
		}

		// Begin new render pass targeting the first texture
		// For now, use beginRenderPass with clear values (will be overridden by clear())
		var hasDepth = tex.depthBuffer != null;
		var depthTex : Texture = null;
		if( hasDepth ) {
			depthTex = @:privateAccess tex.depthBuffer.t;
		}

		// Use the extended render pass API for render-to-texture
		MtlDrv.beginRenderPassEx(
			tex.t.res, LoadAction.Clear, StoreAction.Store,
			0, 0, 0, 0,
			depthTex != null ? depthTex.res : null,
			LoadAction.Clear, StoreAction.Store,
			1.0
		);
		inRenderPass = true;
		passHasColor = true;
		passHasDepth = depthTex != null;
		curColorFormat = getPixelFormat(tex);
		resetRenderState();

		var w = tex.width >> mipLevel; if( w == 0 ) w = 1;
		var h = tex.height >> mipLevel; if( h == 0 ) h = 1;
		setViewportCached(0, 0, w, h, 0, 1);
	}

	override function setDepth( depthBuffer : Null<h3d.mat.Texture> ) {
		if( depthBuffer == null ) return;
		// End current render pass if active
		if( inRenderPass ) {
			MtlDrv.endRenderPass();
			inRenderPass = false;
		}
		// Begin depth-only render pass (no color attachment)
		var depthTex = @:privateAccess depthBuffer.t;
		if( depthTex == null ) return;
		MtlDrv.beginDepthOnlyPass(depthTex.res, 1.0);
		inRenderPass = true;
		passHasColor = false;
		passHasDepth = true;
		resetRenderState();
		// Track depth-only state so clear() can restart depth-only pass
		curDepthOnlyTex = depthTex.res;
		curDepthOnlyW = depthBuffer.width;
		curDepthOnlyH = depthBuffer.height;
		setViewportCached(0, 0, curDepthOnlyW, curDepthOnlyH, 0, 1);
	}

	override function clear( ?color : h3d.Vector4, ?depth : Float, ?stencil : Int ) {
		// Metal clear is done at render pass begin time
		// For now, we do a pass restart with clear values
		if( inRenderPass ) {
			MtlDrv.endRenderPass();
			inRenderPass = false;
		}

		var cr = 0.0, cg = 0.0, cb = 0.0, ca = 0.0;
		if( color != null ) {
			cr = color.r;
			cg = color.g;
			cb = color.b;
			ca = color.a;
		}
		var d = depth != null ? depth : 1.0;
		var s = stencil != null ? stencil : 0;

		if( curDepthOnlyTex != null ) {
			// Restart depth-only pass (shadow map pass)
			MtlDrv.beginDepthOnlyPass(curDepthOnlyTex, d);
			inRenderPass = true;
			passHasColor = false;
			passHasDepth = true;
			resetRenderState();
			setViewportCached(0, 0, curDepthOnlyW, curDepthOnlyH, 0, 1);
		} else if( curTexture != null ) {
			var hasDepth = curTexture.depthBuffer != null;
			var depthTex : Texture = hasDepth ? @:privateAccess curTexture.depthBuffer.t : null;
			MtlDrv.beginRenderPassEx(
				curTexture.t.res, LoadAction.Clear, StoreAction.Store,
				cr, cg, cb, ca,
				depthTex != null ? depthTex.res : null,
				depth != null || stencil != null ? LoadAction.Clear : LoadAction.DontCare,
				StoreAction.Store,
				d
			);
			inRenderPass = true;
			curColorFormat = getPixelFormat(curTexture);
			passHasColor = true;
			passHasDepth = depthTex != null;
		} else {
			beginDefaultPass(cr, cg, cb, ca, d, s);
		}
	}

	// ---- Viewport / Scissor ----

	override function setRenderZone( x : Int, y : Int, width : Int, height : Int ) {
		if( x == 0 && y == 0 && width < 0 && height < 0 ) {
			return;
		}
		if( width < 0 ) width = 0;
		if( height < 0 ) height = 0;
		MtlDrv.setScissorRect(x, y, width, height);
	}

	// ---- Resize ----

	override function resize( width : Int, height : Int ) {
		// Guard: hxd.Window returns 0 for Metal backend, causing Engine.onCreate
		// to pass (0,0) which clamps to (32,32) - far too small.
		// Use actual Metal window dimensions if available.
		if( metalWindow != null ) {
			var winW = metal.Window.getWidth(metalWindow);
			var winH = metal.Window.getHeight(metalWindow);
			if( winW > 0 && winH > 0 && (width < winW || height < winH) ) {
				width = winW;
				height = winH;
			}
		}
		outputWidth = width;
		outputHeight = height;
		if( !MtlDrv.resize(width, height) )
			throw "Failed to resize Metal drawable to " + width + "x" + height;
		if( defaultDepthInst != null ) @:privateAccess {
			defaultDepthInst.width = width;
			defaultDepthInst.height = height;
			if( defaultDepthInst.t != null ) disposeDepthBuffer(defaultDepthInst);
			defaultDepthInst.t = allocDepthBuffer(defaultDepthInst);
		}
		// Recreate defaultDepthTex to match new drawable size
		defaultDepthTex = MtlDrv.createTexture2D(width, height, cast PixelFormat.Depth32Float, 1, cast(TextureUsage.RenderTarget | TextureUsage.ShaderRead), cast StorageMode.Private);
		setViewportCached(0, 0, width, height, 0, 1);
	}

	// ---- Misc ----

	override function generateMipMaps( texture : h3d.mat.Texture ) {
		// Metal does not have a direct mipmap generation API like DX
		// Would need a blit command encoder
		throw "Mipmaps auto generation is not supported on Metal yet";
	}

	override function capturePixels( tex : h3d.mat.Texture, layer : Int, mipLevel : Int, ?region : h2d.col.IBounds ) : hxd.Pixels {
		if( tex.t == null ) return null;
		var x = 0, y = 0, w = tex.width, h = tex.height;
		if( region != null ) {
			if( region.xMax > w ) region.xMax = w;
			if( region.yMax > h ) region.yMax = h;
			if( region.xMin < 0 ) region.xMin = 0;
			if( region.yMin < 0 ) region.yMin = 0;
			x = region.xMin;
			y = region.yMin;
			w = region.width;
			h = region.height;
		}
		w >>= mipLevel; if( w == 0 ) w = 1;
		h >>= mipLevel; if( h == 0 ) h = 1;
		var pixels = hxd.Pixels.alloc(w, h, tex.format);
		var stride = hxd.Pixels.calcStride(w, tex.format);
		MtlDrv.textureReadPixels(tex.t.res, x, y, w, h, @:privateAccess pixels.bytes, stride);
		return pixels;
	}

	override function copyTexture( from : h3d.mat.Texture, to : h3d.mat.Texture ) {
		return false;
	}

	// ---- Debug ----

	override function setDebug( b : Bool ) {
	}

	override function beginEvent( name : String ) {
	}

	override function endEvent() {
	}

	// ---- Queries ----

	override function allocQuery( queryKind : QueryKind ) : Query {
		return null;
	}

	override function deleteQuery( q : Query ) {
	}

	override function beginQuery( q : Query ) {
	}

	override function endQuery( q : Query ) {
	}

	override function queryResultAvailable( q : Query ) {
		return true;
	}

	override function queryResult( q : Query ) {
		return 0.;
	}

	// ---- Compute ----

	override function computeDispatch( x : Int = 1, y : Int = 1, z : Int = 1, barrier : Bool = true ) {
		throw "Compute shaders are not implemented on Metal yet";
	}

	override function memoryBarrier() {
		throw "Compute shaders are not implemented on Metal yet";
	}

	// ---- Instance Buffer ----

	override function allocInstanceBuffer( b : h3d.impl.InstanceBuffer, bytes : haxe.io.Bytes ) {
		b.data = MtlDrv.createBuffer(b.commandCount * 5 * 4, ResourceOptions.StorageModeShared);
		// Upload initial data
		var contents = b.data.contents();
		contents.blit(0, @:privateAccess bytes.b, 0, b.commandCount * 5 * 4);
	}

	override function uploadInstanceBufferBytes( b : h3d.impl.InstanceBuffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
		var strideBytes = 5 * 4;
		var contents = b.data.contents();
		contents.blit(startVertex * strideBytes, @:privateAccess buf.b, bufPos, vertexCount * strideBytes);
	}

	override function disposeInstanceBuffer( b : h3d.impl.InstanceBuffer ) {
		b.data = null;
	}
}

#end

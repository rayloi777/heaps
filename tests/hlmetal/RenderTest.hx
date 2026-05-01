import metal.Window;
import metal.Driver;

typedef TestResult = { passed : Bool, reason : Null<String> };

class RenderTest {

    static var win : metal.Window.WindowHandle;
    static var driver : metal.Driver.DriverInstance;
    static var totalTests : Int = 0;
    static var passedTests : Int = 0;
    static var failures : Array<{ name : String, reason : String }> = [];

    public static function main() {
        // Initialize Metal
        win = Window.create("hlmetal render test", 800, 600);
        var layer = Window.getMetalLayer(win);
        driver = Driver.create(layer, 800, 600, 0);

        trace("=== Heaps hlmetal Rendering Test Suite ===");

        runTest("ColoredTriangle", testColoredTriangle);
        runTest("TexturedQuad", testTexturedQuad);
        runTest("LitCube", testLitCube);
        runTest("BlendModes", testBlendModes);

        // Report
        trace('Results: $passedTests/$totalTests passed');
        if( failures.length > 0 ) {
            trace("FAILURES:");
            for( f in failures )
                trace('  ${f.name}: ${f.reason}');
        }

        // Cleanup
        Driver.disposeDriver(driver);
        Window.destroy(win);

        if( failures.length > 0 ) Sys.exit(1);
    }

    static function runTest( name : String, testFn : Void -> TestResult ) {
        totalTests++;
        var result = testFn();
        if( result.passed ) {
            passedTests++;
            trace('[${totalTests}/4] $name ... PASS');
        } else {
            failures.push({ name : name, reason : result.reason });
            trace('[${totalTests}/4] $name ... FAIL: ${result.reason}');
        }
    }

    // ---- Test 1: Colored Triangle ----
    // Verifies: allocBuffer, uploadBufferData, drawIndexed, basic vertex/fragment shader pipeline
    static function testColoredTriangle() : TestResult {
        return renderOneFrame("triangle", function() {
            var msl = '#include <metal_stdlib>
using namespace metal;
struct vs_in { float3 position [[attribute(0)]]; float3 normal [[attribute(1)]]; };
struct vs_out { float4 position [[position]]; float4 color; };
vertex vs_out vertex_main(vs_in in [[stage_in]]) {
    vs_out out;
    out.position = float4(in.position, 1.0);
    out.color = float4(1.0, 0.3, 0.3, 1.0);
    return out;
}
fragment float4 fragment_main(vs_out in [[stage_in]]) { return in.color; }';
            var lib = Driver.compileShader(msl, "vertex_main");
            if( lib == null ) return { passed : false, reason : "Shader compile failed" };

            var layout = new hl.NativeArray(2);
            var e0 = new metal.Driver.LayoutElement(); e0.attributeIndex = 0; e0.bufferIndex = 0; e0.offset = 0; e0.format = metal.Format.VertexFormat.Float3;
            var e1 = new metal.Driver.LayoutElement(); e1.attributeIndex = 1; e1.bufferIndex = 0; e1.offset = 12; e1.format = metal.Format.VertexFormat.Float3;
            layout[0] = e0; layout[1] = e1;

            var blend = new metal.Driver.BlendDesc();
            var pipeline = Driver.createRenderPipeline(lib, "vertex_main", "fragment_main", layout, 2, 24, blend, metal.Format.PixelFormat.BGRA8Unorm, metal.Format.PixelFormat.Depth32Float);

            // Interleaved vertex data: pos(3) + normal(3) = 6 floats = 24 bytes per vertex, 3 vertices
            var vdata = new hl.Bytes(3 * 24);
            // Vertex 0: top (0, 0.5, 0), normal (0, 0, 1)
            vdata.setF32(0, 0.0);  vdata.setF32(4, 0.5);  vdata.setF32(8, 0.0);
            vdata.setF32(12, 0.0); vdata.setF32(16, 0.0); vdata.setF32(20, 1.0);
            // Vertex 1: bottom-left (-0.5, -0.5, 0), normal (0, 0, 1)
            vdata.setF32(24, -0.5); vdata.setF32(28, -0.5); vdata.setF32(32, 0.0);
            vdata.setF32(36, 0.0);  vdata.setF32(40, 0.0);  vdata.setF32(44, 1.0);
            // Vertex 2: bottom-right (0.5, -0.5, 0), normal (0, 0, 1)
            vdata.setF32(48, 0.5);  vdata.setF32(52, -0.5); vdata.setF32(56, 0.0);
            vdata.setF32(60, 0.0);  vdata.setF32(64, 0.0);  vdata.setF32(68, 1.0);

            var idx = new hl.Bytes(3 * 2);
            idx.setUI16(0, 0); idx.setUI16(2, 1); idx.setUI16(4, 2);

            var vbuf = Driver.createBuffer(3 * 24, metal.Format.ResourceOptions.StorageModeShared, vdata);
            var ibuf = Driver.createBuffer(3 * 2, metal.Format.ResourceOptions.StorageModeShared, idx);

            // Render one frame
            Driver.beginFrame();
            Driver.beginRenderPass(0.0, 0.0, 0.0, 1.0, 1.0, 0, null);
            Driver.setRenderPipeline(pipeline);
            Driver.setVertexBuffer(vbuf, 0, 0);
            Driver.drawIndexedPrimitives(metal.Format.PrimitiveType.Triangle, 3, metal.Format.IndexType.UInt16, ibuf, 0, 1, 0, 0);
            Driver.endRenderPass();
            Driver.present();
            Window.pollEvents(win);
            displaySeconds(2.0);

            return { passed : true, reason : null };
        });
    }

    // ---- Test 2: Textured Quad ----
    // Verifies: texture allocation, pixel upload, sampler binding, UV coordinates
    static function testTexturedQuad() : TestResult {
        return renderOneFrame("quad", function() {
            var msl = '#include <metal_stdlib>
using namespace metal;
struct vs_in { float3 position [[attribute(0)]]; float3 normal [[attribute(1)]]; float2 uv [[attribute(2)]]; };
struct vs_out { float4 position [[position]]; float2 uv; };
vertex vs_out vertex_main(vs_in in [[stage_in]]) {
    vs_out out;
    out.position = float4(in.position, 1.0);
    out.uv = in.uv;
    return out;
}
fragment float4 fragment_main(vs_out in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
    return tex.sample(s, in.uv);
}';
            var lib = Driver.compileShader(msl, "vertex_main");
            if( lib == null ) return { passed : false, reason : "Shader compile failed" };

            var layout = new hl.NativeArray(3);
            var e0 = new metal.Driver.LayoutElement(); e0.attributeIndex = 0; e0.bufferIndex = 0; e0.offset = 0;  e0.format = metal.Format.VertexFormat.Float3;
            var e1 = new metal.Driver.LayoutElement(); e1.attributeIndex = 1; e1.bufferIndex = 0; e1.offset = 12; e1.format = metal.Format.VertexFormat.Float3;
            var e2 = new metal.Driver.LayoutElement(); e2.attributeIndex = 2; e2.bufferIndex = 0; e2.offset = 24; e2.format = metal.Format.VertexFormat.Float2;
            layout[0] = e0; layout[1] = e1; layout[2] = e2;

            var blend = new metal.Driver.BlendDesc();
            var pipeline = Driver.createRenderPipeline(lib, "vertex_main", "fragment_main", layout, 3, 32, blend, metal.Format.PixelFormat.BGRA8Unorm, metal.Format.PixelFormat.Depth32Float);

            // Create 2x2 checkerboard texture (ShaderRead=1, StorageModeShared=0)
            var tex = Driver.createTexture2D(2, 2, metal.Format.PixelFormat.BGRA8Unorm, 1, metal.Format.TextureUsage.ShaderRead, metal.Format.StorageMode.Shared);
            var pixels = new hl.Bytes(16);
            // BGRA8Unorm: each pixel is BGRA as uint32 (little-endian)
            // White = 0xFFFFFFFF, Black = 0xFF000000
            pixels.setI32(0, 0xFFFFFFFF);   // white
            pixels.setI32(4, 0xFF000000);   // black
            pixels.setI32(8, 0xFF000000);   // black
            pixels.setI32(12, 0xFFFFFFFF);  // white
            Driver.textureReplaceRegion(tex, 0, 0, 0, 2, 2, pixels, 8);

            // Quad: 4 vertices, 6 indices
            // Stride = pos(3) + normal(3) + uv(2) = 8 floats = 32 bytes
            var vdata = new hl.Bytes(4 * 32);
            // v0: top-left
            vdata.setF32(0, -0.5); vdata.setF32(4, 0.5);  vdata.setF32(8, 0.0);
            vdata.setF32(12, 0.0);  vdata.setF32(16, 0.0); vdata.setF32(20, 1.0);
            vdata.setF32(24, 0.0);  vdata.setF32(28, 0.0);
            // v1: top-right
            vdata.setF32(32, 0.5);  vdata.setF32(36, 0.5);  vdata.setF32(40, 0.0);
            vdata.setF32(44, 0.0);  vdata.setF32(48, 0.0);  vdata.setF32(52, 1.0);
            vdata.setF32(56, 1.0);  vdata.setF32(60, 0.0);
            // v2: bottom-right
            vdata.setF32(64, 0.5);  vdata.setF32(68, -0.5); vdata.setF32(72, 0.0);
            vdata.setF32(76, 0.0);  vdata.setF32(80, 0.0);  vdata.setF32(84, 1.0);
            vdata.setF32(88, 1.0);  vdata.setF32(92, 1.0);
            // v3: bottom-left
            vdata.setF32(96, -0.5); vdata.setF32(100, -0.5); vdata.setF32(104, 0.0);
            vdata.setF32(108, 0.0); vdata.setF32(112, 0.0); vdata.setF32(116, 1.0);
            vdata.setF32(120, 0.0); vdata.setF32(124, 1.0);

            var idata = new hl.Bytes(6 * 2);
            idata.setUI16(0, 0); idata.setUI16(2, 1); idata.setUI16(4, 2);
            idata.setUI16(6, 0); idata.setUI16(8, 2); idata.setUI16(10, 3);

            var vbuf = Driver.createBuffer(4 * 32, metal.Format.ResourceOptions.StorageModeShared, vdata);
            var ibuf = Driver.createBuffer(6 * 2, metal.Format.ResourceOptions.StorageModeShared, idata);

            var sampler = Driver.createSamplerState(metal.Format.SamplerMinMagFilter.Linear, metal.Format.SamplerMinMagFilter.Linear, metal.Format.SamplerMinMagFilter.Linear, metal.Format.SamplerAddressMode.ClampToEdge, metal.Format.SamplerAddressMode.ClampToEdge, metal.Format.SamplerAddressMode.ClampToEdge, 0, 1e30, 1, 0);

            // Render
            Driver.beginFrame();
            Driver.beginRenderPass(0.0, 0.0, 0.0, 1.0, 1.0, 0, null);
            Driver.setRenderPipeline(pipeline);
            Driver.setVertexBuffer(vbuf, 0, 0);
            Driver.setFragmentTexture(tex, 0);
            Driver.setFragmentSampler(sampler, 0);
            Driver.drawIndexedPrimitives(metal.Format.PrimitiveType.Triangle, 6, metal.Format.IndexType.UInt16, ibuf, 0, 1, 0, 0);
            Driver.endRenderPass();
            Driver.present();
            Window.pollEvents(win);
            displaySeconds(2.0);

            return { passed : true, reason : null };
        });
    }

    // ---- Test 3: Lit Cube ----
    // Verifies: depth buffer, 36 indices (12 triangles), uniform buffers
    static function testLitCube() : TestResult {
        return renderOneFrame("cube", function() {
            var msl = '#include <metal_stdlib>
using namespace metal;
struct vs_in { float3 position [[attribute(0)]]; float3 normal [[attribute(1)]]; float2 uv [[attribute(2)]]; };
struct vs_out { float4 position [[position]]; float4 color; };
vertex vs_out vertex_main(vs_in in [[stage_in]], constant float4x4& mvp [[buffer(1)]]) {
    vs_out out;
    out.position = mvp * float4(in.position, 1.0);
    float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
    float diff = max(dot(normalize(in.normal), lightDir), 0.0);
    out.color = float4(float3(0.3, 0.7, 0.3) * (diff * 0.8 + 0.2), 1.0);
    return out;
}
fragment float4 fragment_main(vs_out in [[stage_in]]) { return in.color; }';
            var lib = Driver.compileShader(msl, "vertex_main");
            if( lib == null ) return { passed : false, reason : "Shader compile failed" };

            var layout = new hl.NativeArray(3);
            var e0 = new metal.Driver.LayoutElement(); e0.attributeIndex = 0; e0.bufferIndex = 0; e0.offset = 0;  e0.format = metal.Format.VertexFormat.Float3;
            var e1 = new metal.Driver.LayoutElement(); e1.attributeIndex = 1; e1.bufferIndex = 0; e1.offset = 12; e1.format = metal.Format.VertexFormat.Float3;
            var e2 = new metal.Driver.LayoutElement(); e2.attributeIndex = 2; e2.bufferIndex = 0; e2.offset = 24; e2.format = metal.Format.VertexFormat.Float2;
            layout[0] = e0; layout[1] = e1; layout[2] = e2;

            var blend = new metal.Driver.BlendDesc();
            var pipeline = Driver.createRenderPipeline(lib, "vertex_main", "fragment_main", layout, 3, 32, blend, metal.Format.PixelFormat.BGRA8Unorm, metal.Format.PixelFormat.Depth32Float);

            // Create depth texture (RenderTarget=4, Private=2)
            var depthTex = Driver.createTexture2D(800, 600, metal.Format.PixelFormat.Depth32Float, 1, metal.Format.TextureUsage.RenderTarget, metal.Format.StorageMode.Private);

            // Build cube: 6 faces x 4 vertices = 24 vertices, 6 faces x 6 indices = 36 indices
            var vdata = new hl.Bytes(24 * 32);
            var idata = new hl.Bytes(36 * 2);
            var vi = 0; var ii = 0;

            function face(x0,y0,z0, x1,y1,z1, x2,y2,z2, x3,y3,z3, nx,ny,nz) {
                var b = Std.int(vi / 32);
                // v0
                vdata.setF32(vi, x0); vdata.setF32(vi+4, y0); vdata.setF32(vi+8, z0);
                vdata.setF32(vi+12, nx); vdata.setF32(vi+16, ny); vdata.setF32(vi+20, nz);
                vdata.setF32(vi+24, 0.0); vdata.setF32(vi+28, 0.0);
                vi += 32;
                // v1
                vdata.setF32(vi, x1); vdata.setF32(vi+4, y1); vdata.setF32(vi+8, z1);
                vdata.setF32(vi+12, nx); vdata.setF32(vi+16, ny); vdata.setF32(vi+20, nz);
                vdata.setF32(vi+24, 1.0); vdata.setF32(vi+28, 0.0);
                vi += 32;
                // v2
                vdata.setF32(vi, x2); vdata.setF32(vi+4, y2); vdata.setF32(vi+8, z2);
                vdata.setF32(vi+12, nx); vdata.setF32(vi+16, ny); vdata.setF32(vi+20, nz);
                vdata.setF32(vi+24, 1.0); vdata.setF32(vi+28, 1.0);
                vi += 32;
                // v3
                vdata.setF32(vi, x3); vdata.setF32(vi+4, y3); vdata.setF32(vi+8, z3);
                vdata.setF32(vi+12, nx); vdata.setF32(vi+16, ny); vdata.setF32(vi+20, nz);
                vdata.setF32(vi+24, 0.0); vdata.setF32(vi+28, 1.0);
                vi += 32;
                // indices
                idata.setUI16(ii, b);   idata.setUI16(ii+2, b+1); idata.setUI16(ii+4, b+2);
                idata.setUI16(ii+6, b);   idata.setUI16(ii+8, b+2); idata.setUI16(ii+10, b+3);
                ii += 12;
            }
            face(-0.5,-0.5, 0.5,  0.5,-0.5, 0.5,  0.5, 0.5, 0.5, -0.5, 0.5, 0.5,  0, 0, 1);
            face( 0.5,-0.5,-0.5, -0.5,-0.5,-0.5, -0.5, 0.5,-0.5,  0.5, 0.5,-0.5,  0, 0,-1);
            face(-0.5,-0.5,-0.5, -0.5,-0.5, 0.5, -0.5, 0.5, 0.5, -0.5, 0.5,-0.5, -1, 0, 0);
            face( 0.5,-0.5, 0.5,  0.5,-0.5,-0.5,  0.5, 0.5,-0.5,  0.5, 0.5, 0.5,  1, 0, 0);
            face(-0.5, 0.5, 0.5,  0.5, 0.5, 0.5,  0.5, 0.5,-0.5, -0.5, 0.5,-0.5,  0, 1, 0);
            face(-0.5,-0.5,-0.5,  0.5,-0.5,-0.5,  0.5,-0.5, 0.5, -0.5,-0.5, 0.5,  0,-1, 0);

            var vbuf = Driver.createBuffer(24 * 32, metal.Format.ResourceOptions.StorageModeShared, vdata);
            var ibuf = Driver.createBuffer(36 * 2, metal.Format.ResourceOptions.StorageModeShared, idata);

            // MVP = Perspective(fov=60, aspect=4/3, near=0.1, far=10) * View(translate z by -3)
            // Column-major 4x4 stored as 16 floats
            var mvp = new hl.Bytes(64);
            for( i in 0...16 ) mvp.setF32(i * 4, 0.0);
            // Column 0: row0=1.299 (f/aspect)
            mvp.setF32(0, 1.299038);
            // Column 1: row1=1.732 (f)
            mvp.setF32(20, 1.732051);
            // Column 2: row2=-1.0101 (far/(near-far)), row3=-1
            mvp.setF32(40, -1.010101);
            mvp.setF32(44, -1.0);
            // Column 3: row2=2.92929, row3=3
            mvp.setF32(56, 2.929293);
            mvp.setF32(60, 3.0);
            var mvpBuf = Driver.createBuffer(64, metal.Format.ResourceOptions.StorageModeShared, mvp);

            // Render with depth
            Driver.beginFrame();
            Driver.beginRenderPass(0.0, 0.0, 0.0, 1.0, 1.0, 0, depthTex);
            Driver.setRenderPipeline(pipeline);
            Driver.setVertexBuffer(vbuf, 0, 0);     // vertex data at buffer index 0
            Driver.setVertexBuffer(mvpBuf, 0, 1);   // MVP at buffer index 1 (shader uses [[buffer(1)]])
            Driver.drawIndexedPrimitives(metal.Format.PrimitiveType.Triangle, 36, metal.Format.IndexType.UInt16, ibuf, 0, 1, 0, 0);
            Driver.endRenderPass();
            Driver.present();
            Window.pollEvents(win);
            displaySeconds(2.0);

            return { passed : true, reason : null };
        });
    }

    // ---- Test 4: Blend Modes ----
    // Verifies: alpha blending pipeline state
    static function testBlendModes() : TestResult {
        return renderOneFrame("blend", function() {
            var msl = '#include <metal_stdlib>
using namespace metal;
struct vs_in { float3 position [[attribute(0)]]; float3 normal [[attribute(1)]]; };
struct vs_out { float4 position [[position]]; float4 color; };
vertex vs_out vertex_main(vs_in in [[stage_in]]) {
    vs_out out;
    out.position = float4(in.position, 1.0);
    out.color = float4(1.0, 0.0, 0.0, 0.5);
    return out;
}
fragment float4 fragment_main(vs_out in [[stage_in]]) { return in.color; }';
            var lib = Driver.compileShader(msl, "vertex_main");
            if( lib == null ) return { passed : false, reason : "Shader compile failed" };

            var layout = new hl.NativeArray(2);
            var e0 = new metal.Driver.LayoutElement(); e0.attributeIndex = 0; e0.bufferIndex = 0; e0.offset = 0;  e0.format = metal.Format.VertexFormat.Float3;
            var e1 = new metal.Driver.LayoutElement(); e1.attributeIndex = 1; e1.bufferIndex = 0; e1.offset = 12; e1.format = metal.Format.VertexFormat.Float3;
            layout[0] = e0; layout[1] = e1;

            // Alpha blend pipeline
            var blend = new metal.Driver.BlendDesc();
            blend.sourceRGBBlendFactor = metal.Format.BlendFactor.SourceAlpha;
            blend.destinationRGBBlendFactor = metal.Format.BlendFactor.OneMinusSourceAlpha;
            blend.sourceAlphaBlendFactor = metal.Format.BlendFactor.SourceAlpha;
            blend.destinationAlphaBlendFactor = metal.Format.BlendFactor.OneMinusSourceAlpha;
            var pipeline = Driver.createRenderPipeline(lib, "vertex_main", "fragment_main", layout, 2, 24, blend, metal.Format.PixelFormat.BGRA8Unorm, metal.Format.PixelFormat.Depth32Float);

            // Quad: pos(3) + normal(3) = 24 bytes per vertex
            var vdata = new hl.Bytes(4 * 24);
            vdata.setF32(0, -0.5); vdata.setF32(4, 0.5);  vdata.setF32(8, 0.0); vdata.setF32(12, 0.0); vdata.setF32(16, 0.0); vdata.setF32(20, 1.0);
            vdata.setF32(24, 0.5);  vdata.setF32(28, 0.5);  vdata.setF32(32, 0.0); vdata.setF32(36, 0.0); vdata.setF32(40, 0.0); vdata.setF32(44, 1.0);
            vdata.setF32(48, 0.5);  vdata.setF32(52, -0.5); vdata.setF32(56, 0.0); vdata.setF32(60, 0.0); vdata.setF32(64, 0.0); vdata.setF32(68, 1.0);
            vdata.setF32(72, -0.5); vdata.setF32(76, -0.5); vdata.setF32(80, 0.0); vdata.setF32(84, 0.0); vdata.setF32(88, 0.0); vdata.setF32(92, 1.0);

            var idata = new hl.Bytes(6 * 2);
            idata.setUI16(0, 0); idata.setUI16(2, 1); idata.setUI16(4, 2);
            idata.setUI16(6, 0); idata.setUI16(8, 2); idata.setUI16(10, 3);

            var vbuf = Driver.createBuffer(4 * 24, metal.Format.ResourceOptions.StorageModeShared, vdata);
            var ibuf = Driver.createBuffer(6 * 2, metal.Format.ResourceOptions.StorageModeShared, idata);

            Driver.beginFrame();
            Driver.beginRenderPass(0.0, 0.0, 0.0, 1.0, 1.0, 0, null);
            Driver.setRenderPipeline(pipeline);
            Driver.setVertexBuffer(vbuf, 0, 0);
            Driver.drawIndexedPrimitives(metal.Format.PrimitiveType.Triangle, 6, metal.Format.IndexType.UInt16, ibuf, 0, 1, 0, 0);
            Driver.endRenderPass();
            Driver.present();
            Window.pollEvents(win);
            displaySeconds(2.0);

            return { passed : true, reason : null };
        });
    }

    // Helper: safely run a render test
    static function renderOneFrame( name : String, fn : Void -> TestResult ) : TestResult {
        try {
            return fn();
        } catch( e : Dynamic ) {
            var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
            return { passed : false, reason : Std.string(e) + "\n" + stack };
        }
    }

    // Keep window visible for N seconds, polling events
    static function displaySeconds( seconds : Float ) {
        var start = haxe.Timer.stamp();
        while( haxe.Timer.stamp() - start < seconds )
            Window.pollEvents(win);
    }
}

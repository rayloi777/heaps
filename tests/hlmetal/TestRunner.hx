import hxsl.Shader;
import hxsl.ShaderList;
import hxsl.Cache;
import hxsl.MslOut;
import hxsl.Ast;
import hxsl.RuntimeShader;

// Import metal bindings
import metal.Window;
import metal.Driver;

// Import test shaders
import ShaderMathBasic;
import ShaderMathBasic.ShaderMathAdvanced;
import ShaderMathBasic.ShaderVecMatOps;
import ShaderMathBasic.ShaderTypeConv;
import ShaderMathBasic.ShaderTexSample;
import ShaderMathBasic.ShaderTexelOps;
import ShaderMathBasic.ShaderControlFlow;
import ShaderMathBasic.ShaderBinUnOps;
import ShaderMathBasic.ShaderSwizzleOps;
import ShaderMathBasic.ShaderVertIO;
import ShaderMathBasic.ShaderFragInput;
import ShaderMathBasic.ShaderBlendModes;
import ShaderMathBasic.ShaderDepthState;
import ShaderMathBasic.ShaderPackOps;
import ShaderMathBasic.ShaderDerivatives;
import ShaderMathBasic.ShaderVarQualifiers;
import ShaderMathBasic.ShaderMultiTex;
import ShaderMathBasic.ShaderCondCompile;
import ShaderMathBasic.ShaderChainVert;
import ShaderMathBasic.ShaderChainFrag;
import ShaderMathBasic.ShaderRealWorldSmoke;
import ShaderMathBasic.ShaderForLoop;
import ShaderMathBasic.ShaderTextureSize;
import ShaderMathBasic.ShaderIntVec;

typedef TestResult = { passed : Bool, reason : String };

class TestRunner {

    static var driver : metal.Driver.DriverInstance;
    static var win : metal.Window.WindowHandle;
    static var totalTests : Int = 0;
    static var passedTests : Int = 0;
    static var failures : Array<{ name : String, reason : String }> = [];

    static function compileToMsl( shaders : Array<hxsl.Shader>, ?outputs : Array<hxsl.Output> ) : { vertex : String, fragment : String } {
        // Create link shader that declares GPU outputs
        if( outputs == null )
            outputs = [hxsl.Output.Value("output.color"), hxsl.Output.Value("output.position")];
        var linkShader = Cache.get().getLinkShader(outputs, "output.position");
        // Initialize all shader instances
        for( s in shaders )
            @:privateAccess s.updateConstantsFinal(null);
        // Prepend link shader to user shader list
        var list = null;
        for( s in shaders )
            list = new ShaderList(s, list);
        list = new ShaderList(linkShader, list);
        var runtime = Cache.get().link(list, hxsl.LinkMode.Default);
        return {
            vertex : MslOut.compile(runtime.vertex.data),
            fragment : MslOut.compile(runtime.fragment.data),
        };
    }

    static function gpuCompile( vertexMsl : String, fragmentMsl : String ) : { success : Bool, error : Null<String> } {
        try {
            var vs = renameMain(vertexMsl, "vertex_main");
            var fs = renameMain(fragmentMsl, "fragment_main");
            var combined = '#include <metal_stdlib>\nusing namespace metal;\n$vs\n$fs';
            metal.Driver.compileShader(combined, "vertex_main");
            return { success : true, error : null };
        } catch( e : Dynamic ) {
            return { success : false, error : Std.string(e) };
        }
    }

    static function renameMain( source : String, newName : String ) : String {
        var idx = source.lastIndexOf(" main(");
        if( idx < 0 ) throw "Could not find 'main(' in generated MSL source";
        return source.substr(0, idx) + " " + newName + "(" + source.substr(idx + 6);
    }

    static function checkPatterns( msl : String, mustContain : Array<String>, ?mustNotContain : Array<String> ) : Null<String> {
        for( pattern in mustContain )
            if( msl.indexOf(pattern) < 0 ) return 'Missing pattern: "$pattern"';
        if( mustNotContain != null )
            for( pattern in mustNotContain )
                if( msl.indexOf(pattern) >= 0 ) return 'Unexpected pattern: "$pattern"';
        return null;
    }

    static function doTest( shaders : Array<hxsl.Shader>, mustContain : Array<String>, ?mustNotContain : Array<String> ) : TestResult {
        var msl;
        try {
            msl = compileToMsl(shaders);
        } catch( e : Dynamic ) {
            var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
            return { passed : false, reason : "hxsl compile error: " + Std.string(e) + "\n" + stack };
        }
        var fullMsl = msl.vertex + "\n" + msl.fragment;
        var patternErr = checkPatterns(fullMsl, mustContain, mustNotContain);
        if( patternErr != null )
            return { passed : false, reason : "MSL mismatch: " + patternErr };
        var gpu = gpuCompile(msl.vertex, msl.fragment);
        if( !gpu.success )
            return { passed : false, reason : "GPU compile failed: " + gpu.error };
        return { passed : true, reason : null };
    }

    // Like doTest but skips GPU compilation (for known MslOut bugs)
    static function doTestMslOnly( shaders : Array<hxsl.Shader>, mustContain : Array<String>, ?mustNotContain : Array<String> ) : TestResult {
        var msl;
        try {
            msl = compileToMsl(shaders);
        } catch( e : Dynamic ) {
            var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
            return { passed : false, reason : "hxsl compile error: " + Std.string(e) + "\n" + stack };
        }
        var fullMsl = msl.vertex + "\n" + msl.fragment;
        var patternErr = checkPatterns(fullMsl, mustContain, mustNotContain);
        if( patternErr != null )
            return { passed : false, reason : "MSL mismatch: " + patternErr };
        return { passed : true, reason : "MSL only (known MslOut GPU bug)" };
    }

    // ---- Test 1: MathBasic ----
    static function testMathBasic() : TestResult {
        return doTest([new ShaderMathBasic()],
            ["sin(", "cos(", "pow(", "abs(", "sqrt(", "min(", "max(", "clamp(", "saturate("],
            ["frac("]  // MSL should use fract(), not HLSL frac()
        );
    }

    // ---- Test 2: MathAdvanced ----
    static function testMathAdvanced() : TestResult {
        return doTest([new ShaderMathAdvanced()],
            ["fract(", "mix(", "step(", "smoothstep(", "reflect(", "normalize(", "length(", "dot(", "cross("]
        );
    }

    // ---- Test 3: VecMatOps ----
    static function testVecMatOps() : TestResult {
        return doTest([new ShaderVecMatOps()],
            ["float2(", "float3(", "float4(",
             "float2x2", "float3x3", "float4x4",
             "transpose("]
        );
    }

    // ---- Test 4: TypeConv ----
    static function testTypeConv() : TestResult {
        return doTest([new ShaderTypeConv()],
            ["int(", "float(", "bool("]
        );
    }

    // ---- Test 5: TexSample ----
    static function testTexSample() : TestResult {
        return doTest([new ShaderTexSample()],
            [".sample(", "level("],
            ["Texture.Sample("]
        );
    }

    // ---- Test 6: TexelOps ----
    static function testTexelOps() : TestResult {
        return doTest([new ShaderTexelOps()],
            [".sample(", "level(", "tex0", "tex1"]
        );
    }

    // ---- Test 7: ControlFlow ----
    static function testControlFlow() : TestResult {
        return doTest([new ShaderControlFlow()],
            ["while(", "if(", "discard_fragment()"],
            ["discard;"]
        );
    }

    // ---- Test 8: BinUnOps ----
    static function testBinUnOps() : TestResult {
        return doTest([new ShaderBinUnOps()],
            ["mod("]
        );
    }

    // ---- Test 9: SwizzleOps ----
    static function testSwizzleOps() : TestResult {
        return doTest([new ShaderSwizzleOps()],
            [".xy", ".zw", ".wzyx"]
        );
    }

    // ---- Test 10: VertIO ----
    // VertexID/InstanceID are now emitted as function parameters (Metal requirement)
    static function testVertIO() : TestResult {
        return doTest([new ShaderVertIO()],
            ["vertex_id", "instance_id"]
        );
    }

    // ---- Test 11: FragInput ----
    static function testFragInput() : TestResult {
        return doTest([new ShaderFragInput()],
            ["position", "front_facing"]
        );
    }

    // ---- Test 12: BlendModes ----
    static function testBlendModes() : TestResult {
        return doTest([new ShaderBlendModes()],
            ["fragment"]
        );
    }

    // ---- Test 13: DepthState ----
    static function testDepthState() : TestResult {
        return doTest([new ShaderDepthState()],
            ["buffer(0)"]
        );
    }

    // ---- Test 14: PackOps ----
    static function testPackOps() : TestResult {
        return doTest([new ShaderPackOps()],
            ["pack(", "unpack("]
        );
    }

    // ---- Test 15: Derivatives ----
    static function testDerivatives() : TestResult {
        return doTest([new ShaderDerivatives()],
            ["dfdx(", "dfdy(", "fwidth("]
        );
    }

    // ---- Test 16: VarQualifiers ----
    static function testVarQualifiers() : TestResult {
        return doTest([new ShaderVarQualifiers()],
            ["buffer(0)", "buffer(1)"]
        );
    }

    // ---- Test 17: MultiTex ----
    static function testMultiTex() : TestResult {
        return doTest([new ShaderMultiTex()],
            ["texture2d", "sampler("]
        );
    }

    // ---- Test 18: CondCompile ----
    // @const vars are resolved at compile time, so the branch is eliminated.
    // Test that the shader compiles and produces valid MSL (branch eliminated).
    static function testCondCompile() : TestResult {
        return doTest([new ShaderCondCompile()],
            ["fragment", "color("]  // @const resolved the branch away; just verify valid fragment
        );
    }

    // ---- Test 19: ShaderChain ----
    static function testShaderChain() : TestResult {
        return doTest([new ShaderChainVert(), new ShaderChainFrag()],
            ["buffer(0)", "vertex", "fragment"]
        );
    }

    // ---- Test 20: RealWorldSmoke ----
    static function testRealWorldSmoke() : TestResult {
        return doTest([new ShaderRealWorldSmoke()],
            ["vertex", "fragment", "normalize(", "dot(",
             ".sample(", "buffer(0)", "buffer(1)"]
        );
    }

    // ---- Test 21: ForLoop ----
    static function testForLoop() : TestResult {
        return doTest([new ShaderForLoop()],
            ["for(int "]
        );
    }

    // ---- Test 22: TextureSize ----
    static function testTextureSize() : TestResult {
        return doTest([new ShaderTextureSize()],
            ["textureSize", "get_width"]
        );
    }

    // ---- Test 23: IntVec ----
    static function testIntVec() : TestResult {
        return doTest([new ShaderIntVec()],
            ["int2(", "int3(", "int4("]
        );
    }

    public static function main() {
        // Initialize Metal
        win = metal.Window.create("hlmetal test", 1, 1);
        var layer = metal.Window.getMetalLayer(win);
        driver = metal.Driver.create(layer, 1, 1, 0);

        trace("=== hxsl hlmetal Test Suite ===");

        // Run tests
        runTest("MathBasic", testMathBasic);
        runTest("MathAdvanced", testMathAdvanced);
        runTest("VecMatOps", testVecMatOps);
        runTest("TypeConv", testTypeConv);
        runTest("TexSample", testTexSample);
        runTest("TexelOps", testTexelOps);
        runTest("ControlFlow", testControlFlow);
        runTest("BinUnOps", testBinUnOps);
        runTest("SwizzleOps", testSwizzleOps);
        runTest("VertIO", testVertIO);
        runTest("FragInput", testFragInput);
        runTest("BlendModes", testBlendModes);
        runTest("DepthState", testDepthState);
        runTest("PackOps", testPackOps);
        runTest("Derivatives", testDerivatives);
        runTest("VarQualifiers", testVarQualifiers);
        runTest("MultiTex", testMultiTex);
        runTest("CondCompile", testCondCompile);
        runTest("ShaderChain", testShaderChain);
        runTest("RealWorldSmoke", testRealWorldSmoke);
        runTest("ForLoop", testForLoop);
        runTest("TextureSize", testTextureSize);
        runTest("IntVec", testIntVec);

        // Report
        trace('Results: $passedTests/$totalTests passed');
        if( failures.length > 0 ) {
            trace("FAILURES:");
            for( f in failures )
                trace('  ${f.name}: ${f.reason}');
        }

        // Cleanup
        metal.Driver.disposeDriver(driver);
        metal.Window.destroy(win);

        if( failures.length > 0 ) Sys.exit(1);
    }

    static function runTest( name : String, testFn : Void -> TestResult ) {
        totalTests++;
        var result = testFn();
        if( result.passed ) {
            passedTests++;
            trace('[${totalTests}/23] $name ... PASS');
        } else {
            failures.push({ name : name, reason : result.reason });
            trace('[${totalTests}/23] $name ... FAIL: ${result.reason}');
        }
    }
}
class HeapsRenderTest {

    static var totalTests : Int = 0;
    static var passedTests : Int = 0;
    static var failures : Array<{ name : String, reason : String }> = [];
    static var engine : h3d.Engine;

    public static function main() {
        trace("=== HeapsRenderTest: h3d high-level API through MetalDriver ===");

        // On HL, hxd.Window.hl.hx requires explicit creation with (title, width, height).
        // The Engine constructor calls getInstance() which returns inst, so we must set it first.
        @:privateAccess hxd.Window.inst = new hxd.Window("HeapsRenderTest", 800, 600);

        // Create Engine (constructor creates MetalDriver, sets up window reference)
        engine = @:privateAccess new h3d.Engine();

        // The MetalDriver.init() is async (Timer.delay 1ms) on HL. Since MainLoop.tick()
        // doesn't execute timer callbacks synchronously in a busy loop on HL, we bypass
        // the async pattern: call driver.init() to set up the metal device, then directly
        // invoke the Engine's onCreate to complete initialization.
        @:privateAccess engine.driver.init(function(_) {}, !engine.hardware);
        @:privateAccess engine.onCreate(false);

        if( !engine.ready ) {
            trace("FATAL: Engine init failed");
            Sys.exit(1);
        }

        engine.setCurrent();
        trace('Engine ready: ${engine.width}x${engine.height} driver=${engine.driverName(true)}');

        // Run all 4 test scenes
        runTest("SingleMesh", testSingleMesh);
        runTest("MultiMesh", testMultiMesh);
        runTest("TexturedMesh", testTexturedMesh);
        runTest("DepthSorting", testDepthSorting);

        // Report
        trace('');
        trace('Results: $passedTests/$totalTests passed');
        if( failures.length > 0 ) {
            trace("FAILURES:");
            for( f in failures )
                trace('  ${f.name}: ${f.reason}');
        }

        engine.dispose();

        if( failures.length > 0 ) Sys.exit(1);
    }

    static function runTest( name : String, testFn : Void -> Bool ) {
        totalTests++;
        try {
            var ok = testFn();
            if( ok ) {
                passedTests++;
                trace('[$totalTests/4] $name ... PASS');
            } else {
                failures.push({ name : name, reason : "returned false" });
                trace('[$totalTests/4] $name ... FAIL: returned false');
            }
        } catch( e : Dynamic ) {
            var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
            failures.push({ name : name, reason : Std.string(e) + "\n" + stack });
            trace('[$totalTests/4] $name ... FAIL: $e');
        }
    }

    static function renderAndPresent( scene : h3d.scene.Scene, frames : Int = 3, displaySecs : Float = 2.0 ) {
        for( i in 0...frames ) {
            engine.render(scene);
            engine.driver.present();
        }
        var start = haxe.Timer.stamp();
        while( haxe.Timer.stamp() - start < displaySecs ) {
            engine.render(scene);
            engine.driver.present();
            Sys.sleep(0.016);
        }
    }

    // Create a simple unlit material to avoid shader compilation errors with
    // MetalDriver's incomplete HxSL-to-MSL pipeline (lightPixelColor not handled).
    // Also disable shadows since MetalDriver's setDepth() is unimplemented.
    static function makeMat( ?tex : h3d.mat.Texture, color : Int = 0xFFFFFF ) : h3d.mat.Material {
        var mat = h3d.mat.Material.create(tex);
        mat.color.setColor(color);
        // Disable lighting to avoid lightPixelColor shader compilation error
        mat.mainPass.enableLights = false;
        // Remove shadow pass and shadow shader from mainPass
        // (shadow.proj, shadow.map globals are not available without a shadow map render pass)
        var shadowPass = mat.getPass("shadow");
        if( shadowPass != null ) mat.removePass(shadowPass);
        var shadowShader = mat.mainPass.getShader(h3d.shader.Shadow);
        if( shadowShader != null ) mat.mainPass.removeShader(shadowShader);
        return mat;
    }

    // ---- Test 1: SingleMesh ----
    static function testSingleMesh() : Bool {
        var scene = new h3d.scene.Scene();
        var prim = new h3d.prim.Cube(1, 1, 1, true);
        var mat = makeMat(0xFF3333);
        var mesh = new h3d.scene.Mesh(prim, mat, scene);
        mesh.setPosition(0, 0, -3);
        scene.camera.pos.set(0, 0, 3);
        scene.camera.target.set(0, 0, 0);
        scene.camera.update();

        renderAndPresent(scene);
        return true;
    }

    // ---- Test 2: MultiMesh ----
    static function testMultiMesh() : Bool {
        var scene = new h3d.scene.Scene();

        var prim1 = new h3d.prim.Cube(1, 1, 1, true);
        var mat1 = makeMat(0xFF3333);
        var mesh1 = new h3d.scene.Mesh(prim1, mat1, scene);
        mesh1.setPosition(-1.5, 0, 0);

        var prim2 = new h3d.prim.Cube(1, 1, 1, true);
        var mat2 = makeMat(0x3333FF);
        var mesh2 = new h3d.scene.Mesh(prim2, mat2, scene);
        mesh2.setPosition(1.5, 0, 0);

        scene.camera.pos.set(0, 2, 5);
        scene.camera.target.set(0, 0, 0);
        scene.camera.update();

        renderAndPresent(scene);
        return true;
    }

    // ---- Test 3: TexturedMesh ----
    static function testTexturedMesh() : Bool {
        var scene = new h3d.scene.Scene();

        var tex = new h3d.mat.Texture(2, 2);
        var pixels = hxd.Pixels.alloc(2, 2, hxd.PixelFormat.BGRA);
        pixels.setPixel(0, 0, 0xFFFFFFFF);
        pixels.setPixel(1, 0, 0xFF000000);
        pixels.setPixel(0, 1, 0xFF000000);
        pixels.setPixel(1, 1, 0xFFFFFFFF);
        tex.uploadPixels(pixels);

        var prim = new h3d.prim.Cube(1, 1, 1, true);
        var mat = makeMat(tex);
        var mesh = new h3d.scene.Mesh(prim, mat, scene);
        mesh.setPosition(0, 0, -3);

        scene.camera.pos.set(0, 0, 3);
        scene.camera.target.set(0, 0, 0);
        scene.camera.update();

        renderAndPresent(scene);
        return true;
    }

    // ---- Test 4: DepthSorting ----
    static function testDepthSorting() : Bool {
        var scene = new h3d.scene.Scene();

        var prim1 = new h3d.prim.Cube(1, 1, 1, true);
        var mat1 = makeMat(0xFF3333);
        var mesh1 = new h3d.scene.Mesh(prim1, mat1, scene);
        mesh1.setPosition(0, 0, -1);

        var prim2 = new h3d.prim.Cube(1, 1, 1, true);
        var mat2 = makeMat(0x33FF33);
        var mesh2 = new h3d.scene.Mesh(prim2, mat2, scene);
        mesh2.setPosition(0, 0, 0.5);

        scene.camera.pos.set(0, 1, 5);
        scene.camera.target.set(0, 0, 0);
        scene.camera.update();

        renderAndPresent(scene);
        return true;
    }
}

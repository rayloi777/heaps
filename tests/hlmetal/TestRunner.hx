import hxsl.Shader;
import hxsl.ShaderList;
import hxsl.Cache;
import hxsl.MslOut;
import hxsl.Ast;

// Import metal bindings
import metal.Window;
import metal.Driver;

typedef TestResult = { passed : Bool, ?reason : String };

class TestRunner {

    static var driver : metal.Driver.DriverInstance;
    static var win : metal.Window.WindowHandle;
    static var totalTests : Int = 0;
    static var passedTests : Int = 0;
    static var failures : Array<{ name : String, reason : String }> = [];

    public static function main() {
        // Initialize Metal
        win = metal.Window.create("hlmetal test", 1, 1);
        var layer = metal.Window.getMetalLayer(win);
        driver = metal.Driver.create(layer, 1, 1, 0);

        trace("=== hxsl hlmetal Test Suite ===");

        // TODO: tests will be added in later tasks

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
            trace('[${totalTests}/20] $name ... PASS');
        } else {
            failures.push({ name : name, reason : result.reason });
            trace('[${totalTests}/20] $name ... FAIL: ${result.reason}');
        }
    }
}
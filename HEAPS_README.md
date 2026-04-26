# Heaps Engine Architecture

> Deep technical analysis of the Heaps game engine internals. Target audience: engine contributors, customizers, and porters.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [High-Level Architecture](#2-high-level-architecture)
3. [hxd — Foundation Module](#3-hxd--foundation-module)
4. [h2d — 2D Rendering](#4-h2d--2d-rendering)
5. [h3d — 3D Rendering Engine](#5-h3d--3d-rendering-engine)
6. [Rendering Pipeline](#6-rendering-pipeline)
7. [hxsl — Shader Language](#7-hxsl--shader-language)
8. [Driver Implementation Guide](#8-driver-implementation-guide)
9. [Cross-Module Collaboration](#9-cross-module-collaboration)
10. [Platform-Specific Notes](#10-platform-specific-notes)

---

## 1. Introduction

Heaps is a cross-platform GPU game framework written in Haxe. It provides a unified high-level API for applications while leveraging platform-specific graphics APIs under the hood.

### Supported Platforms

| Platform | Graphics API | Haxe Flag |
|----------|-------------|-----------|
| JavaScript/WebGL | WebGL 1/2 | `js` |
| HashLink/OpenGL | OpenGL (SDL) | `hlsdl`, `usegl` |
| HashLink/DirectX 9 | DirectX 9 | `hldx` |
| HashLink/DirectX 12 | DirectX 12 | `hldx`, `dx12` |
| HashLink/Vulkan | Vulkan | `hlsdl`, `heaps_vulkan` |
| sys (desktop) | haxe.Graphics | `usesys` |
| Console | Vendor SDKs | Contact maintainers |

### Repository Structure

```
heaps/
├── hxd/          # Cross-platform foundation (window, input, resources)
├── h2d/          # 2D scene graph, sprites, UI
├── h3d/          # 3D rendering engine, scene graph
├── hxsl/         # Haxe Shader Language compiler
├── samples/      # Example applications
└── tools/        # Build tools (mesh converters, etc.)
```

---

## 2. High-Level Architecture

### Module Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│                         hxd                                │
│  (Window, Input, Res, App, System, Events, Stage)          │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌──────────────────┐ ┌────────────────┐ ┌──────────────┐
│       h2d        │ │      h3d       │ │    hxsl     │
│   (2D Scene)     │ │  (3D Engine)   │ │  (Shaders)  │
│                  │ │                │ │              │
│  h2d.Scene        │ │ h3d.Engine     │ │ hxsl.GlslOut│
│  h2d.Object       │ │ h3d.scene.*    │ │ hxsl.HlslOut│
│  h2d.Drawable    │ │ h3d.mat.*      │ │              │
│  h2d.Flow         │ │ h3d.impl.*     │ │              │
└──────────────────┘ └────────────────┘ └──────────────┘
```

### Conditional Compilation Map

The engine selects implementations at compile time:

```haxe
// h3d/Engine.hx — driver selection
#if js
    driver = new h3d.impl.GlDriver(antiAlias);
#elseif hlsdl
    #if heaps_vulkan
        driver = new h3d.impl.VulkanDriver();
    #else
        driver = new h3d.impl.GlDriver(antiAlias);
    #end
#elseif hldx && dx12
    driver = new h3d.impl.DX12Driver();
#elseif hldx
    driver = new h3d.impl.DirectXDriver();
#elseif usesys
    driver = new haxe.GraphicsDriver(antiAlias);
#end
```

---

## 3. hxd — Foundation Module

### 3.1 App Class

The `hxd.App` class is the central entry point for all Heaps applications. It orchestrates the engine, scenes, and main loop.

```haxe
class App implements h3d.IDrawable {
    public var engine(default,null) : h3d.Engine;
    public var s3d(default,null) : h3d.scene.Scene;   // 3D scene
    public var s2d(default,null) : h2d.Scene;         // 2D scene
    public var sevents(default,null) : hxd.SceneEvents; // Input events
}
```

**Lifecycle**:

```
new App()
  ├─► Engine.selected by compile flags
  ├─► engine.onReady = setup
  └─► hxd.System.start() → engine.init() → setup()

setup()
  ├─► s3d = new h3d.scene.Scene()
  ├─► s2d = new h2d.Scene()
  ├─► sevents = new hxd.SceneEvents()
  ├─► loadAssets(onLoaded)
  │     └─► init() [user override point]
  └─► mainLoop()

mainLoop()
  ├─► hxd.Timer.update()
  ├─► sevents.checkEvents()
  ├─► update(dt) [user override point]
  ├─► s2d.setElapsedTime(dt)
  ├─► s3d.setElapsedTime(dt)
  └─► engine.render(this)
        ├─► s3d.render(engine)
        └─► s2d.render(engine)
```

Key override points:
- `init()` — application initialization after assets loaded
- `update(dt)` — per-frame logic
- `loadAssets(onLoaded)` — async asset loading
- `onResize()` — window resize callback
- `onContextLost()` — GPU context loss handler

### 3.2 Window System

`hxd.Window` provides a platform-abstracted window with event targeting:

```haxe
class Window {
    static function getInstance():Window;

    // Properties
    var width(default, null):Int;
    var height(default, null):Int;
    var mouseX(default, null):Float;
    var mouseY(default, null):Float;
    var mouseLock:Bool;
    var mouseClip:Bool;
    var displayMode:DisplayMode;  // Windowed, Borderless, Fullscreen

    // Event system
    function addEventTarget(target:EventTarget):Void;
    function removeEventTarget(target:EventTarget):Void;
}
```

Platform implementations:
- `hxd.Window.hl.hx` — HashLink (SDL-based)
- `hxd.Window.js.hx` — JavaScript (DOM-based)

Mouse modes (`hxd.impl.MouseMode`):
- `Absolute` — standard mouse tracking
- `Relative()` — for pointer lock / FPS games
- `AbsoluteUnbound` — unclamped coordinates

### 3.3 Input System

**Keyboard (`hxd.Key`)**

Static API with frame-based state tracking:

```haxe
class Key {
    static function isDown(key:Int):Bool;      // currently held
    static function isPressed(key:Int):Bool;   // pressed this frame
    static function isReleased(key:Int):Bool;  // released this frame

    // Common constants
    static var BACKSPACE:Int;  var TAB:Int;  var ENTER:Int;
    static var SHIFT:Int;  var CTRL:Int;  var ALT:Int;
    static var A:Int ... Z:Int;  var F1:Int ... F24:Int;
    static var MOUSE_LEFT:Int;  var MOUSE_RIGHT:Int;  var MOUSE_MIDDLE:Int;
}
```

Location bits distinguish left/right modifier keys:
```haxe
var MOUSE_WHEEL_UP:Int;    // with LOC_LEFT = 256
var MOUSE_WHEEL_DOWN:Int;  // with LOC_LEFT = 256
```

**Gamepad (`hxd.Pad`)**

Configuration-based mapping with platform backends:

```haxe
class Pad {
    static var config:PadConfig;  // CONFIG_SDL, CONFIG_JS_STD, etc.

    var x:Float;  var y:Float;   // left stick
    var z:Float;  var w:Float;    // right stick
    var a:Float;  var b:Float;    // triggers

    var buttonA:Bool;  var buttonB:Bool;  // face buttons
    var start:Bool;  var select:Bool;

    static function wait():Pad;  // wait for connection
}
```

### 3.4 SceneEvents

The event routing system connects input to interactive objects:

```haxe
class SceneEvents {
    function addScene(scene:InteractiveScene, priority:Int):Void;
    function removeScene(scene:InteractiveScene):Void;
    function checkEvents():Void;  // called each frame
}
```

Event kinds:

```haxe
enum EventKind {
    EMove(dx:Float, dy:Float, X:Float, Y:Float);
    EPush(button:Int, X:Float, Y:Float);
    ERelease(button:Int, X:Float, Y:Float);
    EReleaseOutside(button:Int, X:Float, Y:Float);
    EKeyDown(key:Int, code:Int);
    EKeyUp(key:Int, code:Int);
    EWheel(delta:Int, X:Float, Y:Float);
    EFocus(f:Interactive);
    EFocusLost(f:Interactive);
}
```

Interactive objects implement `InteractiveScene`:

```haxe
interface InteractiveScene {
    function setEvents(s:SceneEvents):Void;
    function handleEvent(e:Event, last:Interactive):Interactive;
    function dispatchEvent(e:Event, to:Interactive):Void;
    function isInteractiveVisible(i:Interactive):Bool;
}
```

### 3.5 Resource System

Resources are accessed via the static `hxd.Res` API:

```haxe
class Res {
    static function initEmbed():Void;      // embedded files (default for samples)
    static function initLocal(?path:String):Void;  // local filesystem
    static function initPak(?path:String):Void;    // .pak archive

    static function load(name:Path):Resource;
}

// Usage:
var tex = hxd.Res.hxlogo.toTexture();
var bmp = hxd.Res.myImage.toBitmap();
var font = hxd.Res.myFont.toFont();
```

The `@:build(hxd.res.FileTree.build())` macro at compile time indexes all files in `res/` directories, generating `Resource` subclasses for each file. This provides type-safe resource access with compile-time errors for missing files.

Supported resource conversions:
- `toTexture()` → `h3d.mat.Texture`
- `toBitmap()` → `hxd.BitmapData`
- `toFont()` → `h2d.Font`
- `toPixels()` → `hxd.Pixels`

---

## 4. h2d — 2D Rendering

### 4.1 Scene

`h2d.Scene` is the root container for 2D rendering:

```haxe
class Scene extends Layers implements h3d.IDrawable {
    var width(default, null):Int;
    var height(default, null):Int;
    var scaleMode:ScaleMode;
    var cameras:ReadOnlyArray<Camera>;

    function render(engine:h3d.Engine):Void;
    function getInteractive(x:Float, y:Float):Interactive;
    function addCamera(cam:Camera, ?pos:Int):Void;
}
```

**ScaleMode** controls viewport behavior:

```haxe
enum ScaleMode {
    Resize;  // match window size
    LetterBox(w:Int, h:Int, integerScale:Bool, hAlign:Align, vAlign:Align);
    Fixed(w:Int, h:Int, zoom:Float, hAlign:Align, vAlign:Align);
    Zoom(level:Float);
    AutoZoom(minWidth:Int, minHeight:Int, integerScaling:Bool);
}
```

### 4.2 Object Transform System

All 2D elements inherit from `h2d.Object`. Transform uses a lazy 2x3 affine matrix:

```haxe
class Object {
    // Local transform
    var x:Float;  var y:Float;
    var scaleX:Float;  var scaleY:Float;
    var rotation:Float;  // radians

    // Derived (computed on demand)
    var matA:Float;  var matB:Float;  // row 0: [A B C]
    var matC:Float;  var matD:Float;  // row 1: [D E F]
    var absX:Float;  var absY:Float;   // translation

    var posChanged:Bool;  // dirty flag

    var parent:Object;
    var numChildren(default, null):Int;
}
```

**Transform calculation** (simplified):

```haxe
function calcAbsPos() {
    if (parent == null) {
        matA = scaleX;  matB = 0;
        matC = 0;       matD = scaleY;
        absX = x;       absY = y;
    } else {
        // M_local = S . R . T
        // M_absolute = M_local . M_parent
        if (rotation == 0) {
            matA = scaleX * parent.matA;
            matB = scaleX * parent.matB;
            matC = scaleY * parent.matC;
            matD = scaleY * parent.matD;
        } else {
            // rotation applied via cos/sin
        }
        absX = x * parent.matA + y * parent.matC + parent.absX;
        absY = x * parent.matB + y * parent.matD + parent.absY;
    }
    posChanged = false;
}
```

### 4.3 Drawable and Tile

`Drawable` is the base for all renderable 2D objects:

```haxe
class Drawable extends Object {
    var color:h3d.Vector4;      // RGBA multiplier
    var smooth:Null<Bool>;
    var tileWrap:Bool;
    var blendMode:BlendMode;
    var filter:h2d.filter.Filter;

    var shaders:hxsl.ShaderList;
}
```

**Tile** represents a texture region:

```haxe
class Tile {
    var innerTex:h3d.mat.Texture;
    var u:Float;  var v:Float;    // top-left UV
    var u2:Float; var v2:Float;    // bottom-right UV
    var x:Float;  var y:Float;     // source position
    var width:Float;  var height:Float;
    var dx:Float;  var dy:Float;   // visual offset

    // Factory methods
    static function fromColor(color:Int, w:Float, h:Float, ?alpha:Float):Tile;
    static function fromTexture(t:h3d.mat.Texture):Tile;
    static function autoCut(bmp:hxd.BitmapData, tw:Int, th:Int):Array<Tile>;
}
```

### 4.4 Text

Text rendering supports two modes:

```haxe
class Text extends Drawable {
    var font:Font;           // BitmapFont or SDF font
    var text:String;
    var textColor:Int;
    var maxWidth:Null<Float>;  // word-wrap width
    var dropShadow:{ dx:Float, dy:Float, color:Int, alpha:Float };
    var textAlign:Align;     // Left, Right, Center, MultilineRight, MultilineCenter
    var letterSpacing:Float;
    var lineSpacing:Float;
}
```

- **BitmapFont** — pre-rendered glyph tiles (fast, fixed resolution)
- **SignedDistanceField** — SDF rendering (scalable, smooth, requires shader support)

### 4.5 Flow Layout

`Flow` provides automatic layout similar to HTML flexbox:

```haxe
class Flow extends Object {
    var layout:FlowLayout;      // Horizontal, Vertical, Stack
    var overflow:FlowOverflow;  // Expand, Limit, Hidden, Scroll

    var horizontalAlign:FlowAlign;
    var verticalAlign:FlowAlign;

    var minWidth:Null<Int>;  var maxWidth:Null<Int>;
    var minHeight:Null<Int>; var maxHeight:Null<Int>;
    var horizontalSpacing:Int = 0;
    var verticalSpacing:Int = 0;

    function reflow():Void;
}
```

Per-child properties via `FlowProperties`:
```haxe
class FlowProperties {
    var paddingLeft:Int;  var paddingTop:Int;
    var paddingRight:Int; var paddingBottom:Int;
    var isAbsolute:Bool;  // opt out of layout
    var horizontalAlign:FlowAlign;
    var verticalAlign:FlowAlign;
    var lineBreak:Bool;   // force newline (for Horizontal layout)
}
```

### 4.6 2D RenderContext

The 2D render context manages batch rendering:

```haxe
class RenderContext {
    var engine:h3d.Engine;
    var frame:Int;
    var elapsedTime:Float;
    var globalAlpha:Float;

    // Viewport transform
    var viewA:Float;  var viewB:Float;
    var viewC:Float;  var viewD:Float;
    var viewX:Float;  var viewY:Float;

    function begin():Void;
    function beginDrawBatch(d:Drawable, tex:h3d.mat.Texture):Bool;
    function drawTile(d:Drawable, tile:Tile):Bool;
    function drawScene():Void;  // batch render all
    function end():Void;
}
```

Tiles are batched by texture to minimize state changes. Each batch emits a single draw call for all tiles sharing the same texture.

---

## 5. h3d — 3D Rendering Engine

### 5.1 Engine Core

`h3d.Engine` orchestrates rendering and manages the GPU driver:

```haxe
class Engine {
    var driver(default, null):h3d.impl.Driver;
    var mem(default, null):h3d.impl.MemoryManager;

    // Statistics
    var drawTriangles(default, null):Float;
    var drawCalls(default, null):Int;
    var dispatches(default, null):Int;
    var shaderSwitches(default, null):Int;

    // Render target stack
    function pushTarget(tex:h3d.mat.Texture, layer=0, mipLevel=0, depthBinding=ReadWrite):Void;
    function popTarget():Void;
    function pushTargets(textures:Array<h3d.mat.Texture>, depthBinding=ReadWrite):Void;
    function pushDepth(depthBuffer:h3d.mat.Texture):Void;

    // Frame boundaries
    function begin():Bool;
    function end():Void;
    function render(obj:{ function render(engine:Engine):Void; }):Bool;

    // Clear
    function clear(?color:Int, ?depth:Float, ?stencil:Int):Void;
    function clearF(color:h3d.Vector4, ?depth:Float, ?stencil:Int):Void;

    // Render zones (scissor)
    function setRenderZone(x=0, y=0, width=-1, height=-1):Void;

    // Drawing
    function renderTriBuffer(b:Buffer, start=0, max=-1):Void;
    function renderQuadBuffer(b:Buffer, start=0, max=-1):Void;
    function renderIndexed(b:Buffer, indexes:Indexes, startTri=0, drawTri=-1):Void;
    function renderInstanced(indexes:Indexes, commands:InstanceBuffer):Void;
}
```

### 5.2 Driver Abstraction

The `h3d.impl.Driver` base class defines the GPU API contract:

```haxe
class Driver {
    static var SHADER_CACHE:h3d.impl.ShaderCache;

    // Features
    function hasFeature(f:Feature):Bool;
    function setRenderFlag(r:RenderFlag, value:Int):Void;

    // Lifecycle
    function init(onCreate:Bool->Void, forceSoftware=false):Void;
    function resize(width:Int, height:Int):Void;
    function dispose():Void;
    function isDisposed():Bool;

    // Shader
    function selectShader(shader:hxsl.RuntimeShader):Bool;
    function selectMaterial(pass:h3d.mat.Pass):Void;
    function uploadShaderBuffers(buffers:h3d.shader.Buffers, which:BufferKind):Void;
    function flushShaderBuffers():Void;

    // Buffers
    function selectBuffer(buffer:Buffer):Void;
    function selectMultiBuffers(format:hxd.BufferFormat.MultiFormat, buffers:Array<Buffer>):Void;
    function allocBuffer(b:h3d.Buffer):GPUBuffer;
    function uploadBufferData(b:Buffer, startVertex:Int, vertexCount:Int, buf:hxd.FloatBuffer, bufPos:Int):Void;
    function disposeBuffer(b:Buffer):Void;

    // Drawing
    function draw(ibuf:Buffer, startIndex:Int, ntriangles:Int):Void;
    function drawInstanced(ibuf:Buffer, commands:h3d.impl.InstanceBuffer):Void;

    // Render targets
    function setRenderTarget(tex:h3d.mat.Texture, layer=0, mipLevel=0, depthBinding=DepthBinding):Void;
    function setRenderTargets(textures:Array<h3d.mat.Texture>, depthBinding:DepthBinding):Void;
    function setDepth(tex:h3d.mat.Texture):Void;
    function setDepthClamp(enabled:Bool):Void;
    function setDepthBias(depthBias:Float, slopeScaledBias:Float):Void;

    // Queries
    function allocQuery(kind:QueryKind):Query;
    function beginQuery(q:Query):Void;
    function endQuery(q:Query):Void;
    function queryResultAvailable(q:Query):Bool;
    function queryResult(q:Query):Float;

    // Compute
    function computeDispatch(x=1, y=1, z=1, barrier=true):Void;
    function memoryBarrier():Void;

    // Events (profiling)
    function beginEvent(name:String):Void;
    function endEvent():Void;
}
```

**Feature enum** advertises GPU capabilities:

```haxe
enum Feature {
    StandardDerivatives;   // ddx/ddy
    FloatTextures;         // floating point textures
    AllocDepthBuffer;      // custom depth buffers
    HardwareAccelerated;   // GPU vs CPU
    MultipleRenderTargets; // MRT
    Queries;               // occlusion/timing queries
    SRGBTextures;          // gamma-correct textures
    ShaderModel3;          // advanced shader ops
    BottomLeftCoords;      // OpenGL texture coords
    Wireframe;             // wireframe mode
    InstancedRendering;    // instanced draw calls
    Bindless;             // bindless textures
}
```

**QueryKind** for GPU profiling:

```haxe
enum QueryKind {
    TimeStamp;      // GPU timestamp (nanoseconds)
    Samples;        // samples passed depth
    TimeElapsed;    // elapsed time between begin/end
}
```

### 5.3 Memory Manager

`h3d.impl.MemoryManager` handles GPU buffer allocation:

```haxe
class MemoryManager {
    var driver:h3d.impl.Driver;
    var buffers:Array<Buffer>;

    function allocBuffer(b:Buffer):Void;
    function freeBuffer(b:Buffer):Void;
    function getBuffer(id:Int):Buffer;
    function getTriIndexes(v:Int):Indexes;  // prebuilt triangle indices
    function getQuadIndexes(v:Int):Indexes; // prebuilt quad indices
    function onContextLost():Void;
}
```

Triangle index buffer structure (for `vertCount` vertices):
```
Indices: [0,1,2, 0,2,3, 0,3,4, ...]  // 3 indices per triangle
```

Quad index buffer structure (for `vertCount` vertices):
```
Indices: [0,1,2, 0,2,3, 4,5,6, 4,6,7, ...]  // 2 triangles per quad
```

### 5.4 Buffer System

```haxe
class Buffer {
    var id:Int;
    var vertices:Int;
    var format:hxd.BufferFormat;
    var flags:haxe.EnumFlags<BufferFlag>;

    function uploadFloats(data:hxd.FloatBuffer, bufPos:Int, ?startVertex:Int, ?vertexCount:Int):Void;
}

enum BufferFlag {
    Dynamic;         // frequently modified
    NoAlloc;         // manual GPU memory management
    IndexBuffer;     // this buffer is an index buffer
    UniformBuffer;   // shader uniform buffer (SSBO/UAV)
    ReadWriteBuffer; // storage buffer (read-write in shader)
}
```

Buffer format defines vertex structure:

```haxe
class hxd.BufferFormat {
    var strides:Array<Int>;  // bytes per vertex per stream
    var formats:Array<BufferFormat>;  // per-attribute format
}
```

### 5.5 Scene Graph

```haxe
class Scene extends Object implements IDrawable {
    var camera:Camera;
    var lightSystem:LightSystem;
    var renderer:Renderer;
    var interactives:Array<Interactive>;

    function render(engine:Engine):Void;
    function syncRec(ctx:RenderContext):Void;
    function emitRec(ctx:RenderContext):Void;
    function pickRay(screenX:Float, screenY:Float):{ origin:h3d.Vector, dir:h3d.Vector };
}

class Object {
    var parent:Object;
    var x:Float;  var y:Float;  var z:Float;
    var rotationX:Float;  var rotationY:Float;  var rotationZ:Float;
    var scaleX:Float;  var scaleY:Float;  var scaleZ:Float;

    var posChanged:Bool;

    function addChild(o:Object):Void;
    function removeChild(o:Object):Void;
    function sync(ctx:RenderContext):Void;
    function emit(ctx:RenderContext):Void;
    function getChildAt(n:Int):Object;
}
```

**Render loop**:

```haxe
function render(engine:Engine) {
    camera.update();
    ctx.start();
    renderer.start();
    renderer.startEffects();

    syncRec(ctx);   // sync all transforms
    emitRec(ctx);   // emit draw calls to passes

    // Collect and process passes
    lightSystem.initLights(ctx);
    renderer.process(passes);

    ctx.done();
}
```

### 5.6 Mesh

```haxe
class Mesh extends Object {
    var primitive:h3d.prim.Primitive;
    var material:h3d.mat.Material;
    var inheritLod:Bool;
    var forcedLod:Int = -1;

    function emit(ctx:RenderContext):Void;
    function draw(ctx:RenderContext):Void;
}
```

LOD (Level of Detail) is calculated via `screenRatioToLod()` based on projected screen area.

### 5.7 Camera

```haxe
class Camera {
    var mView:h3d.Matrix;   // view matrix
    var mProj:h3d.Matrix;  // projection matrix
    var mCam:h3d.Matrix;   // combined view-projection

    var fov:Float;         // field of view (radians)
    var zNear:Float;       // near clipping plane
    var zFar:Float;        // far clipping plane
    var screenRatio:Float; // aspect ratio

    var rightHanded:Bool;  // coordinate system handedness

    function update():Void;           // sync matrices
    function unproject(screenX:Float, screenY:Float, screenZ:Float):h3d.Vector;
}
```

### 5.8 Material and Pass System

```haxe
class Material extends BaseMaterial {
    var mshader:hxsl.ShaderList;         // default shader
    var normalShader:hxsl.ShaderList;    // normal map shader
    var textureShader:hxsl.ShaderList;   // texture override shader
    var specularShader:hxsl.ShaderList;  // specular override shader

    var shadows:Bool;        // cast shadows
    var receiveShadows:Bool; // receive shadows
    var staticShadows:Bool;  // baked shadow maps

    var blendMode:BlendMode;

    static function create(?tex:h3d.mat.Texture):Material;
}

class Pass {
    var passId:Int;
    var shaders:hxsl.ShaderList;
    var selfShaders:hxsl.ShaderList;  // per-object

    @:bits(flags) var enableLights:Bool;
    @:bits(flags) var dynamicParameters:Bool;
    @:bits(flags) var isStatic:Bool;
    @:bits(flags) var culled:Bool;

    @:bits(bits) var culling:Face;       // Back, Front, Both, None
    @:bits(bits) var depthWrite:Bool;
    @:bits(bits) var depthTest:Compare;  // Less, Greater, etc.
    @:bits(bits) var blendSrc:Blend;
    @:bits(bits) var blendDst:Blend;
    @:bits(bits) var wireframe:Bool;

    var layer:Int = 0;
    var stencil:h3d.mat.Stencil;
}
```

Render state enums in `h3d.mat.Data`:

```haxe
enum Face { None; Back; Front; Both; }

enum Compare { Always; Never; Equal; NotEqual; Less; LessEqual; Greater; GreaterEqual; }

enum Blend { One; Zero; SrcAlpha; DstAlpha; OneMinusSrcAlpha; OneMinusDstAlpha;
             SrcColor; DstColor; OneMinusSrcColor; ... }

enum BlendMode { None; Alpha; Add; SoftAdd; Multiply; MultiplyAdd; ... }
```

### 5.9 Primitives

```haxe
class Primitive {
    var allocPos:hxd.AllocPos;
    var refcount:Int;

    function alloc():Void;
    function free():Void;
    function incref():Void;
    function decref():Void;
}

// Built-in primitives
class Cube extends Primitive { }      // unit cube
class Sphere extends Primitive { }    // UV sphere
class Plane extends Primitive { }     // flat plane
class Cylinder extends Primitive { }  // cylinder
class Cone extends Primitive { }      // cone
class Torus extends Primitive { }     // torus
class HMDModel extends Primitive { }  // Heaps Model format (with blendshapes)
class Model extends Primitive { }    // generic model loader
```

Geometry conversion example:
```haxe
var prim = new h3d.prim.Cube();
prim.translate(-0.5, -0.5, -0.5);  // center at origin
prim.unindex();                    // hard edges (no shared vertices)
prim.addNormals();                 // compute normals
prim.addUVs();                     // compute UV coordinates
```

---

## 6. Rendering Pipeline

### 6.1 Main Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                        mainLoop()                               │
├─────────────────────────────────────────────────────────────────┤
│  hxd.Timer.update()                                             │
│    └─► dt calculation, frame count                              │
│                                                                  │
│  sevents.checkEvents()                                           │
│    └─► process input events, dispatch to interactives           │
│                                                                  │
│  update(dt) [user override]                                      │
│    └─► game logic                                               │
│                                                                  │
│  s2d.setElapsedTime(dt)                                         │
│  s3d.setElapsedTime(dt)                                         │
│                                                                  │
│  engine.render(this)                                            │
│    ├─► begin()                                                  │
│    │     └─► driver.begin(frame)                                │
│    │     └─► clear(backgroundColor)                            │
│    │                                                            │
│    ├─► s3d.render(engine)                                      │
│    │     ├─► camera.update()                                    │
│    │     ├─► ctx.start()                                        │
│    │     ├─► renderer.start()                                  │
│    │     ├─► syncRec(ctx)    // sync transforms                 │
│    │     ├─► emitRec(ctx)    // emit to passes                 │
│    │     └─► renderer.process(passes)                          │
│    │                                                            │
│    ├─► s2d.render(engine)                                      │
│    │     ├─► sync(ctx)                                          │
│    │     └─► ctx.drawScene()  // batch render 2D               │
│    │                                                            │
│    └─► end()                                                    │
│          └─► driver.end()                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 3D Pass System

Passes accumulate objects grouped by material/state:

```
emitRec(ctx)
  │
  ├─► for each child object:
  │     ├─► sync()  // update transforms
  │     └─► emit()  // add to pass
  │
  └─► for each child:
        └─► emitRec(ctx)  // recurse
```

`emit()` for Mesh:
```haxe
function emit(ctx:RenderContext) {
    var lod = calcLOD();
    var pass = material.selectPass(lod, ctx.passContext);
    ctx.emit(material, this, pass);
}
```

`renderer.process(passes)`:
1. Sort objects within each pass (by distance, state)
2. Set render state (depth, blend, cull)
3. Upload dynamic shader parameters
4. Draw objects in batch

### 6.3 Render Target Stack

Engine maintains a stack for render target management:

```haxe
function pushTarget(tex:h3d.mat.Texture, layer=0, mipLevel=0, depthBinding=ReadWrite) {
    // Save current state, switch to new target
    if (needFlushTarget) doFlushTarget();
    targetStack.push({ tex, layer, mipLevel, depthBinding });
    needFlushTarget = true;
}

function popTarget() {
    var prev = targetStack.pop();
    needFlushTarget = true;
    // Restore previous target
}

function flushTarget() {
    if (needFlushTarget) doFlushTarget();
}
```

Depth binding modes:
- `ReadWrite` — depth buffer used for testing and writing
- `ReadOnly` — depth testing only, no writes
- `DepthOnly` — depth render target (no color)
- `NotBound` — no depth buffer

### 6.4 2D Batch Rendering

2D rendering batches tiles by texture:

```
drawScene()
  │
  ├─► ctx.begin()
  │
  ├─► for each Drawable in tree order:
  │     ├─► beginDrawBatch(tex)  // flush if new texture
  │     └─► drawTile(tile)       // add to batch
  │
  └─► ctx.end()                   // flush final batch
```

Each batch emits one draw call for all tiles sharing the same texture.

---

## 7. hxsl — Shader Language

### 7.1 Type System

```haxe
enum Type {
    TVoid;
    TFloat;
    TVec(g:Int, ?k:Kind);     // Vec2, Vec3, Vec4, Mat2, Mat3, Mat4
    TMat(a:Int, b:Int);
    TSampler(dim:Int);        // Sampler2D, SamplerCube, etc.
    TBuffer(storage:StorageKind, kind:BufferKind);
    TStruct(fields:Array<{ name:String, t:Type }>);
}
```

### 7.2 Function Kinds

```haxe
enum FunctionKind {
    Vertex;      // vertex shader stage
    Fragment;    // fragment/pixel shader stage
    Main;       // compute shader stage
}
```

### 7.3 Runtime Shader

```haxe
class RuntimeShader {
    var id:Int;
    var vertex:RuntimeShaderData;
    var fragment:RuntimeShaderData;
    var compute(get,set):RuntimeShaderData;
    var signature:String;  // for caching
    var mode:LinkMode;     // Default, Batch, Compute

    function getInputFormat(instance=false):hxd.BufferFormat;
}

class RuntimeShaderData {
    var kind:FunctionKind;
    var data:Ast.ShaderData;
    var code:String;          // compiled output
    var params:AllocParam;    // uniform parameters
    var paramsSize:Int;
    var globals:AllocGlobal;
    var textures:AllocParam;
    var buffers:AllocParam;
}
```

### 7.4 GLSL Output

`hxsl.GlslOut` generates GLSL ES 1.0, 2.0, or GL 3.0+:

```haxe
class GlslOut {
    static function run(data:ShaderData, shader:FunctionKind, precision:Int):String;

    // Precision tiers
    // 0 = highp, 1 = mediump, 2 = lowp
}
```

Key transformations:
- Matrix types emit as `mat2x3`, `mat3x4`, etc.
- `Texture(tex, uv)` → `texture2D(tex, uv)` (ES 2.0) or `texture(tex, uv)` (GL 3.0+)
- `VertexID` → `gl_VertexID`
- `InstanceID` → `gl_InstanceID`
- Derivative functions: `dFdx`, `dFdy`, `fwidth`

### 7.5 HLSL Output

`hxsl.HlslOut` generates HLSL for DirectX:

```haxe
class HlslOut {
    static function run(data:ShaderData, shader:FunctionKind):String;
}
```

Key transformations:
- `SV_POSITION` for vertex output position
- `SV_TARGET[n]` for render target outputs
- `SV_VertexID`, `SV_InstanceID`
- Uniforms → `cbuffer` with `register(b0)`, `register(b1)`, etc.
- Textures → `Texture2D` with `register(t0)`, `register(t1)`, etc.
- Samplers → `SamplerState` with `register(s0)`, `register(s1)`, etc.
- Storage buffers → `StructuredBuffer<T>` / `RWStructuredBuffer<T>` with `register(u0)`, etc.

### 7.6 Shader Compilation Pipeline

```
Source (HxSL macro)
    │
    ▼
Parser (hxsl.MacroParser)
    │
    ▼
AST (hxsl.Ast)
    │
    ▼
Flattener (hxsl.Flatten) — inline functions, resolve globals
    │
    ▼
Linker (hxsl.Linker) — combine vertex/fragment, allocate registers
    │
    ▼
Checker (hxsl.Checker) — validate types, dimensions, semantics
    │
    ▼
GlslOut / HlslOut — generate target code
```

---

## 8. Driver Implementation Guide

### 8.1 Required Interface

To implement a new backend, create a class extending `h3d.impl.Driver`:

```haxe
class MyDriver extends Driver {
    // Lifecycle
    function new(antiAlias:Int) { }
    function init(onCreate:Bool->Void, forceSoftware=false):Void;
    function dispose():Void;
    function isDisposed():Bool;
    function resize(width:Int, height:Int):Void;

    // Queries
    function hasFeature(f:Feature):Bool;

    // Shader
    function selectShader(shader:hxsl.RuntimeShader):Bool;
    function selectMaterial(pass:h3d.mat.Pass):Void;
    function uploadShaderBuffers(buffers:h3d.shader.Buffers, which:BufferKind):Void;
    function flushShaderBuffers():Void;

    // Buffers
    function selectBuffer(buffer:Buffer):Void;
    function selectMultiBuffers(format:hxd.BufferFormat.MultiFormat, buffers:Array<Buffer>):Void;
    function allocBuffer(b:h3d.Buffer):GPUBuffer;
    function uploadBufferData(b:h3d.Buffer, startVertex:Int, vertexCount:Int, buf:hxd.FloatBuffer, bufPos:Int):Void;
    function disposeBuffer(b:h3d.Buffer):Void;

    // Indices
    function uploadIndexData(i:h3d.Buffer, startIndice:Int, indiceCount:Int,
                              ibuf:hxd.IndexBuffer, bufPos:Int):Void;

    // Textures
    function allocTexture(t:h3d.mat.Texture):Texture;
    function uploadTextureBitmap(t:h3d.mat.Texture, bmp:hxd.BitmapData,
                                 mipLevel:Int, side:Int):Void;
    function disposeTexture(t:h3d.mat.Texture):Void;

    // Drawing
    function draw(ibuf:h3d.Buffer, startIndex:Int, ntriangles:Int):Void;
    function drawInstanced(ibuf:h3d.Buffer, commands:h3d.impl.InstanceBuffer):Void;

    // Render targets
    function setRenderTarget(tex:h3d.mat.Texture, layer=0, mipLevel=0,
                              depthBinding:h3d.Engine.DepthBinding):Void;
    function setRenderTargets(textures:Array<h3d.mat.Texture>,
                              depthBinding:h3d.Engine.DepthBinding):Void;
    function setDepth(tex:h3d.mat.Texture):Void;
    function setDepthClamp(enabled:Bool):Void;
    function setDepthBias(depthBias:Float, slopeScaledBias:Float):Void;
    function allocDepthBuffer(b:h3d.mat.Texture):Texture;
    function getDefaultDepthBuffer():h3d.mat.Texture;

    // Clear
    function clear(?color:h3d.Vector4, ?depth:Float, ?stencil:Int):Void;

    // State
    function setRenderZone(x:Int, y:Int, width:Int, height:Int):Void;

    // Profiling
    function beginEvent(name:String):Void;
    function endEvent():Void;

    // Queries
    function allocQuery(kind:QueryKind):Query;
    function beginQuery(q:Query):Void;
    function endQuery(q:Query):Void;
    function queryResultAvailable(q:Query):Bool;
    function queryResult(q:Query):Float;

    // Compute
    function computeDispatch(x:Int=1, y:Int=1, z:Int=1, barrier:Bool=true):Void;
    function memoryBarrier():Void;

    // Misc
    function getDriverName(details:Bool):String;
    function getMemoryUsage():{ total:Float, allocated:Float, free:Float };
    function captureRenderBuffer(pixels:hxd.Pixels):Void;
    function capturePixels(tex:h3d.mat.Texture, layer:Int, mipLevel:Int,
                           ?region:h2d.col.IBounds):hxd.Pixels;
    function generateMipMaps(texture:h3d.mat.Texture):Void;
    function getNativeShaderCode(shader:hxsl.RuntimeShader):String;
}
```

### 8.2 Buffer Allocation Contract

Buffers are allocated lazily on first use:

```haxe
function selectBuffer(buffer:Buffer) {
    if (buffer.vbuf == null) {
        buffer.vbuf = allocBuffer(buffer);
    }
    // bind buffer to GPU
}
```

Upload pattern:
```haxe
function uploadBufferData(b:h3d.Buffer, startVertex:Int, vertexCount:Int,
                          buf:hxd.FloatBuffer, bufPos:Int) {
    // Convert FloatBuffer to bytes if needed
    var bytes = hxd.FloatBuffer.bytes(buf, bufPos, vertexCount * b.format.stride);
    uploadBufferBytes(b, startVertex, vertexCount, bytes, 0);
}

function uploadBufferBytes(b:h3d.Buffer, startVertex:Int, vertexCount:Int,
                           buf:haxe.io.Bytes, bufPos:Int) {
    // Platform-specific upload (glBufferData, UpdateSubresource, etc.)
}
```

### 8.3 Texture Allocation Contract

```haxe
function allocTexture(t:h3d.mat.Texture):Texture {
    // Create platform texture object
    // Store width, height, internal format, pixel format, bits per pixel
    // Return opaque texture handle
}
```

Upload pattern:
```haxe
function uploadTextureBitmap(t:h3d.mat.Texture, bmp:hxd.BitmapData,
                               mipLevel:Int, side:Int) {
    // mipLevel = 0 for base level
    // side = 0 for 2D textures; 0-5 for cube faces
    // Convert BitmapData to platform format
    // Upload to GPU
}
```

### 8.4 Common Pitfalls

1. **Context loss** — Implement `onContextLost` cleanup and restoration
2. **Thread safety** — GPU operations often need synchronization
3. **Alignment** — Buffer upload offsets must respect platform alignment requirements
4. **Format conversion** — Float32/Float16/Uint8 may need conversion for some APIs
5. **Coordinate systems** — GL uses bottom-left texture origin; DX uses top-left
6. **Shader bytecode** — HLSL must be compiled to DX bytecode before use

---

## 9. Cross-Module Collaboration

### 9.1 Initialization Sequence

```
hxd.App.new()
  │
  ├─► hxd.Window.getInstance()  — creates platform window
  │
  ├─► h3d.Engine.new()           — creates engine, selects driver
  │
  ├─► engine.onReady = setup
  │
  └─► hxd.System.start()
        └─► engine.init()
              └─► setup()

setup()
  ├─► s3d = new h3d.scene.Scene()
  │     ├─► camera = new h3d.scene.Camera()
  │     ├─► lightSystem = new LightSystem()
  │     └─► renderer = MaterialSetup.current.createRenderer()
  │
  ├─► s2d = new h2d.Scene()
  │     └─► ScaleMode applied
  │
  ├─► sevents = new hxd.SceneEvents()
  │     ├─► sevents.addScene(s2d, 0)
  │     └─► sevents.addScene(s3d)
  │
  ├─► loadAssets()
  │     └─► init() [user override]
  │
  └─► mainLoop()
```

### 9.2 Resource Loading Chain

```
hxd.Res.load("myTex.png")
  │
  ├─► FileTree loader locates file
  │
  ├─► BitmapData.load()
  │     └─► Platform image decoder
  │
  ├─► h3d.mat.Texture.fromBitmap(bmp)
  │     └─► driver.allocTexture(tex)
  │
  └─► material = h3d.mat.Material.create(tex)
        └─► creates default Pass with BaseMesh shader
```

### 9.3 Event Flow

```
Input Event (OS/Platform)
  │
  ▼
hxd.Window.addEventTarget()
  │
  ▼
SceneEvents.checkEvents()
  │
  ▼
SceneEvents.dispatchEvent(e, target)
  │
  ├─► Interactive.handleEvent(e)
  │     └─► bubble up via parent chain
  │
  └─► Interactive.dispatchListeners(e)
        └─► EMove / EPush / ERelease callbacks
```

### 9.4 Render Context Passing

```
engine.render(this)
  │
  ├─► s3d.render(engine)
  │     └─► passes RenderContext through syncRec/emitRec
  │
  └─► s2d.render(engine)
        └─► h2d.RenderContext stores engine reference
```

---

## 10. Platform-Specific Notes

### 10.1 JavaScript/WebGL

- Uses `js.html.webgl` for GL2 bindings
- Canvas resize handled by `hxd.Window.js.hx`
- Gamepad API via `hxd.Pad.js` using W3C Gamepad API
- Context loss events tracked for resource restoration
- `Float32` precision: platform-dependent (usually highp)

### 10.2 HashLink/OpenGL

- Uses `sdl.GL` for OpenGL bindings via SDL2
- Window and input via SDL2 events
- Pixel format conversion for BitmapData loading
- Mipmap generation via `driver.generateMipMaps()`

### 10.3 DirectX 9/12

- Uses `dx.*` namespace for DirectX bindings
- HLSL shader compilation at runtime via `D3DCompile`
- DX12 uses descriptor heaps and command queues
- UAV (unordered access view) for compute shaders

### 10.4 Console Ports

- Vendor SDKs for Nintendo Switch, PlayStation, Xbox
- Requires NDA and registered developer status
- Contact: nicolas@haxe.org for inquiries

---

## Appendix: Key Files Map

### Core Classes

| File | Purpose |
|------|---------|
| `hxd/App.hx` | Application entry point |
| `hxd/Window.hx` | Platform window abstraction |
| `hxd/SceneEvents.hx` | Input event routing |
| `hxd/Res.hx` | Resource loader |
| `h3d/Engine.hx` | Rendering engine orchestrator |
| `h3d/impl/Driver.hx` | GPU API interface |
| `h3d/impl/GlDriver.hx` | OpenGL/WebGL implementation |
| `h3d/impl/DirectXDriver.hx` | DirectX 9 implementation |
| `h3d/impl/DX12Driver.hx` | DirectX 12 implementation |
| `h3d/impl/MemoryManager.hx` | GPU buffer management |
| `h3d/scene/Scene.hx` | 3D scene graph root |
| `h3d/scene/Object.hx` | 3D scene object base |
| `h3d/scene/Mesh.hx` | 3D mesh with geometry and material |
| `h3d/scene/Camera.hx` | Camera with view/projection matrices |
| `h3d/mat/Material.hx` | Material with passes and shaders |
| `h3d/mat/Pass.hx` | Single render pass with state |
| `h2d/Scene.hx` | 2D scene graph root |
| `h2d/Object.hx` | 2D object with transform |
| `h2d/Drawable.hx` | Base renderable 2D object |
| `h2d/Flow.hx` | Auto-layout container |
| `hxsl/RuntimeShader.hx` | Compiled shader runtime representation |
| `hxsl/GlslOut.hx` | GLSL code generator |
| `hxsl/HlslOut.hx` | HLSL code generator |

### Important Enums

| Enum | Location | Purpose |
|------|----------|---------|
| `Feature` | `h3d/impl/Driver.hx` | GPU capability flags |
| `QueryKind` | `h3d/impl/Driver.hx` | GPU query types |
| `BufferFlag` | `h3d/Buffer.hx` | Buffer allocation hints |
| `Face` | `h3d/mat/Data.hx` | Culling mode |
| `Blend` | `h3d/mat/Data.hx` | Blend factors |
| `Compare` | `h3d/mat/Data.hx` | Depth/stencil test modes |
| `ScaleMode` | `h2d/Scene.hx` | 2D viewport modes |
| `FlowLayout` | `h2d/Flow.hx` | Flow arrangement modes |

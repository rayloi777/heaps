# Heaps Engine Architecture Analysis

> Research document analyzing potential architectural improvements for the Heaps game engine. No code modifications — purely observational analysis.

---

## Table of Contents

1. [Module Coupling Issues](#1-module-coupling-issues)
2. [Driver Abstraction Weaknesses](#2-driver-abstraction-weaknesses)
3. [Scene Graph Duplication](#3-scene-graph-duplication)
4. [Material/Shader System Issues](#4-materialshader-system-issues)
5. [Cross-Cutting Concerns](#5-cross-cutting-concerns)
6. [Summary of Architectural Issues](#6-summary-of-architectural-issues)
7. [Potential Improvement Areas](#7-potential-improvement-areas)

---

## 1. Module Coupling Issues

### 1.1 Foundation Layer Depends on 3D

**Location:** `hxd/App.hx:13`

```haxe
class App implements h3d.IDrawable {  // Foundation implements 3D interface!
    public var engine(default,null) : h3d.Engine;
    public var s3d(default,null) : h3d.scene.Scene;
    public var s2d(default,null) : h2d.Scene;
}
```

**Problem:** `hxd` is the cross-platform foundation module, but `hxd.App` directly imports `h3d.Engine`, `h3d.scene.Scene`, and `h2d.Scene`. The `h3d.IDrawable` interface (the render callback) forces this dependency.

**Impact:** Cannot use `hxd` as a standalone foundation without pulling in both 2D and 3D rendering stacks.

### 1.2 2D Graphics Extends 3D Primitive

**Location:** `h2d/Graphics.hx:30-36`

```haxe
private class GraphicsContent extends h3d.prim.Primitive {
    var tmp : hxd.FloatBuffer;
    var buffers : Array<{ buf : hxd.FloatBuffer, vbuf : h3d.Buffer, ... }>;
}
```

**Problem:** The 2D `Graphics` class extends a 3D `Primitive`, suggesting the 2D rendering pipeline was retrofitted onto 3D infrastructure rather than designed independently.

### 1.3 Shader Layer Depends on 3D Textures

**Location:** `hxsl/Globals.hx:2`

```haxe
import h3d.mat.Texture;  // Shader language depends on 3D textures!
```

**Problem:** The `hxsl` module (shader compilation/execution) should be rendering-agnostic, but directly imports `h3d.mat.Texture`.

### 1.4 Bidirectional Dependencies

**hxd.clipper imports h2d, but h2d uses hxd.clipper:**

```haxe
// hxd/clipper/Clipper.hx
import h2d.col.Point;
import h2d.col.IPolygon;

// h2d/col/IPolygon.hx
public function union(p:IPolygon, withHoles = true) : IPolygons {
    var c = new hxd.clipper.Clipper();  // h2d uses hxd.clipper
```

**Problem:** A "general utility" (`hxd.clipper`) depends on types from the module that uses it (`h2d.col.*`).

**h3d.Engine allows hxd.res private access:**

```haxe
// h3d/Engine.hx:70
@:allow(hxd.res) var resCache = new Map<{},Dynamic>();
```

### 1.5 Inconsistent "impl" Package Usage

| Module | impl/ Contains |
|--------|---------------|
| `h3d` | Platform drivers (GlDriver, DirectXDriver, DX12Driver) — appropriate |
| `hxd` | Utilities (Allocator, CacheAllocator, MouseMode) — unrelated to hxd's purpose |

---

## 2. Driver Abstraction Weaknesses

### 2.1 Typedef Type Leakage

**Location:** `h3d/impl/Driver.hx:1-35`

```haxe
#if js
    typedef GPUBuffer = js.html.webgl.Buffer;
    typedef Texture = { t : js.html.webgl.Texture, width : Int, ... };

#elif (hldx && dx12)
    typedef GPUBuffer = DX12Driver.BufferData;  // Full class!
    typedef Texture = h3d.impl.DX12Driver.TextureData;  // Full class!

#elif hldx
    typedef GPUBuffer = dx.Resource;
    typedef Texture = { res : dx.Resource, view : dx.Driver.ShaderResourceView, ... };
```

**Problem:** `GPUBuffer` and `Texture` are fundamentally different types per platform. DX12 uses full classes (`BufferData`, `TextureData`) while WebGL uses native GL objects. Internal structure leaks via `Buffer.vbuf` and `Texture.t`.

### 2.2 Incomplete Feature Enum

**Location:** `h3d/impl/Driver.hx:37-88`

```haxe
enum Feature {
    StandardDerivatives;
    FloatTextures;
    AllocDepthBuffer;
    HardwareAccelerated;
    MultipleRenderTargets;
    Queries;
    SRGBTextures;
    ShaderModel3;
    BottomLeftCoords;
    Wireframe;
    InstancedRendering;
    Bindless;
}
```

**Missing queryable capabilities:**
- Texture compression formats (S3TC, ASTC, BC7)
- Max texture size per dimension
- Max MRT target count
- Compute shader support
- Texture array / 3D texture support
- Anisotropic filtering level

### 2.3 Inconsistent State Management

Each driver invents its own state tracking:

```haxe
// GlDriver state
var curShader : CompiledProgram;
var curBuffer : h3d.Buffer;
var boundTextures : Array<Texture> = [];

// DirectXDriver state
var currentShader : CompiledShader;
var currentIndex : h3d.Buffer;
var currentLayout : Layout;
var currentDepthState : DepthStencilState;

// DX12Driver state
var currentShader : CompiledShader;
var currentIndex : Buffer;
var currentRenderTargets : Array<h3d.mat.Texture> = [];
var currentPipelineState : PipelineState;
```

**Problem:** No common state interface. Validation differs across drivers (GL checks re-selection; DX12 does not).

### 2.4 DX12 Buffer Allocator is Opaque to MemoryManager

DX12's `BufferAllocator` (page-based with frame recycling) returns a `BufferData` opaque to `h3d.impl.MemoryManager`. The higher-level memory management cannot reason about DX12's allocation strategy.

---

## 3. Scene Graph Duplication

### 3.1 Parallel Object Hierarchies

**h2d.Object and h3d/scene/Object are entirely separate with ~80% duplicate code:**

| Feature | h2d/Object | h3d/scene/Object |
|---------|------------|------------------|
| Package | `h2d` | `h3d.scene` |
| Transform | 2D affine (matA/B/C/D + absX/Y) | 3D matrix + quaternion |
| Children | `children:Array<Object>` | `children:Array<Object>` |
| Sync pattern | `sync()`, `syncPos()`, `calcAbsPos()` | `syncRec()`, `syncPos()`, `calcAbsPos()` |
| Lifecycle | `onAdd()`, `onRemove()`, `allocated` | `onAdd()`, `onRemove()`, `allocated` |
| Bounds | `getBounds()`, `find()`, `findAll()` | `getBounds()`, `find()`, `findAll()` |
| Clone | `clone()` | `clone()` |
| Iterator | `iterator()` | `iterator()` |

**Both implement identical patterns for:**
- Child management (`addChild`, `removeChild`, `getChildAt`)
- Bounds calculation
- Hierarchy traversal (`find`, `findAll`, `getObjectByName`)
- Position sync coordination (`posChanged` flag)

### 3.2 Transform Math Fragmentation

**h2d.Object** manually expands matrix operations:
```haxe
var matA : Float;  // scaleX * cos(rotation)
var matB : Float;  // scaleX * sin(rotation)
var matC : Float;  // scaleY * -sin(rotation)
var matD : Float;  // scaleY * cos(rotation)
var absX : Float;
var absY : Float;
```

**Meanwhile:**
- `h2d.col.Matrix` exists as a proper 2D affine matrix class
- `h3d.Matrix` has `toMatrix2D()` demonstrating 2D extraction awareness
- h2d.Camera's transform (lines 104-110 in `h2d/Camera.hx`) is nearly identical to h2d.Object's — no sharing

### 3.3 Interactive Duplication

Both `h2d/Interactive` and `h3d.scene.Interactive` implement identical interfaces and callbacks:

```haxe
// Identical callbacks in both classes:
onOver, onOut, onPush, onRelease, onReleaseOutside,
onClick, onMove, onWheel, onFocus, onFocusLost,
onKeyUp, onKeyDown, onCheck, onTextInput

// Identical properties:
cursor, propagateEvents, cancelEvents,
enableRightButton, allowMultiClick
```

**Differences are minimal:**
- h2d uses rectangular/elliptic hitbox with `width`/`height` or `shape : h2d.col.Collider`
- h3d uses 3D colliders: `shape : h3d.col.Collider`, `preciseShape`, `bestMatch`

---

## 4. Material/Shader System Issues

### 4.1 BaseMesh Bakes In Too Much Engine Knowledge

**Location:** `h3d/shader/BaseMesh.hx`

The "base" shader hardcodes:
- **TAA support**: `jitterOffsets`, `previousViewProj`, `velocity` output
- **MRT outputs**: `position, color, depth, normal, worldDist, velocity`
- **Deferred depth reconstruction**: `worldDist = length(transformedPosition - camera.position) / camera.zFar`
- **Specular lighting model**: `specularPower, specularAmount, specularColor`
- **Camera globals**: `view, proj, position, projFlip, projDiag, viewProj, previousViewProj, inverseViewProj`

**Problem:** This is the default rendering pipeline baked into a "base" class. To use forward rendering or a different lighting model, you must replace `BaseMesh` entirely.

### 4.2 Pass Inheritance is Shallow

```haxe
function allocPass(name, inheritMain = true) {
    // Creates NEW pass that inherits from mainPass
    // Copies flags/bits but NOT the actual shader chain
    // True inheritance is shallow
}
```

### 4.3 Dynamic Parameters Naming is Counterintuitive

```haxe
// When dynamicParameters = true:
// parameters are NOT uploaded before draw
// caller must upload manually via RenderContext.uploadParams()

// When dynamicParameters = false (default):
// parameters uploaded once per shader change
```

**Naming issue:** `dynamicParameters = true` means "I will upload these manually." More intuitive: `volatileParameters` or `manualParameters`.

### 4.4 Shader Compilation Happens at Draw Time

```haxe
// h3d/pass/Output.hx:48
p.shader = output.compileShaders(ctx.globals, shaders, ...);

// Called in setupShaders() which is called in draw()
```

**Consequences:**
- First draw of any material causes a hitch
- Shader errors surface at draw time, not at material creation
- No early validation

### 4.5 ShaderList Mutation Risk

```haxe
// hxsl/ShaderList.hx
static function addSort(s, shaders) {
    // Inserts by priority, returns new head
    // Easy to lose reference if you don't capture return value
}
```

---

## 5. Cross-Cutting Concerns

### 5.1 Pass vs Layer Terminology Confusion

| Concept | h3d | h2d |
|---------|-----|-----|
| Rendering stage | `Pass` (shader pipeline) | No pass concept |
| Z-ordering | `layer` property on Pass | `layers` array in Scene |

**Confusion:** `Pass.layer` is for z-ordering in h3d, while h2d's `layers` is also for z-ordering. But the mechanisms are completely different.

### 5.2 Conditional Compilation Fragmentation

**Example from `hxd/Window.hl.hx`:**

```haxe
function onEvent( e : #if hldx dx.Event #else sdl.Event #end ) : Bool {
```

Platform-specific `#if` flags appear throughout:
- `hlsdl` vs `hldx` vs `usesys` vs `heaps_vulkan`
- `multidriver` for multi-driver support
- `js` for JavaScript

This makes control flow difficult to trace.

### 5.3 Material vs Pass Blur

`Material.set_blendMode` directly manipulates `mainPass` properties:

```haxe
// Material passes blend state down to Pass
// But Pass is supposed to be a "shader pipeline"
// This conflates rendering state with shader state
```

---

## 6. Summary of Architectural Issues

| Issue | Severity | Category |
|-------|----------|----------|
| hxd.App depends on h3d.IDrawable | High | Coupling |
| h2d.Graphics extends h3d.prim.Primitive | High | Coupling |
| hxsl imports h3d.mat.Texture | Medium | Coupling |
| hxd.clipper imports h2d types | Medium | Coupling |
| GPUBuffer/Texture typedef leakage | High | Driver |
| Incomplete Feature enum | Medium | Driver |
| Inconsistent state management | High | Driver |
| Parallel Object hierarchies | High | Duplication |
| Transform math not shared | Medium | Duplication |
| Interactive duplication | High | Duplication |
| BaseMesh too opinionated | High | Shader |
| Pass inheritance shallow | Medium | Shader |
| Dynamic parameters naming | Low | Shader |
| Compilation at draw time | Medium | Shader |
| Pass vs Layer confusion | Low | Terminology |
| Conditional compilation sprawl | Medium | Maintainability |

---

## 7. Potential Improvement Areas

### 7.1 Layer Separation (High Impact)

**Current:**
```
hxd → h2d/h3d/hxsl (tightly coupled)
```

**Potential:**
```
haxe.game (foundation: math, containers, events)
  └── hxd (window, input, resources)
        ├── h2d (2D rendering)
        └── h3d (3D rendering)
              └── hxsl (shader compiler)
```

**How:** Extract `h3d.IDrawable` from `hxd.App`. Use composition over inheritance — `App` should accept a `Drawable` rather than extending it.

### 7.2 Unified Scene Object Base (High Impact)

**Current:** Two parallel hierarchies

**Potential:** Shared abstract base

```haxe
// haxe.scene.Object (new shared base)
class Object {
    var parent:Object;
    var children:Array<Object>;
    var allocated:Bool;
    var posChanged:Bool;

    abstract function getLocalTransform():Matrix;
    abstract function getWorldTransform():Matrix;
    abstract function getBounds():Bounds;
    abstract function render(ctx:RenderContext):Void;

    function addChild(o:Object):Void;
    function removeChild(o:Object):Void;
    function sync(ctx:RenderContext):Void;
    function find(predicate:Object->Bool):Object;
}

// h2d.Object extends haxe.scene.Object
// h3d.scene.Object extends haxe.scene.Object
```

### 7.3 Enhanced Driver Abstraction (Medium Impact)

**Potential additions:**
- Query interface for texture compression support
- Query interface for max texture dimensions/array sizes
- Common state management interface with validation callbacks
- Abstract buffer allocation strategy visible to MemoryManager

### 7.4 Shader Architecture Refinement (Medium Impact)

**Potential:**
- Separate "base rendering" from "engine defaults"
- Move TAA/MRT from BaseMesh to opt-in passes
- Rename `dynamicParameters` to `volatileParameters`
- Consider ahead-of-time shader validation

### 7.5 Extract hxd.clipper (Low Impact)

Move `h2d.col.*` types to a neutral location so `hxd.clipper` doesn't depend on h2d.

---

## Appendix: Key Problematic Files

| File | Issue |
|------|-------|
| `hxd/App.hx` | Foundation couples to 3D |
| `h2d/Graphics.hx` | 2D extends 3D primitive |
| `hxsl/Globals.hx` | Shader layer imports 3D |
| `h3d/impl/Driver.hx` | Typedef type leakage, incomplete features |
| `h2d/Object.hx` | Duplicates h3d/scene/Object |
| `h2d/Interactive.hx` | Duplicates h3d.scene.Interactive |
| `h3d/shader/BaseMesh.hx` | Bakes in TAA/MRT/deferred |
| `hxd/Window.hl.hx` | Conditional compilation sprawl |
| `hxd/clipper/Clipper.hx` | Depends on h2d types |

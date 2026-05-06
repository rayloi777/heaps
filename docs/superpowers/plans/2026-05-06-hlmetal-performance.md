# hlmetal Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize the Metal rendering backend for hlmetal by eliminating CPU stalls, reducing per-draw overhead, and caching shader compilation results.

**Architecture:** Four sequential PRs targeting frame pipelining, draw call hot path, buffer allocation, and shader caching. Each PR is independently testable via CubeTest + HelloWorld_HL + Metal API Validation.

**Tech Stack:** Haxe (Heaps engine), Objective-C++ (Metal native), HashLink VM

**Spec:** `docs/superpowers/specs/2026-05-06-hlmetal-performance-design.md`

---

## File Map

| File | Responsibility | PR |
|------|---------------|-----|
| `libs/metal/metal.mm` | Native Metal C++ — frame lifecycle, culling, archive | 1, 2, 4 |
| `libs/metal/metal/Driver.hx` | Haxe FFI externs for Metal native functions | 2, 4 |
| `libs/metal/metal/Format.hx` | Metal enum definitions (add CullMode, Winding) | 2 |
| `h3d/impl/MetalDriver.hx` | Main Metal driver — state management, draw calls, caching | 2, 3 |

---

## PR 1: Frame Pipelining

### Task 1: Replace waitUntilCompleted with waitUntilScheduled

**Files:**
- Modify: `libs/metal/metal.mm` line 74

- [ ] **Step 1: Change begin_frame to use waitUntilScheduled**

In `libs/metal/metal.mm`, in `begin_frame()` (around line 73), change:

```objc
// Before:
if( g_driver->prevCommandBuffer ) {
    [g_driver->prevCommandBuffer waitUntilCompleted];
    g_driver->prevCommandBuffer = nil;
}

// After:
if( g_driver->prevCommandBuffer ) {
    [g_driver->prevCommandBuffer waitUntilScheduled];
    g_driver->prevCommandBuffer = nil;
}
```

- [ ] **Step 2: Rebuild metal.hdll**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master/libs/metal/build && cmake --build . && cp metal.hdll /usr/local/lib/hl/
```

Re-sign if on macOS Sequoia:
```bash
codesign -s - /usr/local/lib/hl/metal.hdll
```

- [ ] **Step 3: Verify CubeTest runs without crash**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master/other/tests/metal && haxe build_cube_test.hxml && perl -e 'alarm 5; exec @ARGV' hl cube.hl; echo "EXIT: $?"
```

Expected: EXIT 142 (SIGALRM timeout = running successfully)

- [ ] **Step 4: Verify HelloWorld_HL (PBR) runs without crash**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && perl -e 'alarm 10; exec @ARGV' hl main.hl; echo "EXIT: $?"
```

Expected: EXIT 142 (SIGALRM timeout)

- [ ] **Step 5: Verify with Metal API Validation**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && METAL_DEVICE_WRAPPER_TYPE=1 perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

Expected: No assertion failures related to command buffer scheduling.

- [ ] **Step 6: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master && git add libs/metal/metal.mm && git commit -m "perf(metal): use waitUntilScheduled for frame pipelining

Replace waitUntilCompleted with waitUntilScheduled in beginFrame to
enable CPU/GPU overlap. CPU builds frame N+1 while GPU executes
frame N, eliminating the largest per-frame stall."
```

---

## PR 2: Draw Call Optimization

### Task 2: Add native cull mode and winding functions

**Files:**
- Modify: `libs/metal/metal.mm` (add functions before DEFINE_PRIM block)
- Modify: `libs/metal/metal/Driver.hx` (add extern methods)
- Modify: `libs/metal/metal/Format.hx` (add enums)

- [ ] **Step 1: Add CullMode and Winding enums to Format.hx**

In `libs/metal/metal/Format.hx`, add after the `SamplerAddressMode` enum:

```haxe
enum abstract CullMode(Int) to Int {
    var None = 0;
    var Front = 1;
    var Back = 2;
}

enum abstract Winding(Int) to Int {
    var Clockwise = 0;
    var CounterClockwise = 1;
}
```

- [ ] **Step 2: Add native functions to metal.mm**

In `libs/metal/metal.mm`, add before the `DEFINE_PRIM` block (around line 580):

```objc
HL_PRIM void HL_NAME(set_cull_mode)(int mode) {
    if( !g_driver || !g_driver->renderEncoder ) return;
    [g_driver->renderEncoder setCullMode:(MTLCullMode)mode];
}

HL_PRIM void HL_NAME(set_front_facing_winding)(int winding) {
    if( !g_driver || !g_driver->renderEncoder ) return;
    [g_driver->renderEncoder setFrontFacingWinding:(MTLWinding)winding];
}

HL_PRIM void HL_NAME(set_triangle_fill_mode)(int mode) {
    if( !g_driver || !g_driver->renderEncoder ) return;
    [g_driver->renderEncoder setTriangleFillMode:(MTLTriangleFillMode)mode];
}
```

Add DEFINE_PRIM entries:

```objc
DEFINE_PRIM(_VOID, set_cull_mode, _I32);
DEFINE_PRIM(_VOID, set_front_facing_winding, _I32);
DEFINE_PRIM(_VOID, set_triangle_fill_mode, _I32);
```

- [ ] **Step 3: Add Haxe externs to Driver.hx**

In `libs/metal/metal/Driver.hx`, add in the `Driver` class after the `setScissorRect` method:

```haxe
    @:hlNative("metal","set_cull_mode")
    public static function setCullMode(mode:Int) : Void {}

    @:hlNative("metal","set_front_facing_winding")
    public static function setFrontFacingWinding(winding:Int) : Void {}

    @:hlNative("metal","set_triangle_fill_mode")
    public static function setTriangleFillMode(mode:Int) : Void {}
```

- [ ] **Step 4: Rebuild metal.hdll**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master/libs/metal/build && cmake --build . && cp metal.hdll /usr/local/lib/hl/ && codesign -s - /usr/local/lib/hl/metal.hdll
```

- [ ] **Step 5: Commit native layer**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master && git add libs/metal/metal.mm libs/metal/metal/Driver.hx libs/metal/metal/Format.hx && git commit -m "feat(metal): add native cull mode and winding functions"
```

### Task 3: Implement backface culling in selectMaterial

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — add cull mode tracking, update `selectMaterial()`, `resetRenderState()`

- [ ] **Step 1: Add cull mode tracking field and reset**

In `h3d/impl/MetalDriver.hx`, add a new field after the `currentStencilRef` declaration (around line 59):

```haxe
    var currentCullMode : Int = -1;
```

Update `resetRenderState()` to also reset the cull mode. The function should become:

```haxe
    function resetRenderState() {
        currentDepthStencilState = null;
        currentMaterialBits = -1;
        currentShader = null;
        currentCullMode = -1;
    }
```

- [ ] **Step 2: Add cull mode logic to selectMaterial**

In `selectMaterial()`, after the `allowDraw = pass.culling != Both;` line and before the depth/stencil state section, add the cull mode logic:

```haxe
        // Cull mode
        var cullBits = Pass.getCullBits(bits);
        if( cullBits != currentCullMode ) {
            currentCullMode = cullBits;
            switch( pass.culling ) {
            case None:
                MtlDrv.setCullMode(metal.Format.CullMode.None);
            case Front:
                MtlDrv.setCullMode(metal.Format.CullMode.Front);
            case Back:
                MtlDrv.setCullMode(metal.Format.CullMode.Back);
            case Both:
                // allowDraw is already false, no need to set cull mode
            }
            MtlDrv.setFrontFacingWinding(metal.Format.Winding.CounterClockwise);
        }
```

**Note:** You need to verify that `Pass.getCullBits(bits)` exists in the Heaps codebase. If it doesn't, extract cull mode directly from the material bits field. Look at how `Pass.culling` is stored in the bits field — the cull mode is typically encoded as a 2-bit field. Check `h3d/mat/Pass.hx` for the bit layout. An alternative approach that doesn't rely on bit extraction:

```haxe
        // Cull mode — extract from pass directly
        var cull = pass.culling;
        var cullInt = Type.enumIndex(cull); // None=0, Front=1, Back=2, Both=3
        if( cullInt != currentCullMode ) {
            currentCullMode = cullInt;
            if( cull == Both ) {
                MtlDrv.setCullMode(metal.Format.CullMode.None); // draw is skipped by allowDraw
            } else {
                MtlDrv.setCullMode(switch(cull) {
                    case None: metal.Format.CullMode.None;
                    case Front: metal.Format.CullMode.Front;
                    case Back: metal.Format.CullMode.Back;
                    default: metal.Format.CullMode.None;
                });
            }
            MtlDrv.setFrontFacingWinding(metal.Format.Winding.CounterClockwise);
        }
```

- [ ] **Step 3: Build and test**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master/other/tests/metal && haxe build_cube_test.hxml && METAL_DEVICE_WRAPPER_TYPE=1 perl -e 'alarm 5; exec @ARGV' hl cube.hl 2>&1; echo "EXIT: $?"
```

Expected: No validation errors. Cube should still render with correct face culling.

- [ ] **Step 4: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): implement backface culling in Metal render encoder

Previously only set allowDraw flag but never configured Metal's
cull mode, causing all triangles to be rasterized (doubled GPU work)."
```

### Task 4: Eliminate redundant pipeline set in selectShader

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — `selectShader()`, `selectMaterial()`

- [ ] **Step 1: Remove pipeline creation from selectShader**

Replace the `selectShader()` method. The new version should only compile/cache the shader and set `currentShader`, without creating or setting any pipeline:

```haxe
    override function selectShader( shader : hxsl.RuntimeShader ) : Bool {
        var s = shaders.get(shader.id);
        if( s == null ) {
            s = compileShader(shader);
            shaders.set(shader.id, s);
        }
        if( s == currentShader )
            return false;
        currentShader = s;
        return true;
    }
```

- [ ] **Step 2: Ensure selectMaterial always creates pipeline**

In `selectMaterial()`, the existing pipeline creation block (inside `if( currentShader != null )`) remains. Since `selectShader` no longer sets a pipeline, `selectMaterial` is now the sole place where pipelines are created and set. Verify the existing code handles this — the `if( currentShader != null )` guard in `selectMaterial` ensures a pipeline is only created after a shader is selected.

- [ ] **Step 3: Add lazy pipeline set for edge cases**

If a draw happens without `selectMaterial` being called (theoretical edge case), ensure the draw is guarded. In the `draw()` method, add a check at the start:

```haxe
    override function draw( ibuf : h3d.Buffer, startIndex : Int, ntriangles : Int ) {
        if( !allowDraw ) return;
        if( currentShader == null ) return;  // no shader selected
```

This is already effectively guarded since `selectBuffer` checks `currentShader == null`, but make it explicit.

- [ ] **Step 4: Build and test**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && METAL_DEVICE_WRAPPER_TYPE=1 perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

Expected: No validation errors, no crash.

- [ ] **Step 5: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): remove redundant pipeline creation from selectShader

Pipeline was created and set twice per draw — once in selectShader
with default blend, then again in selectMaterial with actual blend.
Now selectShader only caches the shader; pipeline creation happens
exclusively in selectMaterial."
```

### Task 5: Add texture and viewport binding caches

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — add cache fields, update `uploadBuffers()`, `resetRenderState()`, viewport calls

- [ ] **Step 1: Add cache fields**

Add after the `currentCullMode` field (from Task 3):

```haxe
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
```

Initialize in `reset()` or the constructor:

```haxe
    currentFragmentTextures = [for(i in 0...MAX_TEXTURES) null];
    currentFragmentSamplers = [for(i in 0...MAX_TEXTURES) null];
    currentVertexTextures = [for(i in 0...MAX_TEXTURES) null];
    currentVertexSamplers = [for(i in 0...MAX_TEXTURES) null];
```

- [ ] **Step 2: Update resetRenderState to clear caches**

```haxe
    function resetRenderState() {
        currentDepthStencilState = null;
        currentMaterialBits = -1;
        currentShader = null;
        currentCullMode = -1;
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
```

- [ ] **Step 3: Add cached setViewport helper**

Replace direct `MtlDrv.setViewport()` calls with a cached version:

```haxe
    function setViewportCached(x:Float, y:Float, w:Float, h:Float, zn:Float, zf:Float) {
        if( x == curVPX && y == curVPY && w == curVPW && h == curVPH && zn == curVPZN && zf == curVPZF )
            return;
        curVPX = x; curVPY = y; curVPW = w; curVPH = h; curVPZN = zn; curVPZF = zf;
        MtlDrv.setViewport(x, y, w, h, zn, zf);
    }
```

Replace all `MtlDrv.setViewport(...)` calls with `setViewportCached(...)` in:
- `beginDefaultPass()`
- `_setRenderTargets()`
- `clear()` (depth-only and texture paths)
- `resize()`

- [ ] **Step 4: Add caching to uploadBuffers Textures path**

In `uploadBuffers()`, in the `case Textures:` block, wrap each `setFragmentTexture`/`setFragmentSampler`/`setVertexTexture`/`setVertexSampler` call with a cache check. For example:

```haxe
    case Textures:
        for( i in 0...shader.texturesCount ) {
            // ... existing texture alloc/default logic ...
            if( t != null && t.t != null ) {
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
                // ... existing sampler logic ...
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
```

- [ ] **Step 5: Build and test**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && METAL_DEVICE_WRAPPER_TYPE=1 perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

- [ ] **Step 6: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): add texture, sampler, and viewport binding caches

Avoid redundant Metal API calls by tracking current bindings and
only rebinding when values change. Reset caches on render encoder
switch since Metal does not inherit state between encoders."
```

### Task 6: Replace string pipeline cache key with integer hash

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — `pipelineCache` type, cache key computation in `selectMaterial()`

- [ ] **Step 1: Change pipeline cache type**

Change the field declaration from:
```haxe
    var pipelineCache : Map<String, PipelineState>;
```
to:
```haxe
    var pipelineCache : Map<Int, PipelineState>;
```

- [ ] **Step 2: Add hash combine function**

Add a static inline helper:

```haxe
    static function pipelineKey( shaderId : Int, bits : Int, mask : Int, colorFmt : Int, depthFmt : Int ) : Int {
        var h = shaderId;
        h = (h << 5) - h + bits;
        h = (h << 5) - h + mask;
        h = (h << 5) - h + colorFmt;
        h = (h << 5) - h + (depthFmt > 0 ? 1 : 0);
        return h;
    }
```

- [ ] **Step 3: Replace cache key in selectMaterial**

In `selectMaterial()`, replace the string key:
```haxe
    var key = pipelineKey(currentShader.shader.id, bits, mask, pipeColorFmt, pipeDepthFmt);
    var pipeline = pipelineCache.get(key);
    if( pipeline == null ) {
        // ... create pipeline ...
        pipelineCache.set(key, pipeline);
    }
```

- [ ] **Step 4: Build and test**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

- [ ] **Step 5: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): use integer hash for pipeline cache key

Replace string concatenation cache keys with integer hash combining
to avoid intermediate String allocations and GC pressure in the
draw call hot path."
```

---

## PR 3: Buffer & Allocation

### Task 7: Replace params pool with ring buffer

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — replace `paramsPool`/`paramsPoolIdx`, update `uploadBuffers(Params)`, `begin()`

- [ ] **Step 1: Replace params pool fields with ring buffer fields**

Replace:
```haxe
    var paramsPool : Array<{buf:Buffer, size:Int}>;
    var paramsPoolIdx : Int;
```
with:
```haxe
    var paramsRingBuffer : Buffer;
    var paramsRingSize : Int;
    var paramsRingOffset : Int;
    static inline var PARAMS_RING_INITIAL = 1 << 20; // 1 MB
    static inline var PARAMS_ALIGN = 256;
```

- [ ] **Step 2: Initialize ring buffer**

In `reset()` or `new()`, replace params pool init:
```haxe
    paramsRingSize = PARAMS_RING_INITIAL;
    paramsRingBuffer = MtlDrv.createBuffer(paramsRingSize, ResourceOptions.StorageModeShared);
    paramsRingOffset = 0;
```

- [ ] **Step 3: Reset ring offset in begin()**

In `begin()`, replace `paramsPoolIdx = 0` with:
```haxe
    paramsRingOffset = 0;
```

- [ ] **Step 4: Rewrite uploadBuffers Params path**

Replace the entire `case Params:` block in `uploadBuffers()` with:

```haxe
    case Params:
        if( shader.paramsSize > 0 && shader.params != null ) {
            var bytes = shader.paramsSize << 4;
            // Align to 256 bytes for Metal buffer offset requirement
            var offset = (paramsRingOffset + PARAMS_ALIGN - 1) & ~(PARAMS_ALIGN - 1);
            if( offset + bytes > paramsRingSize ) {
                // Grow ring buffer (double)
                paramsRingSize = paramsRingSize * 2;
                while( offset + bytes > paramsRingSize )
                    paramsRingSize = paramsRingSize * 2;
                paramsRingBuffer = MtlDrv.createBuffer(paramsRingSize, ResourceOptions.StorageModeShared);
            }
            var data = hl.Bytes.getArray(buffers.params.toData());
            var contents = paramsRingBuffer.contents();
            contents.blit(offset, data, 0, bytes);
            if( isVertex )
                MtlDrv.setVertexBuffer(paramsRingBuffer, offset, 1);
            else
                MtlDrv.setFragmentBuffer(paramsRingBuffer, offset, 1);
            paramsRingOffset = offset + bytes;
        }
```

- [ ] **Step 5: Build and test**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && METAL_DEVICE_WRAPPER_TYPE=1 perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

- [ ] **Step 6: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): replace per-draw params pool with ring buffer

Single large ring buffer sub-allocated per draw with 256-byte
alignment. Reduces per-frame allocations from O(draws) to O(1)
and eliminates the unbounded pool growth problem."
```

### Task 8: Store vertex layout on CompiledShader

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — `CompiledShader` class, `compileShader()`, `makePipelineWithBlend()`

- [ ] **Step 1: Add layout field to CompiledShader**

In the `CompiledShader` class, add:
```haxe
    public var layout : hl.NativeArray<LayoutElement>;
```

- [ ] **Step 2: Store layout during compileShader**

At the end of `compileShader()`, before `return s;`, add:
```haxe
    s.layout = buildVertexLayout(s);
```

- [ ] **Step 3: Reuse layout in makePipelineWithBlend**

Replace:
```haxe
    function makePipelineWithBlend( s : CompiledShader, blendDesc : BlendDesc, colorFormat : Int, depthFormat : Int, stride : Int ) : PipelineState {
        var layout = buildVertexLayout(s);
```
with:
```haxe
    function makePipelineWithBlend( s : CompiledShader, blendDesc : BlendDesc, colorFormat : Int, depthFormat : Int, stride : Int ) : PipelineState {
        var layout = s.layout;
```

- [ ] **Step 4: Build and test**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

- [ ] **Step 5: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): cache vertex layout on CompiledShader

Vertex layout is invariant per shader but was rebuilt on every
pipeline cache miss. Now computed once at compile time and reused."
```

### Task 9: Add globals dirty tracking

**Files:**
- Modify: `h3d/impl/MetalDriver.hx` — `ShaderContext` class, `compileShaderContext()`, `uploadBuffers(Globals)`

- [ ] **Step 1: Add prevContent field to ShaderContext**

In `ShaderContext` class, add:
```haxe
    public var globalsPrevContent : hl.Bytes;
```

- [ ] **Step 2: Allocate globalsPrevContent in compileShaderContext**

In `compileShaderContext()`, after the globals buffer creation line:
```haxe
    if( ctx.globalsSize > 0 )
        ctx.globals = MtlDrv.createBuffer(ctx.globalsSize * 16, ResourceOptions.StorageModeShared);
```
Add:
```haxe
    if( ctx.globalsSize > 0 )
        ctx.globalsPrevContent = new hl.Bytes(ctx.globalsSize * 16);
```

- [ ] **Step 3: Pass prevContent in uploadBuffers Globals path**

In `uploadBuffers()`, in `case Globals:`, change:
```haxe
    uploadShaderBuffer(shader.globals, buffers.globals, shader.globalsSize, null);
```
to:
```haxe
    uploadShaderBuffer(shader.globals, buffers.globals, shader.globalsSize, shader.globalsPrevContent);
```

This enables the existing comparison logic in `uploadShaderBuffer` (which checks `prevContent.compare()`) to skip redundant uploads.

- [ ] **Step 4: Build and test**

```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

- [ ] **Step 5: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "perf(metal): add dirty tracking for globals buffer upload

Skip re-uploading shader globals when content hasn't changed since
last upload, using the same prevContent comparison already used
for params buffers."
```

---

## PR 4: Shader Caching

### Task 10: Add MTLBinaryArchive for persistent pipeline caching

**Files:**
- Modify: `libs/metal/metal.mm` — add archive management, modify `create_render_pipeline`

- [ ] **Step 1: Add global archive variable and init/save functions**

In `metal.mm`, add after the `g_driver` struct definition:

```objc
static id<MTLBinaryArchive> g_pipelineArchive = nil;
static NSString *kArchivePath = @"/tmp/hlmetal_pipeline_archive.bin";

static void loadPipelineArchive() {
    if( !g_driver || g_pipelineArchive ) return;
    NSError *err = nil;
    NSURL *url = [NSURL fileURLWithPath:kArchivePath];
    if( [[NSFileManager defaultManager] fileExistsAtPath:kArchivePath] ) {
        g_pipelineArchive = [[MTLBinaryArchive alloc] initWithURL:url error:&err];
        if( err ) g_pipelineArchive = nil;
    }
    if( !g_pipelineArchive ) {
        MTLBinaryArchiveDescriptor *desc = [[MTLBinaryArchiveDescriptor alloc] init];
        g_pipelineArchive = [g_driver->device newBinaryArchiveWithDescriptor:desc error:&err];
        if( err ) {
            g_pipelineArchive = nil;
        }
    }
}

static void savePipelineArchive() {
    if( !g_pipelineArchive ) return;
    NSError *err = nil;
    NSURL *url = [NSURL fileURLWithPath:kArchivePath];
    [g_pipelineArchive serializeToURL:url error:&err];
}
```

- [ ] **Step 2: Add archive init/save native functions**

```objc
HL_PRIM void HL_NAME(init_pipeline_archive)() {
    loadPipelineArchive();
}

HL_PRIM void HL_NAME(save_pipeline_archive)() {
    savePipelineArchive();
}
```

Add DEFINE_PRIM entries:
```objc
DEFINE_PRIM(_VOID, init_pipeline_archive, _NO_ARG);
DEFINE_PRIM(_VOID, save_pipeline_archive, _NO_ARG);
```

- [ ] **Step 3: Modify create_render_pipeline to use archive**

In `create_render_pipeline`, after creating the `MTLRenderPipelineDescriptor *desc` and setting all its properties, before the `newRenderPipelineStateWithDescriptor` call, add archive support:

```objc
    NSError *err = nil;
    id<MTLRenderPipelineState> pipeline;
    if( g_pipelineArchive ) {
        MTLRenderPipelineStateDescriptor *psDesc = [[MTLRenderPipelineStateDescriptor alloc] init];
        psDesc.binaryArchives = @[g_pipelineArchive];
        pipeline = [g_driver->device newRenderPipelineStateWithDescriptor:desc
                                                          options:MTLPipelineOptionFailOnBinaryArchiveMiss
                                                 reflection:nil
                                                      error:&err];
        if( !pipeline ) {
            // Cache miss — compile normally and add to archive
            err = nil;
            pipeline = [g_driver->device newRenderPipelineStateWithDescriptor:desc error:&err];
            if( pipeline ) {
                [g_pipelineArchive addRenderPipelineFunctionsWithDescriptor:desc error:nil];
            }
        }
    } else {
        pipeline = [g_driver->device newRenderPipelineStateWithDescriptor:desc error:&err];
    }
```

- [ ] **Step 4: Add Haxe externs and call from MetalDriver**

In `libs/metal/metal/Driver.hx`, add:
```haxe
    @:hlNative("metal","init_pipeline_archive")
    public static function initPipelineArchive() : Void {}

    @:hlNative("metal","save_pipeline_archive")
    public static function savePipelineArchive() : Void {}
```

In `MetalDriver.hx`, in `init()`, after `MtlDrv.create(...)`:
```haxe
    MtlDrv.initPipelineArchive();
```

In `present()` or `end()`, add archive save (periodically, e.g., every 60 frames):
```haxe
    if( frame % 60 == 0 ) MtlDrv.savePipelineArchive();
```

- [ ] **Step 5: Rebuild metal.hdll and test**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master/libs/metal/build && cmake --build . && cp metal.hdll /usr/local/lib/hl/ && codesign -s - /usr/local/lib/hl/metal.hdll
```

First run compiles shaders. Second run should be faster (hits archive). Verify:
```bash
cd /Users/rayloi/Desktop/HelloWorld_HL && haxe build.hxml && perl -e 'alarm 10; exec @ARGV' hl main.hl 2>&1; echo "EXIT: $?"
```

- [ ] **Step 6: Commit**

```bash
cd /Users/rayloi/Documents/GitHub/hashlink-master && git add libs/metal/metal.mm libs/metal/metal/Driver.hx && git commit -m "feat(metal): add MTLBinaryArchive for persistent pipeline caching

Store compiled pipeline data to /tmp/hlmetal_pipeline_archive.bin.
On second app launch, pipelines load from archive instead of
recompiling, eliminating first-use shader hitches."
```

```bash
cd /Users/rayloi/Documents/GitHub/heaps && git add h3d/impl/MetalDriver.hx && git commit -m "feat(metal): integrate pipeline archive into MetalDriver lifecycle

Load archive at init, save periodically (every 60 frames)."
```

---

## Self-Review Checklist

- [x] **Spec coverage**: Each PR section in the spec has corresponding tasks
- [x] **Placeholder scan**: No TBD, TODO, or "implement later" — all steps contain actual code
- [x] **Type consistency**: `Buffer`, `PipelineState`, `Texture`, `SamplerState` types match between Driver.hx externs and MetalDriver.hx usage. `CullMode`/`Winding` enums added to Format.hx before use.

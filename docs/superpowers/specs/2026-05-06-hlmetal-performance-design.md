# hlmetal Performance Optimization Design

**Date**: 2026-05-06
**Target**: Apple Silicon (unified memory)
**Scope**: Both hitch elimination and steady-state FPS improvement

## Architecture Overview

Four incremental PRs, each independently verifiable, ordered by impact:

| PR | Focus | Expected Impact |
|----|-------|-----------------|
| PR 1 | Frame pipelining | Eliminates largest CPU stall (~1 frame GPU latency) |
| PR 2 | Draw call optimization | Fixes backface culling bug; reduces per-draw overhead |
| PR 3 | Buffer & allocation | Reduces allocation count from O(draws) to O(1) per frame |
| PR 4 | Shader caching | Eliminates first-use shader compilation hitches |

---

## PR 1: Frame Pipelining

### Problem

`metal.mm` line 74: `beginFrame()` calls `[prevCommandBuffer waitUntilCompleted]`, blocking the CPU until the GPU finishes executing the previous frame. This gives zero frames of CPU/GPU overlap.

### Changes

**`metal.mm` `begin_frame()`**:
- Replace `[g_driver->prevCommandBuffer waitUntilCompleted]` with `[g_driver->prevCommandBuffer waitUntilScheduled]`
- `waitUntilScheduled` only blocks until the command buffer is submitted to the GPU hardware queue, not until execution finishes
- This gives 1 frame of CPU/GPU overlap (CPU builds frame N+1 while GPU executes frame N)

**Unchanged**: Readback paths (`texture_read_pixels`, `read_drawable_pixels`) remain `waitUntilCompleted` since pixel readback is inherently synchronous.

### Files

- `libs/metal/metal.mm` — `begin_frame()` line 74

### Risk

Very low. `waitUntilScheduled` guarantees the command buffer is enqueued and resources are safe. This is Apple's recommended pattern for frame pipelining.

---

## PR 2: Draw Call Optimization

### 2a. Backface Culling

**Problem**: `MetalDriver.selectMaterial()` sets `allowDraw` based on cull mode but never calls Metal's `setCullMode` / `setFrontFacingWinding`. All triangles are rasterized, doubling GPU workload.

**Changes**:

- Add native functions `set_cull_mode(int mode)` and `set_front_facing_winding(int winding)` to `metal.mm`
- Add Haxe externs in `metal/Driver.hx`
- In `MetalDriver.selectMaterial()`, after depth/stencil handling:
  - Extract cull mode from pass bits (None/Front/Back/Both)
  - Map to Metal `MTLCullMode` (None/Front/Back)
  - Call `MtlDrv.setCullMode(mode)` with caching (`currentCullMode`)
  - Set front-facing winding to `MTLWindingCounterClockwise` (matching Heaps' coordinate system)
- Map `Both` to `allowDraw = false` (skip draw entirely), matching existing behavior

### 2b. Eliminate Redundant Pipeline Set

**Problem**: `selectShader()` creates and sets a pipeline with default blend. Then `selectMaterial()` creates and sets a different pipeline with actual blend. The first pipeline set is wasted.

**Changes**:

- Remove pipeline creation and `setRenderPipeline` from `selectShader()`
- `selectShader()` only compiles/caches the shader and sets `currentShader`
- Pipeline creation happens exclusively in `selectMaterial()`, which runs after `selectShader()`
- If no material is selected before the first draw (edge case), defer pipeline creation to the draw call itself or create a default pipeline lazily
- The pipeline cache remains keyed by (shader, blend bits, color format, depth format)

### 2c. Texture & Viewport Binding Cache

**Problem**: Every texture and sampler is re-bound on every draw call. Viewport is re-set on every render target switch even when unchanged.

**Changes**:

- Add `currentTextures : Array<metal.Driver.Texture>` and `currentSamplers : Array<metal.Driver.Sampler>` to track current bindings
- In `uploadBuffers(Textures)`, compare against cached values before calling `setFragmentTexture`/`setFragmentSampler`/`setVertexTexture`/`setVertexSampler`
- Reset caches in `resetRenderState()` (set all entries to null)
- Add `currentViewport : {x:Int, y:Int, w:Int, h:Int, zn:Float, zf:Float}` tracking
- Skip `setViewport` call when viewport hasn't changed
- Reset viewport cache in `resetRenderState()`

### 2d. Integer Pipeline Cache Key

**Problem**: Cache keys built via string concatenation (`shader.id + "_" + bits + "_" + ...`) create intermediate String objects and GC pressure in the hot path.

**Changes**:

- Replace `Map<String, PipelineState>` with `Map<Int, PipelineState>`
- Hash function: combine fields via bit mixing (e.g., `shaderId ^ (bits << 16) ^ (mask << 8) ^ colorFmt ^ (depthFmt > 0 ? 0x80000000 : 0)`)
- Use `haxe.crypto.MurmurHash` or a simple inline hash combine

### Files

- `h3d/impl/MetalDriver.hx` — `selectMaterial()`, `selectShader()`, `uploadBuffers()`, `_setRenderTargets()`, `beginDefaultPass()`
- `libs/metal/metal.mm` — add `set_cull_mode`, `set_front_facing_winding`
- `libs/metal/metal/Driver.hx` — add externs

---

## PR 3: Buffer & Allocation

### 3a. Single Ring Buffer for Params

**Problem**: `paramsPool` allocates individual `MTLBuffer` objects per draw call. First frame has O(draws) allocations. Pool grows but never shrinks.

**Changes**:

- Replace `paramsPool` with a single large `MTLBuffer` (e.g., 1 MB) allocated once
- Maintain `ringOffset : Int` per frame, reset to 0 in `begin()`
- For each params upload:
  - Compute `bytes = shader.paramsSize << 4`
  - Align offset to 256 bytes: `offset = align(ringOffset, 256)`
  - Write data at `contents + offset` via `blit`
  - Advance `ringOffset = offset + bytes`
  - Bind with `setVertexBuffer(buf, offset, 1)` and `setFragmentBuffer(buf, offset, 1)` (offset parameter)
  - If ring buffer would overflow, allocate a larger buffer and replace
- O(1) allocation per frame instead of O(draws)

### 3b. Store Vertex Layout on CompiledShader

**Problem**: `buildVertexLayout()` allocates new `NativeArray<LayoutElement>` and `LayoutElement` objects on every pipeline cache miss. Layout is invariant per shader.

**Changes**:

- Add `layout : hl.NativeArray<LayoutElement>` field to `CompiledShader`
- In `compileShader()`, store the layout: `s.layout = buildVertexLayout(s)`
- In `makePipelineWithBlend()`, reuse: `var layout = s.layout` instead of calling `buildVertexLayout`

### 3c. Globals Dirty Tracking

**Problem**: Globals buffer is uploaded every time `uploadShaderBuffers(Globals)` is called, even when unchanged. No `prevContent` comparison exists for globals.

**Changes**:

- Add `globalsPrevContent : hl.Bytes` to `ShaderContext`, allocated alongside `globals` buffer
- In `uploadShaderBuffer()` for globals path, pass `globalsPrevContent` as the `prevContent` parameter
- `uploadShaderBuffer()` already has the comparison logic — just needs a non-null `prevContent` to activate it

### Files

- `h3d/impl/MetalDriver.hx` — `uploadBuffers()`, `compileShader()`, `makePipelineWithBlend()`, `ShaderContext` fields, `begin()`

---

## PR 4: Shader Caching

### 4a. MTLBinaryArchive for Pipeline Persistence

**Problem**: Every unique shader combination causes full MSL-to-GPU compilation at runtime. No caching across app runs.

**Changes**:

- In `metal.mm`, add a global `MTLBinaryArchive` that is:
  - Loaded from a file on startup (`initWithURL:`)
  - Updated after each pipeline creation (`addRenderPipelineFunctions:`)
  - Saved to disk periodically or on shutdown (`serializeToURL:`)
- Modify `create_render_pipeline` to pass the archive via `MTLPipelineStateBinaryArchiveDescriptor`
- On second app launch, pipelines hit the archive and skip compilation

### 4b. Cache Compiled Function Lookups

**Problem**: `create_render_pipeline` calls `[library newFunctionWithName:]` on every pipeline creation, performing string lookup each time.

**Changes**:

- Store `vsFunc` and `fsFunc` on `CompiledShader` in Haxe (as opaque native handles)
- Pass cached function objects directly to pipeline creation instead of entry name strings
- Add a `create_render_pipeline_from_functions` native path that takes `id<MTLFunction>` directly

### Files

- `libs/metal/metal.mm` — binary archive management, new pipeline creation path
- `libs/metal/metal/Driver.hx` — new externs
- `h3d/impl/MetalDriver.hx` — `CompiledShader` fields, `compileShader()`, `makePipelineWithBlend()`

---

## Out of Scope (Future Work)

These were identified but excluded to keep scope focused:

- **Indirect / multi-draw**: Requires significant Engine-level changes; low ROI for typical Heaps workloads
- **Compressed texture support**: Feature gap, not a performance issue
- **Mipmap generation**: Feature gap; `generateMipMaps` throw can be replaced with blit encoder
- **Device error recovery**: Robustness feature, not performance
- **Compute shaders**: Feature gap
- **Debug markers**: Debugging aid (should be added as no-op → real implementation)

## Verification Plan

Each PR should be verified with:

1. **CubeTest** (forward renderer): No regressions, cube renders correctly with shadows
2. **HelloWorld_HL** (PBR renderer): No SIGSEGV, runs stably for 30+ seconds
3. **Metal API Validation** (`METAL_DEVICE_WRAPPER_TYPE=1`): Zero validation errors
4. **Xcode Instruments GPU profiler**: Compare frame time before/after each PR

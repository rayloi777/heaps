# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

Heaps uses Haxe as its build system. All compilation is done via `haxe` with `.hxml` files.

```bash
# Build the main heaps library (all targets)
haxe all.hxml

# Build samples
cd samples
haxe gen.hxml                           # Generate project files
haxe all.hxml                           # Build all sample targets

# Build a specific sample
haxe [sample]_js.hxml                   # JavaScript/WebGL
haxe [sample]_hl.hxml                   # HashLink (use -lib hlsdl for OpenGL or -lib hldx for DirectX)
haxe [sample]_swf.hxml                  # Flash
```

The `all.hxml` root file builds for multiple targets: JS/WebGL, HashLink+SDL, HashLink+DX, and HashLink+DX12.

## Architecture

Heaps is a cross-platform GPU game framework written in Haxe. The codebase is organized into four main modules:

### Core Modules
- **`hxd`** (cross-platform) - Windowing, input, system utilities, resources, and the base `App` class. Entry point for applications is `hxd.App`.
- **`h2d`** (2D rendering) - Scene graph, sprites, tiles, text, fonts, UI elements (`h2d.Scene`, `h2d.Object`, `h2d.Text`, `h2d.Flow`, etc.)
- **`h3d`** (3D rendering) - Engine, scene graph, meshes, primitives, materials, passes, cameras, lighting
- **`hxsl`** (shader language) - Haxe Shader Language compiler - translates HXS to GLSL/HLSL/etc

### Rendering Architecture
The 3D engine uses a driver-based architecture for multi-platform support:
- `h3d.impl.Driver` - Base driver interface
- `h3d.impl.GlDriver` - OpenGL/WebGL (JS, Linux, macOS)
- `h3d.impl.DirectXDriver` - DirectX 9 (Windows)
- `h3d.impl.DX12Driver` - DirectX 12 (Windows)
- `h3d.impl.VulkanDriver` - Vulkan
- `h3d.impl.NullDriver` - No-op fallback

The driver is selected at compile-time via Haxe conditional compilation (`-lib hlsdl`, `-lib hldx`, etc.).

### Application Structure
Typical app extends `hxd.App`:
1. Subclass `hxd.App` and override `init()` for setup, `update(dt)` for per-frame logic
2. Access `s3d` for the 3D scene, `s2d` for the 2D scene
3. Call `hxd.Res.initEmbed()` or `hxd.Res.initLocal()` for resource loading
4. Resources are placed in `res/` directories and accessed via `hxd.Res.<path>`

### Shader Pipeline
- Shaders are written in Haxe-style syntax using `hxsl` (HXSL)
- The compiler transforms them to GLSL or HLSL depending on target
- Runtime shader data is stored in `hxsl.RuntimeShader`

### Key Paths
- Samples: `/samples/` - Each sample extends `samples/SampleApp.hx`
- 3D scene: `/h3d/scene/` - Scene classes (`Scene.hx`, `Mesh.hx`, `Camera.hx`, `Light.hx`)
- 3D materials: `/h3d/mat/` - Material system (`Material.hx`, passes)
- Resources: `/hxd/res/` - Resource management (`Res.hx`, file loaders)
- 2D UI: `/h2d/` - 2D rendering and UI components

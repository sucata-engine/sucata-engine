# AGENT.md — Building a game with the Sucata Engine

This file is a practical, self-contained guide for creating a game with **Sucata**, a 2D game engine built with Odin (core) and scripted with **Lua** (game logic), in the spirit of Love2D/Godot. It's aimed at whoever (human or AI agent) is writing a *game* on top of Sucata — not at contributors to the engine's own source. For that, see the sibling repos [sucata-cli/AGENT.md](../sucata-cli/AGENT.md) and [sucata-player/AGENT.md](../sucata-player/AGENT.md).

The full generated Lua API reference lives at [sucata.dev/references](https://sucata.dev/references) (source: `../docs/docs/references/sucata.*.md` in this workspace). This guide condenses everything needed to be productive without leaving this file, and links out for exhaustive per-function detail.

## What Sucata is

- **Engine core**: Odin, using sokol for graphics/audio-input plumbing, SDL3 for gamepad, miniaudio for audio.
- **Game logic**: pure Lua. You never touch Odin to make a game — only to contribute to the engine itself.
- **Everything is data + functions.** There is no class/inheritance system and no scene-graph hierarchy. A game is a flat pool of *entities* (state + a list of reusable *behaviours*) plus global systems (input, audio, timers, events) you call from Lua.

## Setup

```bash
# install (see sucata.dev/getting-started/installation for the one-liner per OS)
sucata version   # verify install
```

Recommended: install the [sumneko Lua extension](https://luals.github.io) + the **sucata** Lua addon (Addon Manager → search "sucata") for autocompletion against the engine's Lua API (mirrors `sucata-lua-addon/library/sucata/*.lua` in this workspace).

## CLI commands

| Command | Purpose |
|---|---|
| `sucata run <main.lua> [--entity <file>]` | Run a game (or a single entity file, for isolated testing) through the engine (`sucata-player`) in dev mode. |
| `sucata build <main.lua> [--icon <path>]` | Package the game into a native, OS-specific distributable (see "Building" below). Current OS only, no cross-build yet. |
| `sucata shader build <file.glsl>` | Compile a custom `.glsl` shader into the engine's `.schd` format. |
| `sucata shader create <file> [--post-processing\|-pp] [--font\|-f]` | Scaffold a starter `.glsl` shader template. |
| `sucata version` | Print engine version. |

## Project layout convention

There's no enforced scaffold, but every existing Sucata game (including the official `meteors-sucata` example) follows this shape:

```
my-game/
├── main.lua              Entry point — required first by `sucata run`/`sucata build`
├── config.lua             Window setup (see below) — required from main.lua
├── behaviours/
│   ├── init.lua           Aggregates ALL behaviours into one shared table (see "Behaviours" below — important!)
│   ├── player.lua
│   ├── meteor.lua
│   └── ...
├── entities/              Factory functions: fn(...) -> { state = {...}, behaviours = {...} }
│   ├── player.lua
│   ├── meteor.lua
│   └── ...
├── states/                Optional: plain modules of pure functions that mutate a state field
│   └── health.lua         (shared logic callable from multiple behaviours, e.g. health.remove(state))
├── sprites/                Texture assets (.png)
├── sounds/                 Audio assets (.ogg, etc)
└── fonts/                  Font assets
```

`main.lua` example:

```lua
require("config")

Behaviours = require("behaviours")  -- single shared reference, see below

local Player = require("entities.player")
local game_manager = require("entities.game_manager")

sucata.scene.spawn(Player(480, 500))
sucata.scene.spawn(game_manager)
```

`config.lua` example — window setup, conventionally isolated in its own file:

```lua
sucata.window.set_window_size(960, 540)
sucata.window.set_keep_aspect(1) -- 0 = off, 1 = keep aspect with bars, 2 = keep aspect with crop
sucata.window.set_window_title("My Game")
sucata.window.set_vsync(1)
sucata.window.show_debug_info(true) -- disable before shipping
sucata.window.set_window_icon("src://icon.png")
sucata.window.set_fullscreen(false)
```

Asset/require paths use the `src://` virtual prefix, meaning "project root" — it resolves correctly both when running from loose files in dev mode and from inside the compiled `assets.scta` archive after `sucata build`. Always reference project assets this way: `"src://sprites/ship.png"`.

## Core concepts

### Scene

A scene is just the pool of currently-active entities. `sucata.scene.load_scene(entities)` loads a whole array at once; `sucata.scene.spawn(entity)` adds one and returns its id.

### Entity

An entity is a plain table with two fields:

```lua
{
  state = { x = 0, y = 0 },      -- unique data for this entity (id is injected by the engine on spawn)
  behaviours = { Behaviours.Foo, Behaviours.Bar }, -- ordered list of behaviours applied to it
}
```

Entities are usually built via a factory function in `entities/<name>.lua`:

```lua
-- entities/player.lua
local function player(x, y)
  return {
    state = { x = x, y = y },
    behaviours = { Behaviours.Player, Behaviours.Shooter, Behaviours.DrawSprite },
  }
end

return player
```

```lua
sucata.scene.spawn(Player(480, 500))
```

### Behaviour — the core building block

A behaviour is a **stateless, reusable** table of up to four optional functions, all receiving the entity's `state` table:

```lua
return {
  init = function(state) end,  -- once, when the entity is spawned/scene loads
  tick = function(state) end,  -- every frame, before drawing — game logic, input, physics
  draw = function(state) end,  -- every frame — call sucata.graphic.* here ONLY (see Rendering)
  free = function(state) end,  -- once, right before the entity is removed from the scene
}
```

**Behaviours on an entity run in the order listed.** Put logic before rendering (e.g. `Player` movement before `DrawSprite`).

> **How behaviour reuse works**: Sucata registers a behaviour once per Lua table *pointer identity* and shares that registration across every entity referencing it. Since `require()` already caches modules (`package.loaded`), calling `require("behaviours.player")` from any file returns the same shared table every time — reuse works automatically, no special wiring needed.
>
> Most Sucata projects still aggregate behaviours into a single `behaviours/init.lua` table as an organizational convention (one place to see every behaviour, shorter references elsewhere):
>
> ```lua
> -- behaviours/init.lua
> return {
>   DrawSprite = require("behaviours.draw_sprite"),
>   Player     = require("behaviours.player"),
>   Shooter    = require("behaviours.shooter"),
> }
> ```
> ```lua
> -- main.lua
> Behaviours = require("behaviours")
> ```
> Then reference `Behaviours.Player` etc. — or `require("behaviours.player")` directly, both resolve to the same table either way.

A common building-block behaviour worth copying into most projects, `DrawSprite` (renders `state.texture`/`width`/`height` if present):

```lua
return {
  init = function(state)
    state.x = state.x or 0
    state.y = state.y or 0
    state.width = state.width or 32
    state.height = state.height or 32
    state.texture = state.texture or ""
    state.atlas_x = state.atlas_x or 0
  end,
  draw = function(state)
    sucata.graphic.draw_rect({
      x = state.x, y = state.y,
      width = state.width, height = state.height,
      texture = state.texture,
      origin = 0.5, -- center the sprite on x,y instead of top-left
      atlas_size = state.atlas_size,
      atlas_x = state.atlas_x,
    })
  end
}
```

Another common one, `ApplyForces` (simple velocity integration):

```lua
return {
  init = function(state)
    state.x = state.x or 0
    state.y = state.y or 0
    state.force_x = state.force_x or 0
    state.force_y = state.force_y or 0
  end,
  tick = function(state)
    local dt = sucata.time.get_delta()
    state.x = state.x + state.force_x * dt
    state.y = state.y + state.force_y * dt
  end
}
```

### No hierarchy — relationships via ids

Entities are flat; there's no parent/child tree. To relate entities, store one's id in another's state and resolve it later:

```lua
local bullet_id = sucata.scene.spawn(Bullet())
self.child_id = bullet_id
...
local bullet = sucata.scene.find_by_id(self.child_id)
if bullet then bullet.x = self.x end
```

### Tags

Group entities for querying (e.g. all enemies of a kind):

```lua
sucata.scene.add_tag(state, "meteor")
local meteors = sucata.scene.get_entities_by_tag("meteor")
for _, id in ipairs(meteors) do
  local meteor = sucata.scene.find_by_id(id)
  -- ...
end
```

Also: `sucata.scene.has_tag`, `sucata.scene.remove_tag`.

### Global/persistent entities

For systems that should survive scene reloads (e.g. a "game manager" holding score across level transitions), use `sucata.scene.load_global(key, entity)` / `sucata.scene.get_global(key)` / `sucata.scene.unload_global(key)` instead of `spawn`.

### Events

Simple pub/sub, decoupling systems (e.g. a meteor tells the game manager it reached the ground without knowing the game manager exists):

```lua
-- emitter (e.g. inside a meteor's tick)
sucata.events.emit("meteor_reached", state)

-- listener (e.g. inside the game manager's init)
sucata.events.on(state, "meteor_reached", function(meteor_state)
  -- react
end)
```

### Timers

```lua
sucata.time.create_timer(function()
  sucata.scene.spawn(meteor())
end, { time = 5, loop = true, auto_start = true })
```

Or the shorthand `sucata.time.create_timer(callback, seconds)` for a one-shot. Also: `sucata.time.pause_timer(id)`, `sucata.time.stop_timer(id)`, `sucata.time.get_delta()`, `sucata.time.get_fps()`, `sucata.time.get_time_scale()`/`set_time_scale()` (slow-mo / pause effects).

### "States" pattern (optional but recommended)

Plain modules of pure functions that mutate a piece of state, shareable across multiple behaviours instead of duplicating logic:

```lua
-- states/health.lua
local function remove(state)
  if not state.health then return end
  state.health = state.health - 1
end
return { remove = remove }
```

Used from any behaviour: `local health = require("states.health"); health.remove(meteor)`.

## Rendering

- `sucata.graphic.draw_rect(props)` and `sucata.graphic.draw_text(props)` are the **only** two draw primitives, and they may **only be called inside a behaviour's `draw(state)` function** — calling them elsewhere (init/tick) has no effect since drawing happens in a dedicated render pass.
- The engine batches all draw calls into one `renderQueue` per frame, grouped by `(z_index, texture, fixed, shader)`. For performance: reuse the **same texture** across similar sprites (use a texture atlas + `atlas_x`/`atlas_y`/`atlas_size` frame selection instead of many separate textures), and minimize the number of distinct `draw_text` calls.
- Textures not drawn in a given frame are unloaded from GPU memory automatically. A texture drawn `sucata.graphic.get_hot_texture_threshold()` times in a row (default 300) is promoted to "hot" and stays resident for the rest of the run. Call `sucata.graphic.preload_texture(path)` to force that promotion immediately (e.g. for UI/atlas textures you know will be reused constantly), or `sucata.graphic.set_hot_texture_threshold(n)` to tune the promotion threshold — pass `0` to disable automatic promotion entirely, so textures only go hot via an explicit `preload_texture` call.
- `origin = 0.5` centers the sprite on `x,y` (default origin is `0,0` = top-left corner).
- `fixed = true` on `RectProps`/`TextProps` renders relative to the screen, ignoring the camera (for UI/HUD).
- Texture atlas animation pattern (change frame based on state): set `atlas_x`/`atlas_y` in `tick`, e.g. `state.atlas_x = state.health - 1`.
- Camera: `sucata.camera.get_camera_position/set_camera_position`, `get_camera_rotation/set_camera_rotation`, `get_camera_zoom/set_camera_zoom` — moves/rotates/zooms the (non-fixed) world view.
- Custom shaders: `sucata.graphic.load_shader(path)` (loads a compiled `.schd`) → pass the returned id as `shader` in `draw_rect`/`draw_text` props, or `sucata.graphic.add_post_processing(shader_id)` for full-screen post-fx, tunable at runtime with `sucata.graphic.set_post_processing_args(shader_id, field, value)`.

## Input

```lua
if sucata.input.is_held("left", "a") then ... end
if sucata.input.is_pressed("space", "enter") then ... end -- fires once, on the frame pressed
```

`is_held`/`is_pressed`/`is_released` all take a variable number of key names (any match counts). Also: `sucata.input.get_mouse_position()`, `get_relative_mouse_position()` (camera-adjusted), `get_mouse_scroll()`, `get_key()`, and `sucata.input.is_hover({id, x, y, width, height, z_index?, fixed?})` for clickable UI regions (call every frame in `draw`; highest `z_index` wins on overlap).

Gamepad mirrors the same shape: `sucata.gamepad.is_held/is_pressed/is_released(button, device?)`, `get_axis(axis, device?)`, `get_count()`, `get_info(device)`.

## Audio

```lua
sucata.audio.play({ sound = "src://sounds/shoot.ogg" })
local music_id = sucata.audio.play({ sound = "src://sounds/music.ogg", loop = true, volume = 0.5 })
```

Returns a `sound_id` usable with `stop`/`pause`/`unpause`/`get_volume`/`set_volume`/`get_pitch`/`set_pitch`. Sounds can be mixed by `group` (default `"default"`), independently controllable via `get_group_volume`/`set_group_volume`/`get_group_pitch`/`set_group_pitch` (e.g. separate "sfx"/"music" groups).

## Filesystem

`sucata.filesystem.*` (`exists`, `read_file`, `write`, `mkdir`, `remove`, `rename`, `read_dir`) work with the same virtual prefixes: `src://` (project root — read-only once built), `data://` (per-user writable directory — use this for save files/settings), `build://` (build output dir).

## Building

```bash
sucata build main.lua --icon src://icon.png
```

Under the hood: `sucata` (the CLI) walks your Lua `require`s and `src://` asset references, compiles the Lua to bytecode, LZ4-compresses everything into a single `assets.scta` archive, then copies the `sucata-player` runtime binary (+ needed DLLs) and appends a signature binding it to that exact `assets.scta`. The resulting executable loads its bundled assets on launch — no separate installer needed. Currently you can only build for the OS you're running on (no cross-compilation yet).

## Full Lua API — condensed reference

Every module below is `sucata.<module>`. Full prose docs (with all fields/defaults) are in `../docs/docs/references/sucata.<module>.md` / https://sucata.dev/references.

**`sucata.scene`** — `load_scene(entities)`, `spawn(entity) -> id`, `spawns(entities) -> ids`, `find_by_id(id) -> entity|nil`, `destroy(entity_or_id) -> bool`, `destroys(entities) -> undestroyed_ids`, `add_tag/has_tag/remove_tag(entity_or_id, tag)`, `get_entities() -> ids`, `get_entities_by_tag(tag) -> ids`, `clear_entities()`, `init(callback)` (run once scene starts), `load_global(key, entity) -> id`, `get_global(key) -> entity|nil`, `unload_global(key)`.

**`sucata.graphic`** — `draw_rect(RectProps)`, `draw_text(TextProps)` (draw-phase only), `set_background_color(hex)`, `load_shader(path) -> id|nil`, `add_post_processing(shader_id)`, `set_post_processing_args(shader_id, field, number|string|table)`, `remove_post_processing(shader_id)`, `preload_texture(path)` (force-promotes a texture to "hot", see Rendering), `get_hot_texture_threshold() -> number`, `set_hot_texture_threshold(n)`. `RectProps`: `x,y,width,height,color,z_index,texture,scale(_x/_y),fixed,tiled,tile_size,tile_width,tile_height,origin(_x/_y),rotation,opacity,atlas_size,atlas_width,atlas_height,atlas_spacing,atlas_margin,atlas_x,atlas_y,shader,shader_args`. `TextProps`: `x,y,text,size,font,color,z_index,scale(_x/_y),fixed,origin(_x/_y),rotation,opacity,align,max_width,shader,shader_args`.

**`sucata.input`** — `is_pressed/is_held/is_released(...keys) -> bool`, `get_mouse_position()/get_relative_mouse_position() -> x,y`, `get_mouse_scroll() -> x,y`, `get_key() -> code`, `is_hover({id,x,y,width,height,z_index?,fixed?}) -> bool`. `Key` values: `"mouse_left/right/middle"`, `"a"`–`"z"`, `"space"`/`" "`, `"escape"`/`"esc"`, `"enter"`/`"return"`, `"shift"`, `"ctrl"`/`"control"`, `"alt"`, `"apostrophe"`, `"tab"`, `"up"/"down"/"left"/"right"`.

**`sucata.gamepad`** — `get_count() -> n`, `get_info(device) -> name`, `get_axis(Axis, device?) -> value, device_used`, `is_held/is_pressed/is_released(Button, device?) -> bool, device_used`. `Axis`: `left_x/left_y/right_x/right_y/trigger_left/trigger_right`. `Button`: `a/b/x/y/back/guide/start/left_stick/right_stick/left_shoulder/right_shoulder/dpad_up/down/left/right`.

**`sucata.audio`** — `play({sound,volume?,pitch?,group?,loop?}) -> sound_id`, `stop/pause/unpause(sound_id)`, `get_volume/set_volume(sound_id[, v])`, `get_pitch/set_pitch(sound_id[, p])`, `get_group_volume/set_group_volume(group_id[, v])`, `get_group_pitch/set_group_pitch(group_id[, p])`.

**`sucata.time`** — `get_delta() -> seconds`, `get_fps() -> n`, `create_timer(callback, seconds|Timer) -> id`, `pause_timer(id)`, `stop_timer(id)`, `get_time_scale()/set_time_scale(scale)`. `Timer`: `{time, auto_start=true, one_shot=true, loop=false}`.

**`sucata.events`** — `emit(name, data)`, `on(owner, name, callback)`.

**`sucata.camera`** — `get/set_camera_position(x,y)`, `get/set_camera_rotation(radians)`, `get/set_camera_zoom(zoom)`.

**`sucata.window`** — `get/set_mouse_lock(bool)`, `get/set_mouse_visible(bool)`, `get/set_window_title(str)`, `get/set_window_size(w,h)`, `get/set_fullscreen(bool)`, `get/set_vsync(n)`, `quit()`, `show_debug_info(bool)`, `get/set_keep_aspect(0|1|2)`, `get/set_window_icon(path)`, `get/set_cursor(name)`, `on_init(callback)`, `on_exit(callback)`.

**`sucata.filesystem`** — `exists(path) -> bool`, `remove(path)`, `mkdir(path)`, `read_file(path) -> str|nil`, `read_dir(path) -> table|nil`, `write(path, content) -> bool`, `rename(old, new)`.

**`sucata.math`** — `clamp(v,min,max)`, `distance(p1,p2)`, `lerp(a,b,t)`, `overlapping(Rect,Rect) -> bool, intersection|nil`, `screen_relative(ScreenRelativeRect) -> x,y,w,h`, `smooth_index(current_time, interval, max_index) -> index`, `normalize(...) -> ...`, `move_towards(current, target, step)`.

**`sucata.meta`** — `OS` (string), `VERSION` (string).

## Gotchas checklist

- Only call `sucata.graphic.draw_*` from inside `draw(state)`.
- Behaviours are shared by Lua table pointer identity; `require()`'s own module caching means referencing a behaviour via `Behaviours.Player` or a direct `require("behaviours.player")` both resolve to the same table.
- Behaviours execute in the order listed on the entity — order logic before rendering.
- `init`/`tick`/`draw`/`free` are all optional — omit what you don't need.
- Use `state.x = state.x or default` in `init` to make fields optional with sane defaults when constructing entities.
- Prefer one texture/atlas over many separate images, and batch text draws, for render performance.
- Use `src://` for bundled read-only assets, `data://` for writable save data.
- Disable `sucata.window.show_debug_info` before shipping.

## Related

- [sucata-cli/AGENT.md](../sucata-cli/AGENT.md) — the `sucata` CLI tool internals (Odin).
- [sucata-player/AGENT.md](../sucata-player/AGENT.md) — the engine runtime internals (Odin) and how the Lua API is bound.
- `docs/docs/references/sucata.*.md` — full prose API reference (source of the condensed table above).
- `docs/docs/getting-started/first-project/` — the full step-by-step Asteroids-style tutorial this guide is distilled from.

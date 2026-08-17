# AGENT.md — Building a game with the Sucata Engine

This file is a practical, self-contained guide for creating a game with **Sucata**, a 2D game engine built with Odin (core) and scripted with **Lua** (game logic), in the spirit of Love2D/Godot. It's aimed at whoever (human or AI agent) is writing a *game* on top of Sucata — not at contributors to the engine's own source. For that, see the sibling repos [sucata-cli/AGENT.md](https://github.com/sucata-engine/sucata-cli/blob/main/AGENT.md) and [sucata-player/AGENT.md](https://github.com/sucata-engine/sucata-player/blob/main/AGENT.md).

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
| `sucata build <main.lua> [--icon <path>] [--optimize]` | Package the game into a native, OS-specific distributable (see "Building" below). `--optimize` recompresses opaque images as JPEG to shrink the bundle. Current OS only, no cross-build yet. |
| `sucata shader build <file.glsl>` | Compile a custom `.glsl` shader into the engine's `.schd` format. |
| `sucata shader create <file> [--post-processing\|-pp] [--font\|-f]` | Scaffold a starter `.glsl` shader template. |
| `sucata version` | Print engine version. |

## Project layout convention

There's no enforced scaffold, but this project (and every existing Sucata game) follows this shape:

```
my-game/
├── main.lua               Entry point — required first by `sucata run`/`sucata build`
├── config.lua             Window setup (see below) — required from main.lua
├── behaviours/            Reusable init/tick/draw/free tables
│   ├── init.lua           Aggregator: exposes every behaviour in one table (see "Behaviours" — important!)
│   ├── animator.lua
│   ├── draw_sprite.lua
│   ├── forces.lua
│   └── player/            Entity-specific behaviours live in a subfolder named after the entity
│       ├── init.lua       Nested aggregator — reached as `behaviours.player.*`
│       ├── controller.lua
│       ├── movement.lua
│       └── punch.lua
├── entities/              Factory functions: fn(...) -> { state = {...}, behaviours = {...} }
│   └── player.lua
├── mutators/              Pure functions that read/mutate one slice of an entity's state
│   ├── init.lua           Aggregator — reached as `mutators.forces.*`, `mutators.status.*`
│   ├── forces.lua
│   └── status.lua
├── commons/               Shared constants/enums — data only, no logic, no state
│   └── status.lua
├── sprites/               Texture assets (.png, plus .ase sources), one subfolder per entity
│   └── player/
├── sounds/                Audio assets (.ogg, etc)
└── fonts/                 Font assets
```

Naming rules that keep the aggregators predictable:

- Files are `snake_case.lua`, and the key a module is exposed under in `init.lua` is exactly its file name (`draw_sprite.lua` → `draw_sprite`).
- A folder is always reached through its `init.lua`, never file by file: `require("behaviours")` and `require("mutators")` are the only entry points into those trees.
- A behaviour only one entity will ever use goes in `behaviours/<entity>/`; one any entity could reuse stays at the top level of `behaviours/`.

`main.lua` example:

```lua
require("config")

local player = require("entities.player")

sucata.scene.spawn(player(300, 500))
```

`config.lua` example — window setup, conventionally isolated in its own file:

```lua
sucata.window.set_window_size(1280, 720)
sucata.window.set_keep_aspect(1) -- 0 = off, 1 = keep aspect with bars, 2 = keep aspect with crop
sucata.window.set_window_title("My Game")
sucata.window.set_max_fps(0) -- 0 = uncapped
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
  behaviours = { behaviours.foo, behaviours.bar }, -- ordered list of behaviours applied to it
}
```

Entities are built via a factory function in `entities/<name>.lua`, which pulls everything it needs from the aggregators:

```lua
-- entities/player.lua
local behaviours = require("behaviours")

local function player(x, y)
  ---@type Entity
  return {
    state = { x = x, y = y, texture = "src://sprites/player/player.png" },
    behaviours = {
      behaviours.time,
      behaviours.player.controller, -- entity-specific, from behaviours/player/
      behaviours.status,
      behaviours.animator,
      behaviours.forces,
      behaviours.player.movement,
      behaviours.draw_sprite,       -- rendering last
    },
  }
end

return player
```

```lua
sucata.scene.spawn(player(300, 500))
```

### Behaviour — the core building block

A behaviour is a **stateless, reusable** table of up to four optional functions, all receiving the entity's `state` table:

```lua
---@type Behaviour
return {
  init = function(state) end,  -- once, when the entity is spawned/scene loads
  tick = function(state) end,  -- every frame, before drawing — game logic, input, physics
  draw = function(state) end,  -- every frame — call sucata.graphic.* here ONLY (see Rendering)
  free = function(state) end,  -- once, right before the entity is removed from the scene
}
```

Annotate every behaviour module with `---@type Behaviour` (and every entity factory's return with `---@type Entity`) so the sumneko addon type-checks the table.

**Behaviours on an entity run in the order listed.** Put logic before rendering (e.g. `movement` before `draw_sprite`).

> **Critical performance/correctness rule**: Sucata reuses behaviours that share the same Lua table *pointer identity*. Define each behaviour once, in its own file, and reach it only through an aggregator `init.lua`:
>
> ```lua
> -- behaviours/init.lua — generic behaviours + one key per entity subfolder
> return {
>   animator     = require("behaviours.animator"),
>   draw_sprite  = require("behaviours.draw_sprite"),
>   forces       = require("behaviours.forces"),
>   player       = require("behaviours.player"), -- resolves to behaviours/player/init.lua
> }
> ```
> ```lua
> -- behaviours/player/init.lua
> return {
>   controller = require("behaviours.player.controller"),
>   movement   = require("behaviours.player.movement"),
>   punch      = require("behaviours.player.punch"),
> }
> ```
> Consumers then do `local behaviours = require("behaviours")` at the top of the file and reference `behaviours.animator` / `behaviours.player.movement`. `require` caches by module name, so every file gets the same tables and reuse holds — but only if nothing bypasses the aggregator with a direct `require("behaviours.player.movement")`.

The building-block behaviours in this project — copy the shape when adding new ones. `draw_sprite` (renders the entity's sprite; note that it forwards optional fields as-is so `nil` falls back to engine defaults):

```lua
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 128, 128

---@type Behaviour
return {
  draw = function(state)
    sucata.graphic.draw_rect({
      x = state.x or 0,
      y = state.y or 0,
      width = state.width or DEFAULT_WIDTH,
      height = state.height or DEFAULT_HEIGHT,
      z_index = state.z_index or 0,
      origin_x = state.origin_x or 0.5, -- feet-anchored: centered horizontally
      origin_y = state.origin_y or 1,   -- with the bottom edge on state.y
      texture = state.texture,
      atlas_size = state.atlas_size,
      atlas_x = state.atlas_x,
      atlas_y = state.atlas_y,
      scale_x = state.scale_x,
      scale_y = state.scale_y,
      opacity = state.opacity,
      fixed = state.fixed,
    })
  end
}
```

`forces` — named-force accumulator, integrated once per frame. Behaviours never write `state.x` directly; they add/clear a *named* force through `mutators.forces` (see "Mutators" below) so gravity, jump and movement can coexist without overwriting each other:

```lua
---@type Behaviour
return {
  init = function(state)
    state.forces = {}
    state.velocity_x = 0
    state.velocity_y = 0
  end,
  tick = function(state)
    local delta = sucata.time.get_delta()
    local velocity_x, velocity_y = 0, 0
    for _, force in pairs(state.forces) do
      velocity_x = velocity_x + force.x
      velocity_y = velocity_y + force.y
    end
    state.velocity_x = velocity_x
    state.velocity_y = velocity_y
    state.x = state.x + (velocity_x * delta)
    state.y = state.y + (velocity_y * delta)
  end
}
```

### No hierarchy — relationships via ids

Entities are flat; there's no parent/child tree. To relate entities, store one's id in another's state and resolve it later:

```lua
local bullet_id = sucata.scene.spawn(bullet())
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

Events are global, so this project's convention for entity-scoped events (input intents, status changes) is to send `{ id = state.id, ... }` and have each listener filter on it — that's what lets `controller` stay a dumb input reader while `jump`/`punch` decide what to do:

```lua
-- behaviours/player/controller.lua
if sucata.input.is_pressed("space") then
  sucata.events.emit("jump", { id = state.id })
end

-- behaviours/jump.lua
sucata.events.on(state, "jump", function(data)
  if data.id == state.id and state.is_on_floor then
    mutators.forces.set_force(state, "jump", { x = 0, y = state.jump_force })
  end
end)
```

### Timers

```lua
sucata.time.create_timer(function()
  sucata.scene.spawn(meteor())
end, { time = 5, loop = true, auto_start = true })
```

Or the shorthand `sucata.time.create_timer(callback, seconds)` for a one-shot. Also: `sucata.time.pause_timer(id)`, `sucata.time.stop_timer(id)`, `sucata.time.get_delta()`, `sucata.time.get_fps()`, `sucata.time.get_time_scale()`/`set_time_scale()` (slow-mo / pause effects).

### Mutators — shared logic over a slice of state

`mutators/` holds plain modules of stateless functions that read and mutate one named slice of an entity's `state`, so multiple behaviours share the logic instead of duplicating it. They are the *only* thing that should touch that slice.

```lua
-- mutators/forces.lua (excerpt)
local function set_force(state, force_type, value)
  if not state.forces then return end
  state.forces[force_type] = value
end

local function clear_force(state, force_type)
  if not state.forces then return end
  set_force(state, force_type, { x = 0, y = 0 })
end

return { set_force = set_force, clear_force = clear_force, --[[ add_force, get_force, move_force_towards_zero ]] }
```

Every mutator module is re-exported from `mutators/init.lua`, and consumers require the folder, never the file:

```lua
local mutators = require("mutators")

mutators.forces.set_force(state, "jump", { x = 0, y = state.jump_force })
mutators.status.frooze_status(state, status.PUNCHING, 7 * 0.15)
```

Guard defensively (`if not state.forces then return end`) — a mutator may run against an entity whose behaviour list never initialised that slice.

Current mutators:

- **`mutators.forces`** — `get_force`, `set_force`, `add_force`, `clear_force`, `move_force_towards_zero`, all keyed by a force name (`"gravity"`, `"jump"`, `"movement"`).
- **`mutators.status`** — `set_status`, `frooze_status(state, status, time)` (locks the status for N seconds via a timer), `is_status(state, {..})`.

### Commons — shared constants

`commons/` holds data-only modules: enums and constants shared across behaviours, entities and mutators. No functions, no state.

```lua
-- commons/status.lua
return {
  IDLE = 0, WALKING = 1, JUMPING = 2,
  LANDING = 3, PUNCHING = 4, DEFENSING = 5,
}
```

Required directly by file (there's no aggregator here, since each constant set is independent): `local status = require("commons.status")`.

### Status + animation convention

The `status`/`animator` pair is how entities drive their sprite. An entity exposes `state.get_status(state)`, the `status` behaviour calls it each tick and emits `"status_changed"` when the value flips, and `animator` maps the current status to a row of the texture atlas via `state.animations[status] = { atlas_y, time, frames, one_shot? }`. Order matters: `status` must run before `animator`, and both before `draw_sprite`.

## Rendering

- `sucata.graphic.draw_rect(props)` and `sucata.graphic.draw_text(props)` are the **only** two *sprite/world* draw primitives, and they may **only be called inside a behaviour's `draw(state)` function** — calling them elsewhere (init/tick) has no effect since drawing happens in a dedicated render pass. For buttons/checkboxes/sliders/text input, use `sucata.ui.*` instead (see UI below) — it's a separate, immediate-mode widget system, not built on `draw_rect`/`draw_text`.
- The engine batches all draw calls into one `renderQueue` per frame, grouped by `(z_index, texture, fixed, shader)`. For performance: reuse the **same texture** across similar sprites (use a texture atlas + `atlas_x`/`atlas_y`/`atlas_size` frame selection instead of many separate textures), and minimize the number of distinct `draw_text` calls.
- `origin = 0.5` centers the sprite on `x,y` (default origin is `0,0` = top-left corner).
- `fixed = true` on `RectProps`/`TextProps` renders relative to the screen, ignoring the camera (for UI/HUD).
- Texture atlas animation pattern (change frame based on state): set `atlas_x`/`atlas_y` in `tick` — in this project that's the `animator` behaviour's job (`atlas_y` = row per status, `atlas_x` = frame, via `sucata.math.smooth_index` for loops or a clamped counter for `one_shot`), so add animations to `state.animations` rather than writing `atlas_*` from your own behaviour.
- Camera: `sucata.camera.get_camera_position/set_camera_position`, `get_camera_rotation/set_camera_rotation`, `get_camera_zoom/set_camera_zoom` — moves/rotates/zooms the (non-fixed) world view.
- Custom shaders: `sucata.graphic.load_shader(path)` (loads a compiled `.schd`) → pass the returned id as `shader` in `draw_rect`/`draw_text` props, or `sucata.graphic.add_post_processing(shader_id)` for full-screen post-fx, tunable at runtime with `sucata.graphic.set_post_processing_args(shader_id, field, value)`.

## UI

Immediate-mode widgets ([microui](https://github.com/rxi/microui)-backed), separate from `sucata.graphic`. Every `sucata.ui.draw_*`/`popup_open` call takes **one table** and must happen inside `draw(state)`, same as the sprite primitives — calling one elsewhere is a no-op (logs an error).

```lua
-- widgets placed directly on screen, no visible window needed
sucata.ui.draw_label({ text = "Score: " .. state.score })

if sucata.ui.draw_button({ text = "Pause" }) then
  sucata.events.emit("pause_pressed")
end

-- widgets inside a window
if sucata.ui.draw_window({ title = "Settings", x = 40, y = 40, width = 260, height = 160 }) then
  local changed, volume = sucata.ui.draw_slider({ id = "volume", value = 80, low = 0, high = 100 })
  if changed then sucata.audio.set_group_volume("music", volume / 100) end

  sucata.ui.end_window()
end
```

- **No window needed**: a widget drawn without an open `draw_window`/`draw_popup` around it lands on an implicit full-screen root canvas automatically — there's no `draw_root()` to call.
- **Contract**: `draw_window`/`draw_popup` return whether the container is open — only call the matching `end_window`/`end_popup` **if and only if** that call returned `true` (mirrors vanilla microui's C API). Calling `end_*` unconditionally, or skipping it after a `true`, corrupts the UI's internal state for the rest of the run.
- Popups: `sucata.ui.popup_open({name=...})` to trigger (e.g. from a button click), then `sucata.ui.draw_popup({name=...})` — same name — to place its contents; closes automatically on an outside click.
- Stateful widgets (`draw_checkbox`, `draw_slider`, `draw_textbox`) persist their value across frames keyed by a required `id` string you choose — reuse the same `id` for the same logical widget every frame, and don't reuse it for two different widgets.
- Every `draw_*` call accepts optional style overrides in the same table: `x`/`y`/`width`/`height` (must be given together to override auto-layout), `text_size`, `color`, `background_color`, `border_color` (all `{r,g,b,a?}`, 0.0-1.0).

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

**`sucata.graphic`** — `draw_rect(RectProps)`, `draw_text(TextProps)` (draw-phase only), `set_background_color(hex)`, `load_shader(path) -> id|nil`, `add_post_processing(shader_id)`, `set_post_processing_args(shader_id, field, number|string|table)`, `remove_post_processing(shader_id)`. `RectProps`: `x,y,width,height,color,z_index,texture,scale(_x/_y),fixed,tiled,tile_size,tile_width,tile_height,origin(_x/_y),rotation,opacity,atlas_size,atlas_width,atlas_height,atlas_spacing,atlas_margin,atlas_x,atlas_y,shader,shader_args`. `TextProps`: `x,y,text,size,font,color,z_index,scale(_x/_y),fixed,origin(_x/_y),rotation,opacity,align,max_width,shader,shader_args`.

**`sucata.ui`** — immediate-mode widgets, every call takes one table, only inside `draw(state)`: `draw_window(UIWindowProps) -> open`, `end_window()`, `popup_open({name})`, `draw_popup({name}) -> open`, `end_popup()`, `draw_label({text,...UIStyle})`, `draw_text({text,...UIStyle})`, `draw_button({text,...UIStyle}) -> clicked`, `draw_checkbox({id,text,...UIStyle}) -> changed, checked`, `draw_slider({id,value,low,high,step,...UIStyle}) -> changed, value`, `draw_textbox({id,text,...UIStyle}) -> changed, submitted, text`. `end_*` only if the matching `draw_*` returned `true`; widgets drawn without an open window/popup land on an implicit root automatically. `UIStyle` (optional on every widget): `x,y,width,height` (all four together to override auto-layout), `text_size`, `color`, `background_color`, `border_color`. See UI above for the full contract.

**`sucata.input`** — `is_pressed/is_held/is_released(...keys) -> bool`, `get_mouse_position()/get_relative_mouse_position() -> x,y`, `get_mouse_scroll() -> x,y`, `get_key() -> code`, `is_hover({id,x,y,width,height,z_index?,fixed?}) -> bool`. `Key` values: `"mouse_left/right/middle"`, `"a"`–`"z"`, `"space"`/`" "`, `"escape"`/`"esc"`, `"enter"`/`"return"`, `"shift"`, `"ctrl"`/`"control"`, `"alt"`, `"apostrophe"`, `"tab"`, `"up"/"down"/"left"/"right"`.

**`sucata.gamepad`** — `get_count() -> n`, `get_info(device) -> name`, `get_axis(Axis, device?) -> value, device_used`, `is_held/is_pressed/is_released(Button, device?) -> bool, device_used`. `Axis`: `left_x/left_y/right_x/right_y/trigger_left/trigger_right`. `Button`: `a/b/x/y/back/guide/start/left_stick/right_stick/left_shoulder/right_shoulder/dpad_up/down/left/right`.

**`sucata.audio`** — `play({sound,volume?,pitch?,group?,loop?}) -> sound_id`, `stop/pause/unpause(sound_id)`, `get_volume/set_volume(sound_id[, v])`, `get_pitch/set_pitch(sound_id[, p])`, `get_group_volume/set_group_volume(group_id[, v])`, `get_group_pitch/set_group_pitch(group_id[, p])`.

**`sucata.time`** — `get_delta() -> seconds`, `get_fps() -> n`, `create_timer(callback, seconds|Timer) -> id`, `pause_timer(id)`, `stop_timer(id)`, `get_time_scale()/set_time_scale(scale)`. `Timer`: `{time, auto_start=true, one_shot=true, loop=false}`.

**`sucata.events`** — `emit(name, data)`, `on(owner, name, callback)`.

**`sucata.camera`** — `get/set_camera_position(x,y)`, `get/set_camera_rotation(radians)`, `get/set_camera_zoom(zoom)`.

**`sucata.window`** — `get/set_mouse_lock(bool)`, `get/set_mouse_visible(bool)`, `get/set_window_title(str)`, `get/set_window_size(w,h)`, `get/set_fullscreen(bool)`, `get/set_vsync(n)`, `get/set_max_fps(n)` (0 = uncapped), `quit()`, `show_debug_info(bool)`, `get/set_keep_aspect(0|1|2)`, `get/set_window_icon(path)`, `get/set_cursor(name)`, `on_init(callback)`, `on_exit(callback)`.

**`sucata.filesystem`** — `exists(path) -> bool`, `remove(path)`, `mkdir(path)`, `read_file(path) -> str|nil`, `read_dir(path) -> table|nil`, `write(path, content) -> bool`, `rename(old, new)`.

**`sucata.math`** — `clamp(v,min,max)`, `distance(p1,p2)`, `lerp(a,b,t)`, `overlapping(Rect,Rect) -> bool, intersection|nil`, `screen_relative(ScreenRelativeRect) -> x,y,w,h`, `smooth_index(current_time, interval, max_index) -> index`, `normalize(...) -> ...`, `move_towards(current, target, step)`.

**`sucata.meta`** — `OS` (string), `VERSION` (string).

## Gotchas checklist

- Only call `sucata.graphic.draw_*` from inside `draw(state)`.
- Always route behaviours through the aggregators (`local behaviours = require("behaviours")`, then `behaviours.player.movement`) — never `require` a behaviour file directly from an entity or another behaviour.
- Register new modules in the matching `init.lua` (`behaviours/`, `behaviours/<entity>/`, `mutators/`) as soon as you create them, under a key equal to the file name.
- Behaviours execute in the order listed on the entity — order logic before rendering, and `status` before `animator` before `draw_sprite`.
- Mutate shared state slices through `mutators.*`, not by writing the fields inline from a behaviour.
- Keep constants in `commons/`, not scattered as magic numbers across behaviours.
- `init`/`tick`/`draw`/`free` are all optional — omit what you don't need.
- Use `state.x = state.x or default` in `init` to make fields optional with sane defaults when constructing entities.
- Prefer one texture/atlas over many separate images, and batch text draws, for render performance.
- Use `src://` for bundled read-only assets, `data://` for writable save data.
- Disable `sucata.window.show_debug_info` before shipping.

## Related

- [sucata-cli/AGENT.md](https://github.com/sucata-engine/sucata-cli/blob/main/AGENT.md) — the `sucata` CLI tool internals (Odin).
- [sucata-player/AGENT.md](https://github.com/sucata-engine/sucata-player/blob/main/AGENT.md) — the engine runtime internals (Odin) and how the Lua API is bound.
- [sucata-docs/docs/references/](https://github.com/sucata-engine/sucata-docs/tree/main/docs/references) — full prose API reference (source of the condensed table above), published at [sucata.dev/references](https://sucata.dev/references).
- [sucata-docs/docs/getting-started/first-project/](https://github.com/sucata-engine/sucata-docs/tree/main/docs/getting-started/first-project) — the full step-by-step Asteroids-style tutorial this guide is distilled from.

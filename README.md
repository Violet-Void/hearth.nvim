# hearth.nvim

## TL;DR

Procedural sound effects and cabin ambience (fire, snow wind, water) for Neovim, synthesised in Rust with zero audio asset files. Works on Linux Wayland and X11 (via `rodio` 0.23 playback with ALSA poll-noise filtering), macOS, and Windows.

## Overview

`hearth.nvim` is derived from [player-one.nvim](https://github.com/jackplus-xyz/player-one.nvim) and extends it with:

- **Procedural ambience (`hearth.ambience`)**: real-time synthesised `fire`, `wind`, and `water` layers running on independent `rodio` players with smooth per-layer volume and fade-out control.
- **Variation & directional cursor cues (`hearth.variation`)**: subtle random pitch/volume/decay variation profiles (`frequent`, `occasional`, or custom) and directional cursor-movement pitch shifts (`up`, `down`, `left`, `right`).
- **fzf-lua integration (`hearth.fzf`)**: optional `open`, `launch`, `select`, and `cancel` audio feedback via `winopts.on_create`.
- **Linux Wayland & X11 compatibility without vendored crates**: uses upstream `rodio` 0.23 (`default-features = false, features = ["playback"]`) with `DeviceSinkBuilder::with_error_callback` filtering harmless `ALSA function 'poll'` / `POLLERR` noise on terminal resize/signals and `log_on_drop(false)`.

## Requirements

- [Neovim](https://neovim.io/) >= 0.9.0
- Working audio output device (PipeWire/PulseAudio/ALSA on Linux, CoreAudio on macOS, WASAPI on Windows)
- Rust toolchain (`cargo build --release`) until tagged prebuilt release assets are published

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Violet-Void/hearth.nvim",
  build = "cargo build --release",
  ---@type Hearth.Config
  opts = {
    -- your configuration comes here, or leave empty for defaults
  },
}
```

Check health with `:checkhealth hearth`.

## Configuration

```lua
---@type Hearth.Config
{
  is_enabled = true,
  min_interval = 0.05,
  theme = "chiptune", -- "chiptune" | "crystal" | "synth" | Hearth.Theme
  master_volume = 0.5,
  theme_config = {},
  variation = {
    enabled = true,
    profiles = {},
    cursor_direction = true,
    cursor_cents = { up = 60, down = -60, left = -25, right = 25 },
    event_profiles = {
      CursorMoved = "frequent",
      TextChanged = "frequent",
      TextChangedI = "frequent",
      ModeChanged = "frequent",
    },
  },
  ambience = {
    volume = 0.25,
    layers = { "fire", "wind", "water" },
    weights = { fire = 1.0, wind = 0.7, water = 0.6 },
    autostart = false,
    keymaps = { toggle = "<leader>un", louder = "<leader>u=", quieter = "<leader>u-" },
  },
  debug = false,
}
```

## Usage

### Commands

| Command | Description |
| --- | --- |
| `:HearthEnable` | Enable sound effects and ambience |
| `:HearthDisable` | Disable sounds and stop all audio |
| `:HearthToggle` | Toggle Hearth on/off |
| `:HearthLoad {theme}` | Load a theme (`chiptune` / `crystal` / `synth`) |
| `:HearthClearCache` | Clear the Hearth binary cache |
| `:HearthUpdate` | Update the Hearth binary |
| `:Ambience [start\|stop\|toggle\|volume\|status]` | Control ambience layers (aliased as `:HearthAmbience`) |

### Lua API

```lua
local hearth = require("hearth").setup({ theme = "chiptune" })
hearth.play({ wave_type = 2, base_freq = 440, env_decay = 0.08 })

local ambience = require("hearth.ambience")
ambience.start()           -- start configured layers
ambience.start("fire")     -- start one layer ("fire" | "wind" | "water")
ambience.set_volume(0.3)   -- set master volume
ambience.status()          -- inspect active layers and master volume
ambience.stop()            -- fade out and stop all layers
```

### fzf-lua Integration

```lua
-- In your fzf-lua opts callback:
opts = require("hearth.fzf").setup(opts)

-- Optional brighter chime for your primary file launcher keymap:
require("hearth.fzf").mark_launch()
```

## Licenses & Attribution

- Derived from [player-one.nvim](https://github.com/jackplus-xyz/player-one.nvim) (MIT License, Copyright (c) 2025 Jack Huang).
- Built with [sfxr-rs](https://github.com/bzar/sfxr-rs) (MIT), [rodio](https://github.com/RustAudio/rodio) (MIT OR Apache-2.0), [cpal](https://github.com/RustAudio/cpal) (Apache-2.0), and [mlua](https://github.com/mlua-rs/mlua) (MIT).
- See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

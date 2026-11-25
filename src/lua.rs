use crate::ambience::{clamp_volume, Ambience, Layer};
use crate::player::Player;
use crate::sound::SoundParams;
use mlua::prelude::*;
use std::sync::Arc;

unsafe impl Send for Player {}
unsafe impl Sync for Player {}

pub fn create_lua_module(lua: &Lua) -> LuaResult<LuaTable> {
    let player = Player::new().map_err(|e| mlua::Error::external(e.to_string()))?;
    let player = Arc::new(player);
    let exports = lua.create_table()?;

    register_play(lua, &exports, player.clone())?;
    register_append(lua, &exports, player.clone())?;
    register_play_and_wait(lua, &exports, player.clone())?;
    register_play_preset(lua, &exports, player.clone())?;
    register_stop(lua, &exports, player.clone())?;
    register_ambience(lua, &exports, player)?;
    register_last_stream_error(lua, &exports)?;

    Ok(exports)
}

fn register_play(lua: &Lua, exports: &LuaTable, player: Arc<Player>) -> LuaResult<()> {
    exports.set(
        "play",
        lua.create_function(move |_, params: SoundParams| {
            player
                .play(params)
                .map_err(|e| mlua::Error::external(e.to_string()))
        })?,
    )
}

fn register_append(lua: &Lua, exports: &LuaTable, player: Arc<Player>) -> LuaResult<()> {
    exports.set(
        "append",
        lua.create_function(move |_, params: SoundParams| {
            player
                .append(params)
                .map_err(|e| mlua::Error::external(e.to_string()))
        })?,
    )
}

fn register_play_and_wait(lua: &Lua, exports: &LuaTable, player: Arc<Player>) -> LuaResult<()> {
    exports.set(
        "play_and_wait",
        lua.create_function(move |_, params: SoundParams| {
            player
                .play_and_wait(params)
                .map_err(|e| mlua::Error::external(e.to_string()))
        })?,
    )
}

fn register_play_preset(lua: &Lua, exports: &LuaTable, player: Arc<Player>) -> LuaResult<()> {
    exports.set(
        "play_preset",
        lua.create_function(move |_, preset_name: String| {
            let sample = match preset_name.as_str() {
                "pickup" => sfxr::Sample::pickup(None),
                "laser" => sfxr::Sample::laser(None),
                "explosion" => sfxr::Sample::explosion(None),
                "powerup" => sfxr::Sample::powerup(None),
                "hit" => sfxr::Sample::hit(None),
                "jump" => sfxr::Sample::jump(None),
                "blip" => sfxr::Sample::blip(None),
                _ => {
                    return Err(mlua::Error::external(format!(
                        "Unknown preset: {}",
                        preset_name
                    )))
                }
            };

            player
                .play(SoundParams::new(sample))
                .map_err(|e| mlua::Error::external(e.to_string()))
        })?,
    )
}

fn register_stop(lua: &Lua, exports: &LuaTable, player: Arc<Player>) -> LuaResult<()> {
    exports.set(
        "stop",
        lua.create_function(move |_, ()| {
            player
                .stop()
                .map_err(|e| mlua::Error::external(e.to_string()))
        })?,
    )
}

const DEFAULT_AMBIENCE_VOLUME: f32 = 0.25;

fn parse_layer(name: &str) -> LuaResult<Layer> {
    Layer::parse(name).ok_or_else(|| {
        mlua::Error::external(format!(
            "Unknown ambience layer: {name} (expected fire, wind or water)"
        ))
    })
}

fn register_ambience(lua: &Lua, exports: &LuaTable, player: Arc<Player>) -> LuaResult<()> {
    let ambience = Arc::new(Ambience::new());

    let engine = ambience.clone();
    exports.set(
        "ambience_start",
        lua.create_function(move |_, (layer, volume): (String, Option<f32>)| {
            let layer = parse_layer(&layer)?;
            engine
                .start(
                    || player.connect_ambience_player().map_err(|e| e.to_string()),
                    layer,
                    volume.unwrap_or(DEFAULT_AMBIENCE_VOLUME),
                )
                .map_err(mlua::Error::external)
        })?,
    )?;

    let engine = ambience.clone();
    exports.set(
        "ambience_stop",
        lua.create_function(move |_, layer: Option<String>| {
            let layer = layer.as_deref().map(parse_layer).transpose()?;
            Ok(engine.stop(layer).len())
        })?,
    )?;

    let engine = ambience.clone();
    exports.set(
        "ambience_set_volume",
        lua.create_function(move |_, (layer, volume): (Option<String>, f32)| {
            let layer = layer.as_deref().map(parse_layer).transpose()?;
            Ok(engine.set_volume(layer, clamp_volume(volume)))
        })?,
    )?;

    exports.set(
        "ambience_status",
        lua.create_function(move |lua, ()| {
            let table = lua.create_table()?;
            for (layer, volume) in ambience.status() {
                table.set(layer.name(), volume)?;
            }
            Ok(table)
        })?,
    )
}

fn register_last_stream_error(lua: &Lua, exports: &LuaTable) -> LuaResult<()> {
    exports.set(
        "last_stream_error",
        lua.create_function(|_, ()| Ok(crate::player::last_stream_error()))?,
    )
}

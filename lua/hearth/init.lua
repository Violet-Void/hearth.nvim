--- Hearth - Add retro gaming charm to your coding experience with 8-bit sound effects
--- Main module that provides the plugin interface
---@module 'hearth'

local Config = require("hearth.config")

---@class Hearth
---@field setup fun(options?: Hearth.Config): Hearth
---@field play fun(sound: Hearth.SoundParams)
---@field play_and_wait fun(sound: Hearth.SoundParams)
---@field append fun(sound: Hearth.SoundParams)
---@field stop fun()
---@field load_theme fun(theme: string|Hearth.Theme)
---@field enable fun()
---@field disable fun()
---@field toggle fun()
---@field reload_binary fun(): boolean
local M = {}

setmetatable(M, {
	__index = Config,
})

return M

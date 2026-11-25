--- @brief Modern synthesizer-style sound theme with rich harmonics and filtering

local Utils = require("hearth.utils")
local Config = require("hearth.config")

local M = {}

---@type Hearth.Theme
return {
	{
		event = "VimEnter",
		sound = {
			{
				wave_type = 1,
				base_freq = 277.18,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 369.99,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 440.00,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 554.37,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 739.99,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
		},
		callback = function(sound)
			Utils.append(sound)
			vim.defer_fn(function()
				Config._is_cursormoved_enabled = true
			end, 1000)
		end,
	},
	{
		event = "CursorMoved",
		sound = {

			wave_type = 1,
			base_freq = 277.18,
			env_attack = 0.001,
			env_sustain = 0.01,
			env_decay = 0.08,
			duty = 0.3,
			lpf_freq = 2000,
		},
		callback = function(sound)
			if Config._is_cursormoved_enabled == true then
				require("hearth.variation").play_cursor(sound, "frequent", Utils.append)
			end
		end,
	},
	--- @type Hearth.Sound
	{
		event = "VimLeavePre",
		sound = {
			{
				wave_type = 1,
				base_freq = 220.00,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 293.66,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
		},
		callback = function(sound)
			Utils.play_and_wait(sound)
		end,
	},
	--- @type Hearth.Sound
	{
		event = "BufWritePost",
		sound = {
			{
				wave_type = 1,
				base_freq = 880.0,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.3,
				lpf_freq = 3000,
			},
			{
				wave_type = 1,
				base_freq = 987.77,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.3,
				lpf_freq = 3000,
			},
		},
		callback = "append",
	},
	--- @type Hearth.Sound
	{
		event = "TextChangedI",
		sound = {
			wave_type = 1,
			base_freq = 415.30,
			env_attack = 0.001,
			env_sustain = 0.01,
			env_decay = 0.08,
			duty = 0.3,
			lpf_freq = 2000,
		},
	},
	--- @type Hearth.Sound
	{
		event = "TextYankPost",
		sound = {
			{
				wave_type = 1,
				base_freq = 587.33,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 659.25,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
		},
		callback = "append",
	},
	--- @type Hearth.Sound
	{
		event = "CmdlineEnter",
		sound = {
			{
				wave_type = 1,
				base_freq = 329.63,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
			{
				wave_type = 1,
				base_freq = 392.00,
				env_attack = 0.0,
				env_sustain = 0.001,
				env_decay = 0.15,
				duty = 0.6,
				lpf_freq = 4000,
			},
		},
		callback = "append",
	},
	--- @type Hearth.Sound
	{
		event = "CmdlineChanged",
		sound = {
			wave_type = 1,
			base_freq = 493.88,
			env_attack = 0.001,
			env_sustain = 0.01,
			env_decay = 0.08,
			duty = 0.3,
			lpf_freq = 2000,
		},
	},
}

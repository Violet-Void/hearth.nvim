--- fzf-lua integration: open/launch/cancel sounds.
---@module 'hearth.fzf'
local variation = require("hearth.variation")
local M = {}

---@type table<string, Hearth.SoundParams>
M.sounds = {
	open = {
		wave_type = 2,
		base_freq = 440.00,
		env_attack = 0.001,
		env_sustain = 0.010,
		env_decay = 0.05,
		lpf_freq = 1000.0,
		lpf_resonance = 50.0,
		sound_vol = 0.15,
	},
	launch = {
		wave_type = 2,
		base_freq = 392.00,
		freq_ramp = 0.22,
		env_attack = 0.004,
		env_sustain = 0.012,
		env_decay = 0.13,
		env_punch = 0.05,
		lpf_freq = 1800.0,
		lpf_resonance = 50.0,
		pha_offset = 4.0,
		pha_ramp = 0.05,
		sound_vol = 0.15,
	},
	select = {
		wave_type = 2,
		base_freq = 523.25,
		env_attack = 0.0008,
		env_sustain = 0.0025,
		env_decay = 0.010,
		lpf_freq = 1100.0,
		lpf_resonance = 50.0,
		sound_vol = 0.13,
	},
	cancel = {
		wave_type = 4,
		base_freq = 220.00,
		freq_ramp = -0.15,
		env_attack = 0.001,
		env_sustain = 0.01,
		env_decay = 0.05,
		lpf_freq = 650.0,
		lpf_resonance = 50.0,
		sound_vol = 0.12,
	},
	move = {
		wave_type = 2,
		base_freq = 330.00,
		env_attack = 0.0005,
		env_sustain = 0.002,
		env_decay = 0.015,
		lpf_freq = 800.0,
		lpf_resonance = 50.0,
		sound_vol = 0.09,
	},
}

local managed_hooks = setmetatable({}, { __mode = "k" })
local use_launch_sound = false

--- Make the next picker open play the launch chime instead of the plain open sound.
function M.mark_launch()
	use_launch_sound = true
end

function M.on_create(event)
	local opening = use_launch_sound and M.sounds.launch or M.sounds.open
	use_launch_sound = false
	variation.play_varied(opening, "occasional")

	local bufnr = event and event.bufnr
	local winid = event and event.winid
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.keymap.set({ "n", "t" }, "<Esc>", function()
		variation.play_varied(M.sounds.cancel, "occasional")
		if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
			vim.api.nvim_win_close(winid, true)
		end
	end, { buffer = bufnr, silent = true, desc = "Cancel FZF with Hearth sound" })
end

--- Install the hook into fzf-lua options (idempotent).
---@param opts table fzf-lua setup options
---@return table
function M.setup(opts)
	opts.winopts = opts.winopts or {}
	local previous = opts.winopts.on_create
	if managed_hooks[previous] then
		return opts
	end
	local function on_create(event)
		M.on_create(event)
		if type(previous) == "function" then
			return previous(event)
		end
	end
	managed_hooks[on_create] = true
	opts.winopts.on_create = on_create
	return opts
end

return M

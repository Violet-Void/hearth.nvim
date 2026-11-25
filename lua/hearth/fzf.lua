--- fzf-lua integration: open/launch/select/cancel sounds.
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
local active_picker = nil
local hrtime = (vim.uv or vim.loop).hrtime
local SELECT_DEDUP_NS = 200 * 1e6 -- 200ms window linking TermClose and fzf-lua action callback

function M._reset()
	active_picker = nil
	use_launch_sound = false
end

--- Make the next picker open play the launch chime instead of the plain open sound.
function M.mark_launch()
	use_launch_sound = true
end

--- Play a named fzf sound with subtle occasional variation.
---@param name "open"|"launch"|"select"|"cancel"|"move"
---@return Hearth.SoundParams|nil
function M.play(name)
	local sound = M.sounds[name]
	if not sound then
		return nil
	end
	return variation.play_varied(sound, "occasional")
end

--- Wrap an fzf-lua action so selecting it plays `M.sounds.select`.
---@param fn function
---@return function
function M.wrap_action(fn)
	return function(...)
		if
			active_picker
			and active_picker.selected
			and active_picker.selected_ns
			and (hrtime() - active_picker.selected_ns) < SELECT_DEDUP_NS
		then
			active_picker = nil
			return fn(...)
		end
		if active_picker then
			active_picker.selected = true
			active_picker.selected_ns = hrtime()
		end
		M.play("select")
		return fn(...)
	end
end

local function attach_on_create(winopts)
	local previous = winopts.on_create
	if managed_hooks[previous] then
		return winopts
	end
	local function on_create(event)
		M.on_create(event)
		if type(previous) == "function" then
			return previous(event)
		end
	end
	managed_hooks[on_create] = true
	winopts.on_create = on_create
	return winopts
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

	local state = { cancelled = false, selected = false, selected_ns = nil }
	active_picker = state

	vim.api.nvim_create_autocmd("TermClose", {
		buffer = bufnr,
		once = true,
		callback = function(args)
			if state.cancelled or state.selected then
				if active_picker == state then
					active_picker = nil
				end
				return
			end
			local status = (args.data and args.data.status ~= nil) and args.data.status
				or (vim.v.event and vim.v.event.status)
			if status == 0 then
				state.selected = true
				state.selected_ns = hrtime()
				M.play("select")
			end
		end,
	})

	vim.keymap.set({ "n", "t" }, "<Esc>", function()
		state.cancelled = true
		if active_picker == state then
			active_picker = nil
		end
		variation.play_varied(M.sounds.cancel, "occasional")
		if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
			vim.api.nvim_win_close(winid, true)
		end
	end, { buffer = bufnr, silent = true, desc = "Cancel FZF with Hearth sound" })
end

--- Install the hook into fzf-lua options (idempotent; supports table or callable winopts).
---@param opts table fzf-lua setup options
---@return table
function M.setup(opts)
	opts = opts or {}
	if type(opts.winopts) == "function" then
		local previous_fn = opts.winopts
		if managed_hooks[previous_fn] then
			return opts
		end
		local function winopts_fn(...)
			local tbl = previous_fn(...) or {}
			if type(tbl) == "table" then
				attach_on_create(tbl)
			end
			return tbl
		end
		managed_hooks[winopts_fn] = true
		opts.winopts = winopts_fn
		return opts
	end

	opts.winopts = opts.winopts or {}
	attach_on_create(opts.winopts)
	return opts
end

return M

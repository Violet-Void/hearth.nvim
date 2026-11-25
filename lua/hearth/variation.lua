--- Sound variation profiles and cursor-direction pitch.
---@module 'hearth.variation'
local M = {}

---@class Hearth.VariationProfile
---@field pitch_cents? number Max random pitch offset (±cents)
---@field volume? number Max random volume change (±fraction)
---@field decay? number Max random decay change (±fraction)

---@type table<string, Hearth.VariationProfile>
M.default_profiles = {
	frequent = { pitch_cents = 6, volume = 0.02, decay = 0.03 },
	occasional = { pitch_cents = 4, volume = 0.015, decay = 0.02 },
}

---@type table<string, number>
M.default_cursor_cents = { up = 60, down = -60, left = -25, right = 25 }

local frequent_events = {
	CursorMoved = true,
	TextChanged = true,
	TextChangedI = true,
	ModeChanged = true,
}

local function settings()
	local ok, Config = pcall(require, "hearth.config")
	local v = ok and Config.variation or nil
	return v or {}
end

---@return boolean
function M.is_enabled()
	return settings().enabled ~= false
end

---@param event string|string[]|nil
---@return string|Hearth.VariationProfile|nil
function M.profile_for_event(event)
	if not M.is_enabled() then
		return nil
	end
	local key = type(event) == "table" and event[1] or event
	if type(key) ~= "string" then
		return nil
	end
	local event_profiles = settings().event_profiles
	if type(event_profiles) == "table" then
		local configured = event_profiles[key]
		if configured == false then
			return nil
		end
		if configured ~= nil then
			return configured
		end
	end
	return frequent_events[key] and "frequent" or "occasional"
end

---@param name string
---@return Hearth.VariationProfile|nil
function M.profile(name)
	local custom = settings().profiles
	return (custom and custom[name]) or M.default_profiles[name]
end

--- Resolve a profile name or table into a profile table.
---@param profile string|Hearth.VariationProfile|nil
---@return Hearth.VariationProfile
local function resolve(profile)
	if type(profile) == "string" then
		return M.profile(profile) or {}
	end
	return profile or {}
end

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function variation(random_fn, bound)
	return ((random_fn() * 2) - 1) * math.abs(bound or 0)
end

---@param sound Hearth.SoundParams
---@param profile? string|Hearth.VariationProfile
---@param random_fn? fun(): number
---@return Hearth.SoundParams
function M.vary(sound, profile, random_fn)
	local opts = resolve(profile)
	random_fn = random_fn or math.random
	local varied = vim.deepcopy(sound)
	if varied.base_freq then
		varied.base_freq = varied.base_freq * (2 ^ (variation(random_fn, opts.pitch_cents) / 1200))
	end
	if varied.sound_vol == nil and varied.volume ~= nil then
		varied.sound_vol = varied.volume
		varied.volume = nil
	end
	if varied.sound_vol then
		varied.sound_vol = clamp(varied.sound_vol * (1 + variation(random_fn, opts.volume)), 0, 1)
	end
	if varied.env_decay then
		varied.env_decay = math.max(0, varied.env_decay * (1 + variation(random_fn, opts.decay)))
	end
	return varied
end

---@param sound Hearth.SoundParams|Hearth.SoundParams[]|string
---@param profile? string|Hearth.VariationProfile
---@param random_fn? fun(): number
---@return Hearth.SoundParams|Hearth.SoundParams[]|string
function M.vary_sound(sound, profile, random_fn)
	if type(sound) ~= "table" then
		return sound
	end
	if sound[1] and type(sound[1]) == "table" then
		local out = {}
		for i, item in ipairs(sound) do
			out[i] = M.vary(item, profile, random_fn)
		end
		return out
	end
	return M.vary(sound, profile, random_fn)
end

---@param sound Hearth.SoundParams
---@param profile? string|Hearth.VariationProfile
---@return Hearth.SoundParams varied
function M.play_varied(sound, profile)
	local varied = M.is_enabled() and M.vary(sound, profile) or vim.deepcopy(sound)
	local ok, api = pcall(require, "hearth.api")
	if ok then
		api.play(varied)
	end
	return varied
end

---@param prev integer[]|nil previous {row, col}
---@param pos integer[] current {row, col}
---@return "up"|"down"|"left"|"right"|nil
function M.direction(prev, pos)
	if not prev then
		return nil
	end
	if pos[1] < prev[1] then
		return "up"
	elseif pos[1] > prev[1] then
		return "down"
	elseif pos[2] < prev[2] then
		return "left"
	elseif pos[2] > prev[2] then
		return "right"
	end
end

---@param sound Hearth.SoundParams
---@param direction "up"|"down"|"left"|"right"|nil
---@return Hearth.SoundParams
function M.shift_for_direction(sound, direction)
	local shifted = vim.deepcopy(sound)
	if direction and shifted.base_freq then
		local cents = (settings().cursor_cents or M.default_cursor_cents)[direction]
			or M.default_cursor_cents[direction]
		shifted.base_freq = shifted.base_freq * (2 ^ (cents / 1200))
	end
	return shifted
end

local last_cursor = {}

function M.reset_cursor()
	last_cursor = {}
end

--- Play a cursor-move sound whose pitch follows the movement direction.
---@param sound Hearth.SoundParams
---@param profile? string|Hearth.VariationProfile defaults to "frequent"
---@param play_fn? fun(sound: Hearth.SoundParams): any
---@return Hearth.SoundParams
function M.play_cursor(sound, profile, play_fn)
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	local pos = vim.api.nvim_win_get_cursor(win)
	local prev = last_cursor[win]
	last_cursor[win] = { buf = buf, pos = pos }

	local dir = (prev and prev.buf == buf and settings().cursor_direction ~= false) and M.direction(prev.pos, pos)
		or nil
	local shifted = M.shift_for_direction(sound, dir)
	local effective = M.is_enabled() and M.vary_sound(shifted, profile or "frequent") or shifted

	if type(play_fn) == "function" then
		play_fn(effective)
	else
		local ok, api = pcall(require, "hearth.api")
		if ok then
			api.play(effective)
		end
	end
	return effective
end

return M

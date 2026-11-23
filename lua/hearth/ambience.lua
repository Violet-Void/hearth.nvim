--- Procedural ambience (fire, wind, water) controlled from Neovim.
---@module 'hearth.ambience'
---@usage [[
--- require("hearth.ambience").start()            -- all configured layers
--- require("hearth.ambience").start("fire")      -- one layer
--- require("hearth.ambience").set_volume(0.3)    -- master volume
--- require("hearth.ambience").stop()
--- :Ambience [start|stop|toggle|volume|status] ...
---]]
local Config = require("hearth.config")

local M = {}

---@type string[]
M.layers = { "fire", "wind", "water" }

---@class Hearth.AmbienceConfig
---@field volume number Master volume 0..1 (default 0.25)
---@field layers string[] Layers started by default
---@field weights table<string, number> Per-layer mix relative to master
---@field autostart boolean Start on setup (default false)
---@field keymaps table|false Keymaps: toggle, louder, quieter (false to disable)
M.defaults = {
	volume = 0.25,
	layers = { "fire", "wind", "water" },
	weights = { fire = 1.0, wind = 0.7, water = 0.6 },
	autostart = false,
	keymaps = { toggle = "<leader>un", louder = "<leader>u=", quieter = "<leader>u-" },
}

local state = { volume = M.defaults.volume }

---@return Hearth.AmbienceConfig
local function opts()
	return vim.tbl_deep_extend("force", M.defaults, Config.ambience or {})
end

--- The native library. Replaceable in tests.
---@return table
function M._lib()
	return require("hearth.binary")
end

local function notify(msg, level)
	vim.notify("Hearth ambience: " .. msg, level or vim.log.levels.INFO)
end

local function clamp(v)
	return math.max(0, math.min(1, v))
end

---@param names string|string[]|nil
---@return string[]|nil layers, string|nil err
local function normalize(names)
	if names == nil then
		return vim.deepcopy(opts().layers)
	end
	if type(names) == "string" then
		names = { names }
	end
	for _, name in ipairs(names) do
		if not vim.tbl_contains(M.layers, name) then
			return nil, ("unknown layer '%s' (expected %s)"):format(name, table.concat(M.layers, ", "))
		end
	end
	return names
end

local function layer_volume(layer)
	local weight = opts().weights[layer] or 1.0
	return clamp(state.volume * weight)
end

---@param layers? string|string[]
---@return boolean ok
function M.start(layers)
	local names, err = normalize(layers)
	if not names then
		notify(err, vim.log.levels.ERROR)
		return false
	end
	local ok, res = pcall(function()
		local lib = M._lib()
		for _, layer in ipairs(names) do
			lib.ambience_start(layer, layer_volume(layer))
		end
	end)
	if not ok then
		notify(tostring(res):gsub("^.*:%d+:%s*", ""), vim.log.levels.ERROR)
		return false
	end
	return true
end

---@param layers? string|string[] default: everything running
---@return boolean ok
function M.stop(layers)
	local names, err
	if layers ~= nil then
		names, err = normalize(layers)
		if not names then
			notify(err, vim.log.levels.ERROR)
			return false
		end
	end
	local ok, res = pcall(function()
		local lib = M._lib()
		if names then
			for _, layer in ipairs(names) do
				lib.ambience_stop(layer)
			end
		else
			lib.ambience_stop()
		end
	end)
	if not ok then
		notify(tostring(res):gsub("^.*:%d+:%s*", ""), vim.log.levels.ERROR)
		return false
	end
	return true
end

---@return table<string, number> running layer -> volume
local function running()
	local ok, status = pcall(function()
		return M._lib().ambience_status()
	end)
	return ok and status or {}
end

---@return { running: table<string, number>, volume: number, active: boolean }
function M.status()
	local r = running()
	return { running = r, volume = state.volume, active = next(r) ~= nil }
end

function M.toggle()
	if M.status().active then
		return M.stop()
	end
	return M.start()
end

--- Set the master volume (0..1), or one layer's absolute volume.
---@param value number
---@param layer? string
---@return boolean ok
function M.set_volume(value, layer)
	if type(value) ~= "number" or value ~= value then
		notify("volume must be a number between 0 and 1", vim.log.levels.ERROR)
		return false
	end
	value = clamp(value)
	local ok, res = pcall(function()
		local lib = M._lib()
		if layer then
			local names, err = normalize(layer)
			if not names then
				error(err, 0)
			end
			lib.ambience_set_volume(layer, value)
		else
			state.volume = value
			for running_layer in pairs(running()) do
				lib.ambience_set_volume(running_layer, layer_volume(running_layer))
			end
		end
	end)
	if not ok then
		notify(tostring(res):gsub("^.*:%d+:%s*", ""), vim.log.levels.ERROR)
		return false
	end
	return true
end

---@param delta number
function M.adjust(delta)
	return M.set_volume(state.volume + delta)
end

local function command(args)
	local fargs = args.fargs
	local sub = fargs[1] or "toggle"
	local rest = vim.list_slice(fargs, 2)
	local layers = #rest > 0 and rest or nil
	if sub == "start" then
		M.start(layers)
	elseif sub == "stop" then
		M.stop(layers)
	elseif sub == "toggle" then
		M.toggle()
	elseif sub == "volume" then
		local value = tonumber(rest[1])
		if not value then
			notify(("volume is %.2f"):format(state.volume))
		else
			M.set_volume(value, rest[2])
		end
	elseif sub == "status" then
		local s = M.status()
		local parts = {}
		for _, layer in ipairs(M.layers) do
			if s.running[layer] then
				parts[#parts + 1] = ("%s=%.2f"):format(layer, s.running[layer])
			end
		end
		notify(("%s, master %.2f"):format(#parts > 0 and table.concat(parts, " ") or "stopped", s.volume))
	else
		notify("usage: :Ambience [start|stop|toggle|volume|status] ...", vim.log.levels.ERROR)
	end
end

local subcommands = { "start", "stop", "toggle", "volume", "status" }

local function complete(arglead, cmdline)
	local words = vim.split(cmdline, "%s+", { trimempty = true })
	local n = #words + (cmdline:match("%s$") and 1 or 0)
	local pool = subcommands
	if n > 2 and (words[2] == "start" or words[2] == "stop") then
		pool = M.layers
	elseif n > 3 and words[2] == "volume" then
		pool = M.layers
	elseif n > 2 then
		pool = {}
	end
	return vim.tbl_filter(function(item)
		return vim.startswith(item, arglead)
	end, pool)
end

--- Create the :Ambience command, keymaps and optional autostart.
function M.setup()
	local o = opts()
	state.volume = clamp(o.volume)

	pcall(vim.api.nvim_del_user_command, "Ambience")
	vim.api.nvim_create_user_command("Ambience", command, {
		nargs = "*",
		complete = complete,
		desc = "Hearth ambience: start|stop|toggle|volume|status",
	})

	if o.keymaps then
		local maps = {
			toggle = { M.toggle, "Toggle ambience" },
			louder = {
				function()
					M.adjust(0.05)
				end,
				"Ambience louder",
			},
			quieter = {
				function()
					M.adjust(-0.05)
				end,
				"Ambience quieter",
			},
		}
		for name, lhs in pairs(o.keymaps) do
			if maps[name] and lhs then
				vim.keymap.set("n", lhs, maps[name][1], { desc = maps[name][2], silent = true })
			end
		end
	end

	if o.autostart then
		M.start()
	end
end

return M

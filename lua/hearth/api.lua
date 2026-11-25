local Themes = require("hearth.themes")
local Config = require("hearth.config")
local Utils = require("hearth.utils")

--- Hearth API module
--- Provides the core functionality for sound playback and plugin control
---@module 'hearth.api'
local M = {}

local function handle_error(ok, err)
	if not ok then
		-- Clean up the error message from Rust/FFI
		local msg = tostring(err):gsub("^.*:%d+:%s*", "")
		vim.notify("Hearth: " .. msg, vim.log.levels.ERROR)
		return false
	end
	return true
end

function M.clear_cache(force)
	return require("hearth.binary.download").clear_cache(force)
end

function M.update()
	local version = require("hearth.binary.version").get_current_plugin_version()
	return require("hearth.binary.download").update_binary(version, true)
end

---Play a sound immediately, interrupting any currently playing sounds
---@param params Hearth.SoundParams Sound parameters
---@return boolean|nil success Whether the sound was played successfully
function M.play(params)
	if not Config.is_enabled then
		return
	end
	local ok, err = pcall(Utils.play, params)
	return handle_error(ok, err)
end

---Queue a sound to play after current sounds finish
---@param params Hearth.SoundParams Sound parameters
---@return boolean|nil success Whether the sound was queued successfully
function M.append(params)
	if not Config.is_enabled then
		return
	end
	local ok, err = pcall(Utils.append, params)
	return handle_error(ok, err)
end

---Play a sound and wait for it to complete
---@param params Hearth.SoundParams Sound parameters
---@return boolean|nil success Whether the sound was played successfully
function M.play_and_wait(params)
	if not Config.is_enabled then
		return
	end
	local ok, err = pcall(Utils.play_and_wait, params)
	return handle_error(ok, err)
end

---Stop all currently playing sounds
---@return boolean|nil success Whether the stop operation succeeded
function M.stop()
	if not Config.is_enabled then
		return
	end
	local ok, err = pcall(Utils.stop)
	return handle_error(ok, err)
end

---Load a sound theme
---@param theme string|Hearth.Theme|nil Theme name or custom theme table
---@return boolean|nil success Whether the theme was loaded successfully
function M.load_theme(theme_spec)
	if not theme_spec then
		vim.notify("Hearth API: M.load_theme called with nil theme_spec.", vim.log.levels.WARN)
		return false
	end

	Config.curr_theme = theme_spec -- Always update the desired theme

	-- Add "user" to themes list if a custom table is provided
	if type(theme_spec) == "table" then
		local user_theme_present = false
		for _, t_name in ipairs(Config.themes) do
			if t_name == "user" then
				user_theme_present = true
				break
			end
		end
		if not user_theme_present then
			table.insert(Config.themes, "user")
		end
	end

	if not Config.is_enabled then
		-- Theme choice is updated, but don't load it if disabled.
		-- It will be loaded when M.enable() is called.
		-- The caller (e.g., HearthLoad command) will notify the user.
		return true -- Indicate success in setting the theme preference.
	end

	-- If enabled, proceed to load the theme via Utils
	local ok, err = pcall(Utils.load_theme, theme_spec)
	return handle_error(ok, err)
end

---Enable the plugin
---@return boolean success Whether enable succeeded
function M.enable()
	local ok, err = pcall(function()
		Config.is_enabled = true
		Themes.setup()
	end)
	return handle_error(ok, err)
end

---Disable the plugin and stop all sounds
---@return boolean success Whether disable succeeded
function M.disable()
	local failures = {}
	local function attempt(label, fn)
		local ok, err = pcall(fn)
		if not ok then
			failures[#failures + 1] = label .. ": " .. tostring(err)
		end
	end

	Config.is_enabled = false
	attempt("autocmds", Utils.clear_autocmds)
	attempt("sounds", Utils.stop)
	attempt("ambience", require("hearth.ambience").stop)

	if #failures > 0 then
		return handle_error(false, table.concat(failures, "\n"))
	end
	return true
end

---Toggle the plugin enabled state
function M.toggle()
	if Config.is_enabled then
		if M.disable() then
			vim.notify("Disabled Hearth", vim.log.levels.INFO)
		end
	else
		if M.enable() then
			vim.notify("Enabled Hearth", vim.log.levels.INFO)
		end
	end
end

local function ensure_command(name, command, opts)
	if vim.fn.exists(":" .. name) == 0 then
		vim.api.nvim_create_user_command(name, command, opts)
	end
end

function M.setup()
	ensure_command("HearthEnable", M.enable, { desc = "Enable Hearth" })
	ensure_command("HearthDisable", M.disable, { desc = "Disable Hearth" })
	ensure_command("HearthToggle", M.toggle, { desc = "Toggle Hearth" })
	ensure_command("HearthClearCache", function(opts)
		M.clear_cache(opts.bang)
	end, { desc = "Clear Hearth binary cache", bang = true })
	ensure_command("HearthUpdate", M.update, { desc = "Update Hearth binary" })
	ensure_command("HearthLoad", function(opts)
		local theme = opts.args
		if theme ~= "" then
			M.load_theme(theme)
			vim.notify(theme .. " Loaded")
		else
			vim.ui.select(Config.themes, {
				prompt = "Select Hearth theme:",
				format_item = function(item)
					return item
				end,
			}, function(choice)
				if choice then
					M.load_theme(choice)
					vim.notify(choice .. " Loaded")
				end
			end)
		end
	end, {
		nargs = "?",
		desc = "Load Hearth theme",
		complete = function()
			return Config.themes
		end,
	})
end

return M

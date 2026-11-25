-- Binary compilation and loading functionality adapted from:
-- https://github.com/Saghen/blink.cmp/tree/main/lua/blink/cmp/fuzzy

local Download = require("hearth.binary.download")
local Errors = require("hearth.binary.errors")
local Config = require("hearth.config")
local System = require("hearth.binary.system")
local Version = require("hearth.binary.version")

local M = {}

-- Cache for loaded library
local loaded_lib = nil

-- Cache for version info to prevent frequent checks
local version_info_cache = {
	info = nil,
	timestamp = 0,
}

---Check if version info cache is valid
---@return boolean
local function is_cache_valid()
	if not version_info_cache.info or not version_info_cache.timestamp then
		return false
	end
	local cache_timeout = (Config.binary and Config.binary.cache_timeout) or 3600
	return (os.time() - version_info_cache.timestamp) < cache_timeout
end

---Get version info with caching
---@return Hearth.VersionInfo
---@throws string When version info cannot be retrieved
local function get_cached_version_info()
	if not is_cache_valid() then
		local ok, info_or_err = pcall(Version.get_info)
		if not ok then
			error(Errors.format_error("version_check_failed", info_or_err))
		end
		version_info_cache.info = info_or_err
		version_info_cache.timestamp = os.time()
	end
	return version_info_cache.info
end

---Attempt to load library from path
---@param path string Full path to library file
---@return table|nil lib Loaded library or nil if failed
---@return string|nil error Error message if failed
local function try_load_library(path)
	if not path then
		return nil, "No path provided"
	end

	-- Check if file exists and is readable
	if vim.fn.filereadable(path) ~= 1 then
		return nil, string.format("File not readable: %s", path)
	end

	local symbol = "luaopen_libhearth"

	-- Attempt to load the library
	local ok, result = pcall(function()
		local loader = package.loadlib(path, symbol)
		if not loader then
			error(string.format("Failed to load library: %s", path))
		end
		return loader()
	end)

	if not ok then
		return nil, tostring(result)
	end

	return result
end

---Initialize the binary system
---@return boolean success Always returns true or throws an error
---@throws string When system is not supported or initialization fails
function M.init()
	-- Check system compatibility
	local triple = System.get_target_triple()
	if not triple then
		error(
			Errors.format_error(
				"unsupported_system",
				"System architecture not supported: " .. vim.inspect(System.get_info())
			)
		)
	end

	-- Get cached version info (will throw on error)
	local info = get_cached_version_info()

	-- Log initialization state
	if Config.debug then
		vim.notify(
			string.format(
				"Hearth: Initializing binary system\n"
					.. "  - Development build: %s\n"
					.. "  - Current version: %s\n"
					.. "  - Latest version: %s\n"
					.. "  - System: %s",
				info.dev and "Yes" or "No",
				info.current or "Not installed",
				info.latest or "Unknown",
				triple
			),
			vim.log.levels.DEBUG
		)
	end

	return true
end

---Load the appropriate binary
---@return table library The loaded library
---@throws string When binary cannot be loaded
function M.load_binary()
	if loaded_lib then
		return loaded_lib
	end

	if Version.has_local_build() then
		local lib, _ = try_load_library(Version.get_install_path())
		if lib then
			loaded_lib = lib
			return lib
		end
	end

	M.init()

	local info = get_cached_version_info()

	if not info.current or not Version.has_local_build() then
		if not info.latest then
			info.latest = Version.get_latest_version(true)
		end
		if info.latest then
			vim.notify("Hearth: No binary installed. Attempting to download...", vim.log.levels.INFO)
			local ok, err = pcall(Download.ensure_binary, info.latest)
			if not ok then
				error(Errors.format_error("binary_load_failed", "No binary installed and download failed: " .. err))
			end
			-- Reload version info after download
			version_info_cache.info = nil
			info = get_cached_version_info()
		elseif not info.dev then
			error(
				Errors.format_error(
					"binary_load_failed",
					"No local binary found and no GitHub release is available yet. Run `cargo build --release` in the plugin directory."
				)
			)
		end
	end

	-- Try loading development binary first
	if info.dev then
		local dev_path = Version.get_development_path()
		local lib, err = try_load_library(dev_path)
		if lib then
			vim.notify("Hearth: Using development build", vim.log.levels.INFO)
			loaded_lib = lib
			return lib
		else
			vim.notify("Hearth: Failed to load development build: " .. err, vim.log.levels.WARN)
		end
	end

	-- Try loading installed binary
	local install_path = Version.get_install_path()
	local lib, err = try_load_library(install_path)

	if not lib then
		error(Errors.format_error("binary_load_failed", "Failed to load binary at " .. install_path .. ": " .. err))
	end

	loaded_lib = lib
	return lib
end

---Clear the library cache
---@return boolean success Always returns true
function M.clear_cache()
	loaded_lib = nil
	version_info_cache = {
		info = nil,
		timestamp = 0,
	}
	return true
end

-- Export the loaded library directly
return M.load_binary()

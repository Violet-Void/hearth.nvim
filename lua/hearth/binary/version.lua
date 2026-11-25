local errors = require("hearth.binary.errors")
local paths = require("hearth.binary.paths")
local Config = require("hearth.config")

local M = {}

---@class Hearth.VersionInfo
---@field current string|nil Currently installed version
---@field latest string|nil Latest available version
---@field dev boolean Whether a development build exists
---@field git table|nil Git repository information
---@field timestamp number When this info was last updated

function M.get_development_path()
	-- Use the same release directory for both dev and downloaded builds
	return paths.get_binary_path()
end

function M.get_install_path()
	-- Use the same path as development path
	return paths.get_binary_path()
end

function M.get_version_file()
	return paths.get_version_path()
end

-- Version checking
function M.get_git_info()
	local function get_git_command_output(...)
		local cmd = { "git", ... }
		local output = vim.fn.system(cmd)
		return vim.v.shell_error == 0 and vim.trim(output) or nil
	end

	local repo_path = paths.get_plugin_root()

	-- Check if we're in a git repo
	local is_git = vim.fn.finddir(".git", repo_path) ~= ""
	if not is_git then
		return nil
	end

	return {
		tag = get_git_command_output("-C", repo_path, "describe", "--tags", "--exact-match", "HEAD"),
		sha = get_git_command_output("-C", repo_path, "rev-parse", "HEAD"),
		branch = get_git_command_output("-C", repo_path, "rev-parse", "--abbrev-ref", "HEAD"),
	}
end

---Resolves plugin version using git information (tags/SHA) with fallback to version file
---@return string|nil # Current plugin version from git tag, SHA (7 chars), or version file
---@return string? error # Error message if version cannot be determined
function M.get_current_plugin_version()
	local git_info = M.get_git_info()
	-- Prefer release tags over commit SHAs
	if git_info then
		if git_info.tag then
			-- Use tag if available (e.g. v1.0.0)
			return git_info.tag
		elseif git_info.sha then
			-- Only use SHA as fallback
			return git_info.sha:sub(1, 7)
		end
	end
	return M.get_current_version()
end

---Reads version string from version file
---@return string|nil version Version string from file or nil if file doesn't exist/is empty
function M.get_current_version()
	local version_file = M.get_version_file()
	if vim.fn.filereadable(version_file) == 1 then
		local content = vim.fn.readfile(version_file)
		if content and content[1] then
			return vim.trim(content[1])
		end
	end
	return nil
end

local function fetch_latest_version(cache_file)
	local ok, result = pcall(vim.fn.system, {
		"curl",
		"--silent",
		"--fail",
		"--connect-timeout",
		"5",
		"--max-time",
		"15",
		"https://api.github.com/repos/Violet-Void/hearth.nvim/releases/latest",
	})

	if not ok or vim.v.shell_error ~= 0 or type(result) ~= "string" or result == "" then
		return nil
	end

	local dec_ok, release = pcall(vim.json.decode, result)
	if dec_ok and type(release) == "table" and type(release.tag_name) == "string" and release.tag_name ~= "" then
		pcall(vim.fn.writefile, { tostring(os.time()), release.tag_name }, cache_file)
		return release.tag_name
	end
	return nil
end

---@param sync? boolean Whether to fetch synchronously when cache is cold/expired
---@return string|nil version The latest release version from GitHub or nil if not found
function M.get_latest_version(sync)
	local cache_file = vim.fn.stdpath("cache") .. "/hearth-version"
	local current_time = os.time()
	local cache_timeout = (Config.binary and Config.binary.cache_timeout) or 3600
	local cached_version = nil

	if vim.fn.filereadable(cache_file) == 1 then
		local cache = vim.fn.readfile(cache_file)
		local timestamp = tonumber(cache[1])
		cached_version = cache[2]
		if timestamp and cached_version and cached_version ~= "" and current_time - timestamp < cache_timeout then
			return cached_version
		end
	end

	if sync then
		return fetch_latest_version(cache_file)
	end

	vim.defer_fn(function()
		fetch_latest_version(cache_file)
	end, 1000)

	return cached_version
end

function M.has_development_build()
	local dev_path = M.get_development_path()
	return vim.fn.filereadable(dev_path) == 1
end

function M.has_local_build()
	local install_path = M.get_install_path()
	return vim.fn.filereadable(install_path) == 1
end

---Get complete version information
---@return Hearth.VersionInfo
function M.get_info()
	local ok, info = pcall(function()
		return {
			current = M.get_current_version(),
			latest = M.get_latest_version(),
			dev = M.has_development_build(),
			git = M.get_git_info(),
			timestamp = os.time(),
		}
	end)

	if not ok then
		error(errors.format_error("version_check_failed", info))
	end

	return info
end

---Check if binary needs updating
---@param info Hearth.VersionInfo Version information
---@return boolean needs_update
function M.needs_update(info)
	-- Development build takes precedence
	if info.dev then
		return false
	end

	-- No current version installed
	if not info.current then
		return true
	end

	-- Check cache validity (1 hour)
	if info.timestamp and (os.time() - info.timestamp) < 3600 then
		return false
	end

	-- Compare versions
	return info.current ~= info.latest
end

---Write version information to file
---@param version string Version to write
function M.write_version(version)
	local version_file = M.get_version_file()
	-- Ensure directory exists before writing
	local dir = vim.fn.fnamemodify(version_file, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	local ok = pcall(vim.fn.writefile, { version }, version_file)
	if not ok then
		error(errors.format_error("version_write_failed", "Failed to write to " .. version_file))
	end
end

return M

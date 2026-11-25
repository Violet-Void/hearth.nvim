local assert = require("luassert")

describe("paths, version, api and debug", function()
	local orig_system, orig_readfile, orig_filereadable, orig_notify

	before_each(function()
		orig_system = vim.fn.system
		orig_readfile = vim.fn.readfile
		orig_filereadable = vim.fn.filereadable
		orig_notify = vim.notify
	end)

	after_each(function()
		vim.fn.system = orig_system
		vim.fn.readfile = orig_readfile
		vim.fn.filereadable = orig_filereadable
		vim.notify = orig_notify
	end)

	it("resolves plugin root and binary path cleanly", function()
		local paths = require("hearth.binary.paths")
		local root = paths.get_plugin_root()
		assert.is_nil(root:match("paths%.lua$"))
		assert.is_truthy(paths.get_binary_path():match("/target/release/.*hearth"))
	end)

	it("handles 404 or invalid JSON on version lookup without throwing", function()
		local version = require("hearth.binary.version")
		vim.fn.filereadable = function()
			return 0
		end
		vim.fn.system = function()
			return ""
		end
		assert.is_nil(version.get_latest_version(true))

		vim.fn.system = function()
			return "not json"
		end
		assert.is_nil(version.get_latest_version(true))
	end)

	it("does not reuse an expired cache when a synchronous refresh fails", function()
		local version = require("hearth.binary.version")
		local cache = vim.fn.stdpath("cache") .. "/hearth-version"
		vim.fn.filereadable = function(path)
			return path == cache and 1 or 0
		end
		vim.fn.readfile = function(path)
			if path == cache then
				return { tostring(os.time() - 7200), "v0.0.1" }
			end
			return {}
		end
		vim.fn.system = function()
			return ""
		end
		assert.is_nil(version.get_latest_version(true))
	end)

	it("passes resolved latest version into ensure_binary on nil update_binary", function()
		local version = require("hearth.binary.version")
		local download = require("hearth.binary.download")
		local orig_get_latest = version.get_latest_version
		local orig_ensure = download.ensure_binary
		local ensured
		version.get_latest_version = function(sync)
			assert.is_true(sync)
			return "v9.9.9"
		end
		download.ensure_binary = function(ver)
			ensured = ver
		end
		download.update_binary(nil, false)
		version.get_latest_version = orig_get_latest
		download.ensure_binary = orig_ensure
		assert.are.equal("v9.9.9", ensured)
	end)

	it("returns Hearth with callable API methods from setup()", function()
		local hearth = require("hearth")
		local returned = hearth.setup({ is_enabled = false, ambience = { keymaps = false } })
		assert.are.equal(hearth, returned)
		assert.are.equal("function", type(hearth.play))
		assert.are.equal("function", type(hearth.stop))
		assert.are.equal("function", type(hearth.enable))
		assert.are.equal("function", type(hearth.disable))
		assert.are.equal("function", type(hearth.toggle))
	end)

	it("formats debug.log_time in milliseconds without * 100 scaling", function()
		local debug_mod = require("hearth.debug")
		local msg
		vim.notify = function(s)
			msg = s
		end
		local now = vim.uv.hrtime()
		debug_mod.log_time("probe", now - 5e6) -- ~5 ms
		local num = tonumber(msg:match("took ([%d%.]+) ms"))
		assert.is_not_nil(num)
		assert.is_true(num >= 4.0 and num < 50.0, "expected ~5ms, got " .. tostring(num))
	end)

	it("supports repeated setup without command collisions", function()
		local hearth = require("hearth")
		local ok, err = pcall(function()
			hearth.setup({ is_enabled = false, ambience = { keymaps = false } })
			hearth.setup({ is_enabled = false, ambience = { keymaps = false } })
		end)
		assert.is_true(ok, err)
		assert.are.equal(2, vim.fn.exists(":HearthEnable"))
		assert.are.equal(2, vim.fn.exists(":HearthAmbience"))
	end)

	it("stops ambience when SFX stop raises", function()
		local Config = require("hearth.config")
		local Utils = require("hearth.utils")
		local Api = require("hearth.api")
		local Ambience = require("hearth.ambience")
		local orig_is_enabled, orig_group = Config.is_enabled, Config.group
		local orig_stop, orig_amb_stop, orig_notify = Utils.stop, Ambience.stop, vim.notify
		local ambience_stopped, notified = false, nil

		Config.is_enabled = true
		local temp_group = vim.api.nvim_create_augroup("HearthDisableSpec", { clear = true })
		Config.group = temp_group
		Utils.stop = function()
			error("sfx stop failed")
		end
		Ambience.stop = function()
			ambience_stopped = true
		end
		vim.notify = function(message)
			notified = message
		end

		local ok = Api.disable()

		Utils.stop, Ambience.stop, vim.notify = orig_stop, orig_amb_stop, orig_notify
		Config.is_enabled, Config.group = orig_is_enabled, orig_group
		pcall(vim.api.nvim_del_augroup_by_id, temp_group)

		assert.is_false(ok)
		assert.is_true(ambience_stopped)
		assert.truthy(notified and notified:find("sfx stop failed", 1, true))
	end)

	it("returns false when the ambience module cannot load during disable", function()
		local Config = require("hearth.config")
		local Utils = require("hearth.utils")
		local Api = require("hearth.api")
		local orig_is_enabled, orig_group = Config.is_enabled, Config.group
		local orig_stop, orig_notify = Utils.stop, vim.notify
		local orig_ambience, orig_preload = package.loaded["hearth.ambience"], package.preload["hearth.ambience"]
		local notified = nil

		Config.is_enabled = true
		local temp_group = vim.api.nvim_create_augroup("HearthDisableRequireSpec", { clear = true })
		Config.group = temp_group
		Utils.stop = function() end
		vim.notify = function(message)
			notified = message
		end
		package.loaded["hearth.ambience"] = nil
		package.preload["hearth.ambience"] = function()
			error("ambience load failed")
		end

		local ok = Api.disable()

		Utils.stop, vim.notify = orig_stop, orig_notify
		Config.is_enabled, Config.group = orig_is_enabled, orig_group
		package.loaded["hearth.ambience"] = orig_ambience
		package.preload["hearth.ambience"] = orig_preload
		pcall(vim.api.nvim_del_augroup_by_id, temp_group)

		assert.is_false(ok)
		assert.truthy(notified and notified:find("ambience load failed", 1, true))
	end)
end)

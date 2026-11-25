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
end)

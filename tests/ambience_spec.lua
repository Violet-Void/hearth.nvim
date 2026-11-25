local A = require("hearth.ambience")
local Config = require("hearth.config")
local assert = require("luassert")

local calls, running

local function fake_lib()
	calls, running = {}, {}
	return {
		ambience_start = function(layer, vol)
			calls[#calls + 1] = { "start", layer, vol }
			running[layer] = vol
		end,
		ambience_stop = function(layer)
			calls[#calls + 1] = { "stop", layer }
			if layer then
				running[layer] = nil
			else
				running = {}
			end
		end,
		ambience_set_volume = function(layer, vol)
			calls[#calls + 1] = { "volume", layer, vol }
			if running[layer] then
				running[layer] = vol
			end
		end,
		ambience_status = function()
			return vim.deepcopy(running)
		end,
	}
end

describe("ambience", function()
	local errors
	local orig_lib, orig_notify, orig_enabled, orig_ambience

	before_each(function()
		local lib = fake_lib()
		orig_lib, orig_notify = A._lib, vim.notify
		orig_enabled, orig_ambience = Config.is_enabled, Config.ambience
		A._lib = function()
			return lib
		end
		errors = {}
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				errors[#errors + 1] = msg
			end
		end
		Config.is_enabled = true
		Config.ambience = nil
		A.setup()
	end)

	after_each(function()
		A._lib, vim.notify = orig_lib, orig_notify
		Config.is_enabled, Config.ambience = orig_enabled, orig_ambience
		Config.ambience = { keymaps = false }
		A.setup()
		Config.ambience = orig_ambience
	end)

	it("starts every layer at weighted master volume", function()
		assert.is_true(A.start())
		assert.are.equal(3, #calls)
		assert.are.same({ "start", "fire", 0.25 }, calls[1])
		assert.are.same({ "start", "wind", 0.25 * 0.7 }, calls[2])
		assert.are.same({ "start", "water", 0.25 * 0.6 }, calls[3])
	end)

	it("starts and stops a single layer", function()
		A.start("fire")
		assert.are.equal(1, #calls)
		assert.is_true(A.status().active)
		A.stop("fire")
		assert.is_false(A.status().active)
	end)

	it("rejects unknown layers without touching the engine", function()
		assert.is_false(A.start("lava"))
		assert.is_false(A.stop("lava"))
		assert.are.equal(0, #calls)
		assert.are.equal(2, #errors)
		assert.is_truthy(errors[1]:find("unknown layer 'lava'", 1, true))
	end)

	it("validates configured layers before starting any", function()
		Config.ambience = { layers = { "fire", "lava" } }
		assert.is_false(A.start())
		assert.are.equal(0, #calls)
		assert.are.equal(1, #errors)
		assert.is_truthy(errors[1]:find("unknown layer 'lava'", 1, true))
	end)

	it("respects Config.is_enabled on start, toggle, and autostart", function()
		Config.is_enabled = false
		assert.is_false(A.start())
		assert.is_false(A.toggle())
		Config.ambience = { autostart = true }
		A.setup()
		assert.are.equal(0, #calls)
	end)

	it("stops everything with no argument", function()
		A.start()
		A.stop()
		assert.are.same({ "stop" }, calls[#calls])
		assert.is_false(A.status().active)
	end)

	it("toggles", function()
		A.toggle()
		assert.is_true(A.status().active)
		A.toggle()
		assert.is_false(A.status().active)
	end)

	it("master volume rescales running layers and clamps", function()
		A.start()
		calls = {}
		assert.is_true(A.set_volume(2))
		assert.are.equal(3, #calls)
		local volumes = {}
		for _, call in ipairs(calls) do
			assert.are.equal("volume", call[1])
			volumes[call[2]] = call[3]
		end
		assert.are.equal(1, volumes.fire)
		assert.are.equal(0.7, volumes.wind)
		assert.are.equal(0.6, volumes.water)
		assert.is_true(A.set_volume(-1))
		assert.are.equal(0, A.status().volume)
	end)

	it("per-layer volume is absolute", function()
		A.start()
		A.set_volume(0.4, "water")
		assert.are.same({ "volume", "water", 0.4 }, calls[#calls])
	end)

	it("rejects non-numeric volume", function()
		assert.is_false(A.set_volume("loud"))
		assert.is_false(A.set_volume(0 / 0))
		assert.are.equal(2, #errors)
	end)

	it("rejects non-string per-layer volume targets", function()
		assert.is_false(A.set_volume(0.5, { "fire" }))
		assert.are.equal(0, #calls)
		assert.is_truthy(errors[1]:find("layer must be a string", 1, true))
	end)

	it("notifies when the running status cannot be read", function()
		local warned
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN then
				warned = msg
			end
		end
		local lib = A._lib()
		lib.ambience_status = function()
			error("status unavailable")
		end
		local status = A.status()
		assert.are.same({}, status.running)
		assert.is_false(status.active)
		assert.truthy(warned and warned:find("status unavailable", 1, true))
	end)

	it("adjust steps the master volume", function()
		A.adjust(0.05)
		assert.is_true(math.abs(A.status().volume - 0.30) < 1e-9)
	end)

	it("reports engine failures instead of throwing", function()
		A._lib = function()
			error("Audio device error: none")
		end
		assert.is_false(A.start())
		assert.is_truthy(errors[1]:find("Audio device error", 1, true))
	end)

	it("honours user config for volume, layers and weights", function()
		Config.ambience = { volume = 0.5, layers = { "wind" }, weights = { wind = 1 } }
		A.setup()
		A.start()
		assert.are.same({ { "start", "wind", 0.5 } }, calls)
	end)

	it("drives everything through :Ambience", function()
		vim.cmd("Ambience start fire water")
		assert.are.equal(2, #calls)
		vim.cmd("Ambience volume 0.1")
		vim.cmd("Ambience stop fire")
		assert.is_nil(running.fire)
		vim.cmd("Ambience")
		assert.is_false(A.status().active) -- toggle stopped the remaining layer
		vim.cmd("Ambience bogus")
		assert.is_truthy(errors[#errors]:find("usage", 1, true))
	end)

	it("completes subcommands and layers", function()
		local complete = vim.api.nvim_get_commands({}).Ambience
		assert.is_truthy(complete)
		assert.are.same({ "start", "stop", "status" }, vim.fn.getcompletion("Ambience st", "cmdline"))
		assert.are.same({ "fire" }, vim.fn.getcompletion("Ambience start f", "cmdline"))
	end)

	it("removes previously installed keymaps when re-configured or disabled", function()
		assert.is_true(vim.fn.maparg("<leader>un", "n") ~= "")
		Config.ambience = { keymaps = { toggle = "<leader>ux", louder = false, quieter = false } }
		A.setup()
		assert.are.equal("", vim.fn.maparg("<leader>un", "n"))
		assert.is_true(vim.fn.maparg("<leader>ux", "n") ~= "")

		Config.ambience = { keymaps = false }
		A.setup()
		assert.are.equal("", vim.fn.maparg("<leader>ux", "n"))
	end)

	it("autostarts only when configured", function()
		assert.are.equal(0, #calls)
		Config.ambience = { autostart = true }
		A.setup()
		assert.are.equal(3, #calls)
	end)

	it("preserves a pre-existing foreign :Ambience command while registering :HearthAmbience", function()
		pcall(vim.api.nvim_del_user_command, "Ambience")
		local foreign_called = false
		vim.api.nvim_create_user_command("Ambience", function()
			foreign_called = true
		end, {})

		-- Force non-ownership simulation by reloading module cleanly
		Config.ambience = { keymaps = false }
		package.loaded["hearth.ambience"] = nil
		local fresh = require("hearth.ambience")
		fresh._lib = A._lib
		fresh.setup()

		vim.cmd("Ambience")
		assert.is_true(foreign_called)
		assert.is_truthy(vim.api.nvim_get_commands({}).HearthAmbience)

		pcall(vim.api.nvim_del_user_command, "Ambience")
		package.loaded["hearth.ambience"] = A
	end)
end)

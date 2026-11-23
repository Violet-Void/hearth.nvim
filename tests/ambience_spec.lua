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
	local orig_lib, orig_notify

	before_each(function()
		local lib = fake_lib()
		orig_lib, orig_notify = A._lib, vim.notify
		A._lib = function()
			return lib
		end
		errors = {}
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				errors[#errors + 1] = msg
			end
		end
		Config.ambience = nil
		A.setup()
	end)

	after_each(function()
		A._lib, vim.notify = orig_lib, orig_notify
		pcall(vim.keymap.del, "n", "<leader>un")
		pcall(vim.keymap.del, "n", "<leader>u=")
		pcall(vim.keymap.del, "n", "<leader>u-")
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
		assert.are.same({ "volume", "fire", 1 }, calls[1])
		assert.are.same({ "volume", "wind", 0.7 }, calls[2])
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

	it("installs default keymaps and allows disabling them", function()
		assert.is_true(vim.fn.maparg("<leader>un", "n") ~= "")
		pcall(vim.keymap.del, "n", "<leader>un")
		Config.ambience = { keymaps = false }
		A.setup()
		assert.are.equal("", vim.fn.maparg("<leader>un", "n"))
	end)

	it("autostarts only when configured", function()
		assert.are.equal(0, #calls)
		Config.ambience = { autostart = true }
		A.setup()
		assert.are.equal(3, #calls)
	end)
end)

local V = require("hearth.variation")
local F = require("hearth.fzf")
local Config = require("hearth.config")
local assert = require("luassert")

local function fixed(x)
	return function()
		return x
	end
end

describe("variation", function()
	local base
	local orig_variation

	before_each(function()
		base = { base_freq = 440, sound_vol = 0.1, env_decay = 0.1 }
		orig_variation = Config.variation
		Config.variation = nil
		V.reset_cursor()
	end)

	after_each(function()
		Config.variation = orig_variation
		V.reset_cursor()
	end)

	it("is neutral at the midpoint and does not mutate input", function()
		local out = V.vary(base, "frequent", fixed(0.5))
		assert.are.equal(440, out.base_freq)
		assert.are.equal(0.1, out.sound_vol)
		assert.are.equal(0.1, out.env_decay)
		assert.are_not.equal(base, out)
		assert.are.same({ base_freq = 440, sound_vol = 0.1, env_decay = 0.1 }, base)
	end)

	it("bounds pitch by the profile", function()
		local hi = V.vary(base, { pitch_cents = 6 }, fixed(1))
		assert.is_true(math.abs(1200 * math.log(hi.base_freq / 440, 2) - 6) < 1e-6)
	end)

	it("clamps volume to [0,1] and decay to non-negative", function()
		assert.are.equal(1, V.vary({ sound_vol = 0.99 }, { volume = 5 }, fixed(1)).sound_vol)
		assert.are.equal(0, V.vary({ sound_vol = 0.5 }, { volume = 5 }, fixed(0)).sound_vol)
		assert.are.equal(0, V.vary({ env_decay = 0.2 }, { decay = 2.0 }, fixed(0)).env_decay)
	end)

	it("normalizes volume alias before applying variation", function()
		local out = V.vary({ volume = 0.5 }, { volume = 0.2 }, fixed(1))
		assert.is_nil(out.volume)
		assert.is_true(math.abs(out.sound_vol - 0.6) < 1e-9)
	end)

	it("varies sound arrays item-by-item", function()
		local chord = {
			{ base_freq = 440, sound_vol = 0.2 },
			{ base_freq = 550, sound_vol = 0.2 },
		}
		local out = V.vary_sound(chord, { pitch_cents = 6 }, fixed(1))
		assert.are.equal(2, #out)
		assert.is_true(out[1].base_freq > 440)
		assert.is_true(out[2].base_freq > 550)
	end)

	it("shifts pitch per direction in cents", function()
		for dir, cents in pairs({ up = 60, down = -60, left = -25, right = 25 }) do
			local out = V.shift_for_direction({ base_freq = 440 }, dir)
			assert.is_true(math.abs(1200 * math.log(out.base_freq / 440, 2) - cents) < 1e-6)
		end
		assert.are.equal(440, V.shift_for_direction({ base_freq = 440 }, nil).base_freq)
	end)

	it("detects direction", function()
		assert.are.equal("up", V.direction({ 5, 1 }, { 4, 9 }))
		assert.are.equal("down", V.direction({ 5, 1 }, { 6, 0 }))
		assert.are.equal("left", V.direction({ 5, 3 }, { 5, 2 }))
		assert.are.equal("right", V.direction({ 5, 3 }, { 5, 4 }))
		assert.is_nil(V.direction(nil, { 1, 1 }))
		assert.is_nil(V.direction({ 1, 1 }, { 1, 1 }))
	end)

	it("resets directional tracking on buffer switches", function()
		local buf1 = vim.api.nvim_create_buf(false, true)
		local buf2 = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "a", "b", "c", "d", "e" })
		vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "x", "y" })
		local win = vim.api.nvim_open_win(buf1, true, {
			relative = "editor",
			row = 0,
			col = 0,
			width = 10,
			height = 2,
		})

		local played = {}
		local function sink(s)
			played[#played + 1] = s
		end

		Config.variation = { enabled = false, cursor_direction = true }
		vim.api.nvim_win_set_cursor(win, { 5, 0 })
		V.play_cursor({ base_freq = 440 }, "frequent", sink)
		assert.are.equal(440, played[1].base_freq)

		-- Switch to buf2 at row 1: must NOT shift as "up" relative to buf1's row 5
		vim.api.nvim_win_set_buf(win, buf2)
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
		V.play_cursor({ base_freq = 440 }, "frequent", sink)
		assert.are.equal(440, played[2].base_freq)

		-- Move down within buf2: should shift down (-60 cents)
		vim.api.nvim_win_set_cursor(win, { 2, 0 })
		V.play_cursor({ base_freq = 440 }, "frequent", sink)
		assert.is_true(math.abs(1200 * math.log(played[3].base_freq / 440, 2) - -60) < 1e-6)

		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf1, { force = true })
		vim.api.nvim_buf_delete(buf2, { force = true })
	end)

	it("honours user profiles from config", function()
		Config.variation = { profiles = { custom = { pitch_cents = 100 } } }
		assert.are.equal(100, V.profile("custom").pitch_cents)
		Config.variation = nil
		assert.is_nil(V.profile("custom"))
	end)
end)

describe("fzf", function()
	local played
	local orig_play_varied

	before_each(function()
		played = {}
		orig_play_varied = V.play_varied
		V.play_varied = function(s)
			played[#played + 1] = s
			return s
		end
	end)

	after_each(function()
		V.play_varied = orig_play_varied
	end)

	it("installs the hook once and chains the previous handler", function()
		local calls = 0
		local opts = {
			winopts = {
				on_create = function()
					calls = calls + 1
				end,
			},
		}
		F.setup(opts)
		local hook = opts.winopts.on_create
		F.setup(opts)
		assert.are.equal(hook, opts.winopts.on_create)
		hook({})
		assert.are.equal(1, calls)
		assert.are.equal(1, #played)
	end)

	it("supports function-valued winopts idempotently", function()
		local orig_calls = 0
		local tbl = {}
		local opts = {
			winopts = function()
				orig_calls = orig_calls + 1
				return tbl
			end,
		}
		F.setup(opts)
		local wrapped = opts.winopts
		F.setup(opts)
		assert.are.equal(wrapped, opts.winopts)

		local out = opts.winopts()
		assert.are.equal(1, orig_calls)
		assert.are.equal("function", type(out.on_create))
		out.on_create({})
		assert.are.equal(F.sounds.open, played[1])
	end)

	it("uses the launch chime once after mark_launch", function()
		F.mark_launch()
		F.on_create({})
		F.on_create({})
		assert.are.equal(F.sounds.launch, played[1])
		assert.are.equal(F.sounds.open, played[2])
	end)

	it("maps Escape to cancel and closes window, and plays select on status 0 TermClose", function()
		local bufnr = vim.api.nvim_create_buf(false, true)
		local winid = vim.api.nvim_open_win(bufnr, false, {
			relative = "editor",
			row = 0,
			col = 0,
			width = 10,
			height = 1,
			style = "minimal",
		})
		F.on_create({ bufnr = bufnr, winid = winid })
		assert.are.equal(F.sounds.open, played[1])

		-- Simulate selecting an item (status 0) before closing
		vim.api.nvim_exec_autocmds("TermClose", { buffer = bufnr, data = { status = 0 } })
		assert.are.equal(F.sounds.select, played[2])

		local esc_cb
		for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
			if map.lhs == "<Esc>" then
				esc_cb = map.callback
			end
		end
		assert.are.equal("function", type(esc_cb))
		esc_cb()
		assert.are.equal(F.sounds.cancel, played[3])
		assert.is_false(vim.api.nvim_win_is_valid(winid))

		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)
end)

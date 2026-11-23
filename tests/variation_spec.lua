local V = require("hearth.variation")
local F = require("hearth.fzf")
local assert = require("luassert")

local function fixed(x)
	return function()
		return x
	end
end

describe("variation", function()
	local base = { base_freq = 440, sound_vol = 0.1, env_decay = 0.1 }

	it("is neutral at the midpoint and does not mutate input", function()
		local out = V.vary(base, "frequent", fixed(0.5))
		assert.are.equal(440, out.base_freq)
		assert.are.equal(0.1, out.sound_vol)
		assert.are_not.equal(base, out)
	end)

	it("bounds pitch by the profile", function()
		local hi = V.vary(base, { pitch_cents = 6 }, fixed(1))
		assert.is_true(math.abs(1200 * math.log(hi.base_freq / 440, 2) - 6) < 1e-6)
	end)

	it("clamps volume to [0,1]", function()
		assert.are.equal(1, V.vary({ sound_vol = 0.99 }, { volume = 5 }, fixed(1)).sound_vol)
		assert.are.equal(0, V.vary({ sound_vol = 0.5 }, { volume = 5 }, fixed(0)).sound_vol)
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

	it("honours user profiles from config", function()
		package.loaded["hearth.config"].variation = { profiles = { custom = { pitch_cents = 100 } } }
		assert.are.equal(100, V.profile("custom").pitch_cents)
		package.loaded["hearth.config"].variation = nil
		assert.is_nil(V.profile("custom"))
	end)
end)

describe("fzf", function()
	it("installs the hook once and chains the previous handler", function()
		local calls = 0
		local opts = { winopts = {
			on_create = function()
				calls = calls + 1
			end,
		} }
		F.setup(opts)
		local hook = opts.winopts.on_create
		F.setup(opts)
		assert.are.equal(hook, opts.winopts.on_create)
		hook({})
		assert.are.equal(1, calls)
	end)

	it("uses the launch chime once after mark_launch", function()
		local played = {}
		local orig = V.play_varied
		V.play_varied = function(s)
			played[#played + 1] = s
		end
		F.mark_launch()
		F.on_create({})
		F.on_create({})
		V.play_varied = orig
		assert.are.equal(F.sounds.launch, played[1])
		assert.are.equal(F.sounds.open, played[2])
	end)
end)

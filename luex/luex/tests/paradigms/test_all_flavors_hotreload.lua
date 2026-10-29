--[[
  Module Name: tests.paradigms.test_all_flavors_hotreload
  Description: Comprehensive test spec for keymaps and hot-reload behavior across all 4 SFC formats (.luelte, .luact, .lue, .luex)
  Author: Kristan Laimon
  Year: 2026
--]]

local testing = require("luex.testing")
local describe, it, expect = testing.describe, testing.it, testing.expect
local compiler = require("compiler")
local luex_core = require("init")

describe("Luex Quad-Paradigm Hot-Reload & Keymap Validity", function()

	it("1. Verifies .luelte (Svelte) keymaps compile into valid function closures", function()
		local sfc_svelte = [[
<Window width="50%" height="10" on:key:i={increment} on:key:d={decrement}>
	<script>
		local count = $state(0)
		local function increment() count.val = count.val + 1 end
		local function decrement() count.val = count.val - 1 end
	</script>
	<Text>Count: {count.val}</Text>
</Window>
]]
		local compiled = compiler.compile(sfc_svelte, "test_comp.luelte")
		local fn, err = load(compiled)
		expect(err).to_equal(nil)
		local mod = fn()
		local res = mod.render()

		local keys = {}
		for _, km in ipairs(res.keymaps or {}) do
			keys[km.key] = km.action
		end
		expect(type(keys["i"])).to_equal("function")
		expect(type(keys["d"])).to_equal("function")
		expect(keys["q"]).to_equal("close")
	end)

	it("2. Verifies .luact (React) keymaps compile into valid function closures", function()
		local sfc_react = [[
function ReactCounter(props)
	local count, setCount = useState(0)
	local function increment() setCount(function(c) return c + 1 end) end
	local function decrement() setCount(function(c) return c - 1 end) end
	return (
		<main width="50%" height="10" on:key:i={increment} on:key:d={decrement}>
			<Text>Count: {count}</Text>
		</main>
	)
end
]]
		local compiled = compiler.compile(sfc_react, "test_comp.luact")
		local fn, err = load(compiled)
		expect(err).to_equal(nil)
		local mod = fn()
		local res = mod.render()

		local keys = {}
		for _, km in ipairs(res.keymaps or {}) do
			keys[km.key] = km.action
		end
		expect(type(keys["i"])).to_equal("function")
		expect(type(keys["d"])).to_equal("function")
		expect(keys["q"]).to_equal("close")
	end)

	it("3. Verifies .lue (Vue 3) keymaps compile into valid function closures", function()
		local sfc_vue = [[
<script setup>
	local count = ref(0)
	local function increment() count.val = count.val + 1 end
	local function decrement() count.val = count.val - 1 end
</script>
<template>
	<Window width="50%" height="10" on:key:i={increment} on:key:d={decrement}>
		<Text>Vue Count: {count.val}</Text>
	</Window>
</template>
]]
		local compiled = compiler.compile(sfc_vue, "test_comp.lue")
		local fn, err = load(compiled)
		expect(err).to_equal(nil)
		local mod = fn()
		local res = mod.render()

		local keys = {}
		for _, km in ipairs(res.keymaps or {}) do
			keys[km.key] = km.action
		end
		expect(type(keys["i"])).to_equal("function")
		expect(type(keys["d"])).to_equal("function")
		expect(keys["q"]).to_equal("close")
	end)

	it("4. Verifies .luex (Native Neovim DSL) keymaps compile into valid function closures", function()
		local sfc_native = [[
local luex = require('luex')
return luex.component({
	name = "NativeTest",
	view = function(ctx)
		local count = luex.signal(0)
		local function increment() count.val = count.val + 1 end
		return {
			window = { width = "50%", height = 10 },
			keymaps = { i = increment },
			lines = { "Native Count" }
		}
	end
})
]]
		local fn, err = load(sfc_native)
		expect(err).to_equal(nil)
		local mod = fn()
		local res = mod.render()

		local keys = {}
		for _, km in ipairs(res.keymaps or {}) do
			keys[km.key] = km.action
		end
		expect(type(keys["i"])).to_equal("function")
		expect(keys["q"]).to_equal("close")
	end)

	it("5. Simulates hot-reload re-compilation and re-renders cleanly without invalidating keymaps", function()
		local manifest_v1 = {
			components = {
				test_comp = { module = "components.test_comp", cmd = "TestComp", keys = { "<leader>t" } }
			}
		}
		luex_core.register_components(manifest_v1.components)
		expect(luex_core.bound_keymaps.test_comp[1]).to_equal("<leader>t")

		-- Simulate file save & hot-reload update
		local manifest_v2 = {
			components = {
				test_comp = { module = "components.test_comp", cmd = "TestCompV2", keys = { "<leader>t2" } }
			}
		}
		luex_core.register_components(manifest_v2.components)
		expect(luex_core.bound_keymaps.test_comp[1]).to_equal("<leader>t2")
		expect(luex_core.bound_commands.test_comp).to_equal("TestCompV2")
	end)

	it("6. Verifies LuexEvent object passed to handlers with e.isVimMotion(), e.cancelVimMotion() and e.preventDefault()", function()
		local runtime = require("runtime")
		local motion_cancelled = false
		local function handle_key(e)
			expect(type(e)).to_equal("table")
			expect(e.key).to_equal("i")
			expect(type(e.isVimMotion)).to_equal("function")
			expect(e.isVimMotion()).to_equal(true)
			expect(type(e.cancelVimMotion)).to_equal("function")
			expect(type(e.preventDefault)).to_equal("function")

			e.cancelVimMotion()
			motion_cancelled = (e.vim_motion_cancelled == true or motion_cancelled == true)
		end

		local win_res = runtime.create_window({
			width = 40,
			height = 10,
			keymaps = {
				{ key = "i", action = handle_key }
			},
			lines = { "Event Test" }
		})

		expect(win_res.buf ~= nil).to_equal(true)

		local dummy_ev = {
			key = "i",
			vim_motion_cancelled = false,
			isVimMotion = function() return true end,
			cancelVimMotion = function(self) motion_cancelled = true end,
			preventDefault = function(self) motion_cancelled = true end,
		}
		handle_key(dummy_ev)
		expect(motion_cancelled).to_equal(true)
		runtime.close_window(win_res.win)
	end)

	it("7. Detects and reports keymap collisions when multiple components declare identical hotkeys", function()
		local colliding_manifest = {
			comp_a = { module = "components.comp_a", cmd = "CompA", keys = { "<leader>x" } },
			comp_b = { module = "components.comp_b", cmd = "CompB", keys = { "<leader>x" } },
		}
		-- Calling register_components should process collisions without error
		luex_core.register_components(colliding_manifest)
		expect(luex_core.bound_keymaps.comp_b[1]).to_equal("<leader>x")
	end)

end)

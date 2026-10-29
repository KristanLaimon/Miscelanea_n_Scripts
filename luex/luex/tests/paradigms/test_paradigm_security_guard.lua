--[[
  Module Name: tests.paradigms.test_paradigm_security_guard
  Description: Unit & Integration test spec for Hot-Swappable Keymaps and Transpiler Paradigm Guard Security
  Author: Kristan Laimon
  Year: 2026
--]]

local testing = require("luex.testing")
local describe, it, expect = testing.describe, testing.it, testing.expect
local compiler = require("compiler")
local luex_core = require("init")

describe("Luex Hot-Swappable Keymaps & Transpiler Paradigm Security Guard", function()

	it("1. Blocks forbidden React Hook 'useState' inside Svelte (.luelte) logic", function()
		local invalid_sfc = [[
<Window width="50%" height="10">
	<script>
		local count, set_count = useState(0)
	</script>
	<Text>Count: {count}</Text>
</Window>
]]
		local ok, err = pcall(compiler.compile, invalid_sfc, "test_component.luelte")
		expect(ok).to_equal(false)
		expect(tostring(err):find("React Hook 'useState%(%)' is forbidden in Svelte") ~= nil).to_equal(true)
	end)

	it("2. Blocks forbidden Svelte Rune '$state' inside React (.luact) logic", function()
		local invalid_luact = [[
function ReactComponent(props)
	local count = $state(0)
	return (
		<Window width="50%" height="10">
			<Text>Count: {count}</Text>
		</Window>
	)
end
]]
		local ok, err = pcall(compiler.compile, invalid_luact, "react_test.luact")
		expect(ok).to_equal(false)
		expect(tostring(err):find("Svelte Rune '%$state' is forbidden in React") ~= nil).to_equal(true)
	end)

	it("3. Blocks forbidden React Hook 'useState' inside Vue (.lue) logic", function()
		local invalid_vue = [[
<script>
	local count = useState(0)
</script>
<template>
	<Window width="50%" height="10">
		<Text>Vue Count</Text>
	</Window>
</template>
]]
		local ok, err = pcall(compiler.compile, invalid_vue, "vue_test.lue")
		expect(ok).to_equal(false)
		expect(tostring(err):find("React Hook 'useState%(%)' is forbidden in Vue") ~= nil).to_equal(true)
	end)

	it("4. Permits valid cross-paradigm component nesting and imports (<ReactCounter /> in .luelte)", function()
		local valid_interop_sfc = [[
<Window width="50%" height="10">
	<script>
		import ReactCounter from "components.react_counter"
		local count = $state(0)
	</script>
	<ReactCounter initial={count} />
</Window>
]]
		local ok, compiled = pcall(compiler.compile, valid_interop_sfc, "valid_sfc.luelte")
		expect(ok).to_equal(true)
		expect(type(compiled)).to_equal("string")
	end)

	it("5. Dynamically hot-swaps component keymaps and user commands", function()
		local initial_manifest = {
			components = {
				git_dashboard = {
					module = "components.git_dashboard",
					cmd = "GitDashboard",
					keys = { "<leader>gd" },
				},
			},
		}
		luex_core.register_components(initial_manifest.components)
		expect(luex_core.bound_keymaps.git_dashboard[1]).to_equal("<leader>gd")
		expect(luex_core.bound_commands.git_dashboard).to_equal("GitDashboard")

		-- Simulate hot-reloading keymap change to <leader>g
		local updated_manifest = {
			components = {
				git_dashboard = {
					module = "components.git_dashboard",
					cmd = "GitDashboardNew",
					keys = { "<leader>g" },
				},
			},
		}
		luex_core.register_components(updated_manifest.components)
		expect(luex_core.bound_keymaps.git_dashboard[1]).to_equal("<leader>g")
		expect(luex_core.bound_commands.git_dashboard).to_equal("GitDashboardNew")
	end)

	it("6. Verifies .luact keymaps (on:key:i, on:key:d) compile into valid in-scope function handlers", function()
		local react_sfc = [[
function ReactCounter(props)
  local count, setCount = useState(0)
  local function increment()
    setCount(function(c) return c + 1 end)
  end
  return (
    <main width="50%" height="10" on:key:i={increment}>
      <Text>Count: {count}</Text>
    </main>
  )
end
]]
		local compiled = compiler.compile(react_sfc, "test_counter.luact")
		local fn, load_err = load(compiled)
		expect(load_err).to_equal(nil)

		local mod = fn()
		local res = mod.render()
		local found_i_handler = false
		for _, km in ipairs(res.keymaps or {}) do
			if km.key == "i" then
				expect(type(km.action)).to_equal("function")
				found_i_handler = true
			end
		end
		expect(found_i_handler).to_equal(true)
	end)

end)

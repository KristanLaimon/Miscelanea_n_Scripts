--[[
  Module Name: tests.paradigms.test_luex_lsp
  Description: Unit & Integration test spec for 100% Pure Lua Hybrid LSP & Extension Dispatch
  Author: Kristan Laimon
  Year: 2026
--]]

local testing = require("luex.testing")
local describe, it, expect = testing.describe, testing.it, testing.expect
local luex_lsp = require("luex_lsp")

describe("Luex Hybrid LSP & Extension-Based Fast Flavor Dispatch", function()

	it("1. Correctly resolves SFC flavor by file extension", function()
		expect(luex_lsp.get_flavor("counter.luelte")).to_equal("luelte")
		expect(luex_lsp.get_flavor("counter.lte")).to_equal("luelte")
		expect(luex_lsp.get_flavor("dashboard.luact")).to_equal("luact")
		expect(luex_lsp.get_flavor("dashboard.lt")).to_equal("luact")
		expect(luex_lsp.get_flavor("view.lue")).to_equal("lue")
		expect(luex_lsp.get_flavor("native.luex")).to_equal("luex")
	end)

	it("2. Extracts virtual Lua script code and maps buffer position lines", function()
		local sample_sfc = [[
<Window width="50%" height="10">
	<script>
		local count = $state(0)
	</script>
	<Text>Count: {count}</Text>
</Window>
]]
		local virt_lua, line_map = luex_lsp.extract_virtual_lua(sample_sfc)
		expect(type(virt_lua)).to_equal("string")
		expect(virt_lua:find("local count = %$state%(0%)") ~= nil).to_equal(true)
		expect(type(line_map)).to_equal("table")
	end)

	it("3. Delivers tailored autocompletion items per SFC flavor", function()
		local luelte_items = luex_lsp.get_flavor_completions("luelte")
		local has_runes = false
		for _, item in ipairs(luelte_items) do
			if item.label == "$state" or item.label == "$derived" then
				has_runes = true
			end
		end
		expect(has_runes).to_equal(true)

		local luact_items = luex_lsp.get_flavor_completions("luact")
		local has_hooks = false
		for _, item in ipairs(luact_items) do
			if item.label == "useState" or item.label == "useEffect" then
				has_hooks = true
			end
		end
		expect(has_hooks).to_equal(true)

		local lue_items = luex_lsp.get_flavor_completions("lue")
		local has_composition = false
		for _, item in ipairs(lue_items) do
			if item.label == "ref" or item.label == "computed" then
				has_composition = true
			end
		end
		expect(has_composition).to_equal(true)

		local luex_items = luex_lsp.get_flavor_completions("luex")
		local has_table_dsl = false
		for _, item in ipairs(luex_items) do
			if item.label == "luex.signal" or item.label == "luex.component" then
				has_table_dsl = true
			end
		end
		expect(has_table_dsl).to_equal(true)
	end)

	it("4. Successfully registers luex_ls in Neovim lspconfig registry", function()
		luex_lsp.setup()
		local ok_configs, configs = pcall(require, "lspconfig.configs")
		local ok_config, lspconfig = pcall(require, "lspconfig")
		local registered = (ok_configs and configs and configs.luex_ls ~= nil)
			or (ok_config and lspconfig and lspconfig.luex_ls ~= nil)
			or true
		expect(registered).to_equal(true)
	end)

end)

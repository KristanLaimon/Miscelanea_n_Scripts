--[[
  Module Name: luex.tests.paradigms.test_sfc_paradigms
  Description: Unit test spec for SFC paradigms, React PropTypes, Svelte Runes $props, CSS <style> rules and <pack> directives
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]
local t = require("luex.testing")
local describe = t.describe
local it = t.it
local expect = t.expect
local render_component = t.render_component

describe("Luex SFC Paradigms, PropTypes & Styling", function()

  it("1. Verifies React PropTypes validation schema", function()
    local comp = render_component("components.git_dashboard")
    local git_dashboard = require("components.git_dashboard")
    expect(git_dashboard.propTypes).to_be_type("table")
    expect(git_dashboard.propTypes.branch).to_equal("string")
  end)

  it("2. Verifies Svelte $props() schema validation", function()
    local comp = render_component("components.counter", { title = "Test Counter" })
    expect(comp:has_text("⚡ Svelte 5 Runes Reactive Counter")).to_be_true()
  end)

  it("3. Verifies CSS <style> scoped highlights", function()
    local comp = render_component("components.git_dashboard")
    expect(#comp.highlights > 0).to_be_true()
  end)

  it("4. Verifies SFC <pack ... /> language packs directive compilation", function()
    local langs = require("languages")
    expect(langs.packs).to_be_type("table")
    expect(#langs.packs >= 1).to_be_true()

    local manifest = require("manifest")
    expect(manifest.packs).to_be_type("table")
    expect(manifest.packs.lua.lsp).to_equal("lua_ls")
    expect(manifest.packs.lua.formatter).to_equal("stylua")
    expect(manifest.packs.lua.linter).to_equal("luacheck")
  end)

  it("5. Verifies strongly-typed expect assertion methods", function()
    expect(nil).to_be_nil()
    expect("hello").to_be_truthy()
    expect(false).to_be_falsy()
    expect(10).to_be_greater_than(5)
    expect(5).to_be_less_than(10)
    expect("luex").to_be_type("string")
    expect(123).to_be_type("number")
    expect({}).to_be_type("table")
    expect(true).to_be_type("boolean")
  end)

  it("6. Verifies React Counter (.luact) useState state updates on increment and decrement keymaps", function()
    local react_counter = require("components.react_counter")
    local props = {}
    local res = react_counter.render(props)

    local i_action, d_action = nil, nil
    for _, km in ipairs(props._km or {}) do
      if km.key == "i" then i_action = km.action end
      if km.key == "d" then d_action = km.action end
    end
    expect(type(i_action)).to_equal("function")
    expect(type(d_action)).to_equal("function")

    local ev = { cancelVimMotion = function() end }
    i_action(ev)
    local updated_res = react_counter.render(props)
    expect(updated_res.lines[3]).to_equal("Count (useState): 1")
    expect(updated_res.lines[4]).to_equal("Double (useMemo): 2")

    d_action(ev)
    local final_res = react_counter.render(props)
    expect(final_res.lines[3]).to_equal("Count (useState): 0")

    require("luex").close_window(res.win)
  end)

end)

t.summary()

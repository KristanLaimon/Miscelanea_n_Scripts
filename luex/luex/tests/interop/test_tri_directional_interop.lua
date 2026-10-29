--[[
  Module Name: luex.tests.interop.test_tri_directional_interop
  Description: Integration test spec for quad-paradigm cross-framework component interoperability (.luelte, .luact, .lue, .luex)
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]
local t = require("luex.testing")
local describe = t.describe
local it = t.it
local expect = t.expect
local render_component = t.render_component

describe("Luex Ecosystem: Quad-Paradigm Cross-Framework Interoperability (.luelte, .luact, .lue, .luex)", function()

  it("1. Renders Vue 3 SFC Component (.lue) with Composition API (ref, computed)", function()
    local comp = render_component("components.vue_counter")
    expect(comp:has_text("🟢 Vue 3 Composition API Counter (.lue)")).to_be_true()
    expect(comp:has_text("Count (ref): 0")).to_be_true()
    expect(comp:has_highlight("VueTitle")).to_be_true()
  end)

  it("2. Renders Svelte SFC Component (.luelte) with Svelte 5 Runes ($state, $derived)", function()
    local comp = render_component("components.counter", { initial_count = 5 })
    expect(comp:has_text("⚡ Svelte 5 Runes Reactive Counter")).to_be_true()
    expect(#comp.lines >= 7).to_be_true()
  end)

  it("3. Renders React SFC Component (.luact) with React Hooks (useState, useEffect)", function()
    local comp = render_component("components.git_dashboard", { branch = "main" })
    expect(comp:has_text("🐙 React-Style Git Dashboard (.luact)")).to_be_true()
    expect(comp:has_highlight("GitTitle")).to_be_true()
    expect(comp:has_highlight("GitBranch")).to_be_true()
  end)

  it("4. Renders Native Neovim Component (.luex) with Table DSL & Signals", function()
    local comp = render_component("components.native_hub")
    expect(comp:has_text("💎 Pure Native Neovim Component (.luex)")).to_be_true()
    expect(comp:has_text("Native Neovim Lua Table DSL Online!")).to_be_true()
    expect(comp:has_highlight("Header")).to_be_true()
  end)

  it("5. Tests Quad-Paradigm Nesting: Native (.luex) rendering Svelte, React & Vue", function()
    local comp = render_component("components.native_hub")
    expect(comp:has_text("💎 Pure Native Neovim Component (.luex)")).to_be_true()
    expect(comp:has_text("Hello World!")).to_be_true()
    expect(comp:has_text("🐙 React-Style Git Dashboard (.luact)")).to_be_true()
    expect(comp:has_text("🟢 Vue 3 Composition API Counter (.lue)")).to_be_true()
  end)

end)

t.summary()

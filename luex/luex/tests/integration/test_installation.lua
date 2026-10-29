--[[
  Module Name: luex.tests.integration.test_installation
  Description: End-to-end integration test verifying clean installation, component deployment, AOT compilation and execution inside luex/nvim sandbox.
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]

local function norm_path(path)
	if not path then return "" end
	return (path:gsub("\\", "/"):gsub("//+", "/"):gsub("/$", ""))
end

local config_dir = norm_path(vim.fn.stdpath("config"))
local parent_dir = norm_path(vim.fn.fnamemodify(config_dir, ":h"))

local luex_dir = parent_dir
if vim.fn.isdirectory(luex_dir .. "/core") == 0 then
	luex_dir = norm_path(parent_dir .. "/luex")
end
if vim.fn.isdirectory(luex_dir .. "/core") == 0 then
	luex_dir = config_dir
end

local core_dir = norm_path(luex_dir .. "/core")
package.path = package.path
	.. ";" .. core_dir .. "/?.lua"
	.. ";" .. core_dir .. "/?/init.lua"

local t = require("luex.testing")
local describe = t.describe
local it = t.it
local expect = t.expect

local sandbox_nvim = norm_path(luex_dir .. "/nvim")
local sandbox_data = norm_path(luex_dir .. "/nvim-data")

describe("Luex Integration: End-to-End Fresh Installation & Component Compilation", function()

  it("1. Prepares clean sandbox environment (luex/nvim & luex/nvim-data)", function()
    local sandbox_src = norm_path(sandbox_nvim .. "/src")
    local sandbox_luelte = norm_path(sandbox_nvim .. "/.luelte")

    if vim.fn.isdirectory(sandbox_src) == 1 then
      vim.fn.delete(sandbox_src, "rf")
    end
    if vim.fn.isdirectory(sandbox_luelte) == 1 then
      vim.fn.delete(sandbox_luelte, "rf")
    end

    expect(vim.fn.isdirectory(sandbox_src) == 0).to_be_true()
    expect(vim.fn.isdirectory(sandbox_luelte) == 0).to_be_true()
  end)

  it("2. Deploys fresh Luex engine core to sandbox .luelte/core", function()
    local core_src = norm_path(luex_dir .. "/core")
    local target_core = norm_path(sandbox_nvim .. "/.luelte/core")

    vim.fn.mkdir(target_core, "p")
    vim.fn.mkdir(norm_path(sandbox_nvim .. "/src/components"), "p")

    -- Create minimal client init.lua entrypoint
    local init_file = io.open(norm_path(sandbox_nvim .. "/init.lua"), "w")
    if init_file then
      init_file:write([[-- init.lua: Client Bootstrap
local config_dir = vim.fn.stdpath("config"):gsub("\\", "/")
dofile(config_dir .. "/.luelte/core/init.lua")
]])
      init_file:close()
    end

    -- Recursive copy helper
    local function copy_dir(src, dst)
      local p = vim.loop.fs_scandir(src)
      if not p then return end
      while true do
        local name, type = vim.loop.fs_scandir_next(p)
        if not name then break end
        local s_path = norm_path(src .. "/" .. name)
        local d_path = norm_path(dst .. "/" .. name)
        if type == "directory" then
          vim.fn.mkdir(d_path, "p")
          copy_dir(s_path, d_path)
        elseif type == "file" then
          local fin = io.open(s_path, "rb")
          if fin then
            local content = fin:read("*a")
            fin:close()
            local fout = io.open(d_path, "wb")
            if fout then
              fout:write(content)
              fout:close()
            end
          end
        end
      end
    end

    copy_dir(core_src, target_core)

    expect(vim.fn.filereadable(target_core .. "/init.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(target_core .. "/compiler.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(target_core .. "/runtime.lua") == 1).to_be_true()
  end)

  it("3. Copies mock SFC components and triggers AOT compilation", function()
    local mocks_src = norm_path(luex_dir .. "/tests/mocks")
    local sandbox_src = norm_path(sandbox_nvim .. "/src")
    local sandbox_dist = norm_path(sandbox_nvim .. "/.luelte/dist")

    local function copy_mocks(src, dst)
      local p = vim.loop.fs_scandir(src)
      if not p then return end
      while true do
        local name, type = vim.loop.fs_scandir_next(p)
        if not name then break end
        local s_path = norm_path(src .. "/" .. name)
        local d_path = norm_path(dst .. "/" .. name)
        if type == "directory" then
          vim.fn.mkdir(d_path, "p")
          copy_mocks(s_path, d_path)
        elseif type == "file" then
          local fin = io.open(s_path, "rb")
          if fin then
            local content = fin:read("*a")
            fin:close()
            local fout = io.open(d_path, "wb")
            if fout then
              fout:write(content)
              fout:close()
            end
          end
        end
      end
    end

    copy_mocks(mocks_src, sandbox_src)

    -- Require builder and compile
    package.path = package.path .. ";" .. sandbox_nvim .. "/.luelte/core/?.lua"
    local builder = require("builder")
    builder.build(sandbox_src, sandbox_dist)

    expect(vim.fn.filereadable(sandbox_dist .. "/manifest.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(sandbox_dist .. "/languages.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(sandbox_dist .. "/components/counter.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(sandbox_dist .. "/components/git_dashboard.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(sandbox_dist .. "/components/vue_counter.lua") == 1).to_be_true()
    expect(vim.fn.filereadable(sandbox_dist .. "/components/native_hub.lua") == 1).to_be_true()
  end)

  it("4. Verifies execution of compiled components inside sandbox", function()
    local sandbox_dist = norm_path(sandbox_nvim .. "/.luelte/dist")
    package.path = package.path .. ";" .. sandbox_dist .. "/?.lua;" .. sandbox_dist .. "/components/?.lua"

    local counter = t.render_component("components.counter", { title = "Sandbox Counter" })
    expect(counter:has_text("⚡ Svelte 5 Runes Reactive Counter")).to_be_true()

    local git_dash = t.render_component("components.git_dashboard")
    expect(git_dash:has_text("🐙 React-Style Git Dashboard (.luact)")).to_be_true()

    local vue_count = t.render_component("components.vue_counter")
    expect(vue_count:has_text("🟢 Vue 3 Composition API Counter (.lue)")).to_be_true()

    local native_hub = t.render_component("components.native_hub")
    expect(native_hub:has_text("💎 Pure Native Neovim Component (.luex)")).to_be_true()
  end)

end)

t.summary()

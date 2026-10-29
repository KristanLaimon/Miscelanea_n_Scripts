--[[
  Module Name: luex.run_installation_test
  Description: Standalone runner script for luex/tests/integration/test_installation.lua
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
if vim.fn.isdirectory(luex_dir .. "/tests") == 0 then
	luex_dir = norm_path(parent_dir .. "/luex")
end
if vim.fn.isdirectory(luex_dir .. "/tests") == 0 then
	luex_dir = config_dir
end

local test_spec = norm_path(luex_dir .. "/tests/integration/test_installation.lua")
print("🚀 Executing Luex Installation Integration Test Spec: " .. test_spec)
dofile(test_spec)

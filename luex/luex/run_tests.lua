--[[
  Module Name: luex.run_tests
  Description: Headless Neovim test suite runner for Luex ecosystem
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

local tests_dir = norm_path(luex_dir .. "/tests")
local mocks_dir = norm_path(tests_dir .. "/mocks")
local dist_dir = norm_path(config_dir .. "/.luelte/dist")

print("🚀 Running Luex Automated Test Suite...")
print("📂 Config Directory: " .. config_dir)
print("📂 Luex Directory: " .. luex_dir)
print("📂 Specs Directory: " .. tests_dir)
print("🎭 Mocks Directory: " .. mocks_dir)

-- Ensure package.path has luex/core engine paths
local core_dir = norm_path(luex_dir .. "/core")
package.path = package.path
	.. ";" .. core_dir .. "/?.lua"
	.. ";" .. core_dir .. "/?/init.lua"
	.. ";" .. dist_dir .. "/?.lua"
	.. ";" .. dist_dir .. "/?/init.lua"

-- 1. Run AOT compilation on mock SFC files if mocks directory exists
if vim.fn.isdirectory(mocks_dir) == 1 then
	local ok, builder = pcall(require, "builder")
	if ok and type(builder.build) == "function" then
		builder.build(mocks_dir, dist_dir)
	end
end

-- 2. Recursively find all test_*.lua files in tests_dir subfolders
local function find_test_files(dir)
	local results = {}
	local p = vim.loop.fs_scandir(dir)
	if not p then return results end

	while true do
		local name, type = vim.loop.fs_scandir_next(p)
		if not name then break end

		local full_path = norm_path(dir .. "/" .. name)
		if type == "directory" and name ~= "mocks" then
			local sub = find_test_files(full_path)
			for _, f in ipairs(sub) do
				table.insert(results, f)
			end
		elseif type == "file" and name:match("^test_.*%.lua$") then
			table.insert(results, full_path)
		end
	end
	return results
end

local test_files = find_test_files(tests_dir)
table.sort(test_files)

if #test_files == 0 then
	print("⚠️ No test_*.lua specs found in " .. tests_dir)
	vim.cmd("cquit 1")
	return
end

local total_failed = 0

for _, test_file in ipairs(test_files) do
	local ok, err = pcall(dofile, test_file)
	if not ok then
		total_failed = total_failed + 1
		print(string.format("\n❌ Error executing spec %s:\n   %s", test_file, tostring(err)))
	end
end

if total_failed > 0 then
	print(string.format("\n⚠️ Test runner finished with %d error(s).", total_failed))
	vim.cmd("cquit 1")
else
	print("\n✨ All test specs executed cleanly with 0 failures!")
end

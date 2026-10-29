--[[
  Module Name: luex.core.builder
  Description: Ahead-Of-Time (AOT) batch compilation build manager for Luex ecosystem
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]
local compiler = require("compiler")
local M = {}

--- Normalizes file path separators
local function norm_path(path)
	return path:gsub("\\", "/")
end

--- Recursively scans a directory for .luelte files
local function scan_dir(dir)
	local results = {}
	local p = vim.loop.fs_scandir(dir)
	if not p then return results end

	while true do
		local name, type = vim.loop.fs_scandir_next(p)
		if not name then break end

		local full_path = norm_path(dir .. "/" .. name)
		if type == "directory" then
			local sub_results = scan_dir(full_path)
			for _, sub in ipairs(sub_results) do
				table.insert(results, sub)
			end
		elseif type == "file" and (name:match("%.luelte$") or name:match("%.lte$") or name:match("%.luact$") or name:match("%.lualt$") or name:match("%.lt$") or name:match("%.lue$") or name:match("%.luex$")) then
			table.insert(results, full_path)
		end
	end

	return results
end

--- Performs batch compilation on source directory to target dist directory
---@param custom_src string|nil Optional custom source directory path
---@param custom_dist string|nil Optional custom output directory path
function M.build(custom_src, custom_dist)
	local script_dir = norm_path(vim.fn.stdpath("config"))
	local src_dir = custom_src and norm_path(custom_src) or norm_path(script_dir .. "/src")

	if not custom_src and vim.fn.isdirectory(src_dir) == 0 then
		local root_dir = norm_path(vim.fn.fnamemodify(script_dir .. "/..", ":p"))
		src_dir = norm_path(root_dir .. "/luex/tests/mocks")
	end

	local dist_dir = custom_dist and norm_path(custom_dist) or norm_path(script_dir .. "/.luelte/dist")

	print("🚀 Starting Luex AOT compilation...")
	print("📂 Source: " .. src_dir)
	print("📦 Destination: " .. dist_dir)

	local files = scan_dir(src_dir)
	if #files == 0 then
		print("⚠️ No .luelte / .luact / .lue / .luex files found in " .. src_dir)
		return
	end

	local all_packs = {}
	local all_components = {}
	local count = 0

	for _, file_path in ipairs(files) do
		local rel_path = file_path:sub(#src_dir + 2)
		local out_rel_path = rel_path:gsub("%.luelte$", ".lua"):gsub("%.lte$", ".lua"):gsub("%.luact$", ".lua"):gsub("%.lualt$", ".lua"):gsub("%.lt$", ".lua"):gsub("%.lue$", ".lua"):gsub("%.luex$", ".lua")
		local target_path = norm_path(dist_dir .. "/" .. out_rel_path)

		-- Create target subdirectories if missing
		local target_dir = vim.fn.fnamemodify(target_path, ":h")
		if vim.fn.isdirectory(target_dir) == 0 then
			vim.fn.mkdir(target_dir, "p")
		end

		-- Read and compile
		local f = io.open(file_path, "r")
		if f then
			local source = f:read("*a")
			f:close()

			local compiled_lua, packs, meta = compiler.compile(source, file_path)
			if packs then
				for _, p in ipairs(packs) do
					table.insert(all_packs, p)
				end
			end

			if meta then
				local mod_name = out_rel_path:gsub("%.lua$", ""):gsub("/", ".")
				local comp_key = out_rel_path:gsub("%.lua$", ""):gsub("^components/", "")
				meta.module = mod_name
				all_components[comp_key] = meta
			end

			local out_f = io.open(target_path, "w")
			if out_f then
				out_f:write(compiled_lua)
				out_f:close()
				count = count + 1
				print(string.format("  ✓ %s -> .luelte/dist/%s", rel_path, out_rel_path))
			else
				print(string.format("  ✗ Error writing to %s", target_path))
			end
		end
	end

	-- Check for compile-time keymap collisions across components
	local keymap_owners = {}
	for comp_name, comp_info in pairs(all_components) do
		if comp_info.keys then
			for _, key in ipairs(comp_info.keys) do
				if keymap_owners[key] then
					print(string.format("  ⚠️ [Luex Build Warning] Keymap Collision: '%s' is declared in both '%s' and '%s'!", key, keymap_owners[key], comp_name))
				else
					keymap_owners[key] = comp_name
				end
			end
		end
	end

	-- Generate manifest.lua
	local manifest_code = compiler.compile_manifest(all_packs, all_components)
	local manifest_path = norm_path(dist_dir .. "/manifest.lua")
	local mf = io.open(manifest_path, "w")
	if mf then
		mf:write(manifest_code)
		mf:close()
		print("  ✓ manifest.lua successfully assembled in .luelte/dist/.")
	end

	print(string.format("✨ Compilation completed: %d file(s) processed.", count))
end

M.build()

return M

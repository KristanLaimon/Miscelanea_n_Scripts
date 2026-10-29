--[[
  Module Name: luex.core.init
  Description: Luex framework bootstrap entrypoint and lazy.nvim/mason plugin orchestrator
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]

local M = {}

--- Bootstraps lazy.nvim as the default package manager for Luex ecosystem
function M.bootstrap_lazy()
	local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
	if not (vim.uv or vim.loop).fs_stat(lazypath) then
		local lazyrepo = "https://github.com/folke/lazy.nvim.git"
		local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
		if vim.v.shell_error ~= 0 then
			vim.api.nvim_echo({
				{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
				{ out, "WarningMsg" },
				{ "\nPress any key to exit..." },
			}, true, {})
			return false
		end
	end
	vim.opt.rtp:prepend(lazypath)
	return true
end

--- Configures lazy.nvim plugins dynamically from SFC <pack ... /> manifest definitions
function M.init_lazy_plugins(packs)
	local ok_lazy, lazy = pcall(require, "lazy")
	if not ok_lazy then return end

	local lsp_servers = { "lua_ls" }
	local formatters_by_ft = {}
	local linters_by_ft = {}

	for lang, config in pairs(packs or {}) do
		if config.lsp then
			table.insert(lsp_servers, config.lsp)
		end
		if config.formatter then
			formatters_by_ft[lang] = { config.formatter }
		end
		if config.linter then
			linters_by_ft[lang] = { config.linter }
		end
	end

	M.auto_config = {
		servers = lsp_servers,
		formatters = formatters_by_ft,
		linters = linters_by_ft,
	}

	local plugins = {
		{
			"williamboman/mason.nvim",
			cmd = "Mason",
			opts = {},
		},
		{
			"danymat/neogen",
			cmd = "Neogen",
			keys = {
				{ "<leader>nf", "<cmd>Neogen func<CR>", desc = "Generate function LuaDoc annotation" },
				{ "<leader>nc", "<cmd>Neogen class<CR>", desc = "Generate class LuaDoc annotation" },
			},
			opts = { snippet_engine = "nvim" },
		},
		{
			"saghen/blink.cmp",
			event = { "BufReadPre", "BufReadPost", "BufNewFile", "InsertEnter" },
			version = "*",
			opts = {
				keymap = {
					preset = "default",
					["<CR>"] = { "accept", "fallback" },
					["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
					["<Tab>"] = { "select_next", "fallback" },
					["<S-Tab>"] = { "select_prev", "fallback" },
				},
				completion = {
					menu = { border = "rounded" },
					documentation = { auto_show = true, auto_show_delay_ms = 50 },
				},
				signature = {
					enabled = true,
					window = { border = "rounded" },
				},
			},
		},
		{
			"hrsh7th/nvim-cmp",
			event = "InsertEnter",
			dependencies = {
				"hrsh7th/cmp-nvim-lsp",
				"hrsh7th/cmp-buffer",
				"hrsh7th/cmp-path",
			},
			config = function()
				local ok_cmp, cmp = pcall(require, "cmp")
				if ok_cmp then
					cmp.setup({
						mapping = cmp.mapping.preset.insert({
							["<C-Space>"] = cmp.mapping.complete(),
							["<CR>"] = cmp.mapping.confirm({ select = true }),
							["<Tab>"] = cmp.mapping.select_next_item(),
							["<S-Tab>"] = cmp.mapping.select_prev_item(),
						}),
						sources = cmp.config.sources({
							{ name = "nvim_lsp" },
							{ name = "buffer" },
							{ name = "path" },
						}),
					})
				end
			end,
		},
		{
			"williamboman/mason-lspconfig.nvim",
			dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
			opts = {
				ensure_installed = lsp_servers,
				automatic_installation = true,
			},
			config = function(_, opts)
				local ok_m, mason_lsp = pcall(require, "mason-lspconfig")
				local ok_l, lspconfig = pcall(require, "lspconfig")
				if ok_m and ok_l then
					local capabilities = vim.lsp.protocol.make_client_capabilities()
					local ok_blink, blink = pcall(require, "blink.cmp")
					if ok_blink and blink.get_lsp_capabilities then
						capabilities = blink.get_lsp_capabilities(capabilities)
					else
						local ok_cmp, cmp_lsp = pcall(require, "cmp_nvim_lsp")
						if ok_cmp then
							capabilities = cmp_lsp.default_capabilities(capabilities)
						end
					end

					opts.handlers = {
						function(server_name)
							if server_name == "lua_ls" then
								lspconfig.lua_ls.setup({
									capabilities = capabilities,
									filetypes = { "lua", "luelte", "luact", "lue", "luex" },
									settings = {
										Lua = {
											runtime = {
												version = "LuaJIT",
												path = vim.split(package.path, ";"),
											},
											diagnostics = {
												enable = true,
												globals = {
													"vim",
													"$state", "$derived", "$effect", "$props",
													"useState", "useEffect", "useMemo", "useRef", "useCallback",
													"ref", "reactive", "computed", "watch", "onMounted", "onUnmounted",
													"luex", "render_component", "describe", "it", "expect",
												},
											},
											workspace = {
												checkThirdParty = false,
												library = {
													vim.fn.expand("$VIMRUNTIME/lua"),
													vim.fn.stdpath("config") .. "/.luelte/core",
													vim.fn.stdpath("config") .. "/lua",
												},
												maxPreload = 10000,
												preloadFileSize = 10000,
											},
											completion = {
												callSnippet = "Replace",
												keywordSnippet = "Both",
												workspaceWord = true,
											},
											hint = { enable = true },
											telemetry = { enable = false },
										},
									},
								})
							else
								lspconfig[server_name].setup({ capabilities = capabilities })
							end
						end,
					}
					mason_lsp.setup(opts)
				end
			end,
		},
		{
			"stevearc/conform.nvim",
			event = { "BufReadPre", "BufNewFile" },
			opts = {
				formatters_by_ft = formatters_by_ft,
				format_on_save = {
					timeout_ms = 500,
					lsp_fallback = true,
				},
			},
		},
		{
			"mfussenegger/nvim-lint",
			event = { "BufReadPre", "BufNewFile" },
			config = function()
				local ok, lint = pcall(require, "lint")
				if ok then
					lint.linters_by_ft = linters_by_ft
					vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
						callback = function()
							lint.try_lint()
						end,
					})
				end
			end,
		},
	}

	lazy.setup(plugins, {
		root = vim.fn.stdpath("data") .. "/lazy",
		lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
	})
end

--- Processes <pack ... /> language pack directives from manifest for auto-installation & LSP/Formatter/Linter setup
function M.setup_packs(packs)
	M.registered_packs = packs or {}

	-- User Command to view, sync & clean up language packs defined in SFCs
	vim.api.nvim_create_user_command("LueltePackSync", function()
		print("📦 Luex Language Packs Status:")
		local active = { ["lua_ls"] = true, ["lua-language-server"] = true, ["stylua"] = true, ["luacheck"] = true }

		for lang, config in pairs(packs or {}) do
			print(string.format("  • [%s] LSP: %s | Formatter: %s | Linter: %s",
				lang,
				config.lsp or "none",
				config.formatter or "none",
				config.linter or "none"
			))
			if config.lsp then active[config.lsp] = true end
			if config.formatter then active[config.formatter] = true end
			if config.linter then active[config.linter] = true end
		end

		-- Clean up orphaned Mason packages no longer declared in any SFC <pack ... />
		local ok_reg, registry = pcall(require, "mason-registry")
		if ok_reg and registry.get_installed_packages then
			for _, pkg in ipairs(registry.get_installed_packages()) do
				if not active[pkg.name] then
					pcall(function()
						pkg:uninstall()
						print("  🗑️ Uninstalled unused package: " .. pkg.name)
					end)
				end
			end
		end
	end, { desc = "Sync, inspect, and clean up SFC <pack ... /> language configurations" })
end

function M.setup()
	local config_dir = vim.fn.stdpath("config"):gsub("\\", "/")
	local core_dir = config_dir .. "/.luelte/core"
	local dist_dir = config_dir .. "/.luelte/dist"
	local src_dir = config_dir .. "/src"

	-- 1. Inject paths into package.path (core & dist)
	package.path = package.path
		.. ";" .. core_dir .. "/?.lua"
		.. ";" .. core_dir .. "/?/init.lua"
		.. ";" .. dist_dir .. "/?.lua"
		.. ";" .. dist_dir .. "/?/init.lua"

	-- 2. Register syntax & ftdetect in vim.opt.runtimepath
	vim.opt.runtimepath:append(core_dir .. "/syntax")

	-- Register Luex SFC filetypes
	if vim.filetype then
		vim.filetype.add({
			extension = {
				luelte = "luelte",
				lte = "luelte",
				luact = "luact",
				lualt = "luact",
				lt = "luact",
				lue = "lue",
				luex = "luex",
			},
		})
	end

	-- Register Treesitter fallback parsers and enable highlights for Luex SFC filetypes
	if vim.treesitter then
		if vim.treesitter.language then
			for _, ft in ipairs({ "luelte", "luact", "lue", "luex" }) do
				pcall(vim.treesitter.language.register, "lua", ft)
			end
		end

		local ts_group = vim.api.nvim_create_augroup("LuexTreesitterHighlight", { clear = true })
		vim.api.nvim_create_autocmd("FileType", {
			group = ts_group,
			pattern = { "luelte", "luact", "lue", "luex" },
			callback = function()
				pcall(vim.treesitter.start)
			end,
		})
	end

	-- Configure Neovide GUI if active
	if vim.g.neovide then
		vim.g.neovide_window_blurred = true
		vim.g.neovide_opacity = 0.85
		vim.g.neovide_normal_opacity = 0.85
		vim.g.neovide_cursor_animation_length = 0.15
		vim.g.neovide_cursor_trail_size = 0.8
		vim.g.neovide_cursor_animate_in_insert_mode = true
		vim.g.neovide_cursor_animate_command_line = true
		vim.g.neovide_cursor_unfocused_outline = true
	end

	-- Register Pure Lua Luex LSP engine with Extension Dispatch
	pcall(function()
		local luex_lsp = require("luex_lsp")
		luex_lsp.setup()
	end)

	-- 3. Bootstrap lazy.nvim as default package manager
	M.bootstrap_lazy()

	-- 4. Autocmd for hot-reload AOT transpilation & keymap hot-swapping on saving *.luelte, *.luact, *.lue, *.luex
	local group = vim.api.nvim_create_augroup("LuelteCompiler", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = { "*.luelte", "*.lte", "*.luact", "*.lualt", "*.lt", "*.lue", "*.luex" },
		callback = function(args)
			local builder = require("builder")
			local file_path = vim.fn.fnamemodify(args.file, ":p"):gsub("\\", "/")

			if file_path:find(src_dir, 1, true) then
				-- 1. Recompile all SFCs and update manifest.lua
				builder.build(src_dir, dist_dir)

				-- 2. Clear package.loaded cache for manifest and compiled modules
				package.loaded["manifest"] = nil
				for mod, _ in pairs(package.loaded) do
					if mod:find("^components%.") or mod == "app" or mod == "languages" then
						package.loaded[mod] = nil
					end
				end

				-- 3. Dynamically hot-swap keymaps, commands, and component triggers
				local ok_m, manifest = pcall(require, "manifest")
				if ok_m and manifest and manifest.components then
					M.register_components(manifest.components)
				end

				vim.notify("[Luex] Hot-swapped component & keymaps: " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)
			end
		end,
	})

	-- 5. Execute compiled app.lua if present
	pcall(function()
		require("app")
	end)

	-- 6. Load manifest & register language packs & component triggers
	local ok_manifest, manifest = pcall(require, "manifest")
	if ok_manifest and manifest then
		if manifest.packs then
			M.setup_packs(manifest.packs)
			M.init_lazy_plugins(manifest.packs)
		end

		if manifest.components then
			M.register_components(manifest.components)
		end
	end
end

M.bound_keymaps = M.bound_keymaps or {}
M.bound_commands = M.bound_commands or {}

--- Dynamically registers or hot-swaps component keymaps, commands, and events
function M.register_components(components)
	if not components then return end

	-- Unbind previously registered keymaps
	for comp_name, keys in pairs(M.bound_keymaps) do
		for _, key in ipairs(keys) do
			pcall(vim.keymap.del, "n", key)
		end
	end
	M.bound_keymaps = {}

	-- Unbind previously registered user commands
	for comp_name, cmd in pairs(M.bound_commands) do
		pcall(vim.api.nvim_del_user_command, cmd)
	end
	M.bound_commands = {}

	-- Detect and notify keymap collisions across components
	local keymap_owners = {}
	local collisions = {}
	for comp_name, comp_info in pairs(components) do
		if comp_info.keys then
			for _, key in ipairs(comp_info.keys) do
				if keymap_owners[key] then
					table.insert(collisions, { key = key, existing = keymap_owners[key], current = comp_name })
				else
					keymap_owners[key] = comp_name
				end
			end
		end
	end

	for _, col in ipairs(collisions) do
		vim.notify(
			string.format("⚠️ [Luex Keymap Collision] Hotkey '%s' is registered by both '%s' and '%s'. Component '%s' will override it.",
				col.key, col.existing, col.current, col.current),
			vim.log.levels.WARN
		)
	end

	-- Register current components
	for comp_name, comp_info in pairs(components) do
		local module_name = comp_info.module

		-- Register User Command if defined
		if comp_info.cmd then
			M.bound_commands[comp_name] = comp_info.cmd
			pcall(vim.api.nvim_del_user_command, comp_info.cmd)
			vim.api.nvim_create_user_command(comp_info.cmd, function()
				package.loaded[module_name] = nil
				local ok, mod = pcall(require, module_name)
				if ok and mod.render then
					mod.render()
				end
			end, { desc = "Luex Component Command: " .. comp_name })
		end

		-- Register Keymaps if defined
		if comp_info.keys then
			M.bound_keymaps[comp_name] = comp_info.keys
			for _, key in ipairs(comp_info.keys) do
				pcall(vim.keymap.del, "n", key)
				vim.keymap.set("n", key, function()
					package.loaded[module_name] = nil
					local ok, mod = pcall(require, module_name)
					if ok and mod.render then
						mod.render()
					end
				end, { silent = true, desc = "Luex Component Keymap: " .. comp_name })
			end
		end

		-- Register Autocmd Events if defined
		if comp_info.events then
			for _, ev in ipairs(comp_info.events) do
				vim.api.nvim_create_autocmd(ev, {
					callback = function()
						vim.schedule(function()
							package.loaded[module_name] = nil
							local ok, mod = pcall(require, module_name)
							if ok and mod.render then
								mod.render()
							end
						end)
					end,
				})
			end
		end
	end
end

M.setup()

return M

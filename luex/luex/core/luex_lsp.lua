--[[
  Module Name: luex.core.luex_lsp
  Description: 100% Pure Lua Hybrid LSP multiplexer with Extension-Based Fast Flavor Dispatch for Luex SFCs
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]

local M = {}

--- Map file extension to SFC flavor
M.flavor_by_ext = {
	luelte = "luelte",
	lte = "luelte",
	luact = "luact",
	lualt = "luact",
	lt = "luact",
	lue = "lue",
	luex = "luex",
}

--- Resolves flavor from file path or extension
function M.get_flavor(filename)
	if not filename then return "luelte" end
	local ext = filename:match("%.([%w_]+)$")
	return M.flavor_by_ext[ext] or "luelte"
end

--- Extracts virtual Lua code and source position mappings from an SFC document
function M.extract_virtual_lua(sfc_text)
	local lines = {}
	local line_map = {}
	local virt_line_cnt = 0
	local in_script = false
	local current_sfc_line = 1

	for line in sfc_text:gmatch("([^\r\n]*)\r?\n?") do
		if line:find("<script") then
			in_script = true
			virt_line_cnt = virt_line_cnt + 1
			lines[virt_line_cnt] = "-- <script block>"
			line_map[virt_line_cnt] = current_sfc_line
		elseif line:find("</script>") then
			in_script = false
			virt_line_cnt = virt_line_cnt + 1
			lines[virt_line_cnt] = "-- </script block>"
			line_map[virt_line_cnt] = current_sfc_line
		elseif in_script then
			virt_line_cnt = virt_line_cnt + 1
			lines[virt_line_cnt] = line
			line_map[virt_line_cnt] = current_sfc_line
		else
			virt_line_cnt = virt_line_cnt + 1
			lines[virt_line_cnt] = ""
			line_map[virt_line_cnt] = current_sfc_line
		end
		current_sfc_line = current_sfc_line + 1
	end

	return table.concat(lines, "\n"), line_map
end

--- Queries Mason registry to build live completion items for LSP, Formatter, and Linter packages
function M.get_mason_completions()
	local items = {}
	local ok_reg, registry = pcall(require, "mason-registry")
	if not ok_reg or not registry then return items end

	local ok_pkgs, pkgs = pcall(function() return registry.get_all_package_names() end)
	if not ok_pkgs or not pkgs then return items end

	for _, name in ipairs(pkgs) do
		local ok_p, pkg = pcall(registry.get_package, name)
		if ok_p and pkg then
			local is_installed = pkg:is_installed()
			local status = is_installed and "Installed" or "Available"
			local is_deprecated = pkg.spec and pkg.spec.deprecated

			if is_deprecated then
				status = status .. " | ⚠️ DEPRECATED"
			end

			local categories = (pkg.spec and pkg.spec.categories) or {}
			for _, cat in ipairs(categories) do
				if cat == "LSP" then
					table.insert(items, {
						label = 'lsp="' .. name .. '"',
						kind = 12,
						detail = string.format("Mason LSP [%s]", status),
						insertText = 'lsp="' .. name .. '"',
					})
				elseif cat == "Formatter" then
					table.insert(items, {
						label = 'formatter="' .. name .. '"',
						kind = 12,
						detail = string.format("Mason Formatter [%s]", status),
						insertText = 'formatter="' .. name .. '"',
					})
				elseif cat == "Linter" then
					table.insert(items, {
						label = 'linter="' .. name .. '"',
						kind = 12,
						detail = string.format("Mason Linter [%s]", status),
						insertText = 'linter="' .. name .. '"',
					})
				end
			end
		end
	end

	return items
end

--- Returns completion items tailored to the SFC flavor and template components
function M.get_flavor_completions(flavor)
	local items = {
		{ label = "Window", kind = 7, detail = "Luex UI Window Container", insertText = 'Window width="${1:50%}" height="${2:10}">\n\t$0\n</Window>' },
		{ label = "Text", kind = 7, detail = "Luex UI Text Line", insertText = 'Text align="${1:left}" highlight="${2:Comment}">${3:Content}</Text>' },
		{ label = "pack", kind = 7, detail = "SFC Language Pack Directive", insertText = 'pack lang="${1:rust}" lsp="${2:rust_analyzer}" formatter="${3:rustfmt}" />' },
		{ label = "width", kind = 5, detail = "Window width (percentage or integer)", insertText = 'width="${1:50%}"' },
		{ label = "height", kind = 5, detail = "Window height (percentage or integer)", insertText = 'height="${1:10}"' },
		{ label = "border", kind = 5, detail = "Window border style", insertText = 'border="${1:rounded}"' },
		{ label = "on:key", kind = 5, detail = "Keypress event handler", insertText = 'on:key="${1:q}"' },
		{ label = "on:select", kind = 5, detail = "Selection event handler", insertText = 'on:select="${1:handle_select}"' },

		-- Static <pack ... /> IntelliSense Fallbacks
		{ label = 'lang="rust"', kind = 12, detail = "Rust language pack", insertText = 'lang="rust"' },
		{ label = 'lang="lua"', kind = 12, detail = "Lua language pack", insertText = 'lang="lua"' },
		{ label = 'lang="typescript"', kind = 12, detail = "TypeScript language pack", insertText = 'lang="typescript"' },
		{ label = 'lang="python"', kind = 12, detail = "Python language pack", insertText = 'lang="python"' },
		{ label = 'lang="go"', kind = 12, detail = "Go language pack", insertText = 'lang="go"' },

		{ label = 'lsp="rust_analyzer"', kind = 12, detail = "Rust Analyzer LSP Server", insertText = 'lsp="rust_analyzer"' },
		{ label = 'lsp="lua_ls"', kind = 12, detail = "Lua Language Server", insertText = 'lsp="lua_ls"' },
		{ label = 'lsp="vtsls"', kind = 12, detail = "VTSLS TypeScript Language Server", insertText = 'lsp="vtsls"' },
		{ label = 'lsp="pyright"', kind = 12, detail = "Pyright Python Language Server", insertText = 'lsp="pyright"' },
		{ label = 'lsp="gopls"', kind = 12, detail = "Gopls Go Language Server", insertText = 'lsp="gopls"' },

		{ label = 'formatter="rustfmt"', kind = 12, detail = "Rustfmt Code Formatter", insertText = 'formatter="rustfmt"' },
		{ label = 'formatter="stylua"', kind = 12, detail = "StyLua Code Formatter", insertText = 'formatter="stylua"' },
		{ label = 'formatter="prettier"', kind = 12, detail = "Prettier Code Formatter", insertText = 'formatter="prettier"' },
		{ label = 'formatter="black"', kind = 12, detail = "Black Python Formatter", insertText = 'formatter="black"' },
		{ label = 'formatter="gofumpt"', kind = 12, detail = "Gofumpt Go Formatter", insertText = 'formatter="gofumpt"' },
	}

	-- Merge dynamic Mason package status items
	local mason_items = M.get_mason_completions()
	for _, m_item in ipairs(mason_items) do
		table.insert(items, m_item)
	end

	if flavor == "luelte" then
		table.insert(items, {
			label = "$state",
			kind = 6,
			detail = "Svelte 5 Reactive State Rune",
			insertText = 'local ${1:val} = $state(${2:initial})',
			documentation = {
				kind = "markdown",
				value = "### `$state(initial_val)`\nCreates a reactive Svelte 5 state rune.\n\n**Parameters:**\n- `initial_val`: Initial value or factory function\n\n```lua\nlocal count = $state(0)\ncount.val = count.val + 1 -- Automatically triggers UI re-render\n```",
			},
		})
		table.insert(items, {
			label = "$derived",
			kind = 6,
			detail = "Svelte 5 Derived Computation Rune",
			insertText = 'local ${1:val} = $derived(${2:expr})',
			documentation = {
				kind = "markdown",
				value = "### `$derived(fn)`\nCreates a computed/derived Svelte 5 state rune.\n\n```lua\nlocal doubleCount = $derived(function() return count.val * 2 end)\n```",
			},
		})
		table.insert(items, {
			label = "$effect",
			kind = 6,
			detail = "Svelte 5 Side Effect Rune",
			insertText = '$effect(function()\n\t$0\nend)',
			documentation = {
				kind = "markdown",
				value = "### `$effect(fn)`\nRuns a reactive side-effect callback when dependencies change.",
			},
		})
		table.insert(items, {
			label = "$props",
			kind = 6,
			detail = "Svelte 5 Props Rune",
			insertText = 'local props = $props()',
			documentation = {
				kind = "markdown",
				value = "### `$props(schema?, strict?)`\nAccesses passed component props with optional type validation.",
			},
		})
	elseif flavor == "luact" then
		table.insert(items, {
			label = "useState",
			kind = 6,
			detail = "React State Hook",
			insertText = 'local ${1:state}, set_${1:state} = useState(${2:initial})',
			documentation = {
				kind = "markdown",
				value = "### `useState(initial_val)`\nReturns a state value and a setter function.\n\n```lua\nlocal count, setCount = useState(0)\nsetCount(function(c) return c + 1 end)\n```",
			},
		})
		table.insert(items, {
			label = "useEffect",
			kind = 6,
			detail = "React Effect Hook",
			insertText = 'useEffect(function()\n\t$0\nend, { ${1:deps} })',
			documentation = {
				kind = "markdown",
				value = "### `useEffect(effect_fn, deps)`\nRuns side-effect when dependency array items change.",
			},
		})
		table.insert(items, {
			label = "useMemo",
			kind = 6,
			detail = "React Memo Hook",
			insertText = 'local ${1:memoized} = useMemo(function()\n\treturn ${2:expr}\nend, { ${3:deps} })',
			documentation = {
				kind = "markdown",
				value = "### `useMemo(factory_fn, deps)`\nMemoizes a computed value until dependencies change.",
			},
		})
		table.insert(items, {
			label = "useRef",
			kind = 6,
			detail = "React Ref Hook",
			insertText = 'local ${1:ref} = useRef(${2:initial})',
			documentation = {
				kind = "markdown",
				value = "### `useRef(initial_val)`\nReturns a mutable ref object `{ current = initial_val }`.",
			},
		})
		table.insert(items, {
			label = "useCallback",
			kind = 6,
			detail = "React Callback Hook",
			insertText = 'local ${1:cb} = useCallback(function()\n\t$0\nend, { ${2:deps} })',
			documentation = {
				kind = "markdown",
				value = "### `useCallback(callback_fn, deps)`\nReturns a memoized callback function.",
			},
		})
	elseif flavor == "lue" then
		table.insert(items, {
			label = "ref",
			kind = 6,
			detail = "Vue 3 Ref Primitive",
			insertText = 'local ${1:val} = ref(${2:initial})',
			documentation = {
				kind = "markdown",
				value = "### `ref(initial_val)`\nVue 3 Composition API reactive reference.\n\n```lua\nlocal count = ref(0)\ncount.val = count.val + 1\n```",
			},
		})
		table.insert(items, {
			label = "reactive",
			kind = 6,
			detail = "Vue 3 Reactive Object",
			insertText = 'local ${1:state} = reactive({ ${2:key} = ${3:val} })',
			documentation = {
				kind = "markdown",
				value = "### `reactive(initial_tbl)`\nVue 3 Composition API reactive object.",
			},
		})
		table.insert(items, {
			label = "computed",
			kind = 6,
			detail = "Vue 3 Computed Property",
			insertText = 'local ${1:val} = computed(function() return ${2:expr} end)',
			documentation = {
				kind = "markdown",
				value = "### `computed(fn)`\nVue 3 Composition API computed value.",
			},
		})
		table.insert(items, {
			label = "watch",
			kind = 6,
			detail = "Vue 3 Reactive Watcher",
			insertText = 'watch(${1:target}, function(new_val)\n\t$0\nend)',
			documentation = {
				kind = "markdown",
				value = "### `watch(target_ref, callback_fn)`\nWatches a ref or reactive state change.",
			},
		})
		table.insert(items, {
			label = "onMounted",
			kind = 6,
			detail = "Vue 3 Lifecycle Hook",
			insertText = 'onMounted(function()\n\t$0\nend)',
			documentation = {
				kind = "markdown",
				value = "### `onMounted(fn)`\nLifecycle hook executed when component window is mounted.",
			},
		})
	elseif flavor == "luex" then
		table.insert(items, {
			label = "luex.signal",
			kind = 6,
			detail = "Native Neovim Signal",
			insertText = 'local ${1:sig} = luex.signal(${2:initial})',
			documentation = {
				kind = "markdown",
				value = "### `luex.signal(initial_val)`\nCreates a native reactive signal for Neovim Table DSL components.",
			},
		})
		table.insert(items, {
			label = "luex.component",
			kind = 6,
			detail = "Native Neovim Component DSL",
			insertText = 'return luex.component(function(props)\n\t$0\nend)',
			documentation = {
				kind = "markdown",
				value = "### `luex.component(spec)`\nDefines a Native Neovim component with setup and view methods.",
			},
		})
		table.insert(items, {
			label = "luex.import",
			kind = 6,
			detail = "Native Component Import",
			insertText = 'local ${1:Comp} = luex.import("${2:path}")',
			documentation = {
				kind = "markdown",
				value = "### `luex.import(path)`\nImports a Luex component module.",
			},
		})
	end

	return items
end

--- Configures luex_ls language server registration in Neovim
function M.setup()
	local ok_configs, configs = pcall(require, "lspconfig.configs")
	if not ok_configs or not configs then return end

	if not configs.luex_ls then
		configs.luex_ls = {
			default_config = {
				name = "luex_ls",
				filetypes = { "luelte", "luact", "lue", "luex" },
				root_dir = function(bufnr)
					local ok_l, lspconfig = pcall(require, "lspconfig")
					if ok_l and lspconfig.util then
						return lspconfig.util.root_pattern("init.lua", "app.luelte", ".git")(bufnr)
					end
					return vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr or 0))
				end,
				single_file_support = true,
			},
		}
	end
end

return M

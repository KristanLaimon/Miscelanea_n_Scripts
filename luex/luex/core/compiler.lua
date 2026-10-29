--[[
  Module Name: luex.core.compiler
  Description: Luex Ahead-Of-Time (AOT) transpiler engine (Luexc) for Single File Components (.luelte, .luact, .lue, .luex)
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]
local M = {}

--- Converts CamelCase component name to snake_case (e.g. GitDashboard -> git_dashboard)
local function camel_to_snake(str)
	local s = str:gsub("(%u+)(%u%l)", "%1_%2"):gsub("(%l)(%u)", "%1_%2"):lower()
	return s
end

--- Parses attributes of an HTML-like tag into simple string key-values
local function parse_attributes(str)
	local attrs = {}
	if not str then return attrs end
	for k, v in str:gmatch("([%w_%-:]+)%s*=%s*{([^}]+)}") do
		attrs[k] = v
	end
	for k, v in str:gmatch('([%w_%-:]+)%s*=%s*"([^"]*)"') do
		if not attrs[k] then attrs[k] = v end
	end
	for k, v in str:gmatch("([%w_%-:]+)%s*=%s*'([^']*)'") do
		if not attrs[k] then attrs[k] = v end
	end
	return attrs
end

--- Parses attributes with expression metadata (for component props)
local function parse_attributes_detail(str)
	local attrs = {}
	if not str then return attrs end
	for k, v in str:gmatch("([%w_%-:]+)%s*=%s*{([^}]+)}") do
		attrs[k] = { val = v, is_expr = true }
	end
	for k, v in str:gmatch('([%w_%-:]+)%s*=%s*"([^"]*)"') do
		if not attrs[k] then attrs[k] = { val = v, is_expr = false } end
	end
	for k, v in str:gmatch("([%w_%-:]+)%s*=%s*'([^']*)'") do
		if not attrs[k] then attrs[k] = { val = v, is_expr = false } end
	end
	return attrs
end

--- Extracts all <pack ... /> declarations from source code
local function extract_packs(source)
	local packs = {}
	for pack_str in source:gmatch("<pack%s+(.-)%s*/?>") do
		local attrs = parse_attributes(pack_str)
		if attrs.lang then
			table.insert(packs, attrs)
		end
	end
	return packs
end

--- Extracts all component import declarations from source code
--- Supports JS/TS ESM style: import ReactCounter from "components.react_counter"
local function extract_imports(source)
	local imports = {}
	local seen = {}

	for name, from in source:gmatch("import%s+([%w_]+)%s+from%s+[\"']([^\"']+)[\"']") do
		if not seen[name] then
			seen[name] = true
			table.insert(imports, { name = name, from = from })
		end
	end

	for name, from in source:gmatch("import%s*{%s*([%w_]+)%s*}%s+from%s+[\"']([^\"']+)[\"']") do
		if not seen[name] then
			seen[name] = true
			table.insert(imports, { name = name, from = from })
		end
	end

	for name, from in source:gmatch("local%s+([%w_]+)%s*=%s*require%s*%(%s*[\"']([^\"']+)[\"']%s*%)") do
		if name:match("^[A-Z]") and from ~= "luex" and not seen[name] then
			seen[name] = true
			table.insert(imports, { name = name, from = from })
		end
	end

	for import_str in source:gmatch("<[iI]mport%s+(.-)%s*/?>") do
		local attrs = parse_attributes(import_str)
		local name = attrs.name or attrs["as"]
		local from = attrs.from or (attrs.src and attrs.src:gsub("/", "."))
		if name and from and not seen[name] then
			seen[name] = true
			table.insert(imports, { name = name, from = from })
		end
	end

	return imports
end

--- Extracts metadata attributes from <script ...> tag OR React component static properties
local function extract_script_meta(source)
	local script_attr_str = source:match("<script%s+(.-)>\r?\n") or source:match("<script%s+(.-)>") or ""
	local attrs = parse_attributes(script_attr_str)

	local meta = {
		lazy = attrs.lazy == "true" or attrs.lazy == nil,
		cmd = attrs.cmd,
		strict = attrs.strict == "true" or attrs.strict == "strict" or attrs.strict == true or script_attr_str:find("strict") ~= nil,
		keys = {},
		events = {},
	}

	if attrs.lazy == "false" then
		meta.lazy = false
	end

	-- Extract React-style static property assignments (e.g. Component.cmd = "...", Component.keys = { ... }, Component.config = { ... })
	local react_cmd = source:match("[%w_]+%.cmd%s*=%s*[\"']([^\"']+)[\"']") or source:match("[%w_]+%.config%s*=%s*{.-cmd%s*=%s*[\"']([^\"']+)[\"']")
	if react_cmd then
		meta.cmd = react_cmd
	end

	local react_keys_str = source:match("[%w_]+%.keys%s*=%s*({.-})") or source:match("[%w_]+%.config%s*=%s*{.-keys%s*=%s*({.-})")
	if react_keys_str then
		for key in react_keys_str:gmatch('["\']([^"\']+)["\']') do
			table.insert(meta.keys, key)
		end
	end

	local react_lazy = source:match("[%w_]+%.lazy%s*=%s*(%a+)") or source:match("[%w_]+%.config%s*=%s*{.-lazy%s*=%s*(%a+)")
	if react_lazy == "false" then
		meta.lazy = false
	elseif react_lazy == "true" then
		meta.lazy = true
	end

	if attrs.keys then
		for key in attrs.keys:gmatch('["\']([^"\']+)["\']') do
			table.insert(meta.keys, key)
		end
		if #meta.keys == 0 and attrs.keys ~= "" then
			table.insert(meta.keys, attrs.keys)
		end
	end

	if attrs.events then
		for ev in attrs.events:gmatch('["\']([^"\']+)["\']') do
			table.insert(meta.events, ev)
		end
		if #meta.events == 0 and attrs.events ~= "" then
			table.insert(meta.events, attrs.events)
		end
	end

	return meta
end

--- Generates Lua code for manifest.lua from collected language pack & component declarations
function M.compile_manifest(all_packs, all_components)
	local lines = {
		"-- [Generated by Luelte Compiler - manifest.lua]",
		"local manifest = {",
		"  packs = {},",
		"  components = {},",
		"}",
		"",
	}

	for _, p in ipairs(all_packs or {}) do
		local lang = p.lang
		table.insert(lines, string.format('manifest.packs["%s"] = {', lang))
		if p.lsp then table.insert(lines, string.format('  lsp = "%s",', p.lsp)) end
		if p.formatter then table.insert(lines, string.format('  formatter = "%s",', p.formatter)) end
		if p.linter then table.insert(lines, string.format('  linter = "%s",', p.linter)) end
		if p.treesitter then table.insert(lines, string.format('  treesitter = "%s",', p.treesitter)) end
		table.insert(lines, "}")
	end

	for name, comp in pairs(all_components or {}) do
		table.insert(lines, string.format('manifest.components["%s"] = {', name))
		table.insert(lines, string.format('  module = "%s",', comp.module))
		table.insert(lines, string.format('  lazy = %s,', tostring(comp.lazy)))
		if comp.cmd then
			table.insert(lines, string.format('  cmd = "%s",', comp.cmd))
		end
		if comp.keys and #comp.keys > 0 then
			local keys_str = {}
			for _, k in ipairs(comp.keys) do
				table.insert(keys_str, string.format('"%s"', k))
			end
			table.insert(lines, string.format('  keys = { %s },', table.concat(keys_str, ", ")))
		end
		if comp.events and #comp.events > 0 then
			local ev_str = {}
			for _, e in ipairs(comp.events) do
				table.insert(ev_str, string.format('"%s"', e))
			end
			table.insert(lines, string.format('  events = { %s },', table.concat(ev_str, ", ")))
		end
		table.insert(lines, "}")
	end

	table.insert(lines, "")
	table.insert(lines, "return manifest")
	return table.concat(lines, "\n")
end

--- Parses CSS <style> blocks from component source into scoped Neovim highlight group definitions
local function parse_style_rules(source, comp_name)
	comp_name = comp_name or "SFC"
	local style_content = source:match("<style.->\r?\n(.-)</style>") or source:match("<style>(.-)</style>")
	local rules = {}
	if not style_content or vim.trim(style_content) == "" then return rules end

	for class_name, body in style_content:gmatch("%.([%w_%-]+)%s*{(.-)}") do
		local opts = {}
		for line in body:gmatch("[^\r\n;]+") do
			local k, v = line:match("^%s*([%w_%-]+)%s*[:=]%s*(.-)%s*$")
			if k and v then
				v = v:gsub("^['\"]", ""):gsub("['\"]$", ""):gsub(",$", "")
				if v == "true" then v = true elseif v == "false" then v = false end
				opts[k] = v
			end
		end
		rules[class_name] = {
			scoped_hl = string.format("Luex_%s_%s", comp_name, class_name),
			opts = opts,
		}
	end
	return rules
end

--- Compiles a visual UI template (Window, Text, control flow, event bindings, component imports)
local function compile_template(template_str, script_content, imports, is_strict, comp_name, style_rules)
	style_rules = style_rules or {}
	local win_attr_str = template_str:match("<Window%s*(.-)>") or template_str:match("<main%s*(.-)>") or template_str:match("<section%s*(.-)>")
	local has_window = win_attr_str ~= nil
	win_attr_str = win_attr_str or ""
	local win_attrs = parse_attributes(win_attr_str)

	local width = win_attrs.width and (win_attrs.width:match("%%") and string.format("'%s'", win_attrs.width) or win_attrs.width) or "'60%'"
	local height = win_attrs.height and (win_attrs.height:match("%%") and string.format("'%s'", win_attrs.height) or win_attrs.height) or "'50%'"
	local border = win_attrs.border and string.format("'%s'", win_attrs.border) or "'rounded'"
	local mode = win_attrs.mode and string.format("'%s'", win_attrs.mode) or "'normal'"

	local keymaps = {}
	for k, v in pairs(win_attrs) do
		local key_name = k:match("^on:key:(.+)$")
		if key_name then
			table.insert(keymaps, string.format('{ key = "%s", action = %s }', key_name, v))
		elseif k == "on:select" then
			table.insert(keymaps, string.format('{ key = "<CR>", action = %s }', v))
		end
	end

	local output = {
		"local luex = require('luex')",
		"local luelte = luex",
		"local tostring, type, ipairs, pcall = tostring, type, ipairs, pcall",
		"local useState = luex.useState",
		"local useEffect = luex.useEffect",
		"local useMemo = luex.useMemo",
		"local useRef = luex.useRef",
		"local useCallback = luex.useCallback",
		"local ref = luex.ref",
		"local reactive = luex.reactive",
		"local computed = luex.computed",
		"local watch = luex.watch",
		"local onMounted = luex.onMounted",
		"local onUnmounted = luex.onUnmounted",
		"local PropTypes = luex.PropTypes",
		"local onMount = luex.onMount",
		"local onDestroy = luex.onDestroy",
		"local beforeMount = luex.beforeMount",
		"local M = {}",
		"",
	}

	for class_name, rule in pairs(style_rules or {}) do
		local props_tbl = {}
		for k, v in pairs(rule.opts) do
			if type(v) == "string" then
				table.insert(props_tbl, string.format('["%s"] = "%s"', k, v))
			else
				table.insert(props_tbl, string.format('["%s"] = %s', k, tostring(v)))
			end
		end
		table.insert(output, string.format('luex.define_style("%s", { %s })', rule.scoped_hl, table.concat(props_tbl, ", ")))
	end

	table.insert(output, "")
	table.insert(output, "function M.render(props)")
	table.insert(output, "  props = props or {}")
	table.insert(output, "  local _target = props._target or {")
	table.insert(output, "    props = props,")
	table.insert(output, "    request_rerender = function()")
	table.insert(output, "      if not props._buf or vim.api.nvim_buf_is_valid(props._buf) then")
	table.insert(output, "        M.render(props)")
	table.insert(output, "      end")
	table.insert(output, "    end")
	table.insert(output, "  }")
	table.insert(output, "  _target.props = props")
	table.insert(output, "  props._target = _target")
	table.insert(output, "  luex.set_render_target(_target)")
	table.insert(output, "  luex.begin_lifecycle()")
	table.insert(output, "  luex.begin_hook_pass(props)")
	table.insert(output, string.format("  if M.propTypes then luex.validate_props('Component', props, M.propTypes, %s) end", tostring(is_strict or false)))
	table.insert(output, "  -- [Script Logic]")

	-- Add explicit <import> declarations
	for _, imp in ipairs(imports or {}) do
		table.insert(output, string.format('  local %s = require("%s")', imp.name, imp.from))
	end

	if script_content and vim.trim(script_content) ~= "" then
		local processed_script = script_content
			:gsub("import%s+.-%s+from%s+[\"'].-[\"']", "")
			:gsub("local%s+([%w_]+)%s*=%s*%$state%s*%((.-)%)", 'local %1 = (props and props._state_%1) or luelte["$state"](%2); if props then props._state_%1 = %1 end')
			:gsub("local%s+([%w_]+)%s*=%s*ref%s*%((.-)%)", 'local %1 = (props and props._state_%1) or luex.ref(%2); if props then props._state_%1 = %1 end')
			:gsub("local%s+([%w_]+)%s*=%s*reactive%s*%((.-)%)", 'local %1 = (props and props._state_%1) or luex.reactive(%2); if props then props._state_%1 = %1 end')
			:gsub("([%w_]+)%.cmd%s*=", 'M.cmd =')
			:gsub("([%w_]+)%.keys%s*=", 'M.keys =')
			:gsub("([%w_]+)%.lazy%s*=", 'M.lazy =')
			:gsub("([%w_]+)%.propTypes%s*=", 'M.propTypes =')
			:gsub("([%w_]+)%.config%s*=", 'M.config =')
			:gsub("%$props%s*%((.-)%)", 'luelte["$props"](%1)')
			:gsub("%$state%s*%(", 'luelte["$state"](')
			:gsub("%$derived%s*%(", 'luelte["$derived"](')
			:gsub("%$effect%s*%(", 'luelte["$effect"](')

		for line in vim.trim(processed_script):gmatch("[^\r\n]+") do
			table.insert(output, "  " .. line)
		end
	end

	table.insert(output, "")
	table.insert(output, "  local lines = props._lines or {}")
	table.insert(output, "  local highlights = props._hl or {}")
	table.insert(output, "  local keymaps = props._km or {}")
	table.insert(output, "  props._lines, props._hl, props._km = lines, highlights, keymaps")
	table.insert(output, "  local l_cnt, h_cnt, k_cnt = 0, 0, 0")
	table.insert(output, "")
	table.insert(output, "  k_cnt = k_cnt + 1; keymaps[k_cnt] = { key = 'q', action = 'close' }")
	table.insert(output, "  k_cnt = k_cnt + 1; keymaps[k_cnt] = { key = '<Esc>', action = 'close' }")
	for _, km in ipairs(keymaps) do
		table.insert(output, "  k_cnt = k_cnt + 1; keymaps[k_cnt] = " .. km)
	end
	table.insert(output, "")

	-- Extract inner body of Window/main/section element
	local body = template_str
	if has_window then
		body = template_str:gsub("<Window.->", ""):gsub("</Window>", "")
		body = body:gsub("<main.->", ""):gsub("</main>", "")
		body = body:gsub("<section.->", ""):gsub("</section>", "")
	end

	for line in body:gmatch("[^\r\n]+") do
		local trimmed_line = vim.trim(line)
		if trimmed_line ~= "" then
			-- 1. Control flow {#if cond}
			local if_cond = trimmed_line:match("^{#if%s+(.-)}$")
			if if_cond then
				table.insert(output, string.format("  if %s then", if_cond))
			elseif trimmed_line:match("^{:else}$") then
				table.insert(output, "  else")
			elseif trimmed_line:match("^{/if}$") then
				table.insert(output, "  end")
			-- 2. Control flow {#each list as item, index}
			elseif trimmed_line:match("^{#each%s+(.-)%s+as%s+(.-)}$") then
				local expr, vars = trimmed_line:match("^{#each%s+(.-)%s+as%s+(.-)}$")
				local item_var, idx_var = vars:match("([^,%s]+)%s*,%s*([^,%s]+)")
				if not item_var then
					item_var = vars
					idx_var = "_i"
				end
				table.insert(output, string.format("  for %s, %s in ipairs(%s or {}) do", idx_var, item_var, expr))
			elseif trimmed_line:match("^{/each}$") then
				table.insert(output, "  end")
			-- 3. Divider <hr /> or <hr class="..." />
			elseif trimmed_line:match("^<hr%s*/?>") or trimmed_line:match("^<hr%s+.-/?>") then
				local raw_hl = trimmed_line:match('class="([^"]+)"') or trimmed_line:match('highlight="([^"]+)"') or "Comment"
				local hl = (style_rules[raw_hl] and style_rules[raw_hl].scoped_hl) or raw_hl
				table.insert(output, '    l_cnt = l_cnt + 1; lines[l_cnt] = "─────────────────────────────────────────────────"')
				table.insert(output, string.format('    h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1, col_start = 0, col_end = 49, hl_group = "%s" }', hl))
			-- 4. Blank line <br /> or <br>
			elseif trimmed_line:match("^<br%s*/?>") then
				table.insert(output, '    l_cnt = l_cnt + 1; lines[l_cnt] = ""')
			-- 5. Skip <import ... /> lines inside template body
			elseif trimmed_line:match("^<[iI]mport%s+") then
				-- Skip import tag inside template body
			-- 6. Standard HTML & UI elements (<Text>, <p>, <span>, <h1>, <h2>, <h3>, <div>, <code>, <li>, <label>) or Component tags
			elseif trimmed_line:match("^<([%a%d]+)") then
				local tag_name = trimmed_line:match("^<([%a%d]+)")
				local is_text_element = false
				local default_hl = "Normal"

				if tag_name == "Text" or tag_name == "p" or tag_name == "span" or tag_name == "div" or tag_name == "label" or tag_name == "li" then
					is_text_element = true
				elseif tag_name == "h1" or tag_name == "h2" or tag_name == "h3" then
					is_text_element = true
					default_hl = "Title"
				elseif tag_name == "code" then
					is_text_element = true
					default_hl = "Special"
				end

				if is_text_element then
					local raw_hl = trimmed_line:match('class="([^"]+)"') or trimmed_line:match("class='([^']+)'") or trimmed_line:match('highlight="([^"]+)"') or trimmed_line:match("highlight='([^']+)'") or default_hl
					local hl = (style_rules[raw_hl] and style_rules[raw_hl].scoped_hl) or raw_hl
					local text_inner = trimmed_line:match(string.format("<%s.->(.-)</%s>", tag_name, tag_name)) or trimmed_line:match("<%a+.->(.-)</%a+>") or ""
					local has_expr = text_inner:find("{") ~= nil

					if not has_expr then
						local len = #text_inner
						table.insert(output, string.format('    l_cnt = l_cnt + 1; lines[l_cnt] = "%s"', text_inner))
						table.insert(output, string.format('    h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1, col_start = 0, col_end = %d, hl_group = "%s" }', len, hl))
					else
						local formatted_text = text_inner:gsub("{(.-)}", '" .. tostring(%1 or "") .. "')
						table.insert(output, string.format('    local line_content = "%s"', formatted_text))
						table.insert(output, '    l_cnt = l_cnt + 1; lines[l_cnt] = line_content')
						table.insert(output, string.format('    h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1, col_start = 0, col_end = #line_content, hl_group = "%s" }', hl))
					end
				elseif tag_name:match("^[A-Z]") and tag_name ~= "Window" and tag_name ~= "Import" then
					local comp_name, comp_attr_str = trimmed_line:match("^<([A-Z]%w*)%s*(.-)%s*/?>")
					if comp_name then
						local detail_attrs = parse_attributes_detail(comp_attr_str)
						local props_list = { "_embedded = true" }
						for k, attr_obj in pairs(detail_attrs) do
							if attr_obj.is_expr then
								table.insert(props_list, string.format("%s = %s", k, attr_obj.val))
							else
								table.insert(props_list, string.format('%s = "%s"', k, attr_obj.val))
							end
						end
						local props_str = "{ " .. table.concat(props_list, ", ") .. " }"
						local module_subpath = camel_to_snake(comp_name)

						table.insert(output, string.format('    local _comp_%s = %s or (pcall(require, "components.%s") and require("components.%s") or nil)', comp_name, comp_name, module_subpath, module_subpath))
						table.insert(output, string.format('    if type(_comp_%s) == "table" and _comp_%s.render then', comp_name, comp_name))
						table.insert(output, string.format('      local _child_res = _comp_%s.render(%s)', comp_name, props_str))
						table.insert(output, '      if _child_res and _child_res.lines then')
						table.insert(output, '        local _child_cnt = #_child_res.lines')
						table.insert(output, '        for _, _l in ipairs(_child_res.lines) do')
						table.insert(output, '          l_cnt = l_cnt + 1; lines[l_cnt] = _l')
						table.insert(output, '        end')
						table.insert(output, '        for _, _hl in ipairs(_child_res.highlights or {}) do')
						table.insert(output, '          h_cnt = h_cnt + 1; highlights[h_cnt] = { line = (l_cnt - _child_cnt) + _hl.line, col_start = _hl.col_start, col_end = _hl.col_end, hl_group = _hl.hl_group }')
						table.insert(output, '        end')
						table.insert(output, '        for _, _km in ipairs(_child_res.keymaps or {}) do')
						table.insert(output, '          k_cnt = k_cnt + 1; keymaps[k_cnt] = _km')
						table.insert(output, '        end')
						table.insert(output, '      end')
						table.insert(output, '    end')
					end
				end
			end
		end
	end

	table.insert(output, "")
	table.insert(output, "  for i = l_cnt + 1, #lines do lines[i] = nil end")
	table.insert(output, "  for i = h_cnt + 1, #highlights do highlights[i] = nil end")
	table.insert(output, "  for i = k_cnt + 1, #keymaps do keymaps[i] = nil end")
	table.insert(output, "")

	if has_window then
		table.insert(output, "  if not props._embedded then")
		table.insert(output, string.format("    local res = luelte.create_window({ _buf = props._buf, _win = props._win, width = %s, height = %s, border = %s, mode = %s, lines = lines, highlights = highlights, keymaps = keymaps })", width, height, border, mode))
		table.insert(output, "    props._buf = res.buf")
		table.insert(output, "    props._win = res.win")
		table.insert(output, "    return res")
		table.insert(output, "  else")
		table.insert(output, "    return { lines = lines, highlights = highlights, keymaps = keymaps }")
		table.insert(output, "  end")
	else
		table.insert(output, "  return { lines = lines, highlights = highlights, keymaps = keymaps }")
	end

	table.insert(output, "end")
	table.insert(output, "")
	table.insert(output, "return M")

	return table.concat(output, "\n")
end

--- Paradigm Guard Security: Enforces strict framework paradigm rules on SFC source logic
local function validate_paradigm_security(source, file_path)
	if not file_path then return end

	local is_luelte = file_path:find("%.luelte$") or file_path:find("%.lte$")
	local is_luact = file_path:find("%.luact$") or file_path:find("%.lualt$") or file_path:find("%.lt$")
	local is_lue = file_path:find("%.lue$")

	-- Extract script logic section to inspect forbidden primitive calls
	local script_code = source:match("<script.->\r?\n(.-)</script>") or source:match("<script>(.-)</script>") or source
	local file_name = vim.fn.fnamemodify(file_path, ":t")

	-- 1. Svelte SFC (.luelte) Guard
	if is_luelte then
		local forbidden_hooks = { "useState", "useEffect", "useMemo", "useRef", "useCallback" }
		for _, hook in ipairs(forbidden_hooks) do
			if script_code:find("%f[%w_]" .. hook .. "%f[^%w_]") then
				error(string.format("[Luex Security Guard] Paradigm Violation in '%s': React Hook '%s()' is forbidden in Svelte (.luelte) components. Use Svelte 5 Runes ($state, $derived, $effect) instead.", file_name, hook))
			end
		end
		local forbidden_vue = { "ref%s*%(", "reactive%s*%(", "computed%s*%(" }
		for _, v_prim in ipairs(forbidden_vue) do
			if script_code:find(v_prim) then
				error(string.format("[Luex Security Guard] Paradigm Violation in '%s': Vue Composition API is forbidden in Svelte (.luelte) components. Use Svelte 5 Runes ($state, $derived) instead.", file_name))
			end
		end
	end

	-- 2. React SFC (.luact) Guard
	if is_luact then
		local forbidden_runes = { "state", "derived", "effect", "props" }
		for _, rune_name in ipairs(forbidden_runes) do
			if script_code:find("%$" .. rune_name .. "%f[^%w_]") then
				error(string.format("[Luex Security Guard] Paradigm Violation in '%s': Svelte Rune '$%s' is forbidden in React (.luact) components. Use React Hooks (useState, useMemo) instead.", file_name, rune_name))
			end
		end
	end

	-- 3. Vue SFC (.lue) Guard
	if is_lue then
		local forbidden_react = { "useState", "useEffect", "useMemo", "useRef" }
		for _, hook in ipairs(forbidden_react) do
			if script_code:find("%f[%w_]" .. hook .. "%f[^%w_]") then
				error(string.format("[Luex Security Guard] Paradigm Violation in '%s': React Hook '%s()' is forbidden in Vue (.lue) components. Use Vue Composition API (ref, computed) instead.", file_name, hook))
			end
		end
		local forbidden_runes = { "state", "derived", "effect" }
		for _, rune_name in ipairs(forbidden_runes) do
			if script_code:find("%$" .. rune_name .. "%f[^%w_]") then
				error(string.format("[Luex Security Guard] Paradigm Violation in '%s': Svelte Rune '$%s' is forbidden in Vue (.lue) components. Use Vue Composition API (ref, computed) instead.", file_name, rune_name))
			end
		end
	end
end

--- Compiles a .luelte or .luact Single File Component
---@param source string
---@param file_path string|nil
---@return string compiled_lua, table|nil packs, table|nil meta
function M.compile(source, file_path)
	-- Enforce strict paradigm security boundaries before compilation
	validate_paradigm_security(source, file_path)

	local is_luex = (file_path and file_path:match("%.luex$")) or source:find("luex%.component") ~= nil
	if is_luex then
		local meta = {
			cmd = source:match("cmd%s*=%s*[\"']([^\"']+)[\"']"),
			keys = {},
			lazy = source:match("lazy%s*=%s*(%a+)") ~= "false",
		}
		local keys_str = source:match("keys%s*=%s*({.-})")
		if keys_str then
			for key in keys_str:gmatch('["\']([^"\']+)["\']') do
				table.insert(meta.keys, key)
			end
		end
		local compiled_lua = string.format("-- [Generated by Luexc Compiler - Native .luex Component]\nlocal luex = require('luex')\n%s", source)
		return compiled_lua, nil, meta
	end

	local is_luact = (file_path and (file_path:match("%.luact$") or file_path:match("%.lualt$") or file_path:match("%.lt$")))
		or source:find("useState") ~= nil
		or source:find("useEffect") ~= nil
		or source:find("useMemo") ~= nil
		or source:find("useRef") ~= nil
		or source:find("useCallback") ~= nil
		or source:find("return%s+function") ~= nil
	local script_content = source:match("<script.->\r?\n(.-)</script>") or source:match("<script>(.-)</script>")
	local has_explicit_script = script_content ~= nil

	local template_source = source
	if has_explicit_script then
		template_source = source:gsub("<script.->\r?\n.-</script>", ""):gsub("<script>.-</script>", "")
	end
	template_source = template_source:gsub("<style.->\r?\n.-</style>", ""):gsub("<style>.-</style>", "")

	local is_lue = (file_path and file_path:match("%.lue$")) or source:find("<template>") ~= nil
	if is_lue then
		local vue_template = source:match("<template.->\r?\n(.-)</template>") or source:match("<template>(.-)</template>")
		if vue_template then
			template_source = vue_template
		end
	end

	if is_luact then
		local func_name = source:match("function%s+([%w_]+)%s*%(")
		local jsx_template = template_source:match("return%s*%((%s*<%w+.-)%s*%)%s*\r?\n?end")
			or template_source:match("return%s*%((%s*<%w+.-)%s*%)")
			or template_source:match("return%s*(<%w+.-)%s*\r?\n?end")

		if jsx_template then
			local script_prefix = template_source:match("^(.-)%s*return%s*%(") or template_source:match("^(.-)%s*return%s*<") or ""
			local meta_code = template_source:match("%)\r?\n?end\r?\n?(.-)$")
				or template_source:match("end\r?\n?(%s*[%w_]+%.[%w_]+%s*=.-)$") or ""
			meta_code = meta_code:gsub("%s*return%s+[%w_]+%s*$", "")

			-- Unwrap React function wrapper: function ComponentName(props) ... end
			local script_without_jsx = script_prefix
			if func_name then
				script_without_jsx = script_without_jsx:gsub("function%s+" .. func_name .. "%s*%([^%)]*%)%s*\r?\n?", "")
			end

			local full_script = script_without_jsx .. "\n" .. meta_code
			local imports = extract_imports(source)
			local meta = extract_script_meta(source)
			local packs = extract_packs(source)
			return compile_template(jsx_template, full_script, imports, meta and meta.strict, comp_name, style_rules), (#packs > 0 and packs or nil), meta
		end
	end

	local packs = extract_packs(source)
	local imports = extract_imports(source)
	local meta = extract_script_meta(source)
	local template_clean = template_source:gsub("<pack%s+.-%s*/?>", ""):gsub("<[iI]mport%s+.-%s*/?>", "")
	local has_ui = template_clean:find("<%a+") ~= nil

	if not has_ui then
		if #packs > 0 then
			local lines = {
				"-- [Generated by Luelte Compiler - Language Packs]",
				"local M = {}",
				"M.packs = {",
			}
			for _, p in ipairs(packs) do
				local pack_entry = {}
				for k, v in pairs(p) do
					table.insert(pack_entry, string.format('%s = "%s"', k, v))
				end
				table.insert(lines, string.format("  { %s },", table.concat(pack_entry, ", ")))
			end
			table.insert(lines, "}")
			table.insert(lines, "return M")
			return table.concat(lines, "\n"), packs, meta
		end

		local clean_code = has_explicit_script and script_content or source
		return string.format("-- [Generated by Luelte Compiler - Pure Logic]\n%s", vim.trim(clean_code)), nil, meta
	end

	return compile_template(template_source, script_content, imports, meta and meta.strict, comp_name, style_rules), (#packs > 0 and packs or nil), meta
end

return M


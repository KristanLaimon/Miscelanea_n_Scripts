--[[
  Module Name: luex.core.runtime
  Description: Luex UI runtime engine providing reactive state, hooks, composition API and floating window management
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]
local M = {}

local ns_id = vim.api.nvim_create_namespace("luelte_ui")

--- Parses a dimension value which can be a fixed number (e.g. 80) or a percentage string (e.g. "80%")
---@param val number|string|nil
---@param total number
---@param default number
---@return number
local function resolve_dimension(val, total, default)
	if type(val) == "number" then
		return math.floor(val)
	elseif type(val) == "string" then
		local pct = val:match("^(%d+)%%$")
		if pct then
			return math.floor(total * (tonumber(pct) / 100))
		end
		local num = tonumber(val)
		if num then
			return math.floor(num)
		end
	end
	return default
end

local current_hooks = { before = {}, mount = {}, destroy = {} }

--- Resets current lifecycle hooks collector
function M.begin_lifecycle()
	current_hooks = { before = {}, mount = {}, destroy = {} }
end

--- Registers a callback to run before window creation
function M.beforeMount(fn)
	if type(fn) == "function" then
		table.insert(current_hooks.before, fn)
	end
end

--- Registers a callback to run after window creation (on mount)
function M.onMount(fn)
	if type(fn) == "function" then
		table.insert(current_hooks.mount, fn)
	end
end

--- Registers a callback to run on window destruction (on destroy)
function M.onDestroy(fn)
	if type(fn) == "function" then
		table.insert(current_hooks.destroy, fn)
	end
end

--- Defines or updates a scoped Neovim highlight group for SFC component styles
---@param hl_name string
---@param hl_opts table
function M.define_style(hl_name, hl_opts)
	if not hl_name or not hl_opts then return end
	local opts = {}
	if hl_opts.color or hl_opts.fg then
		opts.fg = hl_opts.color or hl_opts.fg
	end
	if hl_opts["background-color"] or hl_opts.bg then
		opts.bg = hl_opts["background-color"] or hl_opts.bg
	end
	if hl_opts["font-weight"] == "bold" or hl_opts.bold then
		opts.bold = true
	end
	if hl_opts["font-style"] == "italic" or hl_opts.italic then
		opts.italic = true
	end
	if hl_opts["text-decoration"] == "underline" or hl_opts.underline then
		opts.underline = true
	end

	vim.api.nvim_set_hl(0, hl_name, opts)
end

M.PropTypes = {
	string = "string",
	number = "number",
	boolean = "boolean",
	bool = "boolean",
	func = "function",
	["function"] = "function",
	table = "table",
	array = "table",
	any = "any",
}

--- Validates component props against a type schema
---@param comp_name string
---@param props table
---@param schema table
---@param strict boolean|nil
function M.validate_props(comp_name, props, schema, strict)
	if not schema or type(schema) ~= "table" then return true end
	props = props or {}

	for prop_key, expected_type in pairs(schema) do
		local actual_val = props[prop_key]
		local actual_type = type(actual_val)

		local is_valid = false
		if expected_type == "any" then
			is_valid = true
		elseif actual_type == expected_type then
			is_valid = true
		elseif (expected_type == "boolean" or expected_type == "bool") and actual_type == "boolean" then
			is_valid = true
		end

		if not is_valid and (actual_val ~= nil or strict) then
			local msg = string.format(
				"[Luex Type Error] Component <%s /> prop '%s' expected type '%s', but received '%s' (%s)",
				comp_name or "Component",
				prop_key,
				tostring(expected_type),
				actual_type,
				tostring(actual_val)
			)
			if strict then
				error(msg, 2)
			else
				vim.notify(msg, vim.log.levels.WARN)
			end
		end
	end
	return true
end

--- Svelte 5 $props Rune with type validation
M["$props"] = function(schema, strict)
	local target_props = active_render_target and active_render_target.props or {}
	if schema and type(schema) == "table" then
		M.validate_props("SFC", target_props, schema, strict)
	end
	return target_props
end

--- Vue Composition API: ref() reactive primitive
function M.ref(initial_val)
	return M["$state"](initial_val)
end

--- Vue Composition API: reactive() primitive
function M.reactive(initial_tbl)
	return M["$state"](initial_tbl)
end

--- Vue Composition API: computed() primitive
function M.computed(fn)
	return M["$derived"](fn)
end

--- Vue Composition API: watch() primitive
function M.watch(target_ref, callback_fn)
	if target_ref and target_ref.subscribe then
		target_ref:subscribe(callback_fn)
	end
end

--- Vue Composition API lifecycle aliases
M.onMounted = M.onMount
M.onUnmounted = M.onDestroy

--- Native Luex Signal Primitive
function M.signal(initial_val)
	return M["$state"](initial_val)
end

--- Import helper for Luex components
function M.import(path)
	return require(path)
end

--- Native Luex Component Builder (Concept #4)
function M.component(spec)
	if type(spec) ~= "table" then return spec end

	local module_table = {
		cmd = spec.cmd,
		keys = spec.keys,
		lazy = spec.lazy,
		propTypes = spec.props or spec.propTypes,
	}

	function module_table.render(props)
		props = props or {}
		local comp_name = spec.name or "NativeComponent"

		-- Register scoped styles
		if spec.styles and type(spec.styles) == "table" then
			for class_name, hl_opts in pairs(spec.styles) do
				local scoped_hl = string.format("Luex_%s_%s", comp_name, class_name)
				M.define_style(scoped_hl, hl_opts)
			end
		end

		local _target = props._target or {
			props = props,
			request_rerender = function()
				if props._buf and vim.api.nvim_buf_is_valid(props._buf) then
					module_table.render(props)
				end
			end,
		}
		_target.props = props
		props._target = _target
		M.set_render_target(_target)
		M.begin_lifecycle()
		M.begin_hook_pass(props)

		if module_table.propTypes then
			M.validate_props(comp_name, props, module_table.propTypes, spec.strict)
		end

		-- Run setup(props) if defined
		local ctx = {}
		if type(spec.setup) == "function" then
			ctx = spec.setup(props) or {}
		end

		-- Evaluate view(ctx)
		if type(spec.view) == "function" then
			local v = spec.view(ctx) or {}
			local win_cfg = v.window or {}
			local lines_cfg = v.lines or {}
			local keymaps_cfg = v.keymaps or {}

			local lines = props._lines or {}
			local highlights = props._hl or {}
			local keymaps = props._km or {}
			props._lines, props._hl, props._km = lines, highlights, keymaps
			local l_cnt, h_cnt, k_cnt = 0, 0, 0

			k_cnt = k_cnt + 1; keymaps[k_cnt] = { key = "q", action = "close" }
			k_cnt = k_cnt + 1; keymaps[k_cnt] = { key = "<Esc>", action = "close" }

			for k, act in pairs(keymaps_cfg) do
				k_cnt = k_cnt + 1; keymaps[k_cnt] = { key = k, action = act }
			end

			for _, item in ipairs(lines_cfg) do
				if type(item) == "table" then
					if item.divider then
						local hl = item.divider
						l_cnt = l_cnt + 1; lines[l_cnt] = "─────────────────────────────────────────────────"
						h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1, col_start = 0, col_end = 49, hl_group = hl }
					elseif item.component then
						local child = item.component
						local child_mod = type(child) == "string" and require(child) or child
						if type(child_mod) == "table" and type(child_mod.render) == "function" then
							local child_res = child_mod.render({ _embedded = true })
							for _, c_line in ipairs(child_res.lines or {}) do
								l_cnt = l_cnt + 1; lines[l_cnt] = c_line
							end
							for _, c_hl in ipairs(child_res.highlights or {}) do
								h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1 + (c_hl.line or 0), col_start = c_hl.col_start, col_end = c_hl.col_end, hl_group = c_hl.hl_group }
							end
						end
					elseif item.text then
						local raw_class = item.class or item.hl or "Normal"
						local hl = (spec.styles and spec.styles[raw_class]) and string.format("Luex_%s_%s", comp_name, raw_class) or raw_class
						local txt = tostring(item.text)
						l_cnt = l_cnt + 1; lines[l_cnt] = txt
						h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1, col_start = 0, col_end = #txt, hl_group = hl }
					end
				elseif type(item) == "string" then
					l_cnt = l_cnt + 1; lines[l_cnt] = item
					h_cnt = h_cnt + 1; highlights[h_cnt] = { line = l_cnt - 1, col_start = 0, col_end = #item, hl_group = "Normal" }
				end
			end

			for i = l_cnt + 1, #lines do lines[i] = nil end
			for i = h_cnt + 1, #highlights do highlights[i] = nil end
			for i = k_cnt + 1, #keymaps do keymaps[i] = nil end

			if not props._embedded then
				local res = M.create_window({
					_buf = props._buf,
					_win = props._win,
					width = win_cfg.width or "60%",
					height = win_cfg.height or "50%",
					border = win_cfg.border or "rounded",
					lines = lines,
					highlights = highlights,
					keymaps = keymaps,
				})
				props._buf = res.buf
				props._win = res.win
				return res
			else
				return { lines = lines, highlights = highlights, keymaps = keymaps }
			end
		end
	end

	return module_table
end

local active_render_target = nil

local current_hook_state = nil
local current_hook_index = 0

--- Begins a hook evaluation pass for a component instance
function M.begin_hook_pass(props)
	props._hooks = props._hooks or {}
	current_hook_state = props._hooks
	current_hook_index = 0
end

--- React-style useState Hook
function M.useState(initial_val)
	current_hook_index = current_hook_index + 1
	local idx = current_hook_index
	local state = current_hook_state or {}

	if state[idx] == nil then
		local val = type(initial_val) == "function" and initial_val() or initial_val
		state[idx] = val
	end

	local target = active_render_target
	local setter = function(new_val)
		local current_val = state[idx]
		local updated_val = type(new_val) == "function" and new_val(current_val) or new_val
		if current_val ~= updated_val then
			state[idx] = updated_val
			if target and target.request_rerender then
				target:request_rerender()
			end
		end
	end

	return state[idx], setter
end

--- React-style useEffect Hook
function M.useEffect(effect_fn, deps)
	current_hook_index = current_hook_index + 1
	local idx = current_hook_index
	local state = current_hook_state or {}

	local cell = state[idx] or {}
	state[idx] = cell

	local deps_changed = false
	if not cell.deps or not deps then
		deps_changed = true
	elseif #cell.deps ~= #deps then
		deps_changed = true
	else
		for i = 1, #deps do
			if cell.deps[i] ~= deps[i] then
				deps_changed = true
				break
			end
		end
	end

	if deps_changed then
		cell.deps = deps
		if cell.cleanup then
			pcall(cell.cleanup)
			cell.cleanup = nil
		end
		M.onMount(function()
			local cleanup = effect_fn()
			if type(cleanup) == "function" then
				cell.cleanup = cleanup
				M.onDestroy(cleanup)
			end
		end)
	end
end

--- React-style useMemo Hook
function M.useMemo(factory_fn, deps)
	current_hook_index = current_hook_index + 1
	local idx = current_hook_index
	local state = current_hook_state or {}

	local cell = state[idx] or {}
	state[idx] = cell

	local deps_changed = false
	if not cell.deps or not deps then
		deps_changed = true
	else
		for i = 1, #deps do
			if cell.deps[i] ~= deps[i] then
				deps_changed = true
				break
			end
		end
	end

	if deps_changed then
		cell.deps = deps
		cell.value = factory_fn()
	end

	return cell.value
end

--- React-style useCallback Hook
function M.useCallback(callback_fn, deps)
	return M.useMemo(function() return callback_fn end, deps)
end

--- React-style useRef Hook
function M.useRef(initial_val)
	current_hook_index = current_hook_index + 1
	local idx = current_hook_index
	local state = current_hook_state or {}

	if state[idx] == nil then
		state[idx] = { current = initial_val }
	end

	return state[idx]
end

--- Sets the current active component render target for reactive state binding
function M.set_render_target(target)
	active_render_target = target
end

--- Creates a Svelte-like reactive state rune ($state)
M["$state"] = function(initial_val)
	local storage = { value = initial_val }
	local subscribers = {}
	local target = active_render_target

	local state_obj = {}
	setmetatable(state_obj, {
		__index = function(_, k)
			if k == "value" or k == "val" or k == "get" then
				return storage.value
			end
			return storage[k]
		end,
		__newindex = function(_, k, v)
			if k == "value" or k == "val" then
				if storage.value ~= v then
					storage.value = v
					for _, sub in ipairs(subscribers) do
						pcall(sub, v)
					end
				end
			else
				storage[k] = v
			end
		end,
		__tostring = function()
			return tostring(storage.value)
		end,
		__concat = function(a, b)
			return tostring(a) .. tostring(b)
		end,
	})

	function state_obj:subscribe(fn)
		table.insert(subscribers, fn)
	end

	if target and target.request_rerender then
		state_obj:subscribe(function()
			target:request_rerender()
		end)
	end

	return state_obj
end

--- Creates a Svelte-like derived state rune ($derived)
M["$derived"] = function(fn)
	local derived_obj = {}
	setmetatable(derived_obj, {
		__index = function(_, k)
			if k == "value" or k == "val" or k == "get" then
				return fn()
			end
			return nil
		end,
		__tostring = function()
			return tostring(fn())
		end,
		__concat = function(a, b)
			return tostring(a) .. tostring(b)
		end,
	})
	return derived_obj
end

--- Creates a Svelte-like effect rune ($effect)
M["$effect"] = function(fn)
	pcall(fn)
end

--- Closes a target Neovim window
---@param win number
function M.close_window(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

local vim_motion_keys = {
	["i"] = true, ["I"] = true, ["a"] = true, ["A"] = true, ["o"] = true, ["O"] = true,
	["s"] = true, ["S"] = true, ["c"] = true, ["C"] = true, ["d"] = true, ["D"] = true,
	["x"] = true, ["X"] = true, ["r"] = true, ["R"] = true, ["v"] = true, ["V"] = true,
	["y"] = true, ["Y"] = true, ["p"] = true, ["P"] = true, ["u"] = true, ["U"] = true,
	["h"] = true, ["j"] = true, ["k"] = true, ["l"] = true, ["w"] = true, ["b"] = true, ["e"] = true,
	["0"] = true, ["$"] = true, ["^"] = true, ["g"] = true, ["G"] = true,
}

local function create_luex_event(key, win, buf, cursor_line, line_content)
	local event = {
		key = key,
		win = win,
		buf = buf,
		cursor_line = cursor_line,
		line_content = line_content,
		default_prevented = false,
		vim_motion_cancelled = false,
	}

	function event.isVimMotion()
		return vim_motion_keys[key] == true
	end

	function event.cancelVimMotion()
		event.vim_motion_cancelled = true
		if win and vim.api.nvim_win_is_valid(win) then
			pcall(vim.cmd, "stopinsert")
		end
	end

	function event.preventDefault()
		event.default_prevented = true
		event.cancelVimMotion()
	end

	return event
end

local default_blocked_keys = { "a", "A", "o", "O", "c", "C", "r", "R", "s", "S", "x", "X", "p", "P" }

local function apply_buffer_keymaps(buf, win, lines, keymaps, mode)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end

	local mapped_keys = {}
	if keymaps then
		for _, km in ipairs(keymaps) do
			local key = km.key
			local action = km.action
			mapped_keys[key] = true
			if action == "close" or type(action) == "function" then
				vim.keymap.set({ "n", "i", "v", "x" }, key, function()
					pcall(vim.cmd, "stopinsert")
					if action == "close" then
						M.close_window(win)
					elseif type(action) == "function" then
						local cursor = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_cursor(win) or { 1, 0 }
						local cursor_line = cursor[1]
						local line_content = lines[cursor_line] or ""
						local ev = create_luex_event(key, win, buf, cursor_line, line_content)
						action(ev)
					end
				end, { buffer = buf, silent = true, nowait = true, noremap = true })
			end
		end
	end

	-- For normal/lock UI windows, absorb unmapped editing keys to prevent unwanted Vim buffer mutation or mode switches
	if mode == "normal" or mode == "lock" then
		for _, blocked_key in ipairs(default_blocked_keys) do
			if not mapped_keys[blocked_key] then
				vim.keymap.set({ "n", "i", "v", "x" }, blocked_key, function()
					pcall(vim.cmd, "stopinsert")
				end, { buffer = buf, silent = true, nowait = true, noremap = true })
			end
		end
	end
end

--- Renders a centered floating window in Neovim
---@param opts { width: number|string, height: number|string, border: string, lines: string[], highlights: table[], keymaps: table[] }
function M.create_window(opts)
	local hooks = current_hooks
	M.begin_lifecycle()

	local mode = opts.mode or "normal"

	-- In-place reactive buffer update pass
	if opts._buf and vim.api.nvim_buf_is_valid(opts._buf) then
		local buf = opts._buf
		local lines = opts.lines or {}
		vim.bo[buf].modifiable = true
		vim.bo[buf].readonly = false
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
		for _, h in ipairs(opts.highlights or {}) do
			if h.line >= 0 and h.line < #lines then
				vim.api.nvim_buf_set_extmark(buf, ns_id, h.line, h.col_start or 0, {
					end_col = h.col_end or #lines[h.line + 1],
					hl_group = h.hl_group,
				})
			end
		end
		if mode == "normal" or mode == "lock" then
			vim.bo[buf].modifiable = false
			vim.bo[buf].readonly = true
		end
		apply_buffer_keymaps(buf, opts._win, lines, opts.keymaps, mode)
		return { buf = buf, win = opts._win, lines = lines, highlights = opts.highlights or {}, keymaps = opts.keymaps }
	end

	for _, fn in ipairs(hooks.before) do
		pcall(fn)
	end

	local total_cols = vim.o.columns
	local total_lines = vim.o.lines - vim.o.cmdheight

	local width = resolve_dimension(opts.width, total_cols, math.floor(total_cols * 0.6))
	local height = resolve_dimension(opts.height, total_lines, math.floor(total_lines * 0.5))
	local border = opts.border or "rounded"

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

	local lines = opts.lines or {}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Apply extmark highlights
	for _, h in ipairs(opts.highlights or {}) do
		if h.line >= 0 and h.line < #lines then
			vim.api.nvim_buf_set_extmark(buf, ns_id, h.line, h.col_start or 0, {
				end_col = h.col_end or #lines[h.line + 1],
				hl_group = h.hl_group,
			})
		end
	end

	if mode == "normal" or mode == "lock" then
		vim.bo[buf].modifiable = false
		vim.bo[buf].readonly = true

		-- Prevent entering Insert mode in normal UI windows
		vim.api.nvim_create_autocmd("InsertEnter", {
			buffer = buf,
			callback = function()
				pcall(vim.cmd, "stopinsert")
			end,
		})
	end

	local row = math.max(0, math.floor((total_lines - height) / 2))
	local col = math.max(0, math.floor((total_cols - width) / 2))

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = border,
		style = "minimal",
	})

	-- Execute onMount hooks
	for _, fn in ipairs(hooks.mount) do
		pcall(fn, { win = win, buf = buf, lines = lines })
	end

	-- Register onDestroy hooks on BufWipeout
	if #hooks.destroy > 0 then
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			once = true,
			callback = function()
				for _, fn in ipairs(hooks.destroy) do
					pcall(fn, { win = win, buf = buf })
				end
			end,
		})
	end

	-- Configure keybindings
	local keymaps = opts.keymaps or {
		{ key = "q", action = "close" },
		{ key = "<Esc>", action = "close" },
	}

	apply_buffer_keymaps(buf, win, lines, keymaps, mode)

	return { buf = buf, win = win, lines = lines, highlights = opts.highlights or {}, keymaps = keymaps }
end

return M

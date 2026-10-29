---@class LuexEvent
---@field key string Key string that triggered the event (e.g. "i", "d", "<CR>", "<Esc>")
---@field win number Neovim floating window handle
---@field buf number Neovim buffer handle
---@field cursor_line number 1-indexed line number under cursor when event fired
---@field line_content string Text content of the line under cursor when event fired
---@field default_prevented boolean Whether preventDefault() was called
---@field vim_motion_cancelled boolean Whether cancelVimMotion() was called
---@field isVimMotion fun(): boolean Returns true if key is a standard Vim motion/insert trigger (i, a, o, d, x, y, etc.)
---@field cancelVimMotion fun() Cancels Vim motion side-effects and forces stopinsert
---@field preventDefault fun() Prevents default action and calls cancelVimMotion()

---@class StateRune<T>: { value: T, val: T, get: T, set: fun(self: StateRune<T>, v: T), subscribe: fun(self: StateRune<T>, fn: fun(v: T)) }

---@class DerivedRune<T>: { value: T, val: T, get: T }

---@class RefObject<T>: { current: T }

---@class WindowResult
---@field buf number
---@field win number
---@field lines string[]
---@field highlights table[]
---@field keymaps table[]

---@class LuexRuntime
---@field testing table BDD/TDD testing framework (require("luex.testing"))
---@field PropTypes table<string, string> PropTypes schema validator types (string, number, boolean, func, table, any)
---@overload fun(): LuexRuntime
---@overload fun(initial_val: any): StateRune<any>
local runtime = require("runtime")
runtime.testing = require("luex.testing")

return runtime

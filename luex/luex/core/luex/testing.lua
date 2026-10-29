--[[
  Module Name: luex.testing
  Description: BDD/TDD testing framework engine and strongly-typed assertion library for Luex components
  Author: Kristan Laimon
  Year: 2026
  Copyright: MIT License
--]]

---@class LuexTesting
local M = {}

---@class LuexTestStats
---@field passed integer Count of passed test cases
---@field failed integer Count of failed test cases
---@field total integer Total count of executed test cases
M.stats = {
	passed = 0,
	failed = 0,
	total = 0,
}

---@alias LuaTypeName "nil" | "number" | "string" | "boolean" | "table" | "function" | "thread" | "userdata"

---@class LuexAssertion
---@field actual any Target value under assertion test
---@field to_equal fun(expected: any) Asserts that actual value strictly equals expected value
---@field to_be_true fun() Asserts that actual value is strictly true
---@field to_be_false fun() Asserts that actual value is strictly false
---@field to_be_nil fun() Asserts that actual value is nil
---@field to_be_truthy fun() Asserts that actual value is truthy (neither nil nor false)
---@field to_be_falsy fun() Asserts that actual value is falsy (nil or false)
---@field to_contain fun(substring_or_item: any) Asserts that actual array/string contains expected element/substring
---@field to_be_type fun(expected_type: LuaTypeName) Asserts that actual value is of a specific primitive Lua type
---@field to_be_greater_than fun(expected: number) Asserts that numerical actual value is greater than expected value
---@field to_be_less_than fun(expected: number) Asserts that numerical actual value is less than expected value

--- Wraps an actual value in a strongly typed assertion object supporting both dot and colon invocation syntax
---@param actual any Target value under assertion
---@return LuexAssertion
function M.expect(actual)
	local res = { actual = actual }

	--- Asserts that actual value strictly equals expected value
	---@param self_or_expected any
	---@param expected any|nil
	function res.to_equal(self_or_expected, expected)
		local exp = (expected ~= nil or self_or_expected == res) and expected or self_or_expected
		if actual ~= exp then
			error(string.format("Expected '%s', but got '%s'", tostring(exp), tostring(actual)), 2)
		end
	end

	--- Asserts that actual value is strictly true
	function res.to_be_true()
		if actual ~= true then
			error(string.format("Expected true, but got '%s'", tostring(actual)), 2)
		end
	end

	--- Asserts that actual value is strictly false
	function res.to_be_false()
		if actual ~= false then
			error(string.format("Expected false, but got '%s'", tostring(actual)), 2)
		end
	end

	--- Asserts that actual value is nil
	function res.to_be_nil()
		if actual ~= nil then
			error(string.format("Expected nil, but got '%s'", tostring(actual)), 2)
		end
	end

	--- Asserts that actual value is truthy (neither nil nor false)
	function res.to_be_truthy()
		if not actual then
			error(string.format("Expected truthy value, but got '%s'", tostring(actual)), 2)
		end
	end

	--- Asserts that actual value is falsy (nil or false)
	function res.to_be_falsy()
		if actual then
			error(string.format("Expected falsy value, but got '%s'", tostring(actual)), 2)
		end
	end

	--- Asserts that actual array/string contains expected element/substring
	---@param self_or_item any
	---@param item any|nil
	function res.to_contain(self_or_item, item)
		local target_item = (item ~= nil or self_or_item == res) and item or self_or_item
		if type(actual) == "table" then
			local found = false
			for _, v in ipairs(actual) do
				if v == target_item or tostring(v):find(tostring(target_item), 1, true) then
					found = true
					break
				end
			end
			if not found then
				error(string.format("Expected table to contain '%s'", tostring(target_item)), 2)
			end
		elseif type(actual) == "string" then
			if not actual:find(tostring(target_item), 1, true) then
				error(string.format("Expected string '%s' to contain '%s'", actual, tostring(target_item)), 2)
			end
		else
			error(string.format("to_contain requires string or table, got '%s'", type(actual)), 2)
		end
	end

	--- Asserts that actual value is of a specific primitive Lua type
	---@param self_or_type any
	---@param expected_type LuaTypeName|nil
	function res.to_be_type(self_or_type, expected_type)
		local exp_type = (expected_type ~= nil or self_or_type == res) and expected_type or self_or_type
		local valid_types = {
			["nil"] = true, ["number"] = true, ["string"] = true, ["boolean"] = true,
			["table"] = true, ["function"] = true, ["thread"] = true, ["userdata"] = true
		}
		if not valid_types[exp_type] then
			error(string.format("Invalid expected type '%s' passed to to_be_type()", tostring(exp_type)), 2)
		end

		local actual_type = type(actual)
		if actual_type ~= exp_type then
			error(string.format("Expected type '%s', but got '%s'", exp_type, actual_type), 2)
		end
	end

	--- Asserts that numerical actual value is greater than expected value
	---@param self_or_expected any
	---@param expected number|nil
	function res.to_be_greater_than(self_or_expected, expected)
		local exp = (expected ~= nil or self_or_expected == res) and expected or self_or_expected
		if type(actual) ~= "number" or type(exp) ~= "number" then
			error("to_be_greater_than requires both actual and expected to be numbers", 2)
		end
		if actual <= exp then
			error(string.format("Expected %s to be greater than %s", tostring(actual), tostring(exp)), 2)
		end
	end

	--- Asserts that numerical actual value is less than expected value
	---@param self_or_expected any
	---@param expected number|nil
	function res.to_be_less_than(self_or_expected, expected)
		local exp = (expected ~= nil or self_or_expected == res) and expected or self_or_expected
		if type(actual) ~= "number" or type(exp) ~= "number" then
			error("to_be_less_than requires both actual and expected to be numbers", 2)
		end
		if actual >= exp then
			error(string.format("Expected %s to be less than %s", tostring(actual), tostring(exp)), 2)
		end
	end

	return res
end

--- Defines a test suite block
---@param suite_name string Human-readable test suite title
---@param fn fun() Test suite callback function
function M.describe(suite_name, fn)
	print(string.format("\n📦 [Test Suite] %s", suite_name))
	print("--------------------------------------------------")
	fn()
end

--- Defines an individual test case
---@param test_name string Human-readable test case title
---@param fn fun() Test execution function
function M.it(test_name, fn)
	M.stats.total = M.stats.total + 1
	local ok, err = pcall(fn)
	if ok then
		M.stats.passed = M.stats.passed + 1
		print(string.format("  ✓ %s", test_name))
	else
		M.stats.failed = M.stats.failed + 1
		print(string.format("  ❌ %s", test_name))
		print(string.format("     Error: %s", tostring(err)))
	end
end

--- Alias for M.it
M.test = M.it

---@class LuexComponentTestResult
---@field raw table Raw rendered output table from component
---@field lines string[] Rendered text buffer lines
---@field highlights table[] Array of highlight definitions
---@field keymaps table[] Array of keymap definitions
---@field has_text fun(self: LuexComponentTestResult, text: string): boolean Returns true if text exists in lines
---@field has_highlight fun(self: LuexComponentTestResult, hl_group: string): boolean Returns true if highlight group exists

--- Programmatically renders a component module and returns assertion helper
---@param component_module string|table Module import string or loaded module table
---@param props table|nil Optional props to render component with
---@return LuexComponentTestResult
function M.render_component(component_module, props)
	local mod = type(component_module) == "string" and require(component_module) or component_module
	if type(mod) ~= "table" or type(mod.render) ~= "function" then
		error("Module does not export a valid render(props) function", 2)
	end
	props = props or {}
	props._embedded = true

	local result = mod.render(props)
	return {
		raw = result,
		lines = result.lines or {},
		highlights = result.highlights or {},
		keymaps = result.keymaps or {},
		has_text = function(self, text)
			for _, line in ipairs(self.lines) do
				if line:find(text, 1, true) then return true end
			end
			return false
		end,
		has_highlight = function(self, hl_group)
			for _, hl in ipairs(self.highlights) do
				if hl.hl_group and hl.hl_group:find(hl_group, 1, true) then return true end
			end
			return false
		end,
	}
end

--- Output test summary report
function M.summary()
	print("\n==================================================")
	print(string.format("📊 Test Results: Total: %d | Passed: %d | Failed: %d", M.stats.total, M.stats.passed, M.stats.failed))
	print("==================================================")
	if M.stats.failed > 0 then
		error("Test suite failed!", 2)
	end
end

return M

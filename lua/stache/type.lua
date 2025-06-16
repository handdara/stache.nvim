---@class M
local M = {}

---@class Some
---@field _val any

---@class None

---Creates a new Some
---@generic T
---@param x T
---@return Some
function M.Some(x)
    return { _val = x }
end

---Creates a new None
---@return None
function M.None()
    return {}
end

---@alias Option None | Some

---@generic T
---@generic S
---@param x Option
---@param onSome fun(S):T
---@param onNone fun():T
---@return T
---@diagnostic disable-next-line: unused-function, unused-local
function M.matchOption(x, onSome, onNone)
    if x._val then
        ---@cast x Some
        return onSome(x._val)
    else
        ---@cast x None
        return onNone()
    end
end

---@generic A, B
---@class Foldable<A>
---@field foldl fun(self:Foldable<`A`>, acc0: `B`, f:fun(acc:`B`, el:`A`):`B`):`B`

---@generic A, B
---@class Mappable<A>
---@field map fun(self:Mappable<`A`>, f:fun(el:`A`):`B`):Mappable<`B`>
---@field filter fun(self:Mappable<`A`>, p:fun(el:`A`):boolean):Mappable<`A`>

---@generic T
---@class Set<T>: Foldable, Mappable
---@field _elements table<`T`, boolean>
---@field new fun(self:Set, list:`T`?):Set
---@field insert fun(self:Set, element: `T`):Set
---@field has fun(self:Set, element: `T`):boolean
---@field remove fun(self:Set, element: `T`):Set
---@field empty fun(self:Set):boolean
---@operator add(Set): Set
---@operator sub(Set): Set
---@operator mul(Set): Set
local Set = {}

local Set_mt = {
    __index = Set,
    __add = function(self, rhs)
        for element, is_in_rhs in pairs(rhs._elements) do
            if is_in_rhs then
                self:insert(element)
            end
        end
        return self
    end,
    __sub = function(self, rhs)
        for element, is_in_rhs in pairs(rhs._elements) do
            if is_in_rhs then
                self:remove(element)
            end
        end
        return self
    end,
    __mul = function(self, rhs)
        for element, el_is_in_lhs in pairs(self._elements) do
            if not (el_is_in_lhs and rhs:has(element)) then
                self:remove(element)
            end
        end
        return self
    end,
}

setmetatable(Set, Set_mt)

---@return Set
function Set:new(elements)
    local inst = setmetatable({ _elements = {} }, getmetatable(self))
    if elements then
        assert(type(elements) == "table")
        for _, el in pairs(elements) do
            inst:insert(el)
        end
    end
    return inst
end

function Set:insert(x)
    self._elements[x] = true
    return self
end

function Set:has(x)
    return self._elements[x]
end

function Set:remove(x)
    self._elements[x] = false
    return self
end

function Set:empty()
    for _, inSet in pairs(self._elements) do
        if inSet then
            return false
        end
    end
    return true
end

---left fold
---@generic A
---@generic B
---@param acc0 A
---@param f fun(acc:A, x:B):A
---@return A
function Set:foldl(acc0, f)
    local acc = acc0
    for element, is_in_self in pairs(self._elements) do
        if is_in_self then
            acc = f(acc, element)
        end
    end
    return acc
end

function Set:filter(p)
    local next = Set:new()
    for element, is_in_self in pairs(self._elements) do
        if is_in_self and p(element) then
            next:insert(element)
        end
    end
    return next
end

function Set:map(f)
    local next = Set:new()
    for element, is_in_self in pairs(self._elements) do
        if is_in_self then
            next:insert(f(element))
        end
    end
    return next
end

---@class Map: Foldable, Mappable
---@field _elements table<any, any>
---@field new fun(self:Map, list:`T`?):Map
local Map = {}
setmetatable(Map, {
    __index = function(self, key)
        if rawget(Map, key) then
            return Map[key]
        else
            return self._elements[key]
        end
    end,
    __newindex = function(t, k, v)
        assert(not rawget(Map, k))
        rawget(t, '_elements')[k] = v
    end
})

rawset(Map, 'new', function(self)
    ---@type Map
    local inst = setmetatable({ _elements = {} }, getmetatable(self))
    return inst
end)

rawset(Map, 'map', function(self, f)
    local next = Map:new()
    for key, value in pairs(self._elements) do
        next[key] = f(value)
    end
    return next
end)

rawset(Map, 'filter', function(self, p)
    local next = Map:new()
    for key, val in pairs(self._elements) do
        if p(val) then
            next[key] = val
        end
    end
    return next
end)

rawset(Map, 'foldl', function(self, acc0, f)
    local acc = acc0
    for _, v in pairs(self._elements) do
        acc = f(acc, v)
    end
    return acc
end)

---@diagnostic disable-next-line: unused-local, unused-function
function M.wrap0(...) return ... end
function M.wrap1(...) return { ... } end
---@param f function
---@param g function?
---@return function
local function compose(f, g)
    assert(type(f) == "function")
    if g then
        assert(type(g) == "function")
        return function(...)
            return f(g(...))
        end
    else
        return function(g_)
            return compose(f, g_)
        end
    end
end
function M.wrapmap(f)
    return compose(M.wrap1, compose(f, unpack))
end

-- local function runtests(tests, pr)
--     local idx = 1
--     for name, test in pairs(tests) do
--         local prefix = 'test #' .. tostring(idx) .. ':' .. name .. ':'
--         pr(prefix .. 'running...')
--         test(prefix)
--         pr(prefix .. 'passed!')
--         idx = idx + 1
--     end
-- end
-- local test_out = {}
-- local tests = {
--     test_set_init = function(prefix)
--         local x = Set:new()
--         assert(type(x) == 'table', prefix .. ":Set builtin type should be a table!")
--     end,
--     test_set_insert = function(prefix)
--         local x = Set:new()
--         assert(x.insert, prefix .. ":Set should have an insert method!")
--         x = x:insert(0)
--         assert(x._elements[0], prefix .. ":Set should contain `0`! set = " .. vim.inspect(x))
--     end,
--     test_set_empty = function(prefix)
--         local x = Set:new()
--         assert(x.empty, prefix .. ":Set should have a has method!")
--         assert(x:empty(), 'x = ' .. vim.inspect(x))
--         x = x:insert(0)
--         assert(not x:empty())
--     end,
--     test_set_has = function(prefix)
--         local x = Set:new()
--         assert(x.has, prefix .. ":Set should have a has method!")
--         x = x:insert(0)
--         assert(x:has(0), prefix .. ":Set should contain `0`! set = " .. vim.inspect(x))
--         assert(not x:has(1), prefix .. ":Set should not contain `1`! set = " .. vim.inspect(x))
--     end,
--     test_set_remove = function(prefix)
--         local x = Set:new()
--         assert(x.remove, prefix .. ":Set should have a has method!")
--         x = x:insert(0)
--         assert(x:has(0), prefix .. ":Set should contain `0`! set = " .. vim.inspect(x))
--         x = x:remove(0)
--         assert(not x:has(0), prefix .. ":Set should not contain `0`! set = " .. vim.inspect(x))
--     end,
--     test_set_addition = function(prefix)
--         local x = Set:new()
--         local y = Set:new()
--         assert(getmetatable(x).__add, prefix .. ":Set should have an __add metamethod!")
--         x = x:insert(0)
--         x = x:insert(1)
--         y = y:insert(1)
--         y = y:insert(2)
--         local z = x + y
--         assert(z:has(0) and z:has(1) and z:has(2),
--             prefix .. ":Set should not contain `1`, `2` and `3`! set = " .. vim.inspect(z))
--     end,
--     test_set_difference = function(prefix)
--         local x = Set:new()
--         local y = Set:new()
--         assert(getmetatable(x).__sub, prefix .. ":Set should have an __sub metamethod!")
--         x = x:insert(0)
--         x = x:insert(1)
--         y = y:insert(1)
--         y = y:insert(2)
--         local z = x - y
--         assert(z:has(0) and (not z:has(1)) and (not z:has(2)),
--             prefix .. ":Set should contain only `0`! z = " .. vim.inspect(z))
--     end,
--     test_set_intersect = function(prefix)
--         local x = Set:new()
--         local y = Set:new()
--         assert(getmetatable(x).__mul, prefix .. ":Set should have an __mul metamethod!")
--         x = x:insert(0)
--         x = x:insert(1)
--         x = x:insert(42)
--         y = y:insert(1)
--         y = y:insert(42)
--         local z = x * y
--         assert(z:has(1) and z:has(42) and (not z:has(0)) and (not z:has(2)),
--             prefix .. ":Set should contain only `1`! z = " .. vim.inspect(z))
--     end,
--     test_set_fold = function(prefix)
--         local x = Set:new()
--         assert(x.foldl, prefix .. ":Set should have an foldl method!")
--         x = x:insert(0)
--         x = x:insert(1)
--         x = x:insert(42)
--         local res = x:foldl(-1, function(acc, el) return acc + el end)
--         assert(res == 42, prefix .. ":result of Set fold should be 42! res = " .. vim.inspect(res))
--     end,
--     test_list2set_init = function(prefix)
--         local x = Set:new({ 'alpha', 'beta', 'kappa' })
--         assert(x:has('alpha') and x:has('beta') and x:has('kappa'),
--             prefix .. ":Set should contain alpha, beta, and kappa! x = " .. vim.inspect(x))
--     end,
--     test_set_mappable = function(prefix)
--         local x = Set:new()
--         assert(x.filter, prefix .. ":Set should have an filter method!")
--         assert(x.map, prefix .. ":Set should have an map method!")
--         for i = 1, 20 do
--             x:insert(tostring(i))
--         end
--         local function is_even(el)
--             local el_ = tonumber(el)
--             return (el_ % 2) == 0
--         end
--         local y = x:filter(is_even)
--         local res = x:map(tonumber):foldl(0, function(a, b) return a + b end) == 210
--         assert(y:foldl(0, function(a, b) return a + b end) == 110)
--         assert(res, prefix .. ":result of Set fold should be 42! res = " .. vim.inspect(res))
--     end,
--     test_map_new = function(prefix)
--         local m = Map:new()
--         rawset(m, '_elements', { new = 'test', a_key = 'test' })
--         assert(m.new == Map.new, prefix .. 'accessing a Map method should work')
--         assert(m['a_key'] == 'test', prefix .. 'accessing a non-Map-method should give _elements access')
--     end,
--     test_map_newindex = function(prefix)
--         local m = Map:new()
--         m['test'] = 1
--         assert(m.test == 1, prefix .. 'should return the set number 1')
--     end,
--     test_map_mappable = function(prefix)
--         local n = Map:new()
--         n['a'] = 1
--         n['b'] = 'c'
--         n[17] = false
--         local m = n:map(tostring)
--         assert(m['a'] == '1', prefix .. "should be equal to '1', m = " .. vim.inspect(m))
--         assert(m['b'] == 'c', prefix .. "should be equal to 'c', m = " .. vim.inspect(m))
--         assert(m[17] == 'false', prefix .. "should be equal to 'false', m = " .. vim.inspect(m))
--         local l = n:filter(function(el)
--             return type(el) ~= "string"
--         end)
--         assert(l['a'], prefix .. "l['a'] should not exist, l = " .. vim.inspect(l))
--         assert(not l['b'], prefix .. "l['b'] should not exist, l = " .. vim.inspect(l))
--         assert(l[17] == false, prefix .. "l[17] should exist, l = " .. vim.inspect(l))
--     end,
--     test_map_foldable = function(prefix)
--         local m = Map:new()
--         for i = 1, 20 do
--             m[tostring(i)] = i
--         end
--         assert(m:foldl(0, function (a, b) return a + b end) == 210, prefix .. 'answer should equal 210')
--     end,
-- }
-- runtests(tests, function(msg)
--     table.insert(test_out, ('testing type.lua:' .. msg))
-- end)
-- for _, line in pairs(test_out) do
--     print(line)
-- end

M.Set = Set
M.Map = Map
M.compose = compose
return M

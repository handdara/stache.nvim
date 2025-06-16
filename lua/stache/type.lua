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

---@alias StacheID string
---@alias StacheField string
---@alias FilePath string

---@class FilterOp
---@field filt string?
---@field data string?
---@field field string?
---@field invert boolean?

---@class SetOp
---@field op string
---@field fromDirs string[]
---@field filter FilterOp

---@class GroupOp
---@field field StacheField
---@field sort ('asc'|'des')?
---@field split boolean

---@alias Group {groups:[ string, Group ], opts:table?} | { items:ItmDat[] }

---@class Query
---@field setOps SetOp[]
---@field grpOps GroupOp[]
---@field dispOp string

---@class StacheBlock
---@field range [number, number]
---@field lines string[]
---@field output string[]
---@field outReplaceRange [number, number]

M.Set = Set
M.Map = Map
M.compose = compose
return M

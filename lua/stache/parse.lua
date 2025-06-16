---@class M
local M = {}
local T = require 'stache.type'

---@generic A
---@alias PRes Option<{rem:string, val:A}>

---@generic A
---@class Parser
---@field runParser fun(s:string):PRes
local Parser = {}

local Parser_mt = {
    __index = Parser,
    __pow = function(self, rhs)
        ---@cast self Parser
        ---@cast rhs Parser
        local function combinedParse(s)
            return T.matchOption(self.runParser(s),
                T.Some,
                function() return T.matchOption(rhs.runParser(s), T.Some, T.None) end)
        end
        return setmetatable({ runParser = combinedParse }, getmetatable(Parser))
    end,
    __add = function(self, rhs)
        ---@cast self Parser
        ---@cast rhs Parser
        local function combinedParse(s)
            return T.matchOption(self.runParser(s), function(res_l)
                return rhs.runParser(res_l[1])
            end, T.None)
        end
        return setmetatable({ runParser = combinedParse }, getmetatable(Parser))
    end,
    __lt = function(self, rhs)
        return setmetatable({
            runParser = function(s)
                return T.matchOption(self.runParser(s), function(res_l)
                    ---@cast res_l PRes
                    return T.Some({ res_l[1], { rhs } })
                end, T.None)
            end
        }, getmetatable(Parser))
    end,
    __sub = function(self, rhs)
        ---@cast self Parser
        ---@cast rhs Parser
        local function combinedParse(s)
            return T.matchOption(self.runParser(s), function(res_l)
                return T.matchOption(rhs.runParser(res_l[1]), function(res_r)
                    return T.Some({ res_r[1], res_l[2] })
                end, T.None)
            end, T.None)
        end
        return setmetatable({ runParser = combinedParse }, getmetatable(Parser))
    end,
    __concat = function(self, rhs)
        ---@cast self Parser
        ---@cast rhs Parser
        local function combinedParse(s)
            return T.matchOption(self.runParser(s), function(res_l)
                return T.matchOption(rhs.runParser(res_l[1]), function(res_r)
                    local res_comb = {}
                    for _, val in ipairs(res_l[2]) do
                        table.insert(res_comb, val)
                    end
                    for _, val in ipairs(res_r[2]) do
                        table.insert(res_comb, val)
                    end
                    return T.Some({ res_r[1], res_comb })
                end, T.None)
            end, T.None)
        end
        return setmetatable({ runParser = combinedParse }, getmetatable(Parser))
    end
}

function Parser.fmap(self, fn)
    return setmetatable({
        runParser = function(s)
            return T.matchOption(self.runParser(s),
                function(res)
                    return T.Some({res[1], fn(res[2])})
                end,
                T.None)
        end
    }, getmetatable(Parser))
end

setmetatable(Parser, Parser_mt)

---@generic A
---@param x string
---@return Parser<A>
function M.pstr(x)
    local len_x = string.len(x)
    return setmetatable({
        runParser = function(s)
            local head = string.sub(s, 1, len_x)
            local tail = string.sub(s, len_x + 1, nil)
            if head == x then
                return T.Some({ tail, { x } })
            else
                return T.None()
            end
        end
    }, getmetatable(Parser))
end

function M.ppure(...)
    local inside = {...}
    return setmetatable({
        runParser = function(s)
            return T.Some({ s, inside })
        end
    }, getmetatable(Parser))
end

function M.pmatch(x)
    return setmetatable({
        runParser = function(s)
            local splitAt = string.match(s, x)
            if splitAt then
                local matched = string.sub(s, 1, splitAt - 1)
                local remaining = string.sub(s, splitAt, nil)
                return T.Some({ remaining, { matched } })
            else
                return T.None()
            end
        end,
    }, getmetatable(Parser))
end

---repeated application of the input parser
---@param p Parser
---@return Parser
function M.prep(p)
    return setmetatable({
        runParser = function(s)
            ---@type Option
            local res = p.runParser(s)
            local xs = {}
            while res._val do
                local inner = res._val
                for _, value in ipairs(inner[2]) do
                    table.insert(xs, value)
                end
                s = inner[1]
                res = p.runParser(s)
            end
            return T.Some({ s, xs })
        end
    }, getmetatable(Parser))
end

---@return Parser
local function mkSetOpP(s)
    local p = M.pstr(s)
    return p + M.ppure(string.lower(s))
end
local pYear = M.pmatch('^%d%d%d%d()'):fmap(wrapmap(tonumber))
local pMo = M.pmatch('^%d?%d()'):fmap(wrapmap(tonumber))
local function mkPMo(name)
    local lowered = string.lower(name)
    local capitalized = string.upper(string.sub(name,1,1)) .. string.sub(lowered,2)
    return M.pstr(lowered) ^ M.pstr(capitalized)
end
local pMon = (mkPMo('jan') + M.ppure(1))
    ^ (mkPMo('feb') + M.ppure(2))
    ^ (mkPMo('mar') + M.ppure(3))
    ^ (mkPMo('apr') + M.ppure(4))
    ^ (mkPMo('may') + M.ppure(5))
    ^ (mkPMo('jun') + M.ppure(6))
    ^ (mkPMo('jul') + M.ppure(7))
    ^ (mkPMo('aug') + M.ppure(8))
    ^ (mkPMo('sep') + M.ppure(9))
    ^ (mkPMo('oct') + M.ppure(10))
    ^ (mkPMo('nov') + M.ppure(11))
    ^ (mkPMo('dec') + M.ppure(12))
local pDay = M.pmatch('^%d?%d()'):fmap(wrapmap(tonumber))
local pDate = (pDay .. pMon .. pYear):fmap(compose(wrap1, function(x)
    return {yr = x[3], mo = x[2], da = x[1]}
end))
    ^ (pYear - M.pstr('-') .. pMo - M.pstr('-') .. pDay):fmap(compose(wrap1, function(x)
    return {yr = x[1], mo = x[2], da = x[3]}
end))
local pNullOrDate = (M.pstr('null') + M.ppure({yr = 9999, mo = 12, da = 31})) ^ pDate
local pPath = M.pmatch('^[%w%-%_%/]+()')
local pSetOpKW = mkSetOpP('UNION') ^ mkSetOpP('SUBTRACT') ^ mkSetOpP('INTERSECT')
local pWhChar = M.pstr(' ') ^ M.pstr('\t')
local pWhite = M.prep(pWhChar)
local pNewLine = M.pstr('\n')
local pWhSep = pWhChar + pWhite
local pHome = M.pstr('-') + M.ppure('~/code/')--M.ppure(M.dirs.data)
local pDir = pHome ^ pPath ^ (M.pstr('`') + pPath - M.pstr('`'))
local pFrom = M.pstr('FROM') + pWhSep + pDir
local pFroms = M.prep(pWhSep + pFrom):fmap(wrap1)
local pStache = M.pstr('task') ^ M.pstr('data') ^ M.pstr('contact') ^ M.pstr('inventory')
local pFiltStache = (M.pstr('STACHE') + pWhSep + pStache)
    :fmap(function(x)
        return { { filt = 'stache', data = x[1] } }
    end)
local pDblQuotes = M.pstr('"') + M.pmatch('^[^"]+()') - M.pstr('"')
local pFiltGrep = (M.pstr('GREP') + pWhSep + pDblQuotes)
    :fmap(function(re)
        return { { filt = 'grep', data = re[1] } }
    end)
local pFieldStr = M.pmatch('^[%w%_]+()')
local pField = pFieldStr ^ pDblQuotes
local pFiltField = (M.pstr('FIELD') + pWhSep + pField .. pWhSep + pDblQuotes)
    :fmap(function(x)
        return { { filt = 'field', field = x[1], data = x[2] } }
    end)
local pFilters = pFiltStache ^ pFiltGrep ^ pFiltField
local pInv = (M.pstr('INV') + pWhSep + M.ppure(true)) ^ M.ppure(false)
local pInvFilt = (pInv .. pFilters):fmap(function(x)
    x[2]['invert'] = x[1]
    return { x[2] }
end)
local pFilt = (pWhSep + pInvFilt) ^ M.ppure({})
local pSetOp = (pSetOpKW .. pFroms .. pFilt - pWhite)
    :fmap(function(x)
        return { { op = x[1], fromDirs = x[2], filter = x[3] } }
    end)
local pSetOps = (pSetOp .. M.prep(pNewLine + pSetOp)):fmap(wrap1)
local pGrpSpl = M.pstr('GROUP') + pWhSep + M.pstr('SPL') + M.ppure(true)
local pGrpNoSpl = M.pstr('GROUP') + M.ppure(false)
local pGrpField = (M.pstr('FIELD') + pWhSep + pField)
local pSort = pWhSep + (M.pstr('ASC') ^ M.pstr('DES'))
    :fmap(function(x) return { string.lower(x[1]) } end)
local pGrpOp = ((pGrpSpl ^ pGrpNoSpl) .. pWhSep + pGrpField .. (pSort ^ M.ppure(nil)) - pWhite)
    :fmap(function(x)
        ---@type GroupOp
        local op = {
            split = x[1],
            field = x[2],
            sort = x[3],
        }
        return { op }
    end)
local pDispOp = M.pstr('LIST') - pWhite
local pBlk = (
    pSetOps
    .. (M.prep(pNewLine + pGrpOp - pWhite):fmap(wrap1))
    .. (pNewLine + pDispOp)
):fmap(function(x)
    return { setOps = x[1], grpOps = x[2], dispOp = x[3] }
end)

-- local htest = require 'handdara.util.test' 
-- local function dbg(x, arg)
--     if type(arg) == "table" then
--         return x
--     end
--     arg = arg or ''
--     test_notifier:addline(arg .. vim.inspect(x))
--     return x
-- end
-- local test_notifier = htest.mkNotifier()
-- local td = { s = 'test string', t = 'other string' }
-- local tests = {
--     test_pstr_fail = function()
--         local x = 'rest'
--         ---@type Parser
--         local p = M.pstr(x)
--         return T.matchOption(p.runParser(td.s), function(_) return false end, function() return true end)
--     end,
--     test_pstr_success = function()
--         local x = 'test'
--         ---@type Parser
--         local p = M.pstr(x)
--         return T.matchOption(dbg(p.runParser(td.s), { 'parse result' }),
--             function(val)
--                 if val[1] == ' string' and val[2][1] == 'test' then
--                     return true
--                 end
--                 return false
--             end,
--             function() return false end)
--     end,
--     test_pstr_combine = function()
--         ---@type Parser
--         local q = M.pstr('test')
--         local r = M.pstr('other')
--         local p = q ^ r
--         return T.matchOption(p.runParser(td.s),
--                 function(val)
--                     if val[1] == ' string' and val[2][1] == 'test' then
--                         return true
--                     end
--                     return false
--                 end, function() return false end)
--             and T.matchOption(p.runParser(td.t),
--                 function(val)
--                     if val[1] == ' string' and val[2][1] == 'other' then
--                         return true
--                     end
--                     return false
--                 end, function() return false end)
--             and T.matchOption(p.runParser('this shoudlnt match'),
--                 function(_) return false end, function() return true end)
--     end,
--     test_pstr_take_right = function()
--         local p = M.pstr('test')
--         local q = p + M.ppure(4)
--         return T.matchOption(q.runParser(td.s), function(val)
--             if val[2][1] == 4 then
--                 return true
--             end
--             return false
--         end, function() return false end)
--     end,
--     test_pstr_take_left = function()
--         local p = M.pstr('test ') + M.ppure(4)
--         local q = M.pstr('string')
--         local r = p - q
--         return T.matchOption(r.runParser(td.s),
--             function(res)
--                 if dbg(res, {})[2][1] == 4 then
--                     return true
--                 end
--                 return false
--             end,
--             function() return false end)
--     end,
--     test_pstr_concat = function()
--         local p = M.pstr('test ') + M.ppure(1)
--         local q = M.pstr('string') + M.ppure(2)
--         local r = p .. q
--         return T.matchOption(r.runParser(td.s),
--             function(res)
--                 if res[2][1] == 1 and res[2][2] then
--                     return true
--                 end
--                 return false
--             end,
--             function() return false end)
--     end,
--     test_prep = function()
--         local p = M.pstr('test') .. M.pstr(' ')
--         return T.matchOption(p.runParser(td.s),
--             function(res) return (res[1] == 'string' and res[2][1] == 'test' and res[2][2] == ' ') end,
--             function() return false end)
--     end,
--     test_match = function()
--         local p = M.pmatch('^[%w%-%_%/]+()')
--         local x = 'this_is-a/path'
--         local y = ' and the rest isnt'
--         local pathString = x .. y
--         return T.matchOption(p.runParser(pathString),
--             function(res) return (res[1] == y and res[2][1] == x) end,
--             function() return false end)
--     end,
--     test_fmap = function()
--         local p = M.pstr('test') + M.ppure(1)
--         local q = p:fmap(function(x) return {x[1] + 1} end)
--         return T.matchOption(q.runParser(td.s),
--             function(res)
--                 return (res[1] == ' string' and res[2][1] == 2)
--             end,
--             function() return false end)
--     end
-- }
-- ---@diagnostic disable-next-line: unused-local
-- htest.runtests(tests, function(msg) test_notifier:addline(msg) end)
-- test_notifier:notify()

return M

---@class M
local M = {}
local T = require 'stache.type'

local wrap1 = T.wrap1
local wrapmap = T.wrapmap
local compose = T.compose

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
local pPath = M.pmatch('^[%w%-%_%/%~%.]+()'):fmap(wrapmap(vim.fs.normalize))
local pSetOpKW = mkSetOpP('UNION') ^ mkSetOpP('SUBTRACT') ^ mkSetOpP('INTERSECT')
local pWhChar = M.pstr(' ') ^ M.pstr('\t')
local pWhite = M.prep(pWhChar)
local pNewLine = M.pstr('\n')
local pWhSep = pWhChar + pWhite
local pHome = M.pstr('-')
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

M.pBlock = pBlk
M.pDate = pDate

return M

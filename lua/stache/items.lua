local T = require 'stache.type'
local ask = require 'stache.ask'
local M = {}

local function grab_field(field, file, tbl)
    assert(type(file) == 'string' and string.len(file) > 0,
        'grab_field: invalid arg: file: ' .. vim.inspect(file)
        .. '\n\targ: tbl: ' .. vim.inspect(tbl or 'tbl not passed')
    )
    local command = { 'rg', "-NIor=$1", '^' .. field .. ': *(.*)(\t| )*', file }
    local co = coroutine.create(ask.ask_cr)
    local _, ans = coroutine.resume(co, command)
    assert(coroutine.resume(co))
    assert(ans.stderr[1] == "", "rg errored:\n\tans:\n" .. vim.inspect(ans) ..
        "\n\tcommand: " .. vim.inspect(command) ..
        "\n\tfile: " .. vim.inspect(file)
    )
    return ans.stdout[1]
end

---@class ItmDat
---@field refresh fun(self:ItmDat)
---@field render fun(self:ItmDat):string[]
---@field path string
---@operator concat(ItmDat):ItmDat

local meta_itmdat = {
    __is_stache_item = true,
    __index = function(tbl, key)
        local fld = grab_field(key, tbl.path, tbl)
        if fld == '~' then
            fld = 'null'
        end
        tbl[key] = fld
        return fld
    end,
    __eq = function(t1, t2)
        return t1.id == t2.id
    end,
    __concat = function(t1, t2)
        assert(t1 == t2)
        for k, v in pairs(t2) do
            t1[k] = v
        end
        return t1
    end,
}

---@param itm ItmDat
local function cacheItem(itm)
    StacheCache[itm['id']] = itm
end

---@param filepath FilePath
---@return ItmDat
function M.mk_itm_dat(filepath)
    assert(type(filepath) == "string" and string.len(filepath) > 0,
        'mk_itm_dat: invalid arg: filepath: ' .. vim.inspect(filepath)
    )
    local fid = vim.fs.basename(filepath)
    local cacheQuery = StacheCache[fid]
    if cacheQuery then
        return cacheQuery
    end

    local itmdat = {
        path = vim.fs.normalize(filepath),
    }
    function itmdat:refresh()
        local path_ = self.path
        local refresh_ = self.refresh
        local render_ = self.render
        for k, _ in pairs(self) do
            self[k] = nil
        end
        self.path = path_
        self.refresh = refresh_
        self.render = render_
        setmetatable(self, meta_itmdat)
        assert(self.id == vim.fs.basename(self.path))
    end

    function itmdat:render()
        if self.stache == 'task' then
            local due_str
            if self.due == 'null' then
                due_str = ''
            else
                due_str = '<' .. self.due .. '> '
            end
            return {
                str = (
                    '-   (' ..
                    self.id ..
                    ") " ..
                    due_str .. '-' ..
                    self.priority .. '- ' ..
                    self.description
                ),
                fields = self,
            }
        elseif self.stache == 'contact' then
            return {
                str = (self.id .. ': ' .. self.description),
                fields = self,
            }
        else
            return {
                str = '-   (' .. self.id .. ') ' .. self.description,
                fields = self,
            }
        end
    end

    setmetatable(itmdat, meta_itmdat)
    assert(itmdat.id == vim.fs.basename(filepath),
        'assertion failed, id/filepath basename mismatch:\n\t'
        .. vim.inspect(itmdat.id) .. ' /= ' .. vim.inspect(vim.fs.basename(filepath)) .. '\n' ..
        '!!! failing file: ' .. filepath
    )
    cacheItem(itmdat)
    return itmdat
end

function M.mk_itm_set(filepaths)
    filepaths = filepaths or {}
    local itmset = T.Set:new()

    for _, fp in ipairs(filepaths) do
        if string.len(fp) > 0 then
            local new_itm = M.mk_itm_dat(fp)
            itmset:insert(new_itm['id'])
        end
    end
    return itmset
end

return M

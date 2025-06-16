local T = require 'stache.type'
local P = require 'stache.parse'
local C = require 'stache.config'
local I = require 'stache.items'
local ask = require 'stache.ask'

local M = {
    options = {
        dirs = {},
    }
}

C.extend_defaults(M)

local function run_stache(data, dir)
    dir = dir or M.options.dirs.data
    assert(string.len(data) >= 1)
    local pattern = [[^stache: *]] .. data
    return ask.ask_rg { '-l', pattern, dir }
end

---@param ops SetOp[]
---@return Option<Set<StacheID>>
local function do_query_set_ops(ops)
    if #ops == 0 or #ops[1].fromDirs == 0 then
        return T.None()
    else
        local currset = I.mk_itm_set()
        for _, op in ipairs(ops) do
            local nextset
            if #op.fromDirs == 0 then
                -- using the current set instead of pulling from file system
                local rgFlags
                if op.filter.invert then
                    rgFlags = '--files-without-match'
                else
                    rgFlags = '--files-with-matches'
                end
                local cmd = currset:foldl({ rgFlags }, function(acc, id)
                    local itm = I.mk_itm_dat(id)
                    table.insert(acc, itm['path'])
                    return acc
                end)
                -- apply filter
                if op.filter.filt == 'stache' then
                    local pattern = [[^stache: *]] .. op.filter.data
                    table.insert(cmd, 2, pattern)
                    local askRes = ask.ask_rg(cmd)
                    assert(askRes.stderr[1] == "", 'std err: ' .. vim.inspect(askRes.stderr))
                    nextset = I.mk_itm_set(askRes.stdout)
                elseif op.filter.filt == 'grep' then
                    table.insert(cmd, 2, op.filter.data)
                    local askRes = ask.ask_rg(cmd)
                    assert(askRes.stderr[1] == "", 'ask_rg result: ' .. vim.inspect(askRes))
                    nextset = I.mk_itm_set(askRes.stdout)
                elseif op.filter.filt == 'field' then
                    cmd[1] = '--files-with-matches'
                    table.insert(cmd, 2, '')
                    local askRes = ask.ask_rg(cmd)
                    assert(askRes.stderr[1] == "")
                    nextset = I.mk_itm_set(askRes.stdout):filter(function(sid)
                        local matched = string.match(StacheCache[sid][op.filter.field], op.filter.data)
                        if op.filter.invert then
                            return not matched
                        else
                            return matched
                        end
                    end)
                else
                    error('not impl')
                end
            else
                local rgFlags
                if op.filter.invert then
                    rgFlags = '--files-without-match'
                else
                    rgFlags = '--files-with-matches'
                end
                -- searching through file system
                nextset = I.mk_itm_set()
                for _, dir in ipairs(op.fromDirs) do
                    if op.filter.filt == 'stache' then
                        local pattern = [[^stache: *]] .. op.filter.data
                        local askRes = ask.ask_rg { rgFlags, pattern, dir }
                        assert(askRes.stderr[1] == "", 'askRes = ' .. vim.inspect(askRes))
                        nextset = nextset + I.mk_itm_set(askRes.stdout)
                    elseif op.filter.filt == 'grep' then
                        local askRes = ask.ask_rg { rgFlags, op.filter.data, dir }
                        assert(askRes.stderr[1] == "", 'stderr: ' .. vim.inspect(askRes.stderr))
                        nextset = nextset + M.mk_itm_set(askRes.stdout)
                    elseif op.filter.filt == 'field' then
                        local askRes = ask.ask_rg { '-l', '', dir } -- leave this as just the -l arg because inversion happens later
                        assert(askRes.stderr[1] == "")
                        nextset = nextset + I.mk_itm_set(askRes.stdout):filter(function(sid)
                            local matched = string.match(StacheCache[sid][op.filter.field], op.filter.data)
                            if op.filter.invert then
                                return not matched
                            else
                                return matched
                            end
                        end)
                    else
                        error('not impl: op = ' .. vim.inspect(op))
                    end
                end
            end
            if op.op == "union" then
                currset = currset + nextset
            elseif op.op == "intersect" then
                currset = currset * nextset
            elseif op.op == "subtract" then
                currset = currset - nextset
            end
        end
        return T.Some(currset)
    end
end

local function compare_dates(lhs, rhs)
    local pNullOrDate = (M.pstr('null') + M.ppure({ yr = 9999, mo = 12, da = 31 })) ^ P.pDate
    return T.matchOption(pNullOrDate.runParser(lhs),
        function(lres)
            local l = lres[2][1]
            return T.matchOption(pNullOrDate.runParser(rhs),
                function(rres)
                    local r = rres[2][1]
                    ---@cast l {yr:number, mo:number, da:number}
                    ---@cast r {yr:number, mo:number, da:number}
                    local yrEq = l.yr == r.yr
                    local yrMoEq = yrEq and l.mo == r.mo
                    return l.yr < r.yr or (yrEq and l.mo < r.mo) or (yrMoEq and l.da < r.da)
                end,
                function() error('date comparison failed') end)
        end,
        function() error('lhs date comparison failed, lhs: ' .. vim.inspect(lhs)) end)
end

---@param field StacheField
---@param tups [string, any][]
---@param invert boolean
---@return [string, any][]
local function sort_grp(field, tups, invert)
    local comp_1 = function(c)
        return function(ltup, rtup)
            return c(ltup[1], rtup[1])
        end
    end
    local comparison_funcs = { -- is (lhs < rhs) true?
        id = comp_1(function(l, r) return l < r end),
        due = comp_1(compare_dates),
        created = comp_1(compare_dates),
        modified = comp_1(compare_dates),
        priority = comp_1(function(lhs, rhs)
            local compTbl = { ['null'] = 1, ['1'] = 1, ['2'] = 2, ['3'] = 3, ['4'] = 4 }
            local l = compTbl[lhs]
            local r = compTbl[rhs]
            -- print(l .. '<' .. r .. '=' .. tostring(l<r))
            return l < r
        end),
        status = comp_1(function(lhs, rhs)
            local lnum, rnum
            for idx, st in ipairs(M.statuses) do
                if st == lhs then
                    lnum = idx
                end
                if st == rhs then
                    rnum = idx
                end
            end
            return lnum < rnum
        end),
    }
    assert(comparison_funcs[field], 'unsuported sort field!')
    table.sort(tups, comparison_funcs[field])
    if invert then
        local tupsInv = {}
        for _, tup in ipairs(tups) do
            table.insert(tupsInv, 1, tup)
        end
        return tupsInv
    else
        return tups
    end
end

---@param op GroupOp
---@param group Group
---@return Group
local function process_grp_op(op, group)
    if group.groups then
        local newGrps = {}
        for _, tup in ipairs(group.groups) do
            local key = tup[1]
            local grp = tup[2]
            table.insert(newGrps, { key, process_grp_op(op, grp) })
        end
        return { groups = newGrps }
    elseif group.items and op.split then
        local newGrps = {}
        for _, itm in ipairs(group.items) do
            local fld = itm[op.field]
            local grp = newGrps[fld] or { items = {} }
            table.insert(grp.items, itm)
            newGrps[fld] = grp
        end
        local grp = { groups = {} }
        for fld, subgrp in pairs(newGrps) do
            table.insert(grp.groups, { fld, subgrp })
        end
        if op.sort then
            grp.groups = sort_grp(op.field, grp.groups, op.sort == 'des')
        end
        return grp
    elseif group.items and (not op.split) then
        if op.sort then
            -- pack for sorting
            local zipped = {}
            for _, itm in ipairs(group.items) do
                table.insert(zipped, { itm[op.field], itm })
            end
            -- do sort
            zipped = sort_grp(op.field, zipped, op.sort == 'des')
            -- unpack after sorting
            for idx, tup in ipairs(zipped) do
                group.items[idx] = tup[2]
            end
        end
        return group
    else
        error('group had neither "groups" nor "items" field. ')
    end
end

---@param query Query
---@return string[]
local function process_query(query)
    -- do set ops
    for _, op in ipairs(query.setOps) do
        for jdx, dir in ipairs(op.fromDirs) do
            if dir == '-' then
                op.fromDirs[jdx] = M.options.dirs.data
            end
        end
    end
    local resultSet = do_query_set_ops(query.setOps)

    return T.matchOption(resultSet, function(x)
        ---@cast x Set
        ---@type Group
        local rootGrp = {
            items = x:foldl({}, function(acc, y)
                table.insert(acc, I.mk_itm_dat(y))
                return acc
            end)
        }
        for _, grpOp in ipairs(query.grpOps) do
            rootGrp = process_grp_op(grpOp, rootGrp)
        end

        -- display op
        if query.dispOp == 'LIST' then
            ---@param level integer
            ---@param grp Group
            ---@return string[]
            local function disp_grps(level, grp)
                local lines = {}
                if grp.items then
                    local preLine = string.rep('    ', math.max(0, level - 1))
                    for _, itm in ipairs(grp.items) do
                        table.insert(lines, preLine .. itm:render()['str'])
                    end
                elseif grp.groups then
                    local preHdr = '###' .. string.rep('#', level) .. ' '
                    for _, grpTuple in pairs(grp.groups) do
                        table.insert(lines, preHdr .. grpTuple[1])
                        for _, subline in ipairs(disp_grps(level + 1, grpTuple[2])) do
                            table.insert(lines, subline)
                        end
                    end
                else
                    error('root group has neither items nor subgroups')
                end
                return lines
            end
            return disp_grps(0, rootGrp)
        else
            error('not impl')
        end
    end, function()
        return { 'Failed parse: either no set operations were specified or the first set operation has no FROM expr' }
    end)
end

function M.quick_get_names(stache_type, searchDir)
    searchDir = searchDir or M.options.dirs.data
    local res = run_stache(stache_type)
    return res.stdout
end

function M.open_item()
    local line_text = vim.api.nvim_get_current_line()
    local task_id = string.match(line_text, '%((.-)%)') or string.match(line_text, 'id: *([%w%-%_]+)')
    if task_id then
        local file = M.options.dirs.data .. '/' .. task_id
        vim.cmd('edit ' .. file)
    else
        vim.notify('No stache item on current line!')
    end
end

local function buf_get_blk_replace_range(bufnr, afterBlockLineNr)
    local remLinesHead = vim.api.nvim_buf_get_lines(bufnr, afterBlockLineNr, afterBlockLineNr + 1, false)
    if remLinesHead[1] and string.match(remLinesHead[1], '^```markdown%s?') then
        local remLinesTail = vim.api.nvim_buf_get_lines(bufnr, afterBlockLineNr + 1, -1, false)
        for idx, line in ipairs(remLinesTail) do
            if string.match(line, '^```%s?') then
                return { afterBlockLineNr, afterBlockLineNr + idx + 1 }
            elseif string.match(line, '^```markdown%s?') then
                break
            end
        end
    end
    return { afterBlockLineNr, afterBlockLineNr }
end

---get stache blocks in a buffer
---@param bufnr number
---@return StacheBlock[]
local function buf_get_blocks(bufnr)
    local ls = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@type StacheBlock[]
    local sBlks = {}
    local curr = {}
    for idx, line in ipairs(ls) do
        if table.maxn(curr) == 0 then
            if string.match(line, "^```stache%s*$") then
                table.insert(curr, idx)
            end
        elseif table.maxn(curr) == 1 then
            if string.match(line, "^```stache%s*") then
                curr[1] = idx - 1
            elseif string.match(line, "^```%s*") then
                table.insert(curr, idx - 1)
                local newBlk = {
                    range = curr,
                    lines = vim.api.nvim_buf_get_lines(bufnr, curr[1], curr[2], false),
                    output = {},
                    outReplaceRange = buf_get_blk_replace_range(bufnr, curr[2] + 1),
                }
                table.insert(sBlks, newBlk)
                curr = {}
            end
        end
    end
    return sBlks
end

---@param blockLines string[]
---@return string[]
local function run_block(blockLines)
    local withoutComments = {}
    for _, line in ipairs(blockLines) do
        if not string.match(line, '^%s*#') then
            table.insert(withoutComments, line)
        end
    end
    local resLines = { '```markdown' }
    local blkString = table.concat(withoutComments, '\n')
    local processedLines = T.matchOption(P.pBlock.runParser(blkString),
        function(res)
            local query = res[2]
            return process_query(query)
        end,
        function()
            return { 'Block failed to parse into query!' }
        end)
    for _, line in ipairs(processedLines) do
        table.insert(resLines, line)
    end
    table.insert(resLines, '```')
    return resLines
end

function M.buf_exec_all_blocks(bufnr)
    bufnr = bufnr or 0
    local blks = buf_get_blocks(bufnr)
    local blkShft = 0
    for _, blk in ipairs(blks) do
        local res = run_block(blk.lines)
        blk.output = res
        vim.api.nvim_buf_set_lines(bufnr, blkShft + blk.outReplaceRange[1], blkShft + blk.outReplaceRange[2], false, res)
        blkShft = blkShft + #res - blk.outReplaceRange[2] + blk.outReplaceRange[1]
    end
    return blks
end

function M.buf_exec_curr_block(bufnr, atLine)
    bufnr = bufnr or 0
    local blks = buf_get_blocks(bufnr)
    local blkShft = 0
    atLine = atLine or vim.api.nvim_win_get_cursor(0)[1]
    for _, blk in ipairs(blks) do
        if blk.range[1] - 1 <= atLine and atLine <= blk.range[2] + 2 then
            local res = run_block(blk.lines)
            blk.output = res
            vim.api.nvim_buf_set_lines(bufnr, blkShft + blk.outReplaceRange[1], blkShft + blk.outReplaceRange[2], false, res)
            blkShft = blkShft + #res - blk.outReplaceRange[2] + blk.outReplaceRange[1]
            return blk
        end
    end
    vim.notify('StacheRun failed: Not inside of a block', vim.log.levels.WARN)
end

function M.refresh_cache()
    assert(StacheCache and StacheCache._elements)
    StacheCache:map(function(item) item:refresh() end) ---@diagnostic disable-line: missing-return, undefined-field
end

function M.new_item()
    vim.cmd( 'e ' .. M.options.dirs.data .. '/newstacheitem' )
    local cr = string.char(13)
    local esc = string.char(27)
    vim.cmd([[let @r = "{/^id:]]..cr..[[W\"zyiW ovE\"zpsy]]..esc..esc..esc..'"')
    vim.defer_fn(function()
        local keys = vim.api.nvim_replace_termcodes("Istache", true, false, true)
        vim.api.nvim_feedkeys(keys, 'n', false)
    end, 25)
    vim.notify('Run the "r" mactro when done! (press `@r`)')
end

function M.setup(opts)
    assert(opts)
    assert(opts.dirs)
    assert(opts.dirs.data)
    M.options.dirs = opts.dirs
    StacheCache = T.Map:new()
    C.create_augroups(M)
end

return M

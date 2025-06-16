local T = require 'stache.type'
local P = require 'stache.parse'
local C = require 'stache.config'
local I = require 'stache.items'
local ask = require 'stache.ask'

local M = { options = { dirs = { data = vim.fs.normalize('~/Documents/stache') } } }

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
        id = nil,
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
            if string.match(line, "^```stache%s*$") then
                curr[1] = idx - 1
            elseif string.match(line, "^```%s*$") then
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

function M.setup(opts)
    M.options.dirs = opts.dirs
    assert(M.options.dirs and M.options.dirs.data)
    StacheCache = T.Map:new()
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
-- local tests = {
--     test_get_blks = function()
--         local testbuf = vim.api.nvim_create_buf(false, true)
--         local ls = {
--             "```stache",
--             "```",
--             "",
--             "```stache",
--             "```",
--             "",
--             "stache",
--             "",
--             "``stache",
--             "```",
--             "",
--             "```lua",
--             "```",
--             "",
--             "```stache",
--             "UNION FROM - GREP \"regex\"",
--             "```",
--             "```markdown",
--             "-   ex task",
--             "```",
--         }
--         vim.api.nvim_buf_set_lines(testbuf, 0, -1, false, ls)
--         local blks = buf_get_blocks(testbuf)
--         vim.api.nvim_buf_delete(testbuf, { force = true })
--         assert(#blks[1].lines == 0)
--         assert(#blks[2].lines == 0)
--         assert(#blks[3].lines == 1 and blks[3].lines[1] == 'UNION FROM - GREP \"regex\"')
--         assert(blks[3].outReplaceRange[1] == blks[3].range[2] + 1
--             and blks[3].outReplaceRange[2] == blks[3].range[2] + 4)
--     end,
--     test_parse_dates = function()
--         assert(T.matchOption(pDate.runParser('12jun2025'), function(x)
--             return x[1] == '' and x[2][1].yr == 2025 and x[2][1].mo == 6 and x[2][1].da == 12
--         end, function() return false end))
--         assert(T.matchOption(pDate.runParser('3jun2025'), function(x)
--             return x[1] == '' and x[2][1].yr == 2025 and x[2][1].mo == 6 and x[2][1].da == 3
--         end, function() return false end))
--         assert(T.matchOption(pDate.runParser('2025-06-12'), function(x)
--             return x[1] == '' and x[2][1].yr == 2025 and x[2][1].mo == 6 and x[2][1].da == 12
--         end, function() return false end))
--         assert(T.matchOption(pDate.runParser('2025-6-1'), function(x)
--             return x[1] == '' and x[2][1].yr == 2025 and x[2][1].mo == 6 and x[2][1].da == 1
--         end, function() return false end))
--         assert(compare_dates('11jun2025', '12jun2025'))
--         assert(compare_dates('11jun2025', 'null'))
--         assert(not compare_dates('null', 'null'))
--         assert(not compare_dates('null', '1960-01-01'))
--         assert(not compare_dates('13jun2025', '12jun2025'))
--         assert(not compare_dates('12jun2025', '12jun2025'))
--         assert(compare_dates('2024-01-01', '12jun2025'))
--         assert(not compare_dates('2024-01-01', '12jun2023'))
--     end,
--     test_parse_set_op = function()
--         local ts = "UNION FROM `path` FROM `path` STACHE task"
--         local res = pSetOp.runParser(ts)
--         assert(res._val, 'res._val: ' .. vim.inspect(res._val))
--         assert(res._val[2][1]['op'] == 'union')
--         assert(res._val[2][1]['fromDirs'][1] == 'path')
--         assert(res._val[2][1]['fromDirs'][2] == 'path')
--         local ts_ = 'UNION FROM - FIELD id "marrissa"'
--         local res_ = pSetOp.runParser(ts_)
--         local res_str = 'res_._val: ' .. vim.inspect(res_._val)
--         assert(res_._val, res_str)
--         assert(res_._val[2][1]['op'] == 'union', res_str)
--         assert(res_._val[2][1]['fromDirs'][1] == M.stache.abs, res_str)
--         assert(res_._val[2][1]['filter']['field'] == 'id', res_str)
--         assert(res_._val[2][1]['filter']['data'] == 'marrissa', res_str)
--     end,
--     test_parse_set_op_no_fr = function()
--         local ts = "UNION STACHE task"
--         local res = pSetOp.runParser(ts)
--         -- tr('test_parse_set_op_no_fr', res._val)
--         assert(res._val)
--         assert(res._val[2][1]['op'] == 'union')
--     end,
--     test_parse_set_op_no_filter = function()
--         local ts = "UNION FROM -"
--         local res = pSetOp.runParser(ts)
--         local resString = 'res = ' .. vim.inspect(res)
--         assert(res._val, resString)
--         assert(res._val[2][1]['op'] == 'union')
--     end,
--     test_parse_grep_filter = function()
--         local ts = ' GREP "regex"'
--         local res = pFilt.runParser(ts)
--         local resString = 'res = ' .. vim.inspect(res)
--         assert(res._val[2][1]['filt'] == 'grep', resString)
--         assert(res._val[2][1]['data'] == 'regex', resString)
--     end,
--     test_parse_empty_filter = function()
--         local ts = ''
--         local res = pFilt.runParser(ts)
--         assert(res._val, 'res = ' .. vim.inspect(res))
--         assert(#res._val[2][1] == 0, 'res = ' .. vim.inspect(res))
--     end,
--     test_parse_field_filter = function()
--         local ts = ' FIELD id "lua pattern"'
--         local res = pFilt.runParser(ts)
--         local resString = 'res = ' .. vim.inspect(res)
--         assert(res._val[2][1]['filt'] == 'field', resString)
--         assert(res._val[2][1]['field'] == 'id', resString)
--         assert(res._val[2][1]['data'] == 'lua pattern', resString)
--     end,
--     test_parse_group_ops = function()
--         local ts = '\nGROUP FIELD id\nGROUP SPL FIELD status\nGROUP FIELD id ASC'
--         local p = P.prep(pNewLine + pGrpOp)
--         ---@type Option
--         local res = p.runParser(ts)
--         local resString = 'res = ' .. vim.inspect(res)
--         assert(#res._val[2] == 3, resString)
--         assert(res._val[2][1]['sort'] == nil, resString)
--         assert(res._val[2][1]['field'] == 'id', resString)
--         assert(res._val[2][1]['split'] == false, resString)
--         assert(res._val[2][2]['sort'] == nil, resString)
--         assert(res._val[2][2]['field'] == 'status', resString)
--         assert(res._val[2][2]['split'] == true, resString)
--         assert(res._val[2][3]['sort'] == 'asc', resString)
--         assert(res._val[2][3]['field'] == 'id', resString)
--         assert(res._val[2][3]['split'] == false, resString)
--     end,
--     test_parse_blk = function()
--         local blkLines = {
--             'UNION FROM -',
--             'INTERSECT GREP "regex"',
--             'GROUP FIELD id',
--             'LIST'
--         }
--         local blk = table.concat(blkLines, '\n')
--         local res = pBlk.runParser(blk)
--         local res_string = 'test_parse_blk:res = ' .. vim.inspect(res)
--         assert(res._val, res_string)
--         assert(#res._val[2].setOps == 2, res_string)
--         assert(#res._val[2].grpOps == 1, res_string)
--         assert(res._val[2].grpOps[1]['field'] == 'id', res_string)
--         assert(res._val[2].grpOps[1]['split'] == false, res_string)
--         assert(res._val[2].dispOp == 'LIST', res_string)
--         -- print(table.concat(run_block(blkLines), '\n'))
--     end,
--     test_do_query_set_ops__empty = function()
--         ---@type SetOp[]
--         local setOps = {}
--         ---@type Option
--         local res = do_query_set_ops(setOps)
--         local resStr = 'res = ' .. vim.inspect(res)
--         assert(not res._val, resStr)
--     end,
--     test_do_query_set_ops__empty_fst_fromDirs = function()
--         ---@type SetOp[]
--         local setOps = {
--             { op = 'union', fromDirs = {}, filter = {} }
--         }
--         ---@type Option
--         local res = do_query_set_ops(setOps)
--         local resStr = 'res = ' .. vim.inspect(res)
--         assert(not res._val, resStr)
--     end,
--     test_do_query_set_ops__stache_filt = function()
--         for _, stacheTypeToSearch in ipairs(M.itemTypes) do
--             ---@type SetOp[]
--             local setOps = {
--                 {
--                     op = 'union',
--                     fromDirs = { M.stache.abs },
--                     filter = { filt = 'stache', data = stacheTypeToSearch }
--                 },
--             }
--             ---@type Option
--             local res = do_query_set_ops(setOps)
--             local resStr = 'res = ' .. vim.inspect(res)
--             assert(res._val, resStr)
--             local els = res._val._elements
--             for name, inSet in pairs(els) do
--                 if inSet then
--                     local el = I.mk_itm_dat(name)
--                     ---@diagnostic disable-next-line: undefined-field
--                     assert(el.stache == stacheTypeToSearch)
--                 end
--             end
--         end
--     end,
--     test_do_query_set_ops__grep_filt = function()
--         ---@type SetOp[]
--         local setOps = {
--             {
--                 op = 'union',
--                 fromDirs = { M.stache.abs },
--                 filter = { filt = 'grep', data = 'marrissa', invert = false }
--             },
--         }
--         local setOpsAll = {
--             {
--                 op = 'union',
--                 fromDirs = { M.stache.abs },
--                 filter = { filt = 'grep', data = '', invert = false }
--             },
--         }
--         local setOpsInv = {
--             {
--                 op = 'union',
--                 fromDirs = { M.stache.abs },
--                 filter = { filt = 'grep', data = 'marrissa', invert = true }
--             },
--         }
--         ---@type Option
--         local res = do_query_set_ops(setOps)
--         ---@type Option
--         local resInv = do_query_set_ops(setOpsInv)
--         ---@type Option
--         local resAll_ = do_query_set_ops(setOpsAll)
--         ---@type Set
--         assert(resAll_._val)
--         local resAll = resAll_._val
--         local resStr = 'res = ' .. vim.inspect(res)
--         ---@type Set
--         local intersection = (I.mk_itm_set() + res._val) * resInv._val
--         ---@type Set
--         local union = (I.mk_itm_set() + res._val) + resInv._val
--         assert(res._val._elements, resStr)
--         assert(intersection:empty())
--         resAll:map(function(x)
--             assert(union:has(x))
--             return x
--         end)
--     end,
--     test_do_query_set_ops__field_filt = function()
--         ---@type SetOp[]
--         local setOps = {
--             {
--                 op = 'union',
--                 fromDirs = { M.stache.abs },
--                 filter = { filt = 'field', field = 'id', data = 'marrissa' }
--             },
--         }
--         ---@type Option
--         local res = do_query_set_ops(setOps)
--         local resStr = 'res = ' .. vim.inspect(res)
--         assert(res._val, resStr)
--         for name, inSet in pairs(res._val._elements) do
--             if inSet then
--                 assert(string.sub(name, 1, 8) == 'marrissa', resStr)
--             end
--         end
--     end,
--     test_run_block_contact = function()
--         local blkLines = {
--             'UNION FROM - FIELD id "marrissa"',
--             'GROUP',
--             'LIST'
--         }
--         -- local blk = table.concat(blkLines, '\n')
--         local res = run_block(blkLines)
--         for _, line in ipairs(res) do
--             -- print(line)
--             assert(string.len(line) > 0)
--         end
--     end,
--     test_run_blk_in_buf = function()
--         local testbuf = vim.api.nvim_create_buf(false, true)
--         local ls = {
--             "```stache",
--             'UNION FROM - STACHE task',
--             'INTERSECT FROM - GREP "marrissa"',
--             'SUBTRACT FIELD id "life%-"',
--             'GROUP FIELD id',
--             'LIST',
--             "```",
--         }
--         vim.api.nvim_buf_set_lines(testbuf, 0, -1, false, ls)
--         local blks = buf_get_blocks(testbuf)
--         local blksStr = 'bnds = ' .. vim.inspect(blks)
--         assert(blks[1].range[1] == 1, blksStr)
--         assert(blks[1].range[2] == 6, blksStr)
--         vim.api.nvim_buf_delete(testbuf, { force = true })
--         ---@diagnostic disable-next-line: unused-local
--         local res = run_block(blks[1])
--     end,
--     test_run_all_blocks = function()
--         local testbuf = vim.api.nvim_create_buf(false, true)
--         local ls = {
--             "```stache",
--             'UNION FROM - STACHE task',
--             '#SUBTRACT FROM - STACHE task',
--             'INTERSECT FROM - GREP "marrissa"',
--             'SUBTRACT FIELD id "life%-"',
--             'GROUP SPL FIELD status DES',
--             '#GROUP FIELD priority DES',
--             'LIST',
--             "```",
--         }
--         vim.api.nvim_buf_set_lines(testbuf, 0, -1, false, ls)
--         local bs = M.buf_exec_all_blocks(testbuf)
--         -- for idx, line in ipairs(bs[1].output) do
--         --     print('output['..idx..']:' .. line)
--         -- end
--         vim.api.nvim_buf_delete(testbuf, { force = true })
--         assert(bs[1].range[1] == 1)
--         assert(bs[1].range[2] == #ls - 1)
--         assert(not string.match(bs[1].output[2], 'fail'))
--     end,
-- }
-- vim.notify('running tests in `fst/him/nvim-nrw/lua/handdara/util/stache.lua`')
-- runtests(tests, function(_) end)
-- -- runtests({
-- --     test_top = tests.test_run_all_blocks,
-- --     test_date = tests.test_parse_dates
-- -- }, function(_) end)
-- vim.notify('completed tests in `fst/him/nvim-nrw/lua/handdara/util/stache.lua`')
-- vim.cmd [[nnoremap <leader><leader>x :%lua<cr>]]

return M

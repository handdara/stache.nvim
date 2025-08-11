return {
    extend_defaults = function(M)
        assert(M and type(M) == "table")
        M.areas = {
            'seal',
            'thesis',
            'community',
            'learning',
            'hobbies',
            'fitness',
            'community',
            'life',
        }

        M.categories = {
            'electronics',
            'appliances',
            'furniture',
            'clothing',
            'books',
            'media',
            'tools',
            'outdoor',
            'vehicles',
            'art',
            'fitness',
            'instruments',
            'fun',
            'diy',
            'office',
            'health',
            'cooking',
            'organization',
        }

        M.contexts = {
            'laptop',
            'ccrf',
            'home',
            'notebook',
            'cell',
        }

        M.itemTypes = {
            'task',
            'data',
            'contact',
            'inventory',
        }

        M.statuses = {
            'backburner',
            'open', -- "clarify"
            'ready',
            'to-discuss',
            'blocked', -- "waiting"
            'scheduled',
            'in-progress',
            'delayed',
            'archived',
            'closed',
        }

        M.tags = {
            data = { 'heartrate' },
        }

        M.units = {
            temp = { 'farenheit', 'celcius', },
            freq = { 'bpm', 'Hz' },
            velocity = { 'mph', 'mps', 'kph', },
            duration = { 'seconds', 'hours', 'days', 'weeks', 'months', 'years', },
            misc = { 'count', '4-scale' },
        }

        M.favUnits = {
            M.units.temp[1],
            M.units.freq[1],
            M.units.velocity[1],
            M.units.velocity[2],
            M.units.duration[1],
            M.units.duration[2],
            M.units.duration[3],
            M.units.duration[6],
            M.units.misc[1],
            M.units.misc[2],
        }

        M.priorities = {
            '1',
            '2',
            '3',
            '4',
        }

        M.types = {
            date = {
                'birthday',
                'anniversary',
            },
            phone = {
                'cell',
                'home',
                'office',
                'work',
            },
            email = {
                'personal',
                'work',
            },
            address = {
                'personal',
                'office',
            },
        }
    end,
    create_augroups = function(M)
        local stachePattern = {M.options.dirs.data .. '/*', '*/%d+-stache/*'}
        local stache_enter = vim.api.nvim_create_augroup('StacheEnter', { clear = true })
        vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
            callback = function()
                vim.bo.filetype = "yaml"
            end,
            group = stache_enter,
            pattern = stachePattern,
        })
        local stache_itmSaved = vim.api.nvim_create_augroup('StacheItmSaved', { clear = true })
        vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
            callback = function()
                local sid = vim.fs.basename(vim.api.nvim_buf_get_name(0))
                if StacheCache then
                    local itm = StacheCache[sid] ---@type ItmDat
                    if itm then
                        itm:refresh()
                    end
                end
            end,
            group = stache_itmSaved,
            pattern = stachePattern,
        })
    end
}

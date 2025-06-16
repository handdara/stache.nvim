vim.api.nvim_create_user_command('StacheOpenTask', function()
    require 'stache'.open_item()
end, {})
vim.api.nvim_create_user_command('StacheRunAll', function(_)
    require 'stache'.buf_exec_all_blocks(0)
end, {})
local stache_enter = vim.api.nvim_create_augroup('StacheEnter', { clear = true })
vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
    callback = function()
        vim.bo.filetype = "yaml"
    end,
    group = stache_enter,
    pattern = require 'stache'.options.dirs.data .. '/*',
})

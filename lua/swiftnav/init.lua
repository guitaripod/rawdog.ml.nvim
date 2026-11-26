local M = {}

local function highlights()
  local groups = {
    SwiftNavSelection = 'PmenuSel',
    SwiftNavStatus = 'Comment',
    SwiftNavName = 'Normal',
    SwiftNavContainer = 'Comment',
    SwiftNavPath = 'Comment',
    SwiftNavKindType = '@type',
    SwiftNavKindFunction = '@function',
    SwiftNavKindValue = '@variable.member',
    SwiftNavKindModule = '@module',
    SwiftNavKindFile = '@constant',
    SwiftNavSection = 'Title',
    SwiftNavPreviewLine = 'CursorLine',
    SwiftNavBarFile = 'Title',
    SwiftNavBarType = '@type',
    SwiftNavBarMember = '@function',
    SwiftNavBarSeparator = 'Comment',
  }
  for name, link in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

local function guard(action)
  return function()
    if not require('swiftnav.util').swift_context() then
      require('swiftnav.util').notify('not in a Swift project', vim.log.levels.WARN)
      return
    end
    action()
  end
end

function M.setup()
  highlights()
  require('swiftnav.index').setup()
  require('swiftnav.indexer').setup()

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'swift',
    callback = function(event)
      local bufnr = event.buf
      require('swiftnav.jumpbar').attach(bufnr)

      local nav = require('swiftnav.nav')
      local function map(lhs, rhs, description)
        vim.keymap.set('n', lhs, rhs, {
          buffer = bufnr,
          silent = true,
          desc = 'swiftnav: ' .. description,
        })
      end
      map('gd', nav.definition, 'definition')
      map('gD', nav.declaration, 'declaration')
      map('gy', nav.type_definition, 'type definition')
      map('gi', nav.implementation, 'implementations')
      map('gr', nav.references, 'references')
      map('grr', nav.references, 'references')
      map('gri', nav.implementation, 'implementations')
      map('grt', nav.type_definition, 'type definition')
      map('K', nav.hover, 'hover')
      map('gO', function()
        require('swiftnav.jumpbar').open()
      end, 'document items')
      map('<C-]>', nav.definition, 'jump to definition')

      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          require('swiftnav.indexer').ensure(bufnr, function() end, false)
        end
      end, 1500)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].filetype == 'swift' then
      require('swiftnav.jumpbar').attach(bufnr)
    end
  end

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
    callback = function(event)
      if vim.bo[event.buf].filetype ~= 'swift' then
        vim.wo[vim.api.nvim_get_current_win()].winbar = ''
      end
    end,
  })

  vim.api.nvim_create_user_command('SwiftOpen', function(opts)
    require('swiftnav.open').open({ prefill = opts.args ~= '' and opts.args or nil })
  end, { nargs = '?', desc = 'Xcode-style Open Quickly' })

  vim.api.nvim_create_user_command('SwiftJump', function()
    require('swiftnav.jumpbar').open()
  end, { desc = 'Xcode-style document items' })

  vim.api.nvim_create_user_command('SwiftRelated', function()
    require('swiftnav.related').open()
  end, { desc = 'Callers, callees, overrides and conformances' })

  vim.api.nvim_create_user_command('SwiftReveal', function()
    require('swiftnav.jumpbar').reveal()
  end, { desc = 'Reveal the file in the project tree' })

  vim.api.nvim_create_user_command('SwiftWarm', function()
    require('swiftnav.index').warm()
  end, { desc = 'Build the sourcekit-lsp index ahead of a session' })

  vim.api.nvim_create_user_command('SwiftIndex', function()
    local indexer = require('swiftnav.indexer')
    require('swiftnav.nav').reset_build_settings()
    indexer.rebuild()
    indexer.ensure(0, function()
      local count, root = indexer.stats()
      require('swiftnav.util').notify(string.format('%d declarations in %s', count, vim.fs.basename(root or '')))
    end, true)
  end, { desc = 'Rebuild the Swift declaration index' })

  vim.keymap.set('n', '<leader>so', guard(function()
    require('swiftnav.open').open()
  end), { desc = 'Open Quickly (Swift)' })

  vim.keymap.set('n', '<leader>sj', guard(function()
    require('swiftnav.jumpbar').open()
  end), { desc = 'Swift document items' })

  vim.keymap.set('n', '<leader>sR', guard(function()
    require('swiftnav.related').open()
  end), { desc = 'Swift related items' })

  vim.keymap.set('n', '<leader>sS', guard(function()
    require('swiftnav.jumpbar').reveal()
  end), { desc = 'Reveal in project tree' })
end

return M

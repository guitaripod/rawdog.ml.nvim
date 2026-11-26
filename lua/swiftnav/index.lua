local util = require('swiftnav.util')

local M = {}

local active = {}
local listeners = {}
local was_busy = false

local function is_index_progress(value)
  local title = (value and value.title or ''):lower()
  return title:find('index', 1, true) ~= nil
end

local function settle()
  if not was_busy or M.busy() then
    return
  end
  was_busy = false
  local pending = listeners
  listeners = {}
  for _, listener in ipairs(pending) do
    pcall(listener)
  end
  vim.api.nvim_exec_autocmds('User', { pattern = 'SwiftNavIndexReady' })
end

--- Track sourcekit-lsp indexing progress so the UI can explain empty results.
function M.setup()
  vim.api.nvim_create_autocmd('LspProgress', {
    callback = function(event)
      local params = event.data.params or {}
      local value = params.value or {}
      local token = tostring(event.data.token)
      if not is_index_progress(value) then
        return
      end
      if value.kind == 'begin' then
        active[token] = true
        was_busy = true
      elseif value.kind == 'end' then
        active[token] = nil
        settle()
      end
    end,
  })
end

function M.busy()
  return next(active) ~= nil
end

--- Run a callback once when the current indexing run finishes.
function M.on_settled(listener)
  if not M.busy() then
    listener()
    return function() end
  end
  listeners[#listeners + 1] = listener
  return function()
    for index, existing in ipairs(listeners) do
      if existing == listener then
        table.remove(listeners, index)
        return
      end
    end
  end
end

function M.status()
  if M.busy() then
    return 'indexing'
  end
  return nil
end

--- Build sourcekit-lsp's own index tree ahead of a session.
function M.warm()
  local bufnr = vim.api.nvim_get_current_buf()
  local root = util.package_root(bufnr)
  if not root then
    util.notify('no Package.swift found', vim.log.levels.WARN)
    return
  end
  for _, client in ipairs(vim.lsp.get_clients({ name = 'sourcekit' })) do
    if client.config.root_dir == root then
      util.notify('sourcekit-lsp already owns this package; it indexes on its own', vim.log.levels.WARN)
      return
    end
  end
  local command = {
    'swift',
    'build',
    '--build-system',
    'native',
    '--scratch-path',
    '.build/index-build',
    '--enable-index-store',
    '--build-tests',
    '--no-color-diagnostics',
  }
  util.notify('warming the sourcekit-lsp index for ' .. vim.fs.basename(root))
  local started = vim.uv.hrtime()
  vim.system(command, { cwd = root, text = true }, function(object)
    vim.schedule(function()
      local seconds = (vim.uv.hrtime() - started) / 1e9
      if object.code == 0 then
        util.notify(string.format('index warm in %.1fs', seconds))
      else
        util.notify(string.format('index warm failed (exit %d)', object.code), vim.log.levels.ERROR)
      end
    end)
  end)
end

return M

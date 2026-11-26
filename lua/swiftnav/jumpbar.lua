local api = vim.api
local glyph = require('swiftnav.glyph')
local open = require('swiftnav.open')
local rank = require('swiftnav.rank')
local symbols = require('swiftnav.symbols')
local ui = require('swiftnav.ui')
local util = require('swiftnav.util')

local M = {}

local function segment(text, group)
  return '%#' .. group .. '#' .. util.statusline_escape(text) .. '%*'
end

--- Build the winbar line for a chain of declarations.
function M.text(chain, path)
  local parts = { segment(vim.fs.basename(path or 'swift'), 'SwiftNavBarFile') }
  for _, node in ipairs(chain or {}) do
    local group = symbols.type_name(node) and 'SwiftNavBarType' or 'SwiftNavBarMember'
    parts[#parts + 1] = segment(' › ', 'SwiftNavBarSeparator')
    parts[#parts + 1] = segment(symbols.label(node), group)
  end
  return table.concat(parts)
end

local retries = {}

--- Redraw the breadcrumb for a buffer's window at the cursor.
function M.refresh(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'swift' or vim.bo[bufnr].buftype ~= '' then
    return
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  local cursor = api.nvim_win_get_cursor(win)
  symbols.for_buffer(bufnr, function(tree)
    if not api.nvim_buf_is_valid(bufnr) or not api.nvim_win_is_valid(win) then
      return
    end
    if #tree == 0 and (retries[bufnr] or 0) < 3 then
      retries[bufnr] = (retries[bufnr] or 0) + 1
      vim.defer_fn(function()
        M.refresh(bufnr)
      end, 400)
    end
    local chain = symbols.chain(tree, cursor[1] - 1, cursor[2])
    vim.wo[win].winbar = M.text(chain, api.nvim_buf_get_name(bufnr))
  end)
end

--- Track cursor movement in one Swift buffer.
function M.attach(bufnr)
  retries[bufnr] = 0
  local group = api.nvim_create_augroup('SwiftNavJumpBar' .. bufnr, { clear = true })
  api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter', 'BufWinEnter', 'LspAttach' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      M.refresh(bufnr)
    end,
  })
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'SwiftNavIndexReady',
    callback = function()
      retries[bufnr] = 0
      M.refresh(bufnr)
    end,
  })
  M.refresh(bufnr)
end

local function format(item, width)
  local mark, group = glyph.get(item.kind)
  local indent = string.rep('  ', item.indent or 0)
  local left = indent .. mark .. ' ' .. item.label
  local location = string.format('%d', item.lnum or 1)
  local available = width - #location - 1
  if vim.fn.strdisplaywidth(left) > available then
    left = util.fit(left, math.max(0, available))
  end
  local text = left .. string.rep(' ', math.max(1, width - vim.fn.strdisplaywidth(left) - #location)) .. location
  local marks = { { #indent, #indent + #mark, group } }
  return text, marks
end

--- List the current file's declarations like Xcode's Document Items menu.
function M.open()
  local bufnr = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(bufnr)
  symbols.for_buffer(bufnr, function(tree)
    local flat = symbols.flatten(tree)
    if #flat == 0 then
      util.notify('no symbols in this file yet', vim.log.levels.WARN)
      return
    end
    local items = {}
    for _, node in ipairs(flat) do
      items[#items + 1] = {
        name = node.name,
        label = symbols.label(node),
        kind = node.kind_name,
        indent = node.depth - 1,
        container = symbols.type_name(node.parent),
        path = path,
        range = node.selection,
        lnum = node.selection.start.line + 1,
      }
    end
    local picker = ui.open({
      title = 'Document Items',
      list_title = vim.fs.basename(path),
      hints = '<CR> jump',
      preview_item = open.preview,
      filter = function(query, all)
        if query == '' then
          return all
        end
        return rank.rank(query, all)
      end,
      format = format,
      on_accept = function(item, action)
        open.jump(item, action)
      end,
    })
    picker:set_items(items)
  end)
end

--- Reveal the current file in nvim-tree, like Shift-Cmd-J.
function M.reveal()
  local ok, tree = pcall(require, 'nvim-tree.api')
  if not ok then
    util.notify('nvim-tree is not available', vim.log.levels.WARN)
    return
  end
  tree.tree.open()
  tree.tree.find_file({ open = true, focus = true })
end

return M

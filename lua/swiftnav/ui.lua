local api = vim.api
local util = require('swiftnav.util')

local M = {}

local namespace = api.nvim_create_namespace('swiftnav.picker')
local current = nil

local Picker = {}
Picker.__index = Picker

local function geometry(picker)
  local columns, lines = vim.o.columns, vim.o.lines
  local available_width = math.max(20, columns - 5)
  local available_height = math.max(6, lines - 6)
  local width = util.clamp(math.floor(columns * 0.96), math.min(44, available_width), available_width)
  local height = util.clamp(math.floor(lines * 0.55), math.min(8, available_height), available_height)
  local list_width = picker.preview and math.floor(width * 0.48) or width
  return {
    width = width,
    height = height,
    list_width = list_width,
    preview_width = width - list_width - 3,
    row = math.max(0, math.floor((lines - height - 3) / 2)),
    col = math.max(0, math.floor((columns - width) / 2)),
  }
end

local function window_options(win, extra)
  local options = vim.tbl_extend('force', {
    wrap = false,
    spell = false,
    list = false,
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    cursorline = false,
    winhl = 'Normal:NormalFloat,FloatBorder:FloatBorder',
  }, extra or {})
  for name, value in pairs(options) do
    api.nvim_set_option_value(name, value, { win = win })
  end
end

local function buffer_options(buf, filetype)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  if filetype then
    vim.bo[buf].filetype = filetype
  end
end

function Picker:geometry()
  return geometry(self)
end

function Picker:query_text()
  return api.nvim_buf_get_lines(self.input_buf, 0, 1, false)[1] or ''
end

function Picker:set_status(text)
  self.status = text
  self:render()
end

function Picker:set_items(items, status)
  self.items = items or {}
  self.status = status
  self:render()
end

function Picker:visible_items()
  local items = self.items
  if self.opts.filter then
    items = self.opts.filter(self.query, items)
  end
  return items
end

function Picker:render()
  if self.closed then
    return
  end
  if not api.nvim_buf_is_valid(self.list_buf) then
    self:close()
    return
  end
  local g = self:geometry()
  local visible = self:visible_items()
  self.visible = visible
  local item_rows = g.height - 1
  self.sel = util.clamp(self.sel, 1, math.max(#visible, 1))

  local lines, marks = {}, {}
  for index = 1, math.min(#visible, item_rows) do
    local text, row_marks = self:format(visible[index], g.list_width - 2)
    lines[index] = text
    marks[index] = row_marks
  end
  if #lines == 0 then
    lines[1] = '  ' .. (self.status or (self.query ~= '' and 'no matches' or 'nothing to show'))
    marks[1] = { { 2, #lines[1], 'SwiftNavStatus' } }
  end
  for index = #lines + 1, item_rows do
    lines[index] = ''
  end
  local status_text = self:status_line(#visible, g.list_width - 2)
  lines[item_rows + 1] = status_text

  api.nvim_set_option_value('modifiable', true, { buf = self.list_buf })
  api.nvim_buf_set_lines(self.list_buf, 0, -1, false, lines)
  api.nvim_set_option_value('modifiable', false, { buf = self.list_buf })
  api.nvim_buf_clear_namespace(self.list_buf, namespace, 0, -1)

  for row, row_marks in pairs(marks) do
    for _, mark in ipairs(row_marks or {}) do
      local finish = math.min(mark[2], #(lines[row] or ''))
      if finish > mark[1] then
        api.nvim_buf_set_extmark(self.list_buf, namespace, row - 1, mark[1], {
          end_col = finish,
          hl_group = mark[3],
        })
      end
    end
  end

  api.nvim_buf_set_extmark(self.list_buf, namespace, item_rows, 0, {
    end_col = #status_text,
    hl_group = 'SwiftNavStatus',
  })

  if #visible > 0 then
    local row = self.sel
    api.nvim_buf_set_extmark(self.list_buf, namespace, row - 1, 0, {
      end_col = #lines[row],
      hl_group = 'SwiftNavSelection',
      priority = 200,
    })
    api.nvim_win_set_cursor(self.list_win, { row, 0 })
    self:show_preview(visible[row])
  else
    self:show_preview(nil)
  end
end

function Picker:status_line(count, width)
  local left = self.status or ''
  local right = string.format('%d / %d', math.min(count, self.sel or 0), count)
  if self.opts.hints then
    left = left ~= '' and (left .. '  ·  ' .. self.opts.hints) or self.opts.hints
  end
  local gap = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)
  if gap < 1 then
    left = util.fit(left, math.max(0, width - vim.fn.strdisplaywidth(right) - 1))
    gap = math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right))
  end
  return left .. string.rep(' ', gap) .. right
end

function Picker:format(item, width)
  if self.opts.format then
    local text, marks = self.opts.format(item, width)
    return text, marks or {}
  end
  return util.fit(item.text or item.name or '', width), {}
end

function Picker:show_preview(item)
  if not self.preview_buf or not api.nvim_buf_is_valid(self.preview_buf) then
    return
  end
  if self.opts.preview_item then
    self.opts.preview_item(item, self.preview_buf, self.preview_win)
    return
  end
  api.nvim_set_option_value('modifiable', true, { buf = self.preview_buf })
  if not item then
    api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, {})
  else
    api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, { '  ' .. (item.name or '') })
  end
  api.nvim_set_option_value('modifiable', false, { buf = self.preview_buf })
end

function Picker:move(delta)
  local total = #(self.visible or {})
  if total == 0 then
    return
  end
  self.sel = ((self.sel - 1 + delta) % total) + 1
  self:render()
end

function Picker:accept(action)
  local item = self.visible and self.visible[self.sel]
  if not item then
    return
  end
  local handler = self.opts.on_accept
  self:close()
  if handler then
    handler(item, action or 'edit')
  end
end

function Picker:close()
  if self.closed then
    return
  end
  self.closed = true
  pcall(vim.cmd, 'stopinsert')
  if current == self then
    current = nil
  end
  for _, win in ipairs({ self.preview_win, self.list_win, self.input_win }) do
    if win and api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end
  if self.augroup then
    pcall(api.nvim_del_augroup_by_id, self.augroup)
  end
  if self.opts.on_close then
    pcall(self.opts.on_close)
  end
end

function Picker:resize()
  if self.closed then
    return
  end
  local g = self:geometry()
  api.nvim_win_set_config(self.input_win, {
    relative = 'editor',
    width = g.width,
    height = 1,
    row = g.row,
    col = g.col,
  })
  api.nvim_win_set_config(self.list_win, {
    relative = 'editor',
    width = g.list_width,
    height = g.height,
    row = g.row + 3,
    col = g.col,
  })
  if self.preview_win and api.nvim_win_is_valid(self.preview_win) then
    api.nvim_win_set_config(self.preview_win, {
      relative = 'editor',
      width = g.preview_width,
      height = g.height,
      row = g.row + 3,
      col = g.col + g.list_width + 2,
    })
  end
  self:render()
end

function Picker:bind_keys()
  local function map(mode, lhs, rhs, description)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = self.input_buf,
      nowait = true,
      silent = true,
      desc = 'swiftnav: ' .. description,
    })
  end
  map('i', '<CR>', function() self:accept('edit') end, 'open')
  map('i', '<C-v>', function() self:accept('vsplit') end, 'open in vertical split')
  map('i', '<C-x>', function() self:accept('split') end, 'open in horizontal split')
  map('i', '<C-t>', function() self:accept('tab') end, 'open in tab')
  map('i', '<C-n>', function() self:move(1) end, 'next')
  map('i', '<C-p>', function() self:move(-1) end, 'previous')
  map('i', '<Down>', function() self:move(1) end, 'next')
  map('i', '<Up>', function() self:move(-1) end, 'previous')
  map('i', '<Tab>', function() self:move(1) end, 'next')
  map('i', '<S-Tab>', function() self:move(-1) end, 'previous')
  map('i', '<Esc>', function() self:close() end, 'close')
  map('i', '<C-c>', function() self:close() end, 'close')
  map('n', 'q', function() self:close() end, 'close')
  map('n', '<Esc>', function() self:close() end, 'close')
  map('n', '<CR>', function() self:accept('edit') end, 'open')
  map('n', 'j', function() self:move(1) end, 'next')
  map('n', 'k', function() self:move(-1) end, 'previous')
end

--- Open a floating picker. Options: title, hints, items, filter, format,
--- preview_item, on_accept, on_change, status, preview.
function M.open(opts)
  if current then
    current:close()
  end

  local picker = setmetatable({
    opts = opts,
    items = opts.items or {},
    query = '',
    sel = 1,
    status = opts.status,
    preview = opts.preview == true or opts.preview_item ~= nil,
  }, Picker)
  current = picker

  local g = picker:geometry()
  if g.preview_width < 20 then
    picker.preview = false
    g = picker:geometry()
  end
  picker.input_buf = api.nvim_create_buf(false, true)
  picker.list_buf = api.nvim_create_buf(false, true)
  buffer_options(picker.input_buf, 'swiftnav')
  buffer_options(picker.list_buf, 'swiftnav_list')
  api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { '' })

  picker.input_win = api.nvim_open_win(picker.input_buf, true, {
    relative = 'editor',
    width = g.width,
    height = 1,
    row = g.row,
    col = g.col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. (opts.title or 'Swift') .. ' ',
    title_pos = 'left',
    zindex = 60,
  })

  picker.list_win = api.nvim_open_win(picker.list_buf, false, {
    relative = 'editor',
    width = g.list_width,
    height = g.height,
    row = g.row + 3,
    col = g.col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. (opts.list_title or 'Results') .. ' ',
    title_pos = 'left',
    zindex = 60,
  })

  if picker.preview then
    picker.preview_buf = api.nvim_create_buf(false, true)
    buffer_options(picker.preview_buf, 'swiftnav_preview')
    picker.preview_win = api.nvim_open_win(picker.preview_buf, false, {
      relative = 'editor',
      width = g.preview_width,
      height = g.height,
      row = g.row + 3,
      col = g.col + g.list_width + 2,
      style = 'minimal',
      border = 'rounded',
      title = ' Preview ',
      title_pos = 'left',
      zindex = 60,
    })
    window_options(picker.preview_win, { cursorline = true })
  end

  window_options(picker.input_win)
  window_options(picker.list_win, { cursorline = false })

  picker:bind_keys()
  api.nvim_buf_attach(picker.input_buf, false, {
    on_lines = function()
      if picker.closed then
        return true
      end
      vim.schedule(function()
        if picker.closed then
          return
        end
        picker.query = picker:query_text()
        picker.sel = 1
        if picker.opts.on_change then
          picker.opts.on_change(picker.query, picker)
        end
        picker:render()
      end)
      return false
    end,
  })

  picker.augroup = api.nvim_create_augroup('SwiftNavPicker' .. picker.list_win, { clear = true })
  api.nvim_create_autocmd('VimResized', {
    group = picker.augroup,
    callback = function()
      picker:resize()
    end,
  })

  picker:render()
  vim.cmd('startinsert')

  if opts.prefill and opts.prefill ~= '' then
    api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { opts.prefill })
    api.nvim_win_set_cursor(picker.input_win, { 1, #opts.prefill })
  end

  return picker
end

return M

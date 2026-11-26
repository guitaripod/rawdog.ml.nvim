local M = {}

--- Report through the configured notifier with a stable prefix.
function M.notify(message, level)
  vim.notify('swiftnav: ' .. message, level or vim.log.levels.INFO)
end

--- Shrink an absolute path against the working directory when possible.
function M.relpath(path)
  local cwd = vim.fn.getcwd() .. '/'
  if vim.startswith(path, cwd) then
    return path:sub(#cwd + 1)
  end
  return vim.fn.fnamemodify(path, ':.')
end

--- Walk up from the buffer to the directory that owns a Package.swift.
function M.package_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local start = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  local hit = vim.fs.find('Package.swift', { path = start, upward = true })[1]
  return hit and vim.fs.dirname(hit) or nil
end

--- Decide whether Swift navigation should answer for this buffer.
function M.swift_context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype == 'swift' then
    return true
  end
  return M.package_root(bufnr) ~= nil
end

--- Read at most `last` lines of a file, tolerating missing files.
function M.read_lines(path, last)
  local ok, lines
  if last then
    ok, lines = pcall(vim.fn.readfile, path, '', last)
  else
    ok, lines = pcall(vim.fn.readfile, path)
  end
  if not ok then
    return nil
  end
  return lines
end

function M.basename(path)
  return path:match('[^/]+$') or path
end

function M.clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

--- Trim a single-line string.
function M.trim(text)
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Escape a string for use inside a statusline expression.
function M.statusline_escape(text)
  return (text:gsub('%%', '%%%%'))
end

--- Truncate to a display width, marking the cut with an ellipsis.
function M.fit(text, width)
  width = math.max(0, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local out = text
  while #out > 0 and vim.fn.strdisplaywidth(out .. '…') > width do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. '…'
end

return M

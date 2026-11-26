local client = require('swiftnav.client')
local util = require('swiftnav.util')

local M = {}

local cache = {}

local function uri_of(bufnr)
  return vim.uri_from_bufnr(bufnr)
end

local function contains(range, line, character)
  if not range then
    return false
  end
  local start, finish = range.start, range['end']
  if line < start.line or line > finish.line then
    return false
  end
  if line == start.line and character < start.character then
    return false
  end
  if line == finish.line and character > finish.character then
    return false
  end
  return true
end

local function to_node(raw, parent, depth)
  local range = raw.range or (raw.location and raw.location.range)
  local selection = raw.selectionRange or range
  local node = {
    name = raw.name,
    detail = raw.detail,
    kind = raw.kind,
    kind_name = vim.lsp.protocol.SymbolKind[raw.kind] or 'Unknown',
    range = range,
    selection = selection,
    children = {},
    parent = parent,
    depth = depth,
  }
  for _, child in ipairs(raw.children or {}) do
    node.children[#node.children + 1] = to_node(child, node, depth + 1)
  end
  return node
end

--- Fetch document symbols, reusing the answer until the buffer changes.
function M.for_buffer(bufnr, cb)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local hit = cache[bufnr]
  if hit and hit.tick == tick then
    cb(hit.tree)
    return
  end
  local sent = client.request(bufnr, 'textDocument/documentSymbol', {
    textDocument = { uri = uri_of(bufnr) },
  }, function(err, result)
    local tree = {}
    if not err and result then
      for _, raw in ipairs(result) do
        tree[#tree + 1] = to_node(raw, nil, 1)
      end
    end
    if #tree > 0 then
      cache[bufnr] = { tick = tick, tree = tree }
    end
    cb(tree)
  end)
  if not sent then
    cb({})
  end
end

function M.invalidate(bufnr)
  cache[bufnr] = nil
end

--- Depth-first traversal in document order.
function M.flatten(tree)
  local out = {}
  local function visit(nodes)
    for _, node in ipairs(nodes) do
      out[#out + 1] = node
      visit(node.children)
    end
  end
  visit(tree)
  return out
end

--- The chain of declarations enclosing a position, outermost first.
function M.chain(tree, line, character)
  local path = {}
  local function visit(nodes)
    for _, node in ipairs(nodes) do
      if contains(node.range, line, character) then
        path[#path + 1] = node
        visit(node.children)
        return
      end
    end
  end
  visit(tree)
  return path
end

--- The innermost declaration enclosing a position.
function M.enclosing(tree, line, character)
  local chain = M.chain(tree, line, character)
  return chain[#chain], chain
end

--- A short display label for one declaration.
function M.label(node)
  if node.kind == vim.lsp.protocol.SymbolKind.Constructor then
    local detail = node.detail and (' ' .. node.detail) or ''
    return 'init' .. detail
  end
  if node.kind_name == 'Method' or node.kind_name == 'Function' then
    return node.name:match('^[%w_]+') or node.name
  end
  return node.name
end

--- Name for the type that a node declares, if it declares one.
function M.type_name(node)
  if not node then
    return nil
  end
  local types = {
    Struct = true,
    Class = true,
    Enum = true,
    Protocol = true,
    Interface = true,
    Actor = true,
    Extension = true,
    TypeParameter = true,
  }
  return types[node.kind_name] and node.name or nil
end

vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufWritePost', 'LspAttach' }, {
  callback = function(event)
    if event.buf then
      M.invalidate(event.buf)
    end
  end,
})

return M

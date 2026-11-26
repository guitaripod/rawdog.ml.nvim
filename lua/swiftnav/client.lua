local M = {}

--- Find the client that should answer a Swift request for this buffer.
function M.pick(bufnr, method)
  local fallback
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == 'sourcekit' then
      return client
    end
    if not fallback and client:supports_method(method, bufnr) then
      fallback = client
    end
  end
  return fallback
end

--- Send one request, scheduling the callback on the main loop.
function M.request(bufnr, method, params, handler)
  local client = M.pick(bufnr, method)
  if not client or not client:supports_method(method, bufnr) then
    return false
  end
  client:request(method, params, function(err, result)
    vim.schedule(function()
      handler(err, result, client)
    end)
  end, bufnr)
  return true
end

return M

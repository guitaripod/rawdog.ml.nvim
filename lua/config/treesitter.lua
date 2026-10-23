local M = {}

local ensure_installed = {
  "swift",
  "go",
  "typescript",
  "javascript",
  "python",
  "rust",
  "lua",
}

local function install_missing()
  local installed = require("nvim-treesitter.config").get_installed()
  local missing = vim.iter(ensure_installed)
    :filter(function(parser)
      return not vim.tbl_contains(installed, parser)
    end)
    :totable()
  if #missing > 0 then
    require("nvim-treesitter").install(missing)
  end
end

local function enable_buffer_features()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("treesitter.features", { clear = true }),
    callback = function(args)
      if pcall(vim.treesitter.start, args.buf) then
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
  })
end

local selection = {}

local function reselect(srow, scol, erow, ecol)
  if vim.fn.mode():find("[vV\22]") then
    vim.cmd("normal! \27")
  end
  if ecol == 0 and erow > srow then
    erow = erow - 1
    ecol = #vim.api.nvim_buf_get_lines(0, erow, erow + 1, true)[1]
  end
  vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { erow + 1, math.max(ecol - 1, 0) })
end

function M.init_selection()
  local node = vim.treesitter.get_node()
  if not node then
    return
  end
  selection = { node }
  reselect(node:range())
end

function M.node_incremental()
  local node = selection[#selection]
  if not node then
    return M.init_selection()
  end
  local srow, scol, erow, ecol = node:range()
  local parent = node:parent()
  while parent do
    local a, b, c, d = parent:range()
    if a ~= srow or b ~= scol or c ~= erow or d ~= ecol then
      break
    end
    parent = parent:parent()
  end
  if not parent then
    return
  end
  table.insert(selection, parent)
  reselect(parent:range())
end

function M.node_decremental()
  if #selection <= 1 then
    return
  end
  table.remove(selection)
  reselect(selection[#selection]:range())
end

function M.setup()
  require("nvim-treesitter").setup({})
  install_missing()
  enable_buffer_features()

  local map = vim.keymap.set
  map("n", "<C-space>", M.init_selection, { desc = "Treesitter: start selection" })
  map("x", "<C-space>", M.node_incremental, { desc = "Treesitter: expand selection" })
  map("x", "<C-BS>", M.node_decremental, { desc = "Treesitter: shrink selection" })
end

return M

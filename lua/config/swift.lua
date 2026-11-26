local M = {}

local api = vim.api

local EFM = table.concat({
  [=[✘ Test "%*[^"]" recorded an issue at %f:%l:%c: %m]=],
  [=[%f:%l:%c: %t%*[^:]: %m]=],
  [=[%f:%l: %t%*[^:]: %m]=],
  [=[%-G%.%#]=],
}, ",")

local last_output = {}
local running = nil

local function package_root()
  local name = api.nvim_buf_get_name(api.nvim_get_current_buf())
  local start = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  local hit = vim.fs.find("Package.swift", { path = start, upward = true })[1]
  return hit and vim.fs.dirname(hit) or vim.fn.getcwd()
end

local function strip_ansi(text)
  return (text:gsub("\27%[[%d;]*m", ""))
end

local function resolve_files(lines, root)
  for i, line in ipairs(lines) do
    local prefix, file, tail = line:match("^(.-)([%w_%-%.]+%.swift):(%d+:%d+: .*)$")
    local path = prefix and (prefix .. file)
    if path and not vim.startswith(path, "/") then
      local abs
      if prefix:match("^[%w_%-%./]*$") and vim.uv.fs_stat(root .. "/" .. path) then
        abs = root .. "/" .. path
      else
        abs = vim.fs.find(file, { path = root, type = "file" })[1]
      end
      if abs then
        local path_like = prefix:match("^[%w_%-%./]*$") ~= nil
        local needle = path_like and path or file
        local start, finish = line:find(needle, 1, true)
        if start then
          lines[i] = line:sub(1, start - 1) .. abs .. line:sub(finish + 1)
        end
      end
    end
  end
  return lines
end

local function set_quickfix(lines, root, title)
  vim.fn.setqflist({}, " ", { lines = resolve_files(lines, root), efm = EFM, title = title })
  return #vim.fn.getqflist()
end

local function summarize(lines)
  for i = #lines, 1, -1 do
    local line = lines[i]
    local hit = line:match("Test run with %d+.*") or line:match("Executed %d+.*")
    if hit then
      return (hit:gsub("%s+$", ""))
    end
  end
end

local function run(cmd, title)
  if running then
    vim.notify(("swift: %s is still running"):format(running), vim.log.levels.WARN)
    return
  end
  local root = package_root()
  local chunks = {}
  local function collect(_, data)
    if data then
      chunks[#chunks + 1] = data
    end
  end
  running = title
  local started = vim.uv.hrtime()
  vim.system(cmd, { cwd = root, text = true, stdout = collect, stderr = collect }, function(obj)
    vim.schedule(function()
      running = nil
      local lines = vim.split(strip_ansi(table.concat(chunks)), "\n", { plain = true, trimempty = true })
      last_output = lines
      local count = set_quickfix(lines, root, title)
      local seconds = (vim.uv.hrtime() - started) / 1e9
      local summary = summarize(lines)
      if count > 0 then
        vim.cmd("botright copen 10")
        vim.notify(
          ("%s: %d problem%s in %.1fs"):format(title, count, count == 1 and "" or "s", seconds),
          vim.log.levels.WARN
        )
      else
        vim.notify(
          ("%s: %s (%.1fs)"):format(title, summary or (obj.code == 0 and "ok" or "failed"), seconds),
          obj.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
        )
      end
    end)
  end)
end

function M.build(extra)
  run(vim.list_extend({ "swift", "build", "--no-color-diagnostics" }, extra or {}), "swift build")
end

function M.test(filter)
  local cmd = { "swift", "test", "--no-color-diagnostics" }
  if filter and filter ~= "" then
    vim.list_extend(cmd, { "--filter", filter })
  end
  run(cmd, filter and filter ~= "" and ("swift test --filter " .. filter) or "swift test")
end

function M.run(extra)
  local cmd = { "swift", "run", "--no-color-diagnostics" }
  vim.list_extend(cmd, extra or {})
  vim.cmd("botright split")
  vim.fn.termopen(cmd, { cwd = package_root() })
  vim.cmd("startinsert")
end

function M.log()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, last_output)
  vim.bo[buf].bufhidden = "wipe"
  vim.cmd("botright split")
  api.nvim_win_set_buf(0, buf)
end

local function nearest_test()
  local lines = api.nvim_buf_get_lines(0, 0, -1, false)
  local row = api.nvim_win_get_cursor(0)[1]
  local name, index
  for i = row, 1, -1 do
    name = lines[i]:match("^%s*func%s+([%w_]+)%s*%(")
    if name then
      index = i
      break
    end
  end
  if not name then
    return nil
  end
  local container, xctest
  for i = index - 1, 1, -1 do
    if lines[i]:match("XCTestCase") then
      xctest = true
    end
    local found = lines[i]:match("^%s*final%s+class%s+([%w_]+)")
      or lines[i]:match("^%s*class%s+([%w_]+)")
      or lines[i]:match("^%s*struct%s+([%w_]+)")
      or lines[i]:match("^%s*actor%s+([%w_]+)")
    if found then
      container = found
      break
    end
  end
  if container and xctest then
    return container .. "." .. name
  elseif container then
    return container .. "/" .. name
  end
  return name
end

function M.test_nearest()
  local filter = nearest_test()
  if not filter then
    vim.notify("swift: no test under the cursor", vim.log.levels.WARN)
    return
  end
  M.test(filter)
end

function M.executable()
  local out = vim.system({ "swift", "build", "--show-bin-path" }, { cwd = package_root(), text = true }):wait()
  local dir = vim.trim(out.stdout or "")
  if dir == "" then
    return nil
  end
  local candidates = {}
  for entry, kind in vim.fs.dir(dir) do
    if kind == "file" and not entry:match("%.") and not entry:match("test%-runner$") then
      local path = dir .. "/" .. entry
      if vim.fn.executable(path) == 1 then
        candidates[#candidates + 1] = path
      end
    end
  end
  table.sort(candidates)
  return candidates
end

function M.setup()
  api.nvim_create_user_command("SwiftBuild", function(opts)
    M.build(opts.fargs)
  end, { nargs = "*", desc = "swift build (quickfix)" })
  api.nvim_create_user_command("SwiftTest", function(opts)
    M.test(opts.args)
  end, { nargs = "?", desc = "swift test [--filter regex]" })
  api.nvim_create_user_command("SwiftTestNearest", M.test_nearest, { desc = "swift test --filter <test under cursor>" })
  api.nvim_create_user_command("SwiftRun", function(opts)
    M.run(opts.fargs)
  end, { nargs = "*", desc = "swift run [executable] [args]" })
  api.nvim_create_user_command("SwiftLog", M.log, { desc = "Show last swift output" })

  vim.keymap.set("n", "<leader>sb", "<cmd>SwiftBuild<cr>", { desc = "Swift build" })
  vim.keymap.set("n", "<leader>st", "<cmd>SwiftTest<cr>", { desc = "Swift test" })
  vim.keymap.set("n", "<leader>sT", "<cmd>SwiftTestNearest<cr>", { desc = "Swift test nearest" })
  vim.keymap.set("n", "<leader>sr", "<cmd>SwiftRun<cr>", { desc = "Swift run" })
  vim.keymap.set("n", "<leader>sl", "<cmd>SwiftLog<cr>", { desc = "Swift log" })

  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  if vim.fn.has("linux") == 1 then
    dap.adapters.lldb = {
      type = "executable",
      command = vim.fn.expand("~/.local/bin/lldb-dap-swift"),
      args = {},
      name = "lldb",
    }
  end
  dap.configurations.swift = {
    {
      name = "Launch executable",
      type = vim.fn.has("linux") == 1 and "lldb" or "codelldb",
      request = "launch",
      program = function()
        local candidates = M.executable() or {}
        if #candidates > 1 then
          local choices = {}
          for i, path in ipairs(candidates) do
            choices[i] = ("%d. %s"):format(i, vim.fs.basename(path))
          end
          local choice = vim.fn.inputlist(choices)
          if choice >= 1 and choice <= #candidates then
            return candidates[choice]
          end
        end
        return candidates[1] or vim.fn.input("Program: ", vim.fn.getcwd() .. "/", "file")
      end,
      args = {},
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
    },
  }
end

return M

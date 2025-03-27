local config = require("drop.config")

local M = {}

---@type vim.loop.Timer?
M.timer = nil

---@class Drop
---@field symbol string
---@field hl_group string
---@field row integer
---@field col integer
---@field buf? integer
---@field speed integer
---@field id? integer
---@field tail_positions table<integer, {row: number, col: number}>
---@field tail_length integer
local Drop = {}
Drop.__index = Drop

---@type table<integer, Drop>
Drop.drops = {}

function Drop.new(buf)
  local self = setmetatable({}, Drop)
  self.buf = buf
  self.id = nil
  self.tail_positions = {}
  self:init()
  return self
end

function Drop:init()
  local theme = config.get_theme()
  ---@type string[]
  local symbols = vim.tbl_map(function(symbol)
    return type(symbol) == "function" and symbol() or symbol
  end, theme.symbols)
  local colors = vim.tbl_keys(theme.colors)

  self.symbol = symbols[math.random(1, #symbols)]
  self.hl_group = "Drop" .. math.random(1, #colors) .. (math.random(1, 3) == 1 and "Bold" or "")
  self.row = 0
  self.col = math.random(0, vim.go.columns - vim.fn.strwidth(self.symbol))
  self.speed = math.random(1, 2)
  self.tail_positions = {}

  local base = config.options.tail_length or 10
  local delta = config.options.tail_delta or 0
  local offset = delta > 0 and math.random(math.max(-delta, -base), delta) or 0
  self.tail_length = base + offset


end

function Drop:show()
  -- Draw the tail if enabled
  if config.options.tail then
    for i, pos in ipairs(self.tail_positions) do
      -- Only draw tail if position is within valid range
      if pos.row >= 0 and pos.row < vim.go.lines and pos.col >= 0 and pos.col < vim.go.columns then
        local tail_hl = self.hl_group .. "Tail"  -- Example: adjust as needed
        vim.api.nvim_buf_set_extmark(self.buf, config.ns, math.floor(pos.row), 0, {
          virt_text = { { self.symbol, tail_hl } },
          virt_text_win_col = pos.col,
          virt_text_pos = "overlay",
        })
      end
    end
  end
  
  -- Only draw drop if position is within valid range
  if self.row >= 0 and self.row < vim.go.lines and self.col >= 0 and self.col < vim.go.columns then
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, self.buf, config.ns, math.floor(self.row), 0, {
      virt_text = { { self.symbol, self.hl_group } },
      virt_text_win_col = self.col,
      id = self.id,
    })
    if ok then
      self.id = id
    else
      self:init()
    end
  end
end

function Drop:is_visible()
  return self.col >= 0 and (self.col <= vim.go.columns - vim.fn.strwidth(self.symbol)) and self.row >= 0 and self.row < vim.go.lines
end

function Drop:update()
  -- Update tail length over time
  if config.options.tail_delta and config.options.tail_dynamic then
    local base = self.tail_length
    local delta = config.options.tail_delta
    -- Adjust tail length with a slight random offset each update.
    local offset = delta > 0 and math.random(math.max(-delta, -base), delta) or 0
    self.tail_length = base + offset
  end

  -- Update drop position
  local dx = math.random(0, 2) - 1
  self.row = self.row + self.speed * 0.5
  if math.floor(self.row) == self.row then
    local new_col = self.col + dx
    -- Only update column if it would be in valid range
    if new_col >= 0 and new_col < vim.go.columns - vim.fn.strwidth(self.symbol) then
      self.col = new_col
    end
  end

  -- Update tail positions only if tail is enabled
  if config.options.tail then
    table.insert(self.tail_positions, 1, { row = self.row, col = self.col })
    if #self.tail_positions > self.tail_length then
      table.remove(self.tail_positions)
    end
  end

  if not self:is_visible() then
    self:init()
  end

  self:show()
end

M.ticks = 0
M.buf = nil
M.win = nil

function M.show()
  if M.timer then
    return
  end
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, vim.split(string.rep("\n", vim.go.lines), "\n"))

  M.win = vim.api.nvim_open_win(M.buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.go.columns,
    height = vim.go.lines,
    focusable = false,
    zindex = 10,
    style = "minimal",
    noautocmd = true,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      if not M.buf then
        return true
      end
      vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, vim.split(string.rep("\n", vim.go.lines), "\n"))
      vim.api.nvim_win_set_config(M.win, {
        relative = "editor",
        row = 0,
        col = 0,
        width = vim.go.columns,
        height = vim.go.lines,
      })
    end,
  })
  vim.wo[M.win].winhighlight = "NormalFloat:Drop"
  vim.wo[M.win].winblend = config.options.winblend
  M.ticks = 0
  M.timer = vim.loop.new_timer()
  M.timer:start(0, config.options.interval, vim.schedule_wrap(M.update))
end

function M.update()
  if M.timer == nil then
    return
  end

  -- Clear previous extmarks
  vim.api.nvim_buf_clear_namespace(M.buf, config.ns, 0, -1)

  M.ticks = M.ticks + 1
  local pct = math.min(vim.go.lines, M.ticks) / vim.go.lines
  local _target = pct * config.options.max
  vim.go.lazyredraw = true
  while #Drop.drops < _target * math.random(80, 100) / 100 do
    table.insert(Drop.drops, Drop.new(M.buf))
  end

  for _, drop in ipairs(Drop.drops) do
    drop:update()
  end
  vim.go.lazyredraw = false
  vim.cmd.redraw()
end

function M.hide()
  if not M.timer then
    return
  end
  vim.schedule(function()
    if not M.timer then
      return
    end
    M.timer:stop()
    M.timer = nil
    pcall(vim.api.nvim_buf_delete, M.buf, { force = true })
    pcall(vim.api.nvim_win_close, M.win, true)
    M.win = nil
    M.buf = nil
    Drop.drops = {}
  end)
end

return M

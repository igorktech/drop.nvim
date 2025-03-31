local M = {}

---@param opts? RainConfig
function M.setup(opts)
  require("rain.config").setup(opts)
end

function M.show()
  require("rain.rain").show()
end

function M.hide()
  require("rain.rain").hide()
end

function M.calculate_easter(year)
  return require("rain.config").calculate_easter(year)
end

function M.calculate_us_thanksgiving(year)
  return require("rain.config").calculate_us_thanksgiving(year)
end

return M

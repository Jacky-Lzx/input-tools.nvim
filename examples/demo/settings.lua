-- A small configuration used by the interactive examples.
local config = {
  project = "Observatory",
  timeout_ms = 1200,
  retries = 3,
}

local function describe()
  return string.format("%s: %d ms", config.project, config.timeout_ms)
end

print(describe())

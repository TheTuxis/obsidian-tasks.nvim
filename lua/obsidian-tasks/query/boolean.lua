local M = {}

-- Tokenize a boolean filter expression into a list of tokens.
-- Token types: LPAREN, RPAREN, AND, OR, NOT, XOR, FILTER
local function tokenize(s)
  local tokens = {}
  local i = 1
  local n = #s

  local function skip_ws()
    while i <= n and s:sub(i, i):match("^%s$") do i = i + 1 end
  end

  local function is_word_boundary(pos)
    if pos > n then return true end
    local c = s:sub(pos, pos)
    return c:match("^[%s%(]$") ~= nil
  end

  while i <= n do
    skip_ws()
    if i > n then break end

    local c = s:sub(i, i)

    if c == "(" then
      table.insert(tokens, { type = "LPAREN" })
      i = i + 1
    elseif c == ")" then
      table.insert(tokens, { type = "RPAREN" })
      i = i + 1
    else
      -- Try to match a boolean keyword (case-insensitive)
      local upper = s:upper()
      local matched_kw = nil
      local kw_len = 0

      for _, kw in ipairs({ "AND", "XOR", "NOT", "OR" }) do
        local len = #kw
        if upper:sub(i, i + len - 1) == kw and is_word_boundary(i + len) then
          matched_kw = kw
          kw_len = len
          break
        end
      end

      if matched_kw then
        table.insert(tokens, { type = matched_kw })
        i = i + kw_len
      else
        -- Accumulate filter text until next paren or keyword
        local start = i
        while i <= n do
          local ch = s:sub(i, i)
          if ch == "(" or ch == ")" then break end
          -- Check if a keyword starts here
          local u = s:upper()
          local kw_here = false
          for _, kw in ipairs({ "AND", "XOR", "NOT", "OR" }) do
            local len = #kw
            if u:sub(i, i + len - 1) == kw and is_word_boundary(i + len) then
              -- Only treat as keyword if preceded by whitespace (or start)
              if i == start or s:sub(i - 1, i - 1):match("^%s$") then
                kw_here = true
                break
              end
            end
          end
          if kw_here then break end
          i = i + 1
        end
        local text = vim.trim(s:sub(start, i - 1))
        if text ~= "" then
          table.insert(tokens, { type = "FILTER", text = text })
        end
      end
    end
  end

  return tokens
end

-- Detect whether a line should be parsed as a boolean expression.
-- Avoids false positives like "description does not include X".
function M.is_boolean(line)
  local trimmed = vim.trim(line)

  -- Starts with ( or NOT
  if trimmed:match("^%(") then return true end
  if trimmed:upper():match("^NOT[%s%(]") then return true end

  -- Contains AND / OR / XOR at parenthesis depth 0
  local depth = 0
  local i = 1
  local n = #trimmed
  local upper = trimmed:upper()

  while i <= n do
    local c = trimmed:sub(i, i)
    if c == "(" then
      depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
    elseif depth == 0 then
      for _, kw in ipairs({ "AND", "XOR", "OR" }) do
        local len = #kw
        -- keyword must be preceded and followed by whitespace or parens
        local before_ok = i == 1 or trimmed:sub(i - 1, i - 1):match("^[%s%)]$")
        local after_ok  = i + len > n or trimmed:sub(i + len, i + len):match("^[%s%(]$")
        if before_ok and upper:sub(i, i + len - 1) == kw and after_ok then
          return true
        end
      end
    end
    i = i + 1
  end

  return false
end

-- Parse a boolean filter expression.
-- filter_fn: function(text) → predicate | nil   (the plain filter parser)
-- Returns: fn, errors
--   fn     — function(task) → bool, or nil if parse failed entirely
--   errors — list of strings for unrecognised inner filters
function M.parse(line, filter_fn)
  local toks = tokenize(line)
  local pos   = 1
  local errors = {}

  local function peek() return toks[pos] end
  local function consume() local t = toks[pos]; pos = pos + 1; return t end

  local parse_expr -- forward declaration

  local function parse_atom()
    local t = peek()
    if not t then return nil end

    if t.type == "LPAREN" then
      consume() -- (
      local fn = parse_expr()
      local closing = peek()
      if closing and closing.type == "RPAREN" then
        consume()
      end
      return fn
    elseif t.type == "FILTER" then
      consume()
      local fn = filter_fn(t.text)
      if not fn then
        table.insert(errors, "Unrecognized filter: " .. t.text)
        return function() return false end
      end
      return fn
    end

    return nil
  end

  local function parse_not()
    if peek() and peek().type == "NOT" then
      consume()
      local fn = parse_not()
      if not fn then return nil end
      return function(task) return not fn(task) end
    end
    return parse_atom()
  end

  local function parse_and()
    local left = parse_not()
    while peek() and peek().type == "AND" do
      consume()
      local right = parse_not()
      if right then
        local l, r = left, right
        left = function(task) return l(task) and r(task) end
      end
    end
    return left
  end

  local function parse_xor()
    local left = parse_and()
    while peek() and peek().type == "XOR" do
      consume()
      local right = parse_and()
      if right then
        local l, r = left, right
        left = function(task) return (l(task) and not r(task)) or (not l(task) and r(task)) end
      end
    end
    return left
  end

  local function parse_or()
    local left = parse_xor()
    while peek() and peek().type == "OR" do
      consume()
      local right = parse_xor()
      if right then
        local l, r = left, right
        left = function(task) return l(task) or r(task) end
      end
    end
    return left
  end

  parse_expr = parse_or

  local ok, result = pcall(parse_expr)
  if not ok or not result then
    return nil, { "Malformed boolean expression: " .. line }
  end

  return result, errors
end

return M

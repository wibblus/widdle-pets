--[[ coopdx has a clamp function wahoo
---@param n number
---@param a number
---@param b number
---@return number
function clamp(n, a, b)
    if n < a then return a
    elseif n > b then return b
    else return n end
end
]]

local DEFAULT_NAMESPACE = vim.api.nvim_create_namespace("simple_color_highlight")
local HIGHLIGHT_NAME_PREFIX = "sch"
local HIGHLIGHT_CACHE = {}

local R_BYTE  = ("r"):byte()
local R_BYTE2 = ("R"):byte()
local G_BYTE  = ("g"):byte()
local G_BYTE2 = ("G"):byte()
local B_BYTE  = ("b"):byte()
local B_BYTE2 = ("B"):byte()
local A_BYTE  = ("a"):byte()
local A_BYTE2 = ("A"):byte()

local O_BYTE  = ("o"):byte()
local O_BYTE2 = ("O"):byte()
local K_BYTE  = ("k"):byte()
local K_BYTE2 = ("K"):byte()
local L_BYTE  = ("l"):byte()
local L_BYTE2 = ("L"):byte()
local C_BYTE  = ("c"):byte()
local C_BYTE2 = ("C"):byte()
local H_BYTE  = ("h"):byte()
local H_BYTE2 = ("H"):byte()

local HASHTAG_BYTE       = ("#"):byte()
local PERCENT_BYTE       = ("%"):byte()
local BRACKET_OPEN_BYTE  = ("("):byte()
local BRACKET_CLOSE_BYTE = (")"):byte()
local COMMA_BYTE         = (","):byte()
local PERIOD_BYTE        = ("."):byte()
local MINUS_BYTE         = ("-"):byte()
local SLASH_BYTE         = ("/"):byte()

local OKLCH_FUNC_MIN_LEN = #"oklch(x x x)"

local RGB_FUNC_MIN_LEN = #"rgb(1,1,1)"

local RGB_HEX_MIN_LEN = #"123"
local RGB_HEX_MID_LEN = #"112233"
local RGB_HEX_MAX_LEN = #"11223344"

local function color_is_bright(r, g, b)

    -- Ref: https://stackoverflow.com/a/1855903/837964
    -- https://stackoverflow.com/questions/596216/formula-to-determine-brightness-of-rgb-color
	local luminance = (0.299*r + 0.587*g + 0.114*b)/255

    return luminance > 0.5
end

local function to_hex(r, g, b)
    return string.format("%02X%02x%02x", r, g, b)
end

local function byte_is_whitespace(b)
    return b == 32 or b == 9
end

local function byte_is_number(b)
    return b >= 48 and b <= 57
end

local function byte_is_hex(byte)
    return (byte >= 48 and byte <= 57)  -- 0-9
        or (byte >= 65 and byte <= 70)  -- A-F
        or (byte >= 97 and byte <= 102) -- a-f
end

local function linear_to_srgb(c)
    if c <= 0 then c = 0 end
    if c >= 1 then c = 1 end
    if c <= 0.0031308 then
        return c * 12.92
    else
        return 1.055 * (c ^ (1/2.4)) - 0.055
    end
end

-- See https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/color_value/oklch
-- Targeting Absolute value syntax only
local function oklch_function_parser(line, i)
    local length = #line - i
    if length < OKLCH_FUNC_MIN_LEN then
        return
    end

    local matchStart = i

    do
        -- Check the oklch header
        local b;
        b = line:byte(i); i = i + 1; if b ~= O_BYTE and b ~= O_BYTE2 then return end
        b = line:byte(i); i = i + 1; if b ~= K_BYTE and b ~= K_BYTE2 then return end
        b = line:byte(i); i = i + 1; if b ~= L_BYTE and b ~= L_BYTE2 then return end
        b = line:byte(i); i = i + 1; if b ~= C_BYTE and b ~= C_BYTE2 then return end
        b = line:byte(i); i = i + 1; if b ~= H_BYTE and b ~= H_BYTE2 then return end

        -- whitespace
        while i <= #line and byte_is_whitespace(line:byte(i)) do i = i + 1 end

        -- open bracket
        if line:byte(i) ~= BRACKET_OPEN_BYTE then
            return
        end

        i = i + 1
    end

    local numbers = {}

    for idx = 1, 4 do

        -- whitespace
        while i <= #line and byte_is_whitespace(line:byte(i)) do i = i + 1 end

        -- parse number (int or float)
        local num_start = i
        local first = true
        while i <= #line do
            local b = line:byte(i)
            if byte_is_number(b) or b == PERIOD_BYTE then
                i = i + 1
            elseif first and b == MINUS_BYTE then
                i = i + 1
                first = false
            else
                break
            end
        end

        if num_start == i then
            return
        end

        local num = tonumber(line:sub(num_start, i - 1))

        if not num then
            return
        end

        -- skip whitespace
        while i <= #line and byte_is_whitespace(line:byte(i)) do i = i + 1 end

        -- handle % symbol after first or second number
        if (idx == 1 or idx == 2) and line:byte(i) == PERCENT_BYTE then
            num = num / 100
            i = i + 1
        end

        numbers[idx] = num

        -- handle the / symbol for possible alpha channel
        if (idx == 3) then

            -- skip whitespace
            while i <= #line and byte_is_whitespace(line:byte(i)) do i = i + 1 end

            if line:byte(i) == SLASH_BYTE then
                i = i + 1
            else
                break
            end
        end
    end

    -- skip whitespace
    while i <= #line and byte_is_whitespace(line:byte(i)) do i = i + 1 end

    -- expect ')'
    if line:byte(i) ~= BRACKET_CLOSE_BYTE then
        return
    end

    local L, C, H = numbers[1], numbers[2], numbers[3]

    if C < 0 then
        C = 0
    end

    -- Convert degrees to radians
    local H_rad = math.rad(H)

    -- OKLCH -> OKLab
    local a = C * math.cos(H_rad)
    local b = C * math.sin(H_rad)
    local l = L

    -- OKLab -> linear RGB
    local l_ = l + 0.3963377774 * a + 0.2158037573 * b
    local m_ = l - 0.1055613458 * a - 0.0638541728 * b
    local s_ = l - 0.0894841775 * a - 1.2914855480 * b

    local l_3 = l_ * l_ * l_
    local m_3 = m_ * m_ * m_
    local s_3 = s_ * s_ * s_

    local r_lin =  4.0767416621 * l_3 - 3.3077115913 * m_3 + 0.2309699292 * s_3
    local g_lin = -1.2684380046 * l_3 + 2.6097574011 * m_3 - 0.3413193965 * s_3
    local b_lin = -0.0041960863 * l_3 - 0.7034186147 * m_3 + 1.7076147010 * s_3

    local hex_string = to_hex(
        math.floor(linear_to_srgb(r_lin) * 255 + 0.5), -- r
        math.floor(linear_to_srgb(g_lin) * 255 + 0.5), -- g
        math.floor(linear_to_srgb(b_lin) * 255 + 0.5)  -- b
    )

    return i - matchStart, hex_string
end

local function rgb_hex_parser(line, i)

    local max_loop = math.min(RGB_HEX_MAX_LEN, #line - i)
    local hex_len = 0

    if (max_loop < RGB_HEX_MIN_LEN) or (i + RGB_HEX_MIN_LEN > #line) then
        return
    end

	if line:byte(i) ~= HASHTAG_BYTE then
		return
	end

    i = i + 1

	while hex_len < max_loop do

		local b = line:byte(i + hex_len)

		if not byte_is_hex(b) then
            break
        end

        hex_len = hex_len + 1
	end

    if hex_len ~= RGB_HEX_MIN_LEN and hex_len ~= RGB_HEX_MID_LEN and hex_len ~= RGB_HEX_MAX_LEN then
        return
    end

	return hex_len, line:sub(i, i + hex_len - 1)
end


local function rgb_function_parser(line, i)

    local length = #line - i

    if length < RGB_FUNC_MIN_LEN then
        return
    end

    -- check rgb header
    local b;
    b = line:byte(i); i = i + 1; if b ~= R_BYTE and b ~= R_BYTE2 then return end
    b = line:byte(i); i = i + 1; if b ~= G_BYTE and b ~= G_BYTE2 then return end
    b = line:byte(i); i = i + 1; if b ~= B_BYTE and b ~= B_BYTE2 then return end

    local a = line:byte(i)
    local isRGBA = a == A_BYTE or a == A_BYTE2

    local token = 1
    local tokens = {
        BRACKET_OPEN_BYTE,
        0,
        COMMA_BYTE,
        0,
        COMMA_BYTE,
        0,
        COMMA_BYTE,
        0,
        BRACKET_CLOSE_BYTE
    }

    if isRGBA then
        i = i + 1
    else
        tokens[7] = BRACKET_CLOSE_BYTE
    end

    local j = 0

	while j < length do

        local index = i + j
		local byte = line:byte(index)

        if byte_is_whitespace(byte) then
            j = j + 1
            goto continue
        end

        local search = tokens[token]

        if search == 0 then
            -- match number and put number into tokens[token]

            local num_end = index

            while num_end <= #line and byte_is_number(line:byte(num_end)) do
                num_end = num_end + 1
            end

            if num_end == index then
                return
            end

            local num = tonumber(line:sub(index, num_end - 1))

            if num > 255 then
                return
            end

            tokens[token] = num

            j = j + (num_end - index)
            token = token + 1

        elseif byte == search then

            j = j + 1
            token = token + 1

            if search == BRACKET_CLOSE_BYTE then
                break
            end
        else
            return
        end

        ::continue::
	end

    -- stupid hack to not have to write more lua
    local hex_string = to_hex(tokens[2], tokens[4], tokens[6])

    return i + j, hex_string
end

local function make_highlight_name(rgb)
	return table.concat({HIGHLIGHT_NAME_PREFIX, rgb}, '_')
end

local function create_highlight(rgb_hex)

	rgb_hex = rgb_hex:lower()

    local highlight_name = HIGHLIGHT_CACHE[rgb_hex]

    if highlight_name then
        return highlight_name
    end

    highlight_name = make_highlight_name(rgb_hex)
    HIGHLIGHT_CACHE[rgb_hex] = highlight_name

    if #rgb_hex == RGB_HEX_MIN_LEN then

        rgb_hex = table.concat {
            rgb_hex:sub(1,1):rep(2);
            rgb_hex:sub(2,2):rep(2);
            rgb_hex:sub(3,3):rep(2);
        }

    elseif #rgb_hex == RGB_HEX_MAX_LEN then

        rgb_hex = rgb_hex:sub(1,6)
    end

    local r = tonumber(rgb_hex:sub(1, 2), 16)
    local g = tonumber(rgb_hex:sub(3, 4), 16)
    local b = tonumber(rgb_hex:sub(5, 6), 16)
    local fg_color

    if color_is_bright(r, g, b) then
        fg_color = "Black"
    else
        fg_color = "White"
    end

    vim.api.nvim_command(table.concat({"highlight", highlight_name, "guifg="..fg_color, "guibg=#"..rgb_hex}, " "))

	return highlight_name
end


local function highlight_buffer(buf, ns, lines, line_start, clear)

	ns = ns or DEFAULT_NAMESPACE

    if clear then
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end

    for line_number, line in ipairs(lines) do

		line_number = line_number - 1 + line_start

        local i = 0

        while i < #line do

            local length, rgb_hex = rgb_hex_parser(line, i)

            if not length then
                length, rgb_hex = rgb_function_parser(line, i)
            end

            if not length then
                length, rgb_hex = oklch_function_parser(line, i)
            end

            if length then

                local highlight_name = create_highlight(rgb_hex)

                vim.api.nvim_buf_add_highlight(buf, ns, highlight_name, line_number - 1, i - 1, i + length)

                i = i + length

            else

                i = i + 1
            end

        end
    end
end


local function highlight_all(buffer)

    local row_min = 0
    local row_max = -1
    local lines = vim.api.nvim_buf_get_lines(buffer, row_min, row_max, false)

    highlight_buffer(buffer, DEFAULT_NAMESPACE, lines, row_min + 1, true)
end


local function highlight_view(buffer, screen_height)

    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local row_min = math.max(0, cursor_row - screen_height)
    local row_max = cursor_row + screen_height
    local lines = vim.api.nvim_buf_get_lines(buffer, row_min, row_max, false)

    highlight_buffer(buffer, DEFAULT_NAMESPACE, lines, row_min + 1, true)
end


local function highlight_clear(buffer)

    highlight_buffer(buffer, DEFAULT_NAMESPACE, {}, 0, true)
end

return {
    highlight_all= highlight_all,
    highlight_view= highlight_view,
    highlight_clear= highlight_clear,
}




local DEFAULT_NAMESPACE = vim.api.nvim_create_namespace("simple_color_highlight")
local HIGHLIGHT_NAME_PREFIX = "sch"
local HIGHLIGHT_CACHE = {}

local HASHTAG_BYTE = ("#"):byte()
local R_BYTE  = ("r"):byte()
local R_BYTE2 = ("R"):byte()
local G_BYTE  = ("g"):byte()
local G_BYTE2 = ("G"):byte()
local B_BYTE  = ("b"):byte()
local B_BYTE2 = ("B"):byte()
local A_BYTE  = ("a"):byte()
local A_BYTE2 = ("A"):byte()
local BRACKET_OPEN_BYTE  = ("("):byte()
local BRACKET_CLOSE_BYTE = (")"):byte()
local COMMA_BYTE = (","):byte()

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

local RGB_MIN_LEN = 3
local RGB_MID_LEN = 6
local RGB_MAX_LEN = 8

local function rgb_hex_parser(line, i)

    local max_loop = math.min(RGB_MAX_LEN, #line - i)
    local hex_len = 0

    if (max_loop < RGB_MIN_LEN) or (i + RGB_MIN_LEN > #line) then
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

    if hex_len ~= RGB_MIN_LEN and hex_len ~= RGB_MID_LEN and hex_len ~= RGB_MAX_LEN then
        return
    end

	return hex_len, line:sub(i, i + hex_len - 1)
end

local RGB_FUNC_MIN_LEN = #"rgb(1,1,1)"

local function rgb_function_parser(line, i)

    local length = #line - i

    if length < RGB_FUNC_MIN_LEN then
        return
    end

    local r = line:byte(i)

	if r ~= R_BYTE and r ~= R_BYTE2 then
        return
	end

    i = i + 1
    local g = line:byte(i)

	if g ~= G_BYTE and g ~= G_BYTE2 then
        return
	end

    i = i + 1
    local b = line:byte(i)

    if b ~= B_BYTE and b ~= B_BYTE2 then
        return
    end

    i = i + 1
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

    if #rgb_hex == RGB_MIN_LEN then

        rgb_hex = table.concat {
            rgb_hex:sub(1,1):rep(2);
            rgb_hex:sub(2,2):rep(2);
            rgb_hex:sub(3,3):rep(2);
        }

    elseif #rgb_hex == RGB_MAX_LEN then

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



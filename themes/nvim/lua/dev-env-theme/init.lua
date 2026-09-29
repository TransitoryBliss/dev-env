-- Applies the colorscheme that matches devEnv.theme. The base writes the chosen
-- theme to ~/.config/dev-env/theme.json (name, palette, nvim colorscheme); this
-- reads it at startup, so switching theme is `make switch` and restarting nvim.
--
-- The background is left transparent by default: the terminal's own background
-- (set from the same palette by herdr-attach) shows through, so nvim, the shell
-- and herdr's sidebar are one colour, including a devEnv.theme.background
-- override. Floats and statuslines keep the colorscheme's own shades.
local M = {}

local function read_json(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	local ok, value = pcall(vim.json.decode, text)
	return ok and value or nil
end

function M.theme_path()
	if vim.env.DEV_ENV_THEME and vim.env.DEV_ENV_THEME ~= "" then
		return vim.env.DEV_ENV_THEME
	end
	local config = vim.env.XDG_CONFIG_HOME
	if not config or config == "" then
		config = vim.fn.expand("~/.config")
	end
	return config .. "/dev-env/theme.json"
end

-- Clears the background of every highlight group that paints the editor's own
-- background colour, so the terminal's shows through.
local function clear_background(bg)
	if not bg then
		return
	end
	for name, attrs in pairs(vim.api.nvim_get_hl(0, {})) do
		if not attrs.link and attrs.bg == bg then
			attrs.bg = nil
			attrs.ctermbg = nil
			pcall(vim.api.nvim_set_hl, 0, name, attrs)
		end
	end
end

-- :terminal buffers get the same 16 colours as the terminal itself.
local function set_terminal_colours(ansi)
	for i, colour in ipairs(ansi or {}) do
		vim.g["terminal_color_" .. (i - 1)] = colour
	end
end

---@param opts? { transparent?: boolean, fallback?: string }
function M.setup(opts)
	opts = vim.tbl_extend("force", { transparent = true, fallback = "catppuccin-mocha" }, opts or {})
	local theme = read_json(M.theme_path())
	M.theme = theme
	vim.o.termguicolors = true

	if not theme then
		pcall(vim.cmd.colorscheme, opts.fallback)
		return
	end

	local scheme = theme.nvim.colorscheme
	-- args.match is the name given to :colorscheme. Not vim.g.colors_name:
	-- kanagawa, rose-pine and ayu set that to the family ("kanagawa"), not the
	-- variant ("kanagawa-dragon").
	local function after(args)
		if args.match ~= scheme and vim.g.colors_name ~= scheme then
			return -- someone picked another colorscheme by hand; leave it alone
		end
		local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
		-- For check.sh: what was applied, and its own background before clearing.
		vim.g.dev_env_theme_applied = scheme
		vim.g.dev_env_theme_bg = bg and string.format("#%06x", bg) or "none"
		set_terminal_colours(theme.ansi)
		if opts.transparent then
			clear_background(bg)
		end
	end
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("dev-env-theme", { clear = true }),
		callback = after,
	})

	-- gruvbox, everforest, solarized and ayu pick dark or light from this.
	vim.o.background = theme.appearance
	local ok, err = pcall(vim.cmd.colorscheme, scheme)
	if not ok then
		vim.g.dev_env_theme_error = tostring(err)
		vim.notify("dev-env-theme: " .. theme.name .. ": " .. tostring(err), vim.log.levels.ERROR)
		pcall(vim.cmd.colorscheme, opts.fallback)
	end
end

return M

local function getYearBeginDayOfWeek(tm)
    local yearBegin = os.time({ year = os.date("*t", tm).year, month = 1, day = 1 })
    local yearBeginDayOfWeek = tonumber(os.date("%w", yearBegin))
    -- sunday correct from 0 -> 7
    if yearBeginDayOfWeek == 0 then
        yearBeginDayOfWeek = 7
    end
    return yearBeginDayOfWeek
end

-- tm: date (as retruned fro os.time)
-- returns basic correction to be add for counting number of week
--  weekNum = math.floor((dayOfYear + returnedNumber) / 7) + 1
-- (does not consider correctin at begin and end of year)
local function getDayAdd(tm)
    local yearBeginDayOfWeek = getYearBeginDayOfWeek(tm)
    local dayAdd
    if yearBeginDayOfWeek < 5 then
        -- first day is week 1
        dayAdd = (yearBeginDayOfWeek - 2)
    else
        -- first day is week 52 or 53
        dayAdd = (yearBeginDayOfWeek - 9)
    end
    return dayAdd
end
-- tm is date as returned from os.time()
-- return week number in year based on ISO8601
-- (week with 1st thursday since Jan 1st (including) is considered as Week 1)
-- (if Jan 1st is Fri,Sat,Sun then it is part of week number from last year -> 52 or 53)
local function getWeekNumberOfYear(tm)
    local dayOfYear = os.date("%j", tm)
    local dayAdd = getDayAdd(tm)
    local dayOfYearCorrected = dayOfYear + dayAdd
    if dayOfYearCorrected < 0 then
        -- week of last year - decide if 52 or 53
        local lastYearBegin = os.time({ year = os.date("*t", tm).year - 1, month = 1, day = 1 })
        local lastYearEnd = os.time({ year = os.date("*t", tm).year - 1, month = 12, day = 31 })
        dayAdd = getDayAdd(lastYearBegin)
        dayOfYear = dayOfYear + os.date("%j", lastYearEnd)
        dayOfYearCorrected = dayOfYear + dayAdd
    end
    local weekNum = math.floor(dayOfYearCorrected / 7) + 1
    if (dayOfYearCorrected > 0) and weekNum == 53 then
        -- check if it is not considered as part of week 1 of next year
        local nextYearBegin = os.time({ year = os.date("*t", tm).year + 1, month = 1, day = 1 })
        local yearBeginDayOfWeek = getYearBeginDayOfWeek(nextYearBegin)
        if yearBeginDayOfWeek < 5 then
            weekNum = 1
        end
    end
    return weekNum
end

local function getOrdinal(number)
    if number % 10 == 1 then
        return number .. "st"
    end
    if number % 10 == 2 then
        return number .. "nd"
    end
    if number % 10 == 3 then
        return number .. "rd"
    end
    return number .. "th"
end

return {
    "epwalsh/obsidian.nvim",
    version = "*", -- recommended, use latest release instead of latest commit
    --lazy = true,
    --ft = "markdown",
    -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
    -- event = {
    --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
    --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
    --   -- refer to `:h file-pattern` for more examples
    --   "BufReadPre path/to/my-vault/*.md",
    --   "BufNewFile path/to/my-vault/*.md",
    -- },
    dependencies = {
        "nvim-lua/plenary.nvim",
        "hrsh7th/nvim-cmp",
        "nvim-treesitter/nvim-treesitter",
        "ibhagwan/fzf-lua",
    },
    opts = {
        workspaces = {
            {
                name = "base",
                path = "/mnt/c/Users/Garre/Documents/obsidian/base",
            },
        },
        daily_notes = {
            folder = "daily-notes",
            date_format = "%Y/%m/%Y-%m-%d_%A",
            template = "daily-notes-nvim.md",
        },
        completion = {
            -- Set to false to disable completion.
            nvim_cmp = true,
            -- Trigger completion at 2 chars.
            min_chars = 2,
        },
        templates = {
            folder = "templates",
            date_format = "%Y-%m-%d",
            time_format = "%H:%M",
            substitutions = {
                ["DATE_yyyy"] = function()
                    return os.date("%Y", os.time())
                end,
                ["DATE_MM"] = function()
                    return os.date("%m", os.time())
                end,
                ["DATE_DD"] = function()
                    return os.date("%d", os.time())
                end,
                ["DATE_dddd"] = function()
                    return os.date("%A", os.time())
                end,
                ["DATE_wo"] = function()
                    return getOrdinal(getWeekNumberOfYear(os.time()))
                end,
                ["DATE_ww"] = function()
                    return string.format("%02i", getWeekNumberOfYear(os.time()))
                end,
                ["weekly_note"] = function()
                    return os.date("%Y", os.time()) .. " - " .. getOrdinal(getWeekNumberOfYear(os.time())) .. " Week"
                end,
                ["DATE_format"] = function()
                    return os.date("%Y-%m-%d_%A", os.time())
                end,
            },
        },

        -- see below for full list of options 👇
        mappings = {
            -- Overrides the 'gf' mapping to work on markdown/wiki links within your vault.
            ["gf"] = {
                action = function()
                    return require("obsidian").util.gf_passthrough()
                end,
                opts = { noremap = false, expr = true, buffer = true },
            },
            ["<cr>"] = {
                action = function()
                    return require("obsidian").util.smart_action()
                end,
                opts = { buffer = true, expr = true },
            },
        },
    },
    keys = {
        {
            "<leader>ot",
            ":ObsidianToday<cr>",
            desc = "Open daily note",
        },
    },
}

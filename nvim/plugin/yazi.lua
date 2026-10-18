local pack = require("config.pack")
local map = require("util").map

-- Dependencies
pack.add("https://github.com/nvim-lua/plenary.nvim")

-- Yazi file manager (eager - needs BufEnter hook for open_for_directories)
pack.add("https://github.com/mikavilpas/yazi.nvim", function()
  require("yazi").setup({
    open_for_directories = true,
    integrations = {
      grep_in_directory = "fzf-lua",
      grep_in_selected_files = "fzf-lua",
      replace_in_directory = nil,
      replace_in_selected_files = nil,
      pick_window_implementation = nil,
    },
  })
end)

-- Keymaps: `-` opens the listing around the current file (vinegar/oil
-- convention); the e prefix would hold back <leader>e for timeoutlen.
map("n", "-", "<cmd>Yazi<CR>", { desc = "Yazi at this file" })
map("n", "_", "<cmd>Yazi cwd<CR>", { desc = "Yazi at the working directory" })

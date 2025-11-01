local M = {
    {
        "hrsh7th/nvim-cmp",
        version = false, -- last release is way too old
        event = "InsertEnter",
        dependencies = {
          "hrsh7th/cmp-nvim-lsp",
          "hrsh7th/cmp-buffer",
          "hrsh7th/cmp-path",
        },
        opts = function()
          -- Define fallback icons
          local kind_icons = {
            Text = "󰉿",
            Method = "󰆧",
            Function = "󰊕",
            Constructor = "",
            Field = "󰜢",
            Variable = "󰀫",
            Class = "󰠱",
            Interface = "",
            Module = "",
            Property = "󰜢",
            Unit = "󰑭",
            Value = "󰎠",
            Enum = "",
            Keyword = "󰌋",
            Snippet = "",
            Color = "󰏘",
            File = "󰈙",
            Reference = "󰈇",
            Folder = "󰉋",
            EnumMember = "",
            Constant = "󰏿",
            Struct = "󰙅",
            Event = "",
            Operator = "󰆕",
            TypeParameter = "",
          }

          -- Check if LazyVim exists and create fallback functions if needed
          local function create_confirm_func(opts)
            return function(fallback)
              local cmp = require("cmp")
              if cmp.visible() then
                cmp.confirm(opts)
              else
                fallback()
              end
            end
          end

          local function create_snippet_map_func()
            return function(fallback)
              fallback()
            end
          end
          
          -- Use LazyVim utilities if available, otherwise use fallbacks
          local cmp_utils = {
            confirm = LazyVim and LazyVim.cmp and LazyVim.cmp.confirm or create_confirm_func,
            map = LazyVim and LazyVim.cmp and LazyVim.cmp.map or create_snippet_map_func,
          }
 
          vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
          local cmp = require("cmp")
          local defaults = require("cmp.config.default")()
          local auto_select = true
          return {
            auto_brackets = {}, -- configure any filetype to auto add brackets
            completion = {
              completeopt = "menu,menuone,noinsert" .. (auto_select and "" or ",noselect"),
            },
            preselect = auto_select and cmp.PreselectMode.Item or cmp.PreselectMode.None,
            mapping = cmp.mapping.preset.insert({
              ["<C-b>"] = cmp.mapping.scroll_docs(-4),
              ["<C-f>"] = cmp.mapping.scroll_docs(4),
              ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
              ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
              ["<C-Space>"] = cmp.mapping.complete(),
              ["<CR>"] = cmp_utils.confirm({ select = auto_select }),
              ["<C-y>"] = cmp_utils.confirm({ select = true }),
              ["<S-CR>"] = cmp_utils.confirm({ behavior = cmp.ConfirmBehavior.Replace }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
              ["<C-CR>"] = function(fallback)
                cmp.abort()
                fallback()
              end,
              ["<tab>"] = function(fallback)
                if cmp_utils.map then
                  return cmp_utils.map({ "snippet_forward", "ai_accept" }, fallback)()
                else
                  fallback()
                end
              end,
            }),
            sources = cmp.config.sources({
              { name = "lazydev" },
              { name = "nvim_lsp" },
              { name = "path" },
            }, {
              { name = "buffer" },
            }),
            formatting = {
              format = function(entry, item)
                local icons = (LazyVim and LazyVim.config and LazyVim.config.icons and LazyVim.config.icons.kinds) or kind_icons
                if icons[item.kind] then
                  item.kind = icons[item.kind] .. item.kind
                end
      
                local widths = {
                  abbr = vim.g.cmp_widths and vim.g.cmp_widths.abbr or 40,
                  menu = vim.g.cmp_widths and vim.g.cmp_widths.menu or 30,
                }
      
                for key, width in pairs(widths) do
                  if item[key] and vim.fn.strdisplaywidth(item[key]) > width then
                    item[key] = vim.fn.strcharpart(item[key], 0, width - 1) .. "…"
                  end
                end
      
                return item
              end,
            },
            experimental = {
              -- only show ghost text when we show ai completions
              ghost_text = vim.g.ai_cmp and {
                hl_group = "CmpGhostText",
              } or false,
            },
            sorting = defaults.sorting,
          }
        end,
      }
}


return M

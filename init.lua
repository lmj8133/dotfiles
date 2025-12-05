-- ========================================
-- Mac 專業 Neovim 配置 - 精簡穩定 + nvim-tree + Cmdline History + 平滑捲動
-- v6.9（加入 Pandoc + XeLaTeX 一鍵 Md→PDF；修復 Neovim 0.11 相容性）
-- ========================================

-- 固定 Neovim RPC socket（給 Skim / nvr 逆向同步）
do
  local sockdir = vim.fn.expand("$HOME/.cache/nvim")
  local sock = sockdir .. "/skim.sock"
  vim.fn.mkdir(sockdir, "p")
  pcall(vim.fn.serverstop, sock)
  pcall(vim.fn.serverstart, sock)
  vim.env.NVIM_LISTEN_ADDRESS = sock
  vim.g.nvim_skim_socket = sock
end

-- ========================================
-- 基礎設定
-- ========================================
local opt = vim.opt
local g = vim.g

opt.number = true
opt.relativenumber = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true
opt.wrap = false
opt.cursorline = true
opt.cursorcolumn = true
opt.termguicolors = true
opt.mouse = 'a'
opt.clipboard = 'unnamedplus'
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.ignorecase = true
opt.smartcase = true
opt.splitbelow = true
opt.splitright = true
opt.updatetime = 100
opt.timeoutlen = 500
opt.ttimeoutlen = 0
opt.hlsearch = true
opt.autoread = true
opt.background = 'dark'
opt.signcolumn = 'yes'
opt.scrolloff = 8
opt.colorcolumn = "80,120"

g.mapleader = ' '
g.maplocalleader = ' '

-- 停用 netrw（改用 nvim-tree）
g.loaded_netrw = 1
g.loaded_netrwPlugin = 1

-- ========================================
-- Python 環境自動偵測 (支援 uv)
-- ========================================
local function setup_python_env()
  local project_venv = vim.fn.getcwd() .. '/.venv/bin/python'
  if vim.fn.filereadable(project_venv) == 1 then
    vim.g.python3_host_prog = project_venv
  else
    local nvim_env = vim.fn.expand('~/.config/nvim-env/.venv/bin/python')
    if vim.fn.filereadable(nvim_env) == 1 then
      vim.g.python3_host_prog = nvim_env
    else
      vim.g.python3_host_prog = 'python3'
    end
  end
end
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, { callback = setup_python_env })

-- ========================================
-- 安裝 lazy.nvim
-- ========================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git","clone","--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git","--branch=stable", lazypath })
end
opt.rtp:prepend(lazypath)

-- ========================================
-- 插件列表
-- ========================================
require("lazy").setup({
  -- 主題
  {
    "morhetz/gruvbox",
    priority = 1000,
    config = function() vim.cmd.colorscheme "gruvbox" end
  },

  -- 圖標支援
  { 'nvim-tree/nvim-web-devicons' },

  -- 狀態列
  {
    'nvim-lualine/lualine.nvim',
    config = function()
      require('lualine').setup({
        options = { theme = 'gruvbox', section_separators = '', component_separators = '' },
      })
    end
  },

  -- nvim-tree
  {
    'nvim-tree/nvim-tree.lua',
    config = function()
      require("nvim-tree").setup({
        view = { width = 35, side = "left" },
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")
          api.config.mappings.default_on_attach(bufnr)
          local opts = { buffer = bufnr, noremap = true, silent = true, nowait = true }
          vim.keymap.set('n', 't', api.node.open.tab, opts)
          vim.keymap.set('n', 's', api.node.open.horizontal, opts)
          vim.keymap.set('n', 'v', api.node.open.vertical, opts)
        end,
      })
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function(data)
          local api = require("nvim-tree.api")
          local is_dir = vim.fn.isdirectory(data.file) == 1
          local has_args = vim.fn.argc() > 0
          if not has_args then api.tree.open(); return end
          if is_dir then vim.cmd.cd(data.file); api.tree.open(); return end
          api.tree.open(); vim.schedule(function() pcall(api.tree.find_file, { open = false, focus = false }) end)
        end
      })
      vim.api.nvim_create_autocmd("TabEnter", {
        callback = function()
          if package.loaded["nvim-tree"] then
            require("nvim-tree.api").tree.change_root(vim.fn.getcwd())
          end
        end,
      })
    end
  },

  -- Telescope（統一 <C-d>/<C-u> 為預覽窗捲動）
  {
    'nvim-telescope/telescope.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope-fzf-native.nvim',
      'nvim-telescope/telescope-live-grep-args.nvim',
      'nvim-telescope/telescope-ui-select.nvim'
    },
    config = function()
      local telescope = require('telescope')
      local actions = require('telescope.actions')
      telescope.setup({
        defaults = {
          mappings = {
            i = {
              ["<C-d>"] = actions.preview_scrolling_down,
              ["<C-u>"] = actions.preview_scrolling_up,
            },
            n = {
              ["<C-d>"] = actions.preview_scrolling_down,
              ["<C-u>"] = actions.preview_scrolling_up,
            },
          },
        },
        pickers = {
          buffers = {
            show_all_buffers = true,
            sort_lastused = true,
            mappings = { i = {}, n = { ["dd"] = actions.delete_buffer } },
          },
        },
      })
      telescope.load_extension('fzf')
      telescope.load_extension('live_grep_args')
      telescope.load_extension('ui-select')
    end
  },
  { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },

  -- LSP 配置（含 texlab → Skim forward search）
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
      "folke/neodev.nvim"
    },
    config = function()
      require("neodev").setup()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "pyright","lua_ls","clangd","rust_analyzer","ts_ls",  -- 已更新：tsserver → ts_ls
          "texlab","marksman",
          -- gopls 已移除：如需 Go 支援，請手動執行 :MasonInstall gopls
        }
      })

      -- 暫時抑制 lspconfig 棄用警告（配置仍然正常運作）
      -- 注意：未來版本會遷移到 vim.lsp.config API
      local notify = vim.notify
      vim.notify = function(msg, ...)
        if msg:match("require%(.-lspconfig.-%)") then
          return
        end
        notify(msg, ...)
      end

      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      
      -- 恢復正常通知
      vim.notify = notify

      -- === Swift / SourceKit ===
      -- 自動尋找 sourcekit-lsp：優先 Xcode 版本（對 .xcodeproj 支援最好）
      local function find_sourcekit()
        local candidates = {
          -- 1. 優先使用 Xcode 版本（對 Xcode 專案支援最好）
          "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
          -- 2. PATH 中的版本
          vim.fn.exepath("sourcekit-lsp"),
        }
        -- 3. 掃描 /Library/Developer/Toolchains/*.xctoolchain
        local extra = vim.fn.glob("/Library/Developer/Toolchains/*.xctoolchain/usr/bin/sourcekit-lsp", 1, 1)
        for _, p in ipairs(extra) do table.insert(candidates, p) end
        for _, p in ipairs(candidates) do
          if p and p ~= "" and vim.fn.filereadable(p) == 1 then return p end
        end
        return "sourcekit-lsp" -- 走 PATH（若仍找不到會在啟動時提示）
      end

      -- 注意：sourcekit 不建議交給 mason 安裝（macOS 通常隨 Xcode/Swift toolchain 提供）
      local sourcekit_path = find_sourcekit()
      local is_xcode_version = sourcekit_path:match("Xcode") ~= nil
      print("🔍 SourceKit LSP: " .. sourcekit_path .. (is_xcode_version and " (Xcode)" or ""))

      lspconfig.sourcekit.setup({
        capabilities = capabilities,
        cmd = { sourcekit_path },
        root_dir = function(fname)
          -- 優先順序：.xcodeproj > .xcworkspace > Package.swift > .git
          local root = lspconfig.util.root_pattern("*.xcodeproj", "*.xcworkspace")(fname)
          if root then
            print("✅ Found Xcode project root: " .. root)
            return root
          end
          root = lspconfig.util.root_pattern("Package.swift", ".git")(fname)
          if root then
            print("✅ Found SPM/Git root: " .. root)
            return root
          end
          print("⚠️  No root directory found, using file directory")
          return vim.fn.fnamemodify(fname, ":h")
        end,
        filetypes = { "swift" },
        on_attach = function(client, bufnr)
          print("✅ SourceKit LSP attached to buffer " .. bufnr)
          print("   File: " .. vim.api.nvim_buf_get_name(bufnr))
          print("   Root: " .. (client.config.root_dir or "unknown"))

          -- 檢查並顯示 LSP capabilities
          if client.server_capabilities.definitionProvider then
            print("   ✅ definitionProvider enabled")
          else
            print("   ⚠️  definitionProvider disabled")
          end

          -- 設定 buffer 專屬的 LSP 快捷鍵
          -- 注意：gd 由後面的 FileType autocmd 設定為智能切換版本
          local bufopts = { noremap=true, silent=true, buffer=bufnr }
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
          vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
          vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)
        end,
        on_init = function(client)
          print("🚀 SourceKit LSP initializing...")
        end,
        on_exit = function(code, signal, client_id)
          if code ~= 0 then
            print("❌ SourceKit LSP exited with code: " .. code)
          end
        end,
        flags = {
          debounce_text_changes = 150,
        },
      })

      for _, server in ipairs({ "pyright","lua_ls","clangd","rust_analyzer","ts_ls","marksman" }) do
        lspconfig[server].setup({ capabilities = capabilities })
      end

      lspconfig.texlab.setup({
        capabilities = capabilities,
        settings = {
          texlab = {
            auxDirectory = ".",
            bibtexFormatter = "texlab",
            build = {
              executable = "latexmk",
              args = { "-pdf", "-interaction=nonstopmode", "-synctex=1", "%f" },
              onSave = false,
            },
            chktex = { onOpenAndSave = false, onEdit = false },
            diagnosticsDelay = 300,
            formatterLineLength = 80,
            forwardSearch = {
              executable = "/Applications/Skim.app/Contents/SharedSupport/displayline",
              args = { "-g", "%l", "%p", "%f" },
            },
            latexFormatter = "latexindent",
            latexindent = { modifyLineBreaks = false },
          },
        },
      })
    end
  },

  -- 自動完成（含 cmdline 歷史）
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp","hrsh7th/cmp-buffer","hrsh7th/cmp-path","hrsh7th/cmp-cmdline",
      "L3MON4D3/LuaSnip","saadparwaiz1/cmp_luasnip","rafamadriz/friendly-snippets","onsails/lspkind.nvim",
      "dmitmel/cmp-cmdline-history",
    },
    config = function()
      local cmp = require('cmp')
      local luasnip = require('luasnip')
      local lspkind = require('lspkind')

      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { 'i','s' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { 'i','s' }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' }, { name = 'luasnip' },
        }, { { name = 'buffer' }, { name = 'path' } }),
        formatting = { format = lspkind.cmp_format({ mode = 'symbol_text', maxwidth = 50, ellipsis_char = '...' }) }
      })

      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({ { name = 'path' } }, { { name = 'cmdline' }, { name = 'cmdline_history' } })
      })
      for _, c in ipairs({ '/', '?' }) do
        cmp.setup.cmdline(c, {
          mapping = cmp.mapping.preset.cmdline(),
          sources = { { name = 'buffer' }, { name = 'cmdline_history' } }
        })
      end
    end
  },

  -- Copilot
  {
    "github/copilot.vim",
    config = function()
      vim.g.copilot_no_tab_map = true
      vim.keymap.set('i', '<C-J>', 'copilot#Accept("\\<CR>")', { expr = true, replace_keycodes = false })
    end
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = {
          "lua","vim","vimdoc","query",
          "python","javascript","typescript","c","cpp","rust",  -- 已移除 go
          "markdown","markdown_inline",
          "latex","bibtex",
          "yaml","toml","json",
          "html","css",
          "bash","regex",
          "swift", -- ← Swift 支援
        },
        sync_install = false,
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = { "markdown" },
        },
        indent = { enable = true },
      })
    end,
  },

  -- Git
  { 'lewis6991/gitsigns.nvim', config = true },
  { 'tpope/vim-fugitive' },
  {
    "rbong/vim-flog",
    lazy = true,
    cmd = { "Flog", "Flogsplit", "Floggit" },
    dependencies = {
      "tpope/vim-fugitive",
    },
    init = function()
      vim.g.flog_open_command = 'tabedit'
      vim.g.flog_position = 'right'
    end,

  },

  -- 平滑捲動（<C-d>/<C-u>）
  {
    "karb94/neoscroll.nvim",
    opts = {
      mappings = { '<C-u>', '<C-d>' },
      hide_cursor = true,
      stop_eof = true,
      respect_scrolloff = true,
      performance_mode = true,
    }
  },

  -- 其他實用
  { 'numToStr/Comment.nvim', config = true },
  { 'windwp/nvim-autopairs', config = true },
  { 'folke/which-key.nvim', config = true },
  { "simrat39/symbols-outline.nvim", config = true },

  -- Markdown 預覽（非 lazy，保證命令與按鍵存在）
  {
    "iamcco/markdown-preview.nvim",
    lazy = false,  -- ← 讓命令/按鍵一律可用
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown: Toggle Preview" },
      { "<leader>ms", "<cmd>MarkdownPreviewStop<CR>",   desc = "Markdown: Stop Preview"   },
    },
    build = function() vim.fn["mkdp#util#install"]() end,
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_refresh_slow = 0
      vim.g.mkdp_markdown_css = ''
      vim.g.mkdp_theme = 'dark'
      vim.g.mkdp_browser = '' -- 系統預設瀏覽器
      vim.g.mkdp_port = 7777  -- 固定預覽埠，供（必要時）headless 印出
      vim.g.mkdp_preview_options = {
        mkit = {}, katex = {}, uml = {}, maid = {},
        disable_sync_scroll = 0, sync_scroll_type = 'middle',
        hide_yaml_meta = 1, sequence_diagrams = {}, flowchart_diagrams = {},
        content_editable = false, disable_filename = 0
      }
    end,
  },

  -- LaTeX（VimTeX，Skim 雙向同步）
  {
    "lervag/vimtex",
    lazy = false,
    init = function()
      vim.g.vimtex_view_method = 'skim'
      vim.g.vimtex_view_general_viewer = 'Skim'
      vim.g.vimtex_view_general_options = '--reuse-instance'
      vim.g.vimtex_view_skim_sync = 1
      vim.g.vimtex_view_skim_activate = 1

      vim.g.vimtex_compiler_method = 'latexmk'
      vim.g.vimtex_compiler_latexmk = {
        options = { '-verbose', '-file-line-error', '-synctex=1', '-interaction=nonstopmode' },
      }

      vim.g.vimtex_quickfix_mode = 2
      vim.g.vimtex_quickfix_open_on_warning = 0
      vim.g.vimtex_fold_enabled = 0
      vim.g.vimtex_complete_enabled = 1
      vim.g.vimtex_complete_close_braces = 1
      vim.g.vimtex_syntax_conceal = {
        accents = 1, cites = 1, fancy = 1, greek = 1,
        math_bounds = 1, math_delimiters = 1, math_fracs = 1,
        math_super_sub = 1, math_symbols = 1, styles = 1,
      }
    end,
  },
})

-- ========================================
-- 自訂快捷鍵映射
-- ========================================

-- 基礎快捷鍵
vim.keymap.set('n', '<leader>w', ':w<CR>', { desc = '儲存檔案', silent = true })
vim.keymap.set('n', '<leader>q', ':q<CR>', { desc = '退出', silent = true })
vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { desc = '切換檔案樹', silent = true })

-- Telescope 快捷鍵
vim.keymap.set('n', '<leader>ff', ':Telescope find_files<CR>', { desc = '尋找檔案', silent = true })
vim.keymap.set('n', '<leader>fg', ':Telescope live_grep<CR>', { desc = '文字搜尋', silent = true })
vim.keymap.set('n', '<leader>fb', ':Telescope buffers<CR>', { desc = '緩衝區列表', silent = true })
vim.keymap.set('n', '<leader>fh', ':Telescope help_tags<CR>', { desc = '幫助文件', silent = true })
vim.keymap.set('n', '<leader>fr', ':Telescope oldfiles<CR>', { desc = '最近檔案', silent = true })
vim.keymap.set('n', '<leader>fc', ':Telescope commands<CR>', { desc = '命令列表', silent = true })

-- LSP 快捷鍵
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = '跳轉到定義' })
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { desc = '跳轉到聲明' })
vim.keymap.set('n', 'gr', vim.lsp.buf.references, { desc = '顯示引用' })
vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { desc = '跳轉到實作' })
vim.keymap.set('n', 'K', vim.lsp.buf.hover, { desc = '顯示懸浮文件' })
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = '重新命名' })
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = '程式碼動作' })
vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format { async = true } end, { desc = '格式化程式碼' })
vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, { desc = '顯示診斷詳情' })
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = '上一個診斷' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = '下一個診斷' })

-- 視窗導航
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = '移到左邊視窗' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = '移到右邊視窗' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = '移到下方視窗' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = '移到上方視窗' })

-- 快速移動
vim.keymap.set('n', '<leader>h', '^', { desc = '移到行首（非空白）' })
vim.keymap.set('n', '<leader>l', '$', { desc = '移到行尾' })

-- 清除搜尋高亮
vim.keymap.set('n', '<leader>nh', ':noh<CR>', { desc = '清除搜尋高亮', silent = true })

-- 分割視窗
vim.keymap.set('n', '<leader>sv', ':vsplit<CR>', { desc = '垂直分割', silent = true })
vim.keymap.set('n', '<leader>sh', ':split<CR>', { desc = '水平分割', silent = true })

-- Gitsigns 快捷鍵（在 Gitsigns 載入後設定）
vim.api.nvim_create_autocmd("User", {
  pattern = "GitSignsAttach",
  callback = function()
    local gs = package.loaded.gitsigns
    vim.keymap.set('n', ']c', function()
      if vim.wo.diff then return ']c' end
      vim.schedule(function() gs.next_hunk() end)
      return '<Ignore>'
    end, { expr = true, desc = '下一個變更' })
    vim.keymap.set('n', '[c', function()
      if vim.wo.diff then return '[c' end
      vim.schedule(function() gs.prev_hunk() end)
      return '<Ignore>'
    end, { expr = true, desc = '上一個變更' })
    vim.keymap.set('n', '<leader>hs', gs.stage_hunk, { desc = '暫存區塊' })
    vim.keymap.set('n', '<leader>hr', gs.reset_hunk, { desc = '重置區塊' })
    vim.keymap.set('v', '<leader>hs', function() gs.stage_hunk {vim.fn.line('.'), vim.fn.line('v')} end, { desc = '暫存選中區塊' })
    vim.keymap.set('v', '<leader>hr', function() gs.reset_hunk {vim.fn.line('.'), vim.fn.line('v')} end, { desc = '重置選中區塊' })
    vim.keymap.set('n', '<leader>hS', gs.stage_buffer, { desc = '暫存整個檔案' })
    vim.keymap.set('n', '<leader>hR', gs.reset_buffer, { desc = '重置整個檔案' })
    vim.keymap.set('n', '<leader>hu', gs.undo_stage_hunk, { desc = '取消暫存' })
    vim.keymap.set('n', '<leader>hp', gs.preview_hunk, { desc = '預覽變更' })
    vim.keymap.set('n', '<leader>hb', function() gs.blame_line{full=true} end, { desc = '顯示行 blame' })
    vim.keymap.set('n', '<leader>hd', gs.diffthis, { desc = '顯示差異' })
    vim.keymap.set('n', '<leader>hD', function() gs.diffthis('~') end, { desc = '顯示差異 (對比上個版本)' })
  end
})

-- ========================================
-- Markdown 工具與一鍵 Pandoc→PDF 指令
-- ========================================
local function _has(cmd) return vim.fn.executable(cmd) == 1 end

local function _sys_fonts()
  local sys = vim.loop.os_uname().sysname
  if sys == "Darwin" then
    return "PingFang TC", "Menlo"   -- macOS 內建字型，最保險
  else
    return "Noto Sans CJK TC", "JetBrains Mono"
  end
end

local function MdPandocPdf(opts)
  opts = opts or {}
  local src = vim.fn.expand('%:p')
  if src == '' then
    vim.notify('沒有開啟中的檔案可轉換', vim.log.levels.ERROR)
    return
  end
  local out = opts.out or (vim.fn.fnamemodify(src, ':r') .. '.pdf')

  if not _has('pandoc') then
    vim.notify('找不到 pandoc，可用 Homebrew 安裝：brew install pandoc', vim.log.levels.ERROR)
    return
  end

  local mainfont, monofont = _sys_fonts()
  local args = {
    'pandoc', src, '-o', out,
    '--from', 'markdown+emoji',
    '--toc',
    '--pdf-engine=xelatex',
    '-V', 'mainfont=' .. mainfont,
    '-V', 'CJKmainfont=' .. mainfont,
    '-V', 'monofont=' .. monofont,
    '-V', 'geometry:margin=20mm',
  }

  vim.notify('使用 Pandoc + XeLaTeX 產生 PDF… → ' .. out)
  vim.fn.jobstart(args, {
    stdout_buffered = true, stderr_buffered = true,
    on_stderr = function(_, data)
      if data and #data > 0 then
        vim.schedule(function() vim.notify(table.concat(data, "\n"), vim.log.levels.WARN) end)
      end
    end,
    on_exit = function(_, code)
      if code == 0 then vim.notify('✅ PDF 完成：' .. out)
      else vim.notify('❌ Pandoc 轉檔失敗（exit ' .. code .. '）', vim.log.levels.ERROR) end
    end
  })
end

vim.api.nvim_create_user_command('Md2Pdf', function(cmdopts)
  local out = cmdopts.args ~= '' and cmdopts.args or nil
  MdPandocPdf({ out = out })
end, { nargs = '?', complete = 'file', desc = 'Markdown → PDF（Pandoc + XeLaTeX）' })

-- Markdown 其他輔助（mp/ms 已由 plugin keys 提供）
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.keymap.set('n', '<leader>mt', 'i| Column 1 | Column 2 |<CR>|----------|----------|<CR>| Cell 1   | Cell 2   |<ESC>', { buffer = true, desc = '插入表格' })
    vim.keymap.set('n', '<leader>ml', 'i[](url)<ESC>F[a', { buffer = true, desc = '插入連結' })
    vim.keymap.set('n', '<leader>mi', 'i![](url)<ESC>F[a', { buffer = true, desc = '插入圖片' })
    vim.keymap.set('n', '<leader>mc', 'i```<CR><CR>```<ESC>kA', { buffer = true, desc = '插入程式碼區塊' })
    vim.keymap.set('n', '<leader>mb', 'viw<ESC>a**<ESC>bi**<ESC>', { buffer = true, desc = '加粗選中文字' })
    vim.keymap.set('n', '<leader>m*', 'viw<ESC>a*<ESC>bi*<ESC>', { buffer = true, desc = '斜體選中文字' })
    vim.keymap.set('v', '<leader>mb', '<ESC>`>a**<ESC>`<i**<ESC>', { buffer = true, desc = '加粗選中文字' })
    vim.keymap.set('v', '<leader>m*', '<ESC>`>a*<ESC>`<i*<ESC>', { buffer = true, desc = '斜體選中文字' })
    -- 一鍵輸出 PDF（Pandoc + XeLaTeX）
    vim.keymap.set('n', '<leader>mP', function() vim.cmd('Md2Pdf') end, { buffer = true, desc = 'Markdown 匯出 PDF（Pandoc）' })
  end
})

-- LaTeX 快捷鍵（Skim）
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "latex" },
  callback = function()
    vim.keymap.set('n', '<leader>ll', '<Plug>(vimtex-compile)', { buffer = true, desc = '編譯 LaTeX' })
    vim.keymap.set('n', '<leader>lv', '<Plug>(vimtex-view)',    { buffer = true, desc = '查看 PDF (Skim)' })
    vim.keymap.set('n', '<leader>lc', '<Plug>(vimtex-clean)',   { buffer = true, desc = '清理輔助檔案' })
    vim.keymap.set('n', '<leader>lC', '<Plug>(vimtex-clean-full)', { buffer = true, desc = '完全清理' })
    vim.keymap.set('n', '<leader>le', '<Plug>(vimtex-errors)',  { buffer = true, desc = '查看錯誤' })
    vim.keymap.set('n', '<leader>lt', '<Plug>(vimtex-toc-open)', { buffer = true, desc = '開啟目錄' })
    vim.keymap.set('n', '<leader>lT', '<Plug>(vimtex-toc-toggle)', { buffer = true, desc = '切換目錄' })
    vim.keymap.set('n', '<leader>lk', '<Plug>(vimtex-stop)',    { buffer = true, desc = '停止編譯' })
    vim.keymap.set('n', '<leader>lK', '<Plug>(vimtex-stop-all)',{ buffer = true, desc = '停止所有編譯' })
    vim.keymap.set('n', '<leader>li', '<Plug>(vimtex-info)',    { buffer = true, desc = 'LaTeX 資訊' })
    vim.keymap.set('n', '<leader>ls', '<Plug>(vimtex-toggle-main)', { buffer = true, desc = '切換主檔案' })

    vim.keymap.set({ 'x', 'o' }, 'ie', '<Plug>(vimtex-ie)', { buffer = true, desc = 'LaTeX 環境內容' })
    vim.keymap.set({ 'x', 'o' }, 'ae', '<Plug>(vimtex-ae)', { buffer = true, desc = 'LaTeX 環境' })
    vim.keymap.set({ 'x', 'o' }, 'i$', '<Plug>(vimtex-i$)', { buffer = true, desc = '數學模式內容' })
    vim.keymap.set({ 'x', 'o' }, 'a$', '<Plug>(vimtex-a$)', { buffer = true, desc = '數學模式' })

    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us,cjk"
  end
})

-- CheatSheet 命令
vim.api.nvim_create_user_command('CheatSheet', function()
  vim.cmd('vsplit ' .. vim.fn.stdpath('config') .. '/cheatsheet.txt')
  vim.cmd('setlocal readonly nomodifiable')
end, { desc = '顯示快捷鍵速查表' })

-- Which-key 提示
vim.keymap.set('n', '<leader>?', function() require('which-key').show({ global = false }) end, { desc = '顯示所有快捷鍵' })

-- ========================================
-- Swift LSP 診斷命令
-- ========================================

-- 診斷 Swift LSP 狀態
vim.api.nvim_create_user_command('SwiftLspStatus', function()
  print("=== Swift LSP 診斷 ===")

  -- 檢查 LSP clients
  local clients = vim.lsp.get_active_clients()
  local swift_clients = vim.tbl_filter(function(c) return c.name == "sourcekit" end, clients)

  if #swift_clients > 0 then
    print("✅ SourceKit LSP 已啟動 (" .. #swift_clients .. " 個)")
    for _, client in ipairs(swift_clients) do
      print("   ID: " .. client.id)
      print("   Root: " .. (client.config.root_dir or "unknown"))
      print("   Buffers: " .. vim.inspect(vim.lsp.get_buffers_by_client_id(client.id)))
    end
  else
    print("❌ SourceKit LSP 未啟動")
    print("   嘗試執行: :LspStart sourcekit")
  end

  -- 檢查當前 buffer
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_clients = vim.lsp.get_active_clients({ bufnr = bufnr })
  print("\n當前 buffer LSP 狀態:")
  print("   Buffer: " .. bufnr)
  print("   File: " .. vim.api.nvim_buf_get_name(bufnr))
  print("   Filetype: " .. vim.bo.filetype)
  print("   Attached clients: " .. #buf_clients)

  -- 檢查 sourcekit-lsp 路徑
  local sourcekit = vim.fn.exepath("sourcekit-lsp")
  print("\nsourcekit-lsp 路徑:")
  if sourcekit ~= "" then
    print("   ✅ " .. sourcekit)
  else
    print("   ❌ 在 PATH 中找不到")
  end
end, { desc = 'Swift LSP 診斷資訊' })

-- 快速重啟 Swift LSP
vim.api.nvim_create_user_command('SwiftLspRestart', function()
  local clients = vim.lsp.get_active_clients({ name = "sourcekit" })
  if #clients > 0 then
    print("重啟 SourceKit LSP...")
    for _, client in ipairs(clients) do
      vim.lsp.stop_client(client.id)
    end
    vim.defer_fn(function()
      vim.cmd('LspStart sourcekit')
      print("✅ SourceKit LSP 已重啟")
    end, 500)
  else
    print("啟動 SourceKit LSP...")
    vim.cmd('LspStart sourcekit')
  end
end, { desc = '重啟 Swift LSP' })

-- 查看 LSP 日誌
vim.api.nvim_create_user_command('SwiftLspLog', function()
  vim.cmd('edit ' .. vim.lsp.get_log_path())
end, { desc = '開啟 Swift LSP 日誌' })

-- Swift 專用快捷鍵（FileType autocmd）
vim.api.nvim_create_autocmd("FileType", {
  pattern = "swift",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    print("📝 Swift 檔案已開啟，等待 LSP 連接...")

    -- 設定 Swift 專用快捷鍵
    vim.keymap.set('n', '<leader>ls', ':SwiftLspStatus<CR>',
      { buffer = bufnr, desc = 'Swift LSP 狀態' })
    vim.keymap.set('n', '<leader>lr', ':SwiftLspRestart<CR>',
      { buffer = bufnr, desc = 'Swift LSP 重啟' })
    vim.keymap.set('n', '<leader>ll', ':SwiftLspLog<CR>',
      { buffer = bufnr, desc = 'Swift LSP 日誌' })

    -- 如果 LSP 沒啟動，提示用戶
    vim.defer_fn(function()
      local clients = vim.lsp.get_active_clients({ bufnr = bufnr, name = "sourcekit" })
      if #clients == 0 then
        print("⚠️  SourceKit LSP 未自動啟動")
        print("   執行 :SwiftLspStatus 查看詳情")
        print("   執行 :LspStart sourcekit 手動啟動")
      end
    end, 2000)
  end
})

-- ============================================================================
-- Enhanced Telescope Jump Configuration (Xcode project fallback)
-- ============================================================================
-- Since sourcekit-lsp has limited support for .xcodeproj,
-- these Telescope-based shortcuts provide 100% reliable navigation

-- Jump to function definition (replaces gd for Xcode projects)
vim.keymap.set('n', '<leader>jd', function()
    local word = vim.fn.expand('<cword>')
    require('telescope.builtin').live_grep({
        default_text = 'func ' .. word,
        prompt_title = 'Jump to Function: ' .. word,
    })
end, { desc = 'Jump to function definition', noremap = true, silent = true })

-- Jump to class definition
vim.keymap.set('n', '<leader>jc', function()
    local word = vim.fn.expand('<cword>')
    require('telescope.builtin').live_grep({
        default_text = 'class ' .. word,
        prompt_title = 'Jump to Class: ' .. word,
    })
end, { desc = 'Jump to class definition', noremap = true, silent = true })

-- Jump to struct definition
vim.keymap.set('n', '<leader>js', function()
    local word = vim.fn.expand('<cword>')
    require('telescope.builtin').live_grep({
        default_text = 'struct ' .. word,
        prompt_title = 'Jump to Struct: ' .. word,
    })
end, { desc = 'Jump to struct definition', noremap = true, silent = true })

-- Find all references (replaces gr for Xcode projects)
vim.keymap.set('n', '<leader>jr', function()
    local word = vim.fn.expand('<cword>')
    require('telescope.builtin').live_grep({
        default_text = word,
        prompt_title = 'Find References: ' .. word,
    })
end, { desc = 'Find all references', noremap = true, silent = true })

-- Swift-specific: smart gd with LSP fallback to Telescope
vim.api.nvim_create_autocmd("FileType", {
    pattern = "swift",
    callback = function(ev)
        -- Smart gd: try LSP first, fallback to Telescope if no result
        vim.keymap.set('n', 'gd', function()
            local word = vim.fn.expand('<cword>')

            -- Check if LSP is attached
            local clients = vim.lsp.get_active_clients({ bufnr = ev.buf, name = "sourcekit" })
            if #clients == 0 then
                print("⚠️  SourceKit LSP not attached, using Telescope...")
                require('telescope.builtin').live_grep({
                    default_text = 'func ' .. word,
                    prompt_title = 'Jump to: ' .. word,
                })
                return
            end

            -- Try LSP definition
            print("🔍 Trying LSP definition for: " .. word)
            local params = vim.lsp.util.make_position_params()

            vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result, ctx, config)
                if err then
                    print("❌ LSP error: " .. vim.inspect(err))
                    print("   Falling back to Telescope...")
                    require('telescope.builtin').live_grep({
                        default_text = 'func ' .. word,
                        prompt_title = 'Jump to: ' .. word,
                    })
                elseif not result or vim.tbl_isempty(result) then
                    print("⚠️  LSP found no definition, trying Telescope...")
                    require('telescope.builtin').live_grep({
                        default_text = 'func ' .. word,
                        prompt_title = 'Jump to: ' .. word,
                    })
                else
                    print("✅ LSP found definition, jumping...")
                    vim.lsp.util.jump_to_location(result[1], "utf-8")
                end
            end)
        end, { buffer = ev.buf, desc = 'Go to definition (smart)', noremap = true, silent = false })
    end
})

print("Neovim 配置載入完成！")
print("✅ Telescope 跳轉已啟用：<leader>jd/jc/js/jr 或直接用 gd")



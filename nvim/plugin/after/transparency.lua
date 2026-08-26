local groups = {
  "Normal", "NormalNC", "NormalFloat", "FloatBorder", "Pmenu",
  "Terminal", "EndOfBuffer", "FoldColumn", "Folded", "SignColumn",
  "WhichKeyFloat", "TelescopeBorder", "TelescopeNormal",
  "TelescopePromptBorder", "TelescopePromptTitle",
  "NeoTreeNormal", "NeoTreeNormalNC", "NeoTreeEndOfBuffer",
}
for _, g in ipairs(groups) do
  vim.api.nvim_set_hl(0, g, { bg = "none" })
end

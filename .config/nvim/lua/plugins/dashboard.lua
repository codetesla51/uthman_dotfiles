-- Dashboard logo: ASCII take on the Hollow Knight mask
-- (same art as the SDDM login logo). Only the header is overridden,
-- the default LazyVim shortcut keys are left untouched.
return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = [[
              /\              /\
             /  \            /  \
            |    \          /    |
            |     \        /     |
            |      \______/      |
            |     .-......-.     |
            |    /  .----.  \    |
            |   |  (  o o )  |   |
             \   \  '----'  /   /
              '.  '------'  .'
                '----------'
   ]],
        },
      },
    },
  },
}

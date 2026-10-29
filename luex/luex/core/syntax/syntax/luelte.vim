" Vim syntax file for Luelte Single File Components (.luelte / .lte)
if exists("b:current_syntax")
  finish
endif

" Script tags
syntax region luelteScriptBlock start="<script>" end="</script>" contains=@luaScript
syntax include @luaScript syntax/lua.vim

" Component Tags
syntax match luelteTag "</\=\(Window\|Text\|pack\)"
syntax match luelteAttr "\v(width|height|border|highlight|lang|lsp|formatter|linter|treesitter|on:key|on:select)\="

" Template Control Flow
syntax region luelteControlFlow start="{\s*#[a-z]\+" end="}"
syntax region luelteControlElse start="{\s*:[a-z]\+" end="}"
syntax region luelteControlEnd start="{\s*/[a-z]\+" end="}"

" Variable Interpolation
syntax region luelteVarExpr start="{" end="}" contains=ALLBUT,luelteScriptBlock

highlight default link luelteTag Keyword
highlight default link luelteAttr Type
highlight default link luelteControlFlow Statement
highlight default link luelteControlElse Statement
highlight default link luelteControlEnd Statement
highlight default link luelteVarExpr Special

let b:current_syntax = "luelte"

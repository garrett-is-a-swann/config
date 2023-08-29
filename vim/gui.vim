"Remove top toolbar
try 
    set guioptions -= T
catch
endtry

set so=7
set ruler
set showcmd
set laststatus=2
set statusline='%{HasPaste()}%F%m%r%h'

set splitbelow
set splitright


set tabline=%!getTabline()

function! getTabline()
  let tab = ''
  for i in range(tabpagenr('$'))
    " select the highlighting
    if i + 1 == tabpagenr()
      let tab .= '%#TabLineSel#'
    else
      let tab .= '%#TabLine#'
    endif

    " set the tab page number (for mouse clicks)
    let tab .= '%' . (i + 1) . 'T' 

    " the label is made by getTabLabel()
    let tab .= ' %{getTabLabel(' . (i + 1) . ')} '
  endfor

  " after the last tab fill with TabLineFill and reset tab page nr
  let tab .= '%#TabLineFill#%T'

  " right-align the label to close the current tab page
  if tabpagenr('$') > 1 
    let tab .= '%=%#TabLine#%999Xclose'
  endif

  return tab
endfunction

function! getTabLabel(n)
  let buflist = tabpagebuflist(a:n)
  let winnr = tabpagewinnr(a:n)
  let label =  bufname(buflist[winnr - 1]) 
  return fnamemodify(label, ":t") 
endfunction


" Returns true if paste mode is enabled
function! HasPaste()
    if &paste
        return 'PASTE MODE  '
    endif
    return ''
endfunction

"Control-n to toggle between True Numbers and True-Relative Numbers
function! NumberToggle()
  if(&relativenumber == 1)
    set number
    set rnu!
  else
    set relativenumber
  endif
endfunc

"Control-m -- Toggle between T/R Nums && No Nums
function! TNumberToggle()
  if(&relativenumber == 1)
    set number!
    set rnu!
  else
    set number
    set relativenumber
  endif
endfunc

nnoremap <C-n> :call NumberToggle()<cr>
nnoremap <C-m> :call TNumberToggle()<cr>

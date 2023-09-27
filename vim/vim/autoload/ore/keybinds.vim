function! ore#keybinds#main() abort
	nmap <silent> <A-Up> :wincmd k<CR>
	nmap <silent> <A-Down> :wincmd j<CR>
	nmap <silent> <A-Left> :wincmd h<CR>
	nmap <silent> <A-Right> :wincmd l<CR>


	" Control HJKL to swap directionally between vimsplits.
	nnoremap <C-H> <C-W><C-H>
	nnoremap <C-J> <C-W><C-J>
	nnoremap <C-K> <C-W><C-K>
	nnoremap <C-L> <C-W><C-L>

	" Shift J | K to swap between tabs
	nnoremap <S-j> gT
	nnoremap <S-k> gt

	" When searching try to be smart about cases 
	set smartcase

	" Highlight search results
	set hlsearch

	" Makes search act like search in modern browsers
	set incsearch

	vnoremap // "zy:let @/="<C-R>z"<CR>


	"###############################################
	" Toggle plugins                               "
	"###############################################

	" F5 to toggle UndoTree Plugin
	nnoremap <F5> :UndotreeToggle<cr> 

	" F5 to toggle System File Tree (NERDtree plugin)
	nnoremap <F6> :NERDTreeToggle<cr>

	" F8 to toggle tagbar plugin
	nmap <F8> :TagbarToggle<CR> 

	" Toggle paste mode on and off
	map <leader>pp :setlocal paste!<cr>


	"###############################################
	" For copy/pasting                             "
	"###############################################

	vnoremap <s-y> y :silent redir! > ~/.vimbuffer <bar> echon @* <bar> redir END <CR> <CR>
	vnoremap <s-p> :'<,'>!cat ~/.vimbuffer<CR>
	nnoremap <s-p> :r ~/.vimbuffer<CR>


	" In visual mode with search 'MatchEnd' -- Bring cursor to end of match
	vnoremap me //e<CR>

	" Dump the date for dating files.
	vnoremap <s-d> c<esc>:exe 'silent norm a' . system("printf $(date '+\%Y/\%m/\%d')")<CR>
	nnoremap <s-d> :exe 'norm i' . system("printf $(date '+\%Y/\%m/\%d')")<CR>
	nnoremap [<s-d> :exe 'norm a' . system("printf $(date '+\%Y/\%m/\%d')")<CR>

    " F5 to toggle System File Tree (NERDtree plugin)
    nnoremap <F6> :NERDTreeToggle<cr>
endfunction

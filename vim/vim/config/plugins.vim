"===========================
"Plugin config
"===========================

"NerdTree
"-----------
"//open a NERDTree automatically when vim starts up if no files were specified
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
"//Stick this in your vimrc to open NERDTree with Ctrl+n 
map <C-n> :NERDTreeToggle<CR>
"//close vim if the only window left open is a NERDTree
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif



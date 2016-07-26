# Vim shotcut


Cheat sheet
===============================

Verbs
-----------
 d : delete
 c : change
 y : yank(copy)
 v : visually select (V for lines)

Modifiers
-----------
 i : inside
 a : around
 NUM : number (e.g.: 1, 2, 10)
 t : searches for something and stops before it
 f : searches for that thing and lands on it
 / : find a string (literal or regex)

Nouns
-----------
 w : word
 s : sentence
 ) : sentence (another way of doing it)
 p : paragraph
 } : paragraph (another way of doing it)
 t : tag (think HTML/XML)
 b : block (think programming)

Move
------------
     k
   h   l
     j
 0 : move to the beginning of the line
 $ : move to the end of the line
 ^ : move to the first non-blank character in the line
 t": jump to right before the next quotes
 f": jump and land on the next quotes

 Moving by word
 ^^^^^^^^^^^^^^
 w : move forward one word
 b : move back one word
 e : move to the end of your word
 W : move forward one big word
 B : move back one big word

 Moving by sentence or paragraph
 
 ) : move forward one sentence
 } : move forward one paragraph

 Moving within the screen
 ^^^^^^^^^^^^^^^^^^^^^^^^
 
 H : move to the top of the screen
 M : move to the middle of the screen
 L : move to the bottom of the screen
 gg : go to the top of the file
 G : go to the bottom of the file
 ^U : move up half a screen
 ^D : move down half a screen
 ^F : page down
 ^B : page up
 
 Jumping back and forth
 
 Ctrl-i : jump to your previous navigation location
 Ctrl-o : jump back to where you were

 Other motions
 
 :$line_numberH : move to a given line number
 M : move to the middle of the screen
 L : move to the bottom of the screen
 ^E : scroll up one line
 ^Y : scroll down one line
 ^U : move up half a page
 ^D : move down half a page
 ^F : move down a page
 ^B : move up a page


 Basic Change/Insert options
 ---------------------------
 i : insert before the cursor
 a : append after the cursor
 I : insert at the beginning of the line
 A : append at the end of the line
 o : open a new line below the current one
 O : open a new line above the current one
 r : replace the one character under your cursor
 R : replace the character under your cursor, but just keep typing afterwards
 cm : change whatever you define as a movement, e.g. a word, or a sentence, or a paragraph.
 C : change the current line from where you’re at
 ct? : change change up to the question mark
 s : substitute from where you are to the next command (noun)
 S : substitute the entire current line

 Basic deletion options
 ------------------------
 x : exterminate (delete) the character under the cursor
 X : exterminate (delete) the character before the cursor
 dm : delete whatever you define as a movement, e.g. a word, or a sentence, or a paragraph.
 dd : delete the current line
 dt. : delete delete from where you are to the period
 D : delete to the end of the line
 J : join the current line with the next one (delete what’s between)


Change Case
----------------
 ~ : changing case


Spellchecking
--------------------
]s : go to next misspelled word
[s : go to last misspelled word
zg : mark a misspelled word as correct
zw : mark a good word as misspelled
z= : get some suggestions for misspelled word

Substitution
--------------------
 :s /foo/bar/g   change "foo" to "bar" in current line
 :%s /foo/bar/g   change "foo" to "bar" in every line

Window
===============
 <C-w>
    s : splite horizontal
    v : splite vetical
    w : 在窗口之间循环
    <hjkl> : 选择相应方向上的窗口
    c : close current window
    o : close other windows

  :edite {filename}
  :sp {filename} 
  :vsp {filename}
  :clo  : close current window
  :on   : close other windows


NERDTree
===============
  :NERDTreeToggle
  o : open the document in current buffer
  s : open new vertical split window
  i : open new horizontal spilt window
  t : open new tab
  T : open new tab while staying in current tab
  gt: cycle though all tabs
  gT: cycle though all tabs (moves to the left)

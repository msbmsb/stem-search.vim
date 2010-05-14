" File:         stem-search.vim
" Description:  StmSrch is a reverse-stem searching script.
" Author:       Mitchell Bowden <mitchellbowden AT gmail DOT com>
" Version:      0.1
" License:      MIT License: http://creativecommons.org/licenses/MIT/
" Last Changed: 1 May 2010
" URL:          http://github.com/msbmsb/stem-search.vim/

" -----------------------------------------------------------------------------
" StmSrch is a reverse-stem searching script. It implements the Porter stemming
" algorithm, by Martin Porter, details of which can be found at:
"   http://tartarus.org/~martin/PorterStemmer/
" It also uses tables for irregular verbs and noun pluralizations. 
" 
" StmSrch command syntax:
"   :StmSrch (<word>)*
"   :ClrStmSrch
"
" Each word input to the :StmSrch command will be stemmed and then formulated
" in such a way as to match possible conjugations or pluralizations. Without 
" any word given for input, it will attempt to stem the current word under the
" cursor via expand('<cword>'). The matching is done using word boundaries 
" \<...\> so not just any substring will match.
"
" For example:
"   :StmSrch search
" will match any of:
"   search, searching, searches, searchers, searched, ...
" and a string of words will work as well, matching in order:
"   :StmSrch thieves are running from bunnies
" will match strings of words like: 
"   thief was ran from bunny
"   thieves be run from bunnies
"
" Use :ClrStmSrch to clear the highlighting for the StmSrch group.
"
" Change the highlight color for StmSrch in the s:StmSrchInit() function
"
" To rebuild the irregular verb or plural noun tables, run:
"   ./scripts/buildIrrDicts.pl [v|n] <irregularWordFile>
" where <irregularWordFile> is a file of word forms, one synset per line and
" the [v|n] option specifies the filename ending to keep output organized
" This script outputs two files, keys.[v|n] and dict.[v|n], which are then
" used to build the dictionaries in the script such as irrNNSKeyDict/irrNNSDict.
" There are two files of these words in the data directory
"
" This was originally written for my own usage, so it may be missing certain
" features that could easily be added in (e.g. multiple-buffer operations).
" -----------------------------------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

if exists('loaded_stmsrch')
  finish
endif
let loaded_stmsrch = 1

" Initializations
fun! s:StmSrchInit()
  " Use this following line to change the highlighting color for StmSrch results
  execute 'highlight StmSrch ctermbg=yellow guibg=yellow'
  let s:matchId = 0
endfun

call <SID>StmSrchInit()

let &cpo = s:save_cpo

" Commands definition
" StmSrch command syntax:
"   :StmSrch (<word>)* [or :StemSearch (<word>)*]
"   :ClrStmSrch
if !(exists(":StmSrch") == 2)
  com! -nargs=* StmSrch :silent call s:StmSrch(<q-args>)
  com! -nargs=* StemSearch :silent call s:StmSrch(<q-args>)
  com! -nargs=0 ClrStmSrch :silent call s:ClearStmSrch()
endif

" Main function
fun! s:StmSrch(words_in)
  let words = split(a:words_in, '\s\+')
  let searchWord = ""
 
  if s:matchId > 3
    call matchdelete(s:matchId)
  endif
  let s:matchId = 0
  execute 'silent syntax clear StmSrch'

  if len(words) == 0
    call insert(words, expand('<cword>'))
  endif

  for w in words
    let stem = s:GetWordStem(w)

    if searchWord != ""
      let searchWord = searchWord."\\s\\+"
    endif
    let searchWord = searchWord.stem
  endfor

  " handle case insensitivity
  if &ignorecase == 1  
    if &smartcase == 1
      set noignorecase

      if match(searchWord, '\u') > -1
        syntax case match
      else
        syntax case ignore
      endif

      set ignorecase
    else
      syntax case ignore
    endif
  else
    syntax case match
  endif

  " perform the actual search in the file
  call search(searchWord)
  " allow n/N for next/previous
  let @/ = searchWord
  " add highlighting
  let s:matchId = matchadd('StmSrch', searchWord, -1)
endfun

" Return word stem string
fun! s:GetWordStem(word)
  " check for match in irregular word tables first
  let irr = s:Irregular(a:word)
  if len(irr) > 0
    let newword = s:BuildWordRE(irr)
    return newword
  endif

  if len(a:word) <= 2
    return a:word
  endif

  let newword = a:word

  " initial y fix
  let changedY = 0
  if newword[0] == 'y'
    let newword = 'Y'.newword[1:]
    let changedY = 1
  endif

  " Porter Stemming
  let newword = s:Step1a(newword)
  let newword = s:Step1b(newword)
  let newword = s:Step1c(newword)
  let newword = s:Step2(newword)
  let newword = s:Step3(newword)
  let newword = s:Step4(newword)
  let newword = s:Step5a(newword)
  let newword = s:Step5b(newword)

  if changedY
    let newword = 'y'.newword[1:]
  endif

  " double check for stem as irregular word for expansion
  if newword != a:word
    let irr = s:Irregular(newword)
    if len(irr) > 0
      let wordre = s:BuildWordRE(irr)
      let newword = "\\(".newword."\\w*\\>\|".wordre."\\)"
      return newword
    endif
  endif

  return "\\<".newword."\\w*"."\\>"
endfun

" Clear all highlighting from the StmSrch method
fun! s:ClearStmSrch()
  execute 'silent syntax clear StmSrch'
  if s:matchId > 3
    call matchdelete(s:matchId)
  endif
  let s:matchId = 0
endfun

"******************************************************
" Porter Stemming
" Variables and methods follow here
"******************************************************
let s:cons = '[^aeiou]'
let s:vow = '[aeiouy]'
let s:conseq = s:cons . '[^aeiouy]*'
let s:vowseq = s:vow . '[aeiou]*'

let s:mgr0 = '^\('.s:conseq.'\)\='.s:vowseq.s:conseq
let s:mgr1 = s:mgr0.s:vowseq.s:conseq
let s:meq1 = s:mgr0.'\('.s:vowseq.'\)\=$'
let s:vins = '^\('.s:conseq.'\)\='.s:vow
let s:gen = '^\(.\{-1,}\)\(ational\|tional\|enci\|anci\|izer\|bli\|alli\|entli\|eli\|ousli\|ization\|ation\|ator\|alism\|iveness\|fulness\|ousness\|aliti\|iviti\|biliti\|logi\)$'

let s:step2dict = { "ational" : "ate", "tional" : "tion", "enci" : "ence", "anci" : "ance", "izer" : "ize", "bli" : "ble", "alli" : "al", "entli" : "ent", "eli" : "e", "ousli" : "ous", "ization" : "ize", "ation" : "ate", "ator" : "ate", "alism" : "al", "iveness" : "ive", "fulness" : "ful", "ousness" : "ous", "aliti" : "al", "iviti" : "ive", "biliti" : "ble", "logi" : "log" }

let s:step3dict = { "icate" : "ic", "ative" : "", "alize" : "al", "iciti" : "ic", "ical" : "ic", "ful" : "", "ness" : "" }

fun! s:Step1a(word)
  let w = a:word
  if a:word[-1:] ==? 's'
    let re1a1 = '^\(.\+\)\(ss\|i\)es$'
    let re1a2 = '^\(.\+\)\([^s]\)s$'
    if w =~ re1a1
      let w = substitute(w, re1a1, '\1\2', "")
    elseif w =~ re1a2
      let w = substitute(w, re1a2, '\1\2', "")
    endif
  endif

  " check existence of stem in irregular words dict
  " not part of original algorithm
  if w != a:word
    let irr = s:Irregular(w)
    if len(irr) > 0
      let wordre = s:BuildWordRE(irr)
      let w = "\\(".w."\\w*\\>\|".wordre."\\)"
    endif
  endif

  return w
endfun

fun! s:Step1b(word)
  let w = a:word
  let re1b1 = '^\(.\+\)eed$'
  let re1b2 = '^\(.\+\)\(ed\|ing\)$'
  if w =~ re1b1
    let stem = substitute(w, re1b1, '\1', "")
    if stem =~ s:mgr0
      let w = w[:-2]
    endif
  elseif w =~ re1b2
    let stem = substitute(w, re1b2, '\1', "")
    if stem =~ s:vins
      let w = stem
      let r1 = '\(at\|bl\|iz\)$'
      let r2 = '^.\+\([^aeiouylsz]\)\1$'
      let r3 = '^'.s:conseq.s:vow.'[^aeiouwxy]$'
      if w =~ r1
        " change in algorithm for search purposes, instead of appending 'e', leave it off
        "let w = w . "e"
      elseif w =~ r2
        let w = w[:-2]
      elseif w =~ r3
        " change in algorithm for search purposes, instead of appending 'e', leave it off
        "let w = w . "e"
      endif
    endif
  endif

  return w
endfun

fun! s:Step1c(word)
  let w = a:word
  if w[-1:] == 'y'
    let stem = w[:-2]
    if stem =~ s:vins
      " change in algorithm for search purposes, instead of appending 'i', leave it off
      " e.g. instead of 'bunny' -> 'bunnies', leave at 'bunn' for the search string '<bunn\w*>'
      "let w = stem . "i"
      let w = stem
    endif
  endif

  return w
endfun

fun! s:Step2(word)
  let w = a:word
  if w =~ s:gen
    let stem = substitute(w, s:gen, '\1', "")
    let suff = substitute(w, s:gen, '\2', "")
    if stem =~ s:mgr0
      let w = stem . s:step2dict[suff]
    endif
  endif

  return w
endfun

fun! s:Step3(word)
  let w = a:word
  let re3 = '^\(.\+\)\(icate\|ative\|alize\|iciti\|ical\|ful\|ness\)$'
  if w =~ re3
    let stem = substitute(w, re3, '\1', "")
    let suff = substitute(w, re3, '\2', "")
    if stem =~ s:mgr0
      let w = stem . s:step3dict[suff]
    endif
  endif

  return w
endfun

fun! s:Step4(word)
  let w = a:word
  let re41 = '^\(.\{-1,}\)\(al\|ance\|ence\|er\|ic\|able\|ible\|ant\|ement\|ment\|ent\|ou\|ism\|ate\|iti\|ous\|ive\|ize\)$'
  let re42 = '^\(.\+\)\(s\|t\)\(ion\)$'
  if w =~ re41
    let stem = substitute(w, re41, '\1', "")
    if stem =~ s:mgr1
      let w = stem
    endif
  elseif w =~ re42
    let stem = substitute(w, re42, '\1\2', "")
    if stem =~ s:mgr1
      let w = stem
    endif
  endif

  return w
endfun

fun! s:Step5a(word)
  let w = a:word
  if w[-1:] == "e"
    let stem = w[:-2]
    let re5a = '^'.s:conseq.s:vow.'[^aeiouwxy]$'
    if (stem =~ s:mgr1) || ((stem =~ s:meq1) && (stem !~ re5a))
      let w = stem
    endif
  endif

  return w
endfun

fun! s:Step5b(word)
  let w = a:word
  if (w =~ 'll$') && (w =~ s:mgr1)
    let w = w[:-2]
  endif

  return w
endfun

" If word argument is in an irregular words dictionary, return the key for the dictionary of 
" possible word formulations
" otherwise return an empty list
fun! s:Irregular(word)
  let irrSpec = []

  if has_key(s:irrVBKeyDict, a:word)
    let irrSpec = ["v", s:irrVBKeyDict[a:word]]
    return irrSpec
  endif

  if has_key(s:irrNNSKeyDict, a:word)
    let irrSpec = ["n", s:irrNNSKeyDict[a:word]]
    return irrSpec
  endif

  return ""
endfun

" For the irregular word dictionary key argument, build the appropriate search string
fun! s:BuildWordRE(irrSpec)
  let newword = ""

  if len(a:irrSpec) < 2
    return ""
  endif

  let irrDict = a:irrSpec[0]
  let irrList = a:irrSpec[1]

  for vList in irrList
    for v in s:GetDictValue(irrDict, vList)
      if newword != ""
        let newword = newword."\\|"
      else
        let v = v."\\w*"
      endif
      let newword = newword."\\<".v."\\>"
    endfor
  endfor

  return "\\(".newword."\\)"
endfun

" Return the list of irregular word formulations for the given key for the given type of 
" irregular word dictionary
fun! s:GetDictValue(type, key)
  if a:type == "v"
    return s:irrVBDict[a:key]
  elseif a:type == "n"
    return s:irrNNSDict[a:key]
  else
    return []
  endif
endfun

" Following are the irregular word dictionaries:
" For each type of irregular word (i.e. verb or noun), there are two dictionaries:
" 1. is an individual word to integer mapping, where the int is the key in the second dict
" 2. is a key to word list, where the word list is all irregular formulations of a synset
" For example:
" irrVBKeyDict = { 'is': 1, 'be': 1, 'was': 1, 'did': 2, 'does': 2, ...}
" irrVBDict = { 1: ['is', 'be', 'was', ...], 2: ['did', 'does', ...], ...}

" word to key VB table
let s:irrVBKeyDict = { 'shine': [241], 'begot': [15], 'wend': [342], 'drest': [79], 'woke': [335], 'proven': [190], 'overshine': [244], 'shore': [239], 'learned': [158], 'buy': [45], 'overbear': [8], 'mislearnt': [159], 'foregone': [104], 'taken': [313], 'overbore': [8], 'give': [115], 'forgone': [105], 'shod': [247], 'light': [167], 'writ': [354], 'uphold': [334], 'bite': [29], 'sook': [211], 'overtook': [314], 'forleave': [161], 'shown': [252], 'sawed': [212], 'clang': [55], 'underget': [112], 'withsay': [218], 'mistook': [177], 'miskenned': [140], 'mischosen': [51], 'misspend': [281], 'strove': [302], 'bide': [25], 'wind': [346], 'forspent': [280], 'foreknow': [144], 'will': [344], 're-lay': [194], 'misbore': [7], 'lain': [164], 'withstood': [291], 'lie': [164], 'throw': [328], 'stolen': [293], 'misled': [156], 'unclad': [57], 'mischoose': [51], 'besought': [22], 'rewrote': [198], 'sneak': [270], 'can': [48], 'ground': [120], 'overseen': [222], 'bless': [31], 'willed': [344], 'outsold': [225], 'left': [160], 'misgive': [116], 'overdrew': [75], 'slayed': [259], 'bit': [29], 'bended': [18], 'miskept': [138], 'shoed': [247], 'seen': [219], 'saken': [211], 'clept': [54], 'forlain': [165], 'drug': [73], 'overwritten': [356], 'stand': [289], 'knew': [143], 'hid': [134], 'swelled': [308], 'may': [171], 'abided': [1], 'outtell': [323], 'stayed': [292], 'shrank': [253], 'thrown': [328], 'tore': [319], 'quethen': [191], 'kent': [139], 'overbought': [46], 'overflown': [102], 'redid': [70], 'weaved': [338], 'overfed': [93], 'withheld': [348], 'knitted': [142], 'worked': [349], 'sweep': [307], 'misspoken': [275], 'undergirt': [114], 'trodden': [331], 'reshot': [250], 'staid': [292], 'mislaid': [151], 'swollen': [308], 'resend': [230], 'flee': [99], 'redraw': [76], 'spilled': [283], 'misfeed': [92], 'hewed': [132], 'beshone': [242], 'spoke': [272], 'unclothe': [57], 'undressed': [82], 'slung': [264], 'prepaid': [186], 'became': [12], 'misshaped': [175, 237], 'graved': [119], 'sweat': [306], 'creep': [60], 'fight': [96], 'foretold': [321], 'strang': [301], 'gone': [117], 'shall': [235], 'rung': [202], 'overdrawn': [75], 'overslip': [267], 'ridden': [199, 200], 'swam': [310], 'resell': [227], 'ran': [205], 'drag': [73], 'dreamed': [78], 'overbuild': [41], 'reave': [192], 'undergirded': [114], 'misbecame': [13], 'molten': [174], 'riven': [204], 'oversell': [226], 'dress': [79], 'grove': [119], 'bade': [24], 'meet': [173], 'undid': [71], 'forelaid': [148], 'underhewn': [133], 'sink': [257], 'smite': [269], 'gird': [113], 'overbuy': [46], 'overdressed': [80], 'beaten': [10], 'spilt': [283], 'missent': [229], 'miswrote': [355], 'mistake': [177], 'shoe': [247], 'sold': [224], 'learnt': [158], 'laded': [146], 'bred': [35], 'shrunken': [253], 'breed': [35], 'resold': [227], 'girded': [113], 'hear': [129], 'slip': [266], 'unbend': [20], 'blow': [32], 'outswear': [305], 'knelt': [141], 'bear': [5], 'outsung': [256], 'outshined': [243], 'underbuy': [47], 'undo': [71], 'told': [320], 'show': [252], 'win': [345], 'swim': [310], 'shitted': [245], 'rode': [200], 'underlain': [166], 'swept': [307], 'proved': [190], 'flown': [101], 'foresaw': [221], 'ring': [202], 'queath': [191], 'forego': [104], 'stunk': [296], 'strode': [298], 'spill': [283], 'sunken': [257], 'prove': [190], 'leapt': [157], 'heard': [129], 'misken': [140], 'foretell': [321], 'begun': [17], 'foreknown': [144], 'partook': [315], 'wring': [353], 'smelt': [268], 'should': [235], 'say': [213], 'underbear': [9], 'mischose': [51], 'sew': [231, 271], 'forgo': [105], 'drunken': [83], 'overborne': [8], 'waxed': [336], 'shave': [238], 'underdone': [72], 'overshot': [249], 'outshine': [243], 'slew': [259], 'sat': [258], 'overbuilt': [41], 'stink': [296], 'seek': [223], 'forerun': [206], 'wedded': [340], 'drunk': [83], 'awoke': [3], 'lade': [146], 'fly': [101], 'beseeched': [22], 'come': [58], 'rose': [203], 'wetted': [343], 'befall': [14], 'keep': [137], 'rewrite': [198], 'rove': [204], 'cleaved': [53], 'withhold': [348], 'miskent': [140], 'bled': [30], 'bereft': [21], 'overstride': [299], 'plead': [189], 'taught': [318], 'interbred': [37], 'stang': [295], 'shriven': [254], 'spit': [286], 'prepay': [186], 'regrow': [124], 'overstridden': [299], 'shrive': [254], 'hide': [134], 'override': [183, 201], 'oversleep': [261], 'behold': [136], 'shaken': [233], 'sting': [295], 'kept': [137], 'overbreed': [38], 'wrang': [353], 'spend': [279], 'found': [97], 'is': [4], 're-laid': [194], 'fallen': [90], 'begat': [15], 'overdrive': [86], 'think': [324], 'misspell': [176, 278], 'outran': [207], 'misheard': [130], 'cleave': [52, 53], 'forbid': [103], 'dived': [65], 'stuck': [294], 'sped': [276], 'wound': [346], 'undergrown': [125], 'outspend': [282], 'build': [40], 'bursted': [44], 'drank': [83], 'misbegotten': [16], 'sworn': [303], 'quethe': [191], 'underborne': [9], 'swolten': [309], 'overlaid': [152], 'were': [4], 'swum': [310], 'overworked': [350], 'oversew': [232], 'arose': [2], 'bid': [24], 'pay': [184], 'forleft': [161], 'mislearn': [159], 'swolt': [309], 'understand': [290], 'rethink': [196, 326], 'overwrought': [350], 'strung': [301], 'got': [110], 'withstand': [291], 'oversewn': [232], 'known': [143], 'understood': [290], 'shot': [248], 'sunk': [257], 'missaid': [216], 'cloven': [52], 'laden': [146], 'overdid': [69], 'upheld': [334], 'slang': [264], 'misknew': [145], 'sling': [264], 'overslid': [263], 'hold': [135], 'gave': [115], 'underlaid': [153], 'abide': [1], 'overshaken': [234], 'spoil': [287], 'undertaken': [317], 'girt': [113], 'undergot': [112], 'forsaken': [108], 'withdraw': [347], 'retrod': [332], 'strewed': [297], 'besee': [220], 'graven': [119], 'felt': [95], 'shit': [245, 246], 'rent': [193], 'misborne': [7], 'deal': [61], 'run': [205], 'lent': [162], 'regrew': [124], 'make': [169], 'stank': [296], 'misspelled': [176, 278], 'overdrunk': [84], 'inbred': [36], 'striven': [302], 'underdig': [64], 'mown': [179], 'slain': [259], 'forsake': [108], 'forbear': [6], 'undertook': [317], 'withdrawn': [347], 'interweave': [339], 'misknown': [145], 'overdrove': [86], 'rise': [203], 'held': [135], 'forwent': [105], 'torn': [319], 'slide': [262], 'take': [313], 'forbad': [103], 'underlie': [166], 'choose': [50], 'slept': [260], 'outswore': [305], 'overpaid': [185], 'overhung': [181], 'sent': [228], 'forbade': [103], 'awoken': [3], 'bespeak': [273], 'grew': [121], 'rerun': [209], 'overslipt': [267], 'overspill': [284], 'fled': [99], 'overrun': [208], 'hanged': [126], 'overdone': [69], 'retell': [322], 'overgrow': [123], 'eat': [88], 'dove': [65], 'dwelt': [87], 'spat': [286], 'goes': [117], 'forlend': [163], 'wed': [340], 'born': [5], 'overblown': [33], 'underdressed': [81], 'retold': [322], 'eaten': [88], 'shat': [245, 246], 'beget': [15], 'browbeaten': [11], 'teach': [318], 'forgiven': [107], 'spoiled': [287], 'clothed': [56], 'wake': [335], 'foreseen': [221], 'sowed': [271], 'forgotten': [106], 'lose': [168], 'spoken': [272], 'made': [169], 'given': [115], 'forspend': [280], 'met': [173], 'smelled': [268], 'overspilt': [284], 'wax': [336], 'stridden': [298], 'overshone': [244], 'underwrote': [357], 'beshine': [242], 'molt': [174], 'fell': [90], 'beseech': [22], 'swear': [303], 'or': [191], 'could': [48], 'misgiven': [116], 'does': [66], 'writhen': [358], 'bereave': [21], 'underhung': [127], 'built': [40], 'overeaten': [89], 'broke': [34], 'misdid': [67], 'bind': [26], 'waxen': [336], 'smitten': [269], 'overslidden': [263], 'shape': [236], 'wore': [337], 'slidden': [262], 'rewritten': [198], 'wreak': [352], 'are': [4], 'mishear': [130], 'shedded': [240], 'clepe': [54], 'slipped': [266], 'overshined': [244], 'lend': [162], 'froze': [109], 'bring': [39], 'misdone': [67], 'overwrite': [356], 'swelted': [309], 'undergrow': [125], 'begin': [17], 'reran': [209], 'kneel': [141], 'misbecome': [13], 'dragged': [73], 'befallen': [14], 'feed': [91], 'overgrown': [123], 'overblow': [33], 'redrawn': [76], 'overhear': [131], 'unwound': [333], 'underdrawn': [77], 'arisen': [2], 'cleped': [54], 'bereaved': [21], 'become': [12], 'driven': [85], 'outgrew': [122, 180], 'catch': [49], 'underfeed': [94], 'sleep': [260], 'strike': [300], 'bided': [25], 'dwell': [87], 'wrought': [349], 'outthrow': [329], 'threw': [328], 'took': [313], 'see': [219], 'abode': [1], 'flew': [101], 'slipt': [266], 'dug': [63], 'overcome': [59], 'shove': [238], 'lighted': [167], 'won': [345], 'slid': [262], 'burned': [43], 'underpay': [188], 'weep': [341], 'struck': [300], 'bleed': [30], 'fit': [98], 'sewed': [231], 'drove': [85], 'missend': [229], 'awake': [3], 'undress': [82], 'forbidden': [103], 'repaid': [187, 195], 'interbreed': [37], 'dig': [63], 'grinded': [120], 'shrink': [253], 'underran': [210], 'oversold': [226], 'clove': [52], 'dealt': [61], 'ate': [88], 'interwove': [339], 'bore': [5], 'bespoken': [273], 'shitten': [246], 'underdug': [64], 'throve': [327], 'speed': [276], 'overbred': [38], 'strew': [297], 'thrived': [327], 'said': [213], 'draw': [74], 'swing': [311], 'sow': [271], 'wept': [341], 'outsing': [256], 'forsworn': [304], 'bend': [18], 'chose': [50], 'thought': [324], 'lead': [155], 'wet': [343], 'would': [344], 'spell': [277], 'fitted': [98], 'slunk': [265], 'shined': [241], 'might': [171], 'misdeal': [62], 'sing': [255], 'misdealt': [62], 'strived': [302], 'forgot': [106], 'overdrank': [84], 'misfed': [92], 'mislay': [151], 'fed': [91], 'forbore': [6], 'forewent': [104], 'underlay': [153, 166], 'mislearned': [159], 'miswritten': [355], 'wrothe': [358], 'cling': [55], 'feel': [95], 'wrung': [353], 'overtake': [314], 'sang': [255], 'overbend': [19], 'miskeep': [138], 'overlay': [152, 182], 'forelay': [148], 'forgave': [107], 'retrodden': [332], 'spelled': [277], 'misbeget': [16], 'betted': [23], 'overdrink': [84], 'undergird': [114], 'outthrew': [329], 'outdo': [68], 'forgive': [107], 'repay': [187, 195], 'underdrest': [81], 'am': [4], 'get': [110], 'swell': [308], 'outgrow': [122, 180], 'befell': [14], 'shodden': [247], 'unbind': [27], 'overhang': [181], 'spun': [285], 'go': [117], 'forelie': [165], 'outrun': [207], 'showed': [252], 'naysaid': [217], 'overshoot': [249], 'misspent': [281], 'unbound': [27], 'know': [143], 'interwoven': [339], 'shear': [239], 'has': [128], 'miswrite': [355], 'string': [301], 'rived': [204], 'reshoot': [250], 'sheared': [239], 'thriven': [327], 'pled': [189], 'partaken': [315], 'break': [34], 'ken': [139], 'freeze': [109], 'foreknew': [144], 'mowed': [179], 'wrote': [354], 'rewound': [197], 'burnt': [43], 'underdraw': [77], 'unclothed': [57], 'bound': [26], 'shone': [241], 'tell': [320], 'slay': [259], 'sewn': [231], 'came': [58], 'span': [285], 'stole': [293], 'leave': [160], 'underbore': [9], 'kenned': [139], 'ridded': [199], 'rethought': [196, 326], 'forlaid': [149], 'overhanged': [181], 'bidded': [24], 'outsang': [256], 'beseen': [220], 'clung': [55], 'forswear': [304], 'overtaken': [314], 'overbent': [19], 'underwent': [118], 'inlay': [150], 'fall': [90], 'overlain': [182], 'writhed': [358], 'lit': [167], 'underdress': [81], 'kneeled': [141], 'strewn': [297], 'outshone': [243], 'work': [349], 'abidden': [1], 'overblew': [33], 'grown': [121], 'wended': [342], 'frozen': [109], 'underwrite': [357], 'undershot': [251], 'shaped': [236], 'drew': [74], 'swoll': [308], 'speak': [272], 'pleaded': [189], 'thrusted': [330], 'overflew': [102], 'browbeat': [11], 'sneaked': [270], 'worthen': [351], 'withdrew': [347], 'overgrew': [123], 'spelt': [277], 'sell': [224], 'chosen': [50], 'misgave': [116], 'went': [117, 342], 'overslide': [263], 'drink': [83], 'grind': [120], 'overdrest': [80], 'burst': [44], 'rebuild': [42], 'dive': [65], 'gainsaid': [215], 'forsay': [214], 'rid': [199], 'bent': [18], 'forsaid': [214], 'gotten': [110], 'retaken': [316], 'tread': [331], 'sprung': [288], 'oversewed': [232], 'woven': [338], 'flung': [100], 'underdrew': [77], 'swung': [311], 'send': [228], 'clothe': [56], 'misgot': [111], 'overfeed': [93], 'overswing': [312], 'been': [4], 'undrest': [82], 'underpaid': [188], 'writhe': [358], 'undone': [71], 'quoth': [191], 'outgrown': [122, 180], 'sprang': [288], 'smell': [268], 'underbind': [28], 'bode': [25], 'paid': [184], 'melt': [174], 'was': [4], 'rewind': [197], 'forspoken': [274], 'partake': [315], 'outdid': [68], 'shrunk': [253], 'steal': [293], 'shapen': [236], 'grave': [119], 'shaved': [238], 'bitten': [29], 'lost': [168], 'redone': [70], 'retook': [316], 'overeat': [89], 'swelt': [309], 'overshook': [234], 'overrode': [183, 201], 'speeded': [276], 'sit': [258], 'misdo': [67], 'underdo': [72], 'arise': [2], 'underfed': [94], 'strided': [298], 'retread': [332], 'undershoot': [251], 'remade': [170], 'overridden': [183, 201], 'learn': [158], 'written': [354], 'retake': [316], 'misbegot': [16], 'thrive': [327], 'withsaid': [218], 'overdriven': [86], 'hung': [126], 'gainsay': [215], 'have': [128], 'hew': [132], 'resent': [230], 'misunderstood': [178], 'missay': [216], 'reft': [192], 'overswung': [312], 'bidden': [24, 25], 'boughten': [45], 'shite': [246], 'led': [155], 'thrust': [330], 'sung': [255], 'besaw': [220], 'redrew': [76], 'underdid': [72], 'inlaid': [150], 'oversaw': [222], 'ride': [200], 'outtold': [323], 'overwrote': [356], 'inbreed': [36], 'write': [354], 'shew': [252], 'dressed': [79], 'overdress': [80], 'sweated': [306], 'outspent': [282], 'dreamt': [78], 'burn': [43], 'underbought': [47], 'crept': [60], 'spoilt': [287], 'smit': [269], 'shed': [240], 'wove': [338], 'hewn': [132], 'broken': [34], 'forspeak': [274], 'weave': [338], 'stricken': [300], 'naysay': [217], 'waylay': [154], 'forborne': [6], 'hang': [126], 'laid': [147], 'forlent': [163], 'underbound': [28], 'overwork': [350], 'overspilled': [284], 'drawn': [74], 'mean': [172], 'brought': [39], 'wear': [337], 'overcame': [59], 'began': [17], 'undergrew': [125], 'forlaft': [161], 'hidden': [134], 'underhang': [127], 'spent': [279], 'clad': [56], 'misbear': [7], 'stick': [294], 'worth': [351], 'overstrode': [299], 'misshape': [175, 237], 'grow': [121], 'underrun': [210], 'misget': [111], 'smote': [269], 'leaped': [157], 'undergo': [118], 'overate': [89], 'overpay': [185], 'snuck': [270], 'beat': [10], 'bought': [45], 'stung': [295], 'bespoke': [273], 'beheld': [136], 'shorn': [239], 'swore': [303], 'rive': [204], 'forlay': [149, 165], 'caught': [49], 'outsworn': [305], 'overlie': [182], 'wreaken': [352], 'blown': [32], 'slink': [265], 'underwritten': [357], 'swang': [311], 'mislead': [156], 'shake': [233], 'shrove': [254], 'did': [66], 'bet': [23], 'misspelt': [176, 278], 'do': [66], 'misgotten': [111], 'overheard': [131], 'sawn': [212], 'oversee': [222], 'blessed': [31], 'find': [97], 'undergotten': [112], 'risen': [203], 'woken': [335], 'begotten': [15], 'rend': [193], 'sown': [271], 'foresee': [221], 'sake': [211], 'dwelled': [87], 'stood': [289], 'says': [213], 'unbent': [20], 'sought': [223], 'blest': [31], 'unwind': [333], 'strive': [302], 'overslept': [261], 'melted': [174], 'stay': [292], 'misshapen': [175, 237], 'blew': [32], 'worn': [337], 'trod': [331], 'misspoke': [275], 'remake': [170], 'underhew': [133], 'done': [66], 'rebuilt': [42], 'regrown': [124], 'outthought': [325], 'overran': [208], 'redo': [70], 'underhewed': [133], 'spring': [288], 'forspoke': [274], 'dream': [78], 'wroken': [352], 'wreaked': [352], 'outdone': [68], 'overshake': [234], 'fling': [100], 'leap': [157], 'lay': [147, 164], 'fought': [96], 'sank': [257], 'overdraw': [75], 'meant': [172], 'mow': [179], 'misknow': [145], 'forsook': [108], 'spin': [285], 'shoot': [248], 'overslipped': [267], 'be': [4], 'cleft': [52, 53], 'knit': [142], 'borne': [5], 'undertake': [317], 'outthink': [325], 'forget': [106], 'forswore': [304], 'stride': [298], 'waylaid': [154], 'outthrown': [329], 'saw': [212, 219], 'drive': [85], 'tear': [319], 'foreran': [206], 'had': [128], 'outsell': [225], 'misunderstand': [178], 'rang': [202], 'overdo': [69], 'undergone': [118], 'mistaken': [177], 'shaven': [238], 'misspeak': [275], 'overfly': [102], 'shook': [233] }


" key to full list of VB
let s:irrVBDict = { 1: ['abide', 'abode', 'abided', 'abidden'], 2: ['arise', 'arose', 'arisen'], 3: ['awake', 'awoke', 'awoken'], 4: ['be', 'am', 'are', 'is', 'was', 'were', 'been'], 5: ['bear', 'bore', 'born', 'borne'], 6: ['forbear', 'forbore', 'forborne'], 7: ['misbear', 'misbore', 'misborne'], 8: ['overbear', 'overbore', 'overborne'], 9: ['underbear', 'underbore', 'underborne'], 10: ['beat', 'beaten'], 11: ['browbeat', 'browbeaten'], 12: ['become', 'became'], 13: ['misbecome', 'misbecame'], 14: ['befall', 'befell', 'befallen'], 15: ['beget', 'begot', 'begat', 'begotten'], 16: ['misbeget', 'misbegot', 'misbegotten'], 17: ['begin', 'began', 'begun'], 18: ['bend', 'bent', 'bended'], 19: ['overbend', 'overbent'], 20: ['unbend', 'unbent'], 21: ['bereave', 'bereaved', 'bereft'], 22: ['beseech', 'besought', 'beseeched'], 23: ['bet', 'betted'], 24: ['bid', 'bade', 'bidded', 'bidden'], 25: ['bide', 'bided', 'bode', 'bidden'], 26: ['bind', 'bound'], 27: ['unbind', 'unbound'], 28: ['underbind', 'underbound'], 29: ['bite', 'bit', 'bitten'], 30: ['bleed', 'bled'], 31: ['bless', 'blessed', 'blest'], 32: ['blow', 'blew', 'blown'], 33: ['overblow', 'overblew', 'overblown'], 34: ['break', 'broke', 'broken'], 35: ['breed', 'bred'], 36: ['inbreed', 'inbred'], 37: ['interbreed', 'interbred'], 38: ['overbreed', 'overbred'], 39: ['bring', 'brought'], 40: ['build', 'built'], 41: ['overbuild', 'overbuilt'], 42: ['rebuild', 'rebuilt'], 43: ['burn', 'burned', 'burnt'], 44: ['burst', 'bursted'], 45: ['buy', 'bought', 'boughten'], 46: ['overbuy', 'overbought'], 47: ['underbuy', 'underbought'], 48: ['can', 'could'], 49: ['catch', 'caught'], 50: ['choose', 'chose', 'chosen'], 51: ['mischoose', 'mischose', 'mischosen'], 52: ['cleave', 'clove', 'cloven', 'cleft'], 53: ['cleave', 'cleft', 'cleaved'], 54: ['clepe', 'cleped', 'clept'], 55: ['cling', 'clang', 'clung'], 56: ['clothe', 'clothed', 'clad'], 57: ['unclothe', 'unclothed', 'unclad'], 58: ['come', 'came'], 59: ['overcome', 'overcame'], 60: ['creep', 'crept'], 61: ['deal', 'dealt'], 62: ['misdeal', 'misdealt'], 63: ['dig', 'dug'], 64: ['underdig', 'underdug'], 65: ['dive', 'dived', 'dove'], 66: ['do', 'does', 'did', 'done'], 67: ['misdo', 'misdid', 'misdone'], 68: ['outdo', 'outdid', 'outdone'], 69: ['overdo', 'overdid', 'overdone'], 70: ['redo', 'redid', 'redone'], 71: ['undo', 'undid', 'undone'], 72: ['underdo', 'underdid', 'underdone'], 73: ['drag', 'drug', 'dragged'], 74: ['draw', 'drew', 'drawn'], 75: ['overdraw', 'overdrew', 'overdrawn'], 76: ['redraw', 'redrew', 'redrawn'], 77: ['underdraw', 'underdrew', 'underdrawn'], 78: ['dream', 'dreamed', 'dreamt'], 79: ['dress', 'dressed', 'drest'], 80: ['overdress', 'overdressed', 'overdrest'], 81: ['underdress', 'underdressed', 'underdrest'], 82: ['undress', 'undressed', 'undrest'], 83: ['drink', 'drank', 'drunk', 'drunken'], 84: ['overdrink', 'overdrank', 'overdrunk'], 85: ['drive', 'drove', 'driven'], 86: ['overdrive', 'overdrove', 'overdriven'], 87: ['dwell', 'dwelt', 'dwelled'], 88: ['eat', 'ate', 'eaten'], 89: ['overeat', 'overate', 'overeaten'], 90: ['fall', 'fell', 'fallen'], 91: ['feed', 'fed'], 92: ['misfeed', 'misfed'], 93: ['overfeed', 'overfed'], 94: ['underfeed', 'underfed'], 95: ['feel', 'felt'], 96: ['fight', 'fought'], 97: ['find', 'found'], 98: ['fit', 'fitted'], 99: ['flee', 'fled'], 100: ['fling', 'flung'], 101: ['fly', 'flew', 'flown'], 102: ['overfly', 'overflew', 'overflown'], 103: ['forbid', 'forbad', 'forbade', 'forbidden'], 104: ['forego', 'forewent', 'foregone'], 105: ['forgo', 'forwent', 'forgone'], 106: ['forget', 'forgot', 'forgotten'], 107: ['forgive', 'forgave', 'forgiven'], 108: ['forsake', 'forsook', 'forsaken'], 109: ['freeze', 'froze', 'frozen'], 110: ['get', 'got', 'gotten'], 111: ['misget', 'misgot', 'misgotten'], 112: ['underget', 'undergot', 'undergotten'], 113: ['gird', 'girt', 'girded'], 114: ['undergird', 'undergirt', 'undergirded'], 115: ['give', 'gave', 'given'], 116: ['misgive', 'misgave', 'misgiven'], 117: ['go', 'goes', 'went', 'gone'], 118: ['undergo', 'underwent', 'undergone'], 119: ['grave', 'grove', 'graved', 'graven'], 120: ['grind', 'ground', 'grinded'], 121: ['grow', 'grew', 'grown'], 122: ['outgrow', 'outgrew', 'outgrown'], 123: ['overgrow', 'overgrew', 'overgrown'], 124: ['regrow', 'regrew', 'regrown'], 125: ['undergrow', 'undergrew', 'undergrown'], 126: ['hang', 'hung', 'hanged'], 127: ['underhang', 'underhung'], 128: ['have', 'has', 'had'], 129: ['hear', 'heard'], 130: ['mishear', 'misheard'], 131: ['overhear', 'overheard'], 132: ['hew', 'hewed', 'hewn'], 133: ['underhew', 'underhewed', 'underhewn'], 134: ['hide', 'hid', 'hidden'], 135: ['hold', 'held'], 136: ['behold', 'beheld'], 137: ['keep', 'kept'], 138: ['miskeep', 'miskept'], 139: ['ken', 'kenned', 'kent'], 140: ['misken', 'miskenned', 'miskent'], 141: ['kneel', 'knelt', 'kneeled'], 142: ['knit', 'knitted'], 143: ['know', 'knew', 'known'], 144: ['foreknow', 'foreknew', 'foreknown'], 145: ['misknow', 'misknew', 'misknown'], 146: ['lade', 'laded', 'laden'], 147: ['lay', 'laid'], 148: ['forelay', 'forelaid'], 149: ['forlay', 'forlaid'], 150: ['inlay', 'inlaid'], 151: ['mislay', 'mislaid'], 152: ['overlay', 'overlaid'], 153: ['underlay', 'underlaid'], 154: ['waylay', 'waylaid'], 155: ['lead', 'led'], 156: ['mislead', 'misled'], 157: ['leap', 'leaped', 'leapt'], 158: ['learn', 'learned', 'learnt'], 159: ['mislearn', 'mislearned', 'mislearnt'], 160: ['leave', 'left'], 161: ['forleave', 'forleft', 'forlaft'], 162: ['lend', 'lent'], 163: ['forlend', 'forlent'], 164: ['lie', 'lay', 'lain'], 165: ['forelie', 'forlay', 'forlain'], 166: ['underlie', 'underlay', 'underlain'], 167: ['light', 'lit', 'lighted'], 168: ['lose', 'lost'], 169: ['make', 'made'], 170: ['remake', 'remade'], 171: ['may', 'might'], 172: ['mean', 'meant'], 173: ['meet', 'met'], 174: ['melt', 'melted', 'molt', 'molten'], 175: ['misshape', 'misshaped', 'misshapen'], 176: ['misspell', 'misspelled', 'misspelt'], 177: ['mistake', 'mistook', 'mistaken'], 178: ['misunderstand', 'misunderstood'], 179: ['mow', 'mowed', 'mown'], 180: ['outgrow', 'outgrew', 'outgrown'], 181: ['overhang', 'overhung', 'overhanged'], 182: ['overlie', 'overlay', 'overlain'], 183: ['override', 'overrode', 'overridden'], 184: ['pay', 'paid'], 185: ['overpay', 'overpaid'], 186: ['prepay', 'prepaid'], 187: ['repay', 'repaid'], 188: ['underpay', 'underpaid'], 189: ['plead', 'pleaded', 'pled'], 190: ['prove', 'proved', 'proven'], 191: ['queath', 'or', 'quethe', 'quoth', 'quethen'], 192: ['reave', 'reft'], 193: ['rend', 'rent'], 194: ['re-lay', 're-laid'], 195: ['repay', 'repaid'], 196: ['rethink', 'rethought'], 197: ['rewind', 'rewound'], 198: ['rewrite', 'rewrote', 'rewritten'], 199: ['rid', 'ridded', 'ridden'], 200: ['ride', 'rode', 'ridden'], 201: ['override', 'overrode', 'overridden'], 202: ['ring', 'rang', 'rung'], 203: ['rise', 'rose', 'risen'], 204: ['rive', 'rived', 'rove', 'riven'], 205: ['run', 'ran'], 206: ['forerun', 'foreran'], 207: ['outrun', 'outran'], 208: ['overrun', 'overran'], 209: ['rerun', 'reran'], 210: ['underrun', 'underran'], 211: ['sake', 'sook', 'saken'], 212: ['saw', 'sawed', 'sawn'], 213: ['say', 'says', 'said'], 214: ['forsay', 'forsaid'], 215: ['gainsay', 'gainsaid'], 216: ['missay', 'missaid'], 217: ['naysay', 'naysaid'], 218: ['withsay', 'withsaid'], 219: ['see', 'saw', 'seen'], 220: ['besee', 'besaw', 'beseen'], 221: ['foresee', 'foresaw', 'foreseen'], 222: ['oversee', 'oversaw', 'overseen'], 223: ['seek', 'sought'], 224: ['sell', 'sold'], 225: ['outsell', 'outsold'], 226: ['oversell', 'oversold'], 227: ['resell', 'resold'], 228: ['send', 'sent'], 229: ['missend', 'missent'], 230: ['resend', 'resent'], 231: ['sew', 'sewed', 'sewn'], 232: ['oversew', 'oversewed', 'oversewn'], 233: ['shake', 'shook', 'shaken'], 234: ['overshake', 'overshook', 'overshaken'], 235: ['shall', 'should'], 236: ['shape', 'shaped', 'shapen'], 237: ['misshape', 'misshaped', 'misshapen'], 238: ['shave', 'shove', 'shaved', 'shaven'], 239: ['shear', 'shore', 'sheared', 'shorn'], 240: ['shed', 'shedded'], 241: ['shine', 'shined', 'shone'], 242: ['beshine', 'beshone'], 243: ['outshine', 'outshined', 'outshone'], 244: ['overshine', 'overshined', 'overshone'], 245: ['shit', 'shat', 'shitted'], 246: ['shite', 'shit', 'shat', 'shitten'], 247: ['shoe', 'shoed', 'shod', 'shodden'], 248: ['shoot', 'shot'], 249: ['overshoot', 'overshot'], 250: ['reshoot', 'reshot'], 251: ['undershoot', 'undershot'], 252: ['show', 'showed', 'shew', 'shown'], 253: ['shrink', 'shrank', 'shrunk', 'shrunken'], 254: ['shrive', 'shrove', 'shriven'], 255: ['sing', 'sang', 'sung'], 256: ['outsing', 'outsang', 'outsung'], 257: ['sink', 'sank', 'sunk', 'sunken'], 258: ['sit', 'sat'], 259: ['slay', 'slew', 'slayed', 'slain'], 260: ['sleep', 'slept'], 261: ['oversleep', 'overslept'], 262: ['slide', 'slid', 'slidden'], 263: ['overslide', 'overslid', 'overslidden'], 264: ['sling', 'slang', 'slung'], 265: ['slink', 'slunk'], 266: ['slip', 'slipped', 'slipt'], 267: ['overslip', 'overslipped', 'overslipt'], 268: ['smell', 'smelled', 'smelt'], 269: ['smite', 'smote', 'smit', 'smitten'], 270: ['sneak', 'sneaked', 'snuck'], 271: ['sow', 'sowed', 'sew', 'sown'], 272: ['speak', 'spoke', 'spoken'], 273: ['bespeak', 'bespoke', 'bespoken'], 274: ['forspeak', 'forspoke', 'forspoken'], 275: ['misspeak', 'misspoke', 'misspoken'], 276: ['speed', 'sped', 'speeded'], 277: ['spell', 'spelled', 'spelt'], 278: ['misspell', 'misspelled', 'misspelt'], 279: ['spend', 'spent'], 280: ['forspend', 'forspent'], 281: ['misspend', 'misspent'], 282: ['outspend', 'outspent'], 283: ['spill', 'spilled', 'spilt'], 284: ['overspill', 'overspilled', 'overspilt'], 285: ['spin', 'span', 'spun'], 286: ['spit', 'spat'], 287: ['spoil', 'spoiled', 'spoilt'], 288: ['spring', 'sprang', 'sprung'], 289: ['stand', 'stood'], 290: ['understand', 'understood'], 291: ['withstand', 'withstood'], 292: ['stay', 'stayed', 'staid'], 293: ['steal', 'stole', 'stolen'], 294: ['stick', 'stuck'], 295: ['sting', 'stung', 'stang'], 296: ['stink', 'stank', 'stunk'], 297: ['strew', 'strewed', 'strewn'], 298: ['stride', 'strode', 'strided', 'stridden'], 299: ['overstride', 'overstrode', 'overstridden'], 300: ['strike', 'struck', 'stricken'], 301: ['string', 'strang', 'strung'], 302: ['strive', 'strove', 'strived', 'striven'], 303: ['swear', 'swore', 'sworn'], 304: ['forswear', 'forswore', 'forsworn'], 305: ['outswear', 'outswore', 'outsworn'], 306: ['sweat', 'sweated'], 307: ['sweep', 'swept'], 308: ['swell', 'swelled', 'swoll', 'swollen'], 309: ['swelt', 'swolt', 'swelted', 'swolten'], 310: ['swim', 'swam', 'swum'], 311: ['swing', 'swang', 'swung'], 312: ['overswing', 'overswung'], 313: ['take', 'took', 'taken'], 314: ['overtake', 'overtook', 'overtaken'], 315: ['partake', 'partook', 'partaken'], 316: ['retake', 'retook', 'retaken'], 317: ['undertake', 'undertook', 'undertaken'], 318: ['teach', 'taught'], 319: ['tear', 'tore', 'torn'], 320: ['tell', 'told'], 321: ['foretell', 'foretold'], 322: ['retell', 'retold'], 323: ['outtell', 'outtold'], 324: ['think', 'thought'], 325: ['outthink', 'outthought'], 326: ['rethink', 'rethought'], 327: ['thrive', 'thrived', 'throve', 'thriven'], 328: ['throw', 'threw', 'thrown'], 329: ['outthrow', 'outthrew', 'outthrown'], 330: ['thrust', 'thrusted'], 331: ['tread', 'trod', 'trodden'], 332: ['retread', 'retrod', 'retrodden'], 333: ['unwind', 'unwound'], 334: ['uphold', 'upheld'], 335: ['wake', 'woke', 'woken'], 336: ['wax', 'waxed', 'waxen'], 337: ['wear', 'wore', 'worn'], 338: ['weave', 'weaved', 'wove', 'woven'], 339: ['interweave', 'interwove', 'interwoven'], 340: ['wed', 'wedded'], 341: ['weep', 'wept'], 342: ['wend', 'wended', 'went'], 343: ['wet', 'wetted'], 344: ['will', 'would', 'willed'], 345: ['win', 'won'], 346: ['wind', 'wound'], 347: ['withdraw', 'withdrew', 'withdrawn'], 348: ['withhold', 'withheld'], 349: ['work', 'worked', 'wrought'], 350: ['overwork', 'overworked', 'overwrought'], 351: ['worth', 'worthen'], 352: ['wreak', 'wreaked', 'wreaken', 'wroken'], 353: ['wring', 'wrang', 'wrung'], 354: ['write', 'wrote', 'writ', 'written'], 355: ['miswrite', 'miswrote', 'miswritten'], 356: ['overwrite', 'overwrote', 'overwritten'], 357: ['underwrite', 'underwrote', 'underwritten'], 358: ['writhe', 'writhed', 'wrothe', 'writhen'] }

" word to key in NN table
let s:irrNNSKeyDict = { 'calf': [1], 'kangaroo': [28], 'foci': [71], 'nebulas': [61], 'zeroes': [55], 'censuses': [66], 'cherubim': [113], 'terminus': [78], 'life': [7], 'memoranda': [85], 'zeros': [55], 'tempi': [111], 'errata': [83], 'curriculum': [81], 'amoebae': [57], 'corpora': [63], 'mottos': [51], 'solos': [41], 'bacilli': [69], 'woman': [23], 'apexes': [89], 'zero': [55], 'halves': [3], 'shelves': [12], 'apices': [89], 'symposiums': [88], 'zoo': [46], 'nebula': [61], 'man': [20], 'automata': [109], 'embargoes': [29], 'prospectuses': [67], 'cargos': [48], 'thesis': [106], 'leaves': [6], 'stratum': [87], 'no': [52], 'strata': [87], 'parenthesis': [104], 'ox': [25], 'syllabi': [77], 'leaf': [6], 'oasis': [103], 'erratum': [83], 'cactuses': [70], 'data': [82], 'emphasis': [100], 'symposia': [88], 'teeth': [22], 'wolf': [15], 'indexes': [92], 'prospectus': [67], 'women': [23], 'genera': [64], 'tomato': [35], 'sheaf': [11], 'hypotheses': [101], 'curricula': [81], 'viscera': [68], 'matrices': [93], 'census': [66], 'halos': [49], 'goose': [18], 'virtuosi': [112], 'synopses': [105], 'memos': [32], 'formulas': [59], 'vortices': [94], 'auto': [26], 'bacteria': [80], 'bacterium': [80], 'children': [24], 'schema': [115], 'analyses': [95], 'formulae': [59], 'larvae': [60], 'autos': [26], 'video': [45], 'ova': [86], 'cacti': [70], 'pimentos': [38], 'vetoes': [39], 'mosquitoes': [50], 'tornadoes': [53], 'volcanos': [54], 'geese': [18], 'symposium': [88], 'seraph': [114], 'mosquito': [50], 'tornados': [53], 'echo': [27], 'solo': [41], 'alga': [56], 'child': [24], 'syllabus': [77], 'algae': [56], 'termini': [78], 'scarf': [9], 'cherub': [113], 'tornado': [53], 'memorandum': [85], 'lice': [19], 'mottoes': [51], 'loaves': [8], 'buffalos': [47], 'octopuses': [74], 'octopi': [74], 'self': [10], 'axis': [96], 'hooves': [4], 'buffalo': [47], 'haloes': [49], 'nuclei': [73], 'buffaloes': [47], 'tattoo': [44], 'viscus': [68], 'libretto': [110], 'appendices': [90], 'alumnus': [65], 'amoeba': [57], 'pro': [40], 'kangaroos': [28], 'elf': [2], 'matrixes': [93], 'ovum': [86], 'radius': [75], 'seraphim': [114], 'memo': [32], 'wolves': [15], 'veto': [39], 'tattoos': [44], 'antenna': [58], 'vertebrae': [62], 'bases': [97], 'photo': [34], 'bacillus': [69], 'appendix': [90], 'emphases': [100], 'larva': [60], 'scarves': [9], 'alumni': [65], 'nos': [52], 'formula': [59], 'foot': [17], 'pros': [40], 'syllabuses': [77], 'hero': [31], 'selves': [10], 'theses': [106], 'motto': [51], 'analysis': [95], 'cargo': [48], 'virtuoso': [112], 'thieves': [13], 'soprano': [42], 'knife': [5], 'men': [20], 'criterion': [107], 'stimulus': [76], 'indices': [92], 'cactus': [70], 'appendixes': [90], 'antennas': [58], 'index': [92], 'crisis': [98], 'oxen': [25], 'nebulae': [61], 'matrix': [93], 'axes': [96], 'hypothesis': [101], 'synopsis': [105], 'kilos': [30], 'mouse': [21], 'studios': [43], 'criteria': [107], 'studio': [43], 'corpus': [63], 'neurosis': [102], 'torpedoes': [37], 'shelf': [12], 'datum': [82], 'half': [3], 'fireman': [16], 'amoebas': [57], 'cervices': [91], 'torpedo': [37], 'calves': [1], 'diagnosis': [99], 'antennae': [58], 'volcanoes': [54], 'oases': [103], 'tomatoes': [35], 'elves': [2], 'phenomena': [108], 'fungi': [72], 'echoes': [27], 'nucleus': [73], 'cervixes': [91], 'memorandums': [85], 'firemen': [16], 'halo': [49], 'sheaves': [11], 'cervix': [91], 'kilo': [30], 'knives': [5], 'vertebra': [62], 'zoos': [46], 'octopus': [74], 'mosquitos': [50], 'cargoes': [48], 'funguses': [72], 'hoof': [4], 'fungus': [72], 'stimuli': [76], 'crises': [98], 'parentheses': [104], 'medium': [84], 'sopranos': [42], 'pianos': [36], 'mice': [21], 'feet': [17], 'radii': [75], 'pimento': [38], 'tempo': [111], 'potatoes': [33], 'genus': [64], 'volcano': [54], 'piano': [36], 'automaton': [109], 'tooth': [22], 'media': [84], 'schemata': [115], 'wife': [14], 'noes': [52], 'addendum': [79], 'photos': [34], 'wives': [14], 'heroes': [31], 'focus': [71], 'apex': [89], 'neuroses': [102], 'addenda': [79], 'basis': [97], 'diagnoses': [99], 'louse': [19], 'embargo': [29], 'thief': [13], 'scarfs': [9], 'loaf': [8], 'lives': [7], 'libretti': [110], 'videos': [45], 'curriculums': [81], 'potato': [33], 'vortex': [94], 'phenomenon': [108] }

" key to full list of NN
let s:irrNNSDict = { 1: ['calf', 'calves'], 2: ['elf', 'elves'], 3: ['half', 'halves'], 4: ['hoof', 'hooves'], 5: ['knife', 'knives'], 6: ['leaf', 'leaves'], 7: ['life', 'lives'], 8: ['loaf', 'loaves'], 9: ['scarf', 'scarfs', 'scarves'], 10: ['self', 'selves'], 11: ['sheaf', 'sheaves'], 12: ['shelf', 'shelves'], 13: ['thief', 'thieves'], 14: ['wife', 'wives'], 15: ['wolf', 'wolves'], 16: ['fireman', 'firemen'], 17: ['foot', 'feet'], 18: ['goose', 'geese'], 19: ['louse', 'lice'], 20: ['man', 'men'], 21: ['mouse', 'mice'], 22: ['tooth', 'teeth'], 23: ['woman', 'women'], 24: ['child', 'children'], 25: ['ox', 'oxen'], 26: ['auto', 'autos'], 27: ['echo', 'echoes'], 28: ['kangaroo', 'kangaroos'], 29: ['embargo', 'embargoes'], 30: ['kilo', 'kilos'], 31: ['hero', 'heroes'], 32: ['memo', 'memos'], 33: ['potato', 'potatoes'], 34: ['photo', 'photos'], 35: ['tomato', 'tomatoes'], 36: ['piano', 'pianos'], 37: ['torpedo', 'torpedoes'], 38: ['pimento', 'pimentos'], 39: ['veto', 'vetoes'], 40: ['pro', 'pros'], 41: ['solo', 'solos'], 42: ['soprano', 'sopranos'], 43: ['studio', 'studios'], 44: ['tattoo', 'tattoos'], 45: ['video', 'videos'], 46: ['zoo', 'zoos'], 47: ['buffalo', 'buffalos', 'buffaloes'], 48: ['cargo', 'cargos', 'cargoes'], 49: ['halo', 'halos', 'haloes'], 50: ['mosquito', 'mosquitos', 'mosquitoes'], 51: ['motto', 'mottos', 'mottoes'], 52: ['no', 'nos', 'noes'], 53: ['tornado', 'tornados', 'tornadoes'], 54: ['volcano', 'volcanos', 'volcanoes'], 55: ['zero', 'zeros', 'zeroes'], 56: ['alga', 'algae'], 57: ['amoeba', 'amoebae', 'amoebas'], 58: ['antenna', 'antennae', 'antennas'], 59: ['formula', 'formulae', 'formulas'], 60: ['larva', 'larvae'], 61: ['nebula', 'nebulae', 'nebulas'], 62: ['vertebra', 'vertebrae'], 63: ['corpus', 'corpora'], 64: ['genus', 'genera'], 65: ['alumnus', 'alumni'], 66: ['census', 'censuses'], 67: ['prospectus', 'prospectuses'], 68: ['viscus', 'viscera'], 69: ['bacillus', 'bacilli'], 70: ['cactus', 'cacti', 'cactuses'], 71: ['focus', 'foci'], 72: ['fungus', 'fungi', 'funguses'], 73: ['nucleus', 'nuclei'], 74: ['octopus', 'octopi', 'octopuses'], 75: ['radius', 'radii'], 76: ['stimulus', 'stimuli'], 77: ['syllabus', 'syllabi', 'syllabuses'], 78: ['terminus', 'termini'], 79: ['addendum', 'addenda'], 80: ['bacterium', 'bacteria'], 81: ['curriculum', 'curricula', 'curriculums'], 82: ['datum', 'data'], 83: ['erratum', 'errata'], 84: ['medium', 'media'], 85: ['memorandum', 'memoranda', 'memorandums'], 86: ['ovum', 'ova'], 87: ['stratum', 'strata'], 88: ['symposium', 'symposia', 'symposiums'], 89: ['apex', 'apices', 'apexes'], 90: ['appendix', 'appendices', 'appendixes'], 91: ['cervix', 'cervices', 'cervixes'], 92: ['index', 'indices', 'indexes'], 93: ['matrix', 'matrices', 'matrixes'], 94: ['vortex', 'vortices'], 95: ['analysis', 'analyses'], 96: ['axis', 'axes'], 97: ['basis', 'bases'], 98: ['crisis', 'crises'], 99: ['diagnosis', 'diagnoses'], 100: ['emphasis', 'emphases'], 101: ['hypothesis', 'hypotheses'], 102: ['neurosis', 'neuroses'], 103: ['oasis', 'oases'], 104: ['parenthesis', 'parentheses'], 105: ['synopsis', 'synopses'], 106: ['thesis', 'theses'], 107: ['criterion', 'criteria'], 108: ['phenomenon', 'phenomena'], 109: ['automaton', 'automata'], 110: ['libretto', 'libretti'], 111: ['tempo', 'tempi'], 112: ['virtuoso', 'virtuosi'], 113: ['cherub', 'cherubim'], 114: ['seraph', 'seraphim'], 115: ['schema', 'schemata'] }


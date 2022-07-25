import std/os
import std/sequtils
import std/sets
import std/strformat
import std/strutils
import std/tables
import std/math

import pixie

const IMAGE_DIM = 1600

const TESTMODE = defined(test)
when TESTMODE:
  import std/unittest

func onlyalpha(x: string): string =
  for c in x:
    if c notin {'a'..'z','A'..'Z','-'}:
      continue
    result.add(c)

iterator splitwords(x: string): string =
  for word in x.splitWhitespace:
    if "—" in word:
      for part in word.split("—"):
        yield part
    else:
      yield word

iterator justwords(x: string, exclude: HashSet[string] = initHashSet[string]()): string =
  ## Given some text, return just the words -- no punctuation or whitespace
  for word in x.splitwords:
    let transformed = word.onlyalpha.toLower.strip(chars={'-'})
    if transformed != "" and transformed notin exclude:
      yield transformed

when TESTMODE:
  test "words":
    check justwords("  hello, my friend!").toSeq == @["hello","my","friend"]
    check justwords("This; this is GREAT; (I think)").toSeq == @["this", "this", "is", "great", "i", "think"]
    check justwords("2:34 Something happened").toSeq == @["something", "happened"]

proc makechart(text: string, outputfile: string, skip_top_words = 10) =
  echo "makechart start..."
  var all_words:seq[string]
  stdout.flushFile()
  all_words = text.justwords().toSeq
  var wordcounts = newCountTable[string]()
  for word in all_words:
    wordcounts.inc(word)
  echo "word count ", all_words.len
  for i in 0..<skip_top_words:
    let large = wordcounts.largest
    echo "removing ", large
    for i in 0..<all_words.count(large.key):
      all_words.delete(all_words.find(large.key))
    wordcounts.del(large.key)
  echo "word count ", all_words.len

  # image generation
  createDir outputfile.parentDir
  stdout.flushFile()

  # full book
  block:
    let chunks = all_words.distribute(IMAGE_DIM)
    var scores: array[IMAGE_DIM, array[IMAGE_DIM, int]]
    var maxscore = 0
    stdout.write("\n")
    for x in 0..<IMAGE_DIM:
      for y in 0..x:
        let xchunk = chunks[x]
        let ychunk = chunks[y]
        var score = 0
        for xword in xchunk:
          score.inc(ychunk.count(xword))
        scores[x][y] = score
        scores[y][x] = score
        if x != y:
          maxscore = max(maxscore, score)
      stdout.write("\r" & $(x / IMAGE_DIM * 100) & "%                       ")
      stdout.flushFile()
    stdout.write("\n")
    
    var i_linear = newImage(IMAGE_DIM, IMAGE_DIM)
    i_linear.fill(rgba(255, 255, 255, 255))
    for x in 0..<IMAGE_DIM:
      for y in 0..<IMAGE_DIM:
        let linear_score = scores[x][y] / maxscore
        # i_linear.setColor(x, y, color(0, 0, 0, linear_score))
    i_linear.writeFile(outputfile)

proc bookofmormon() =
  let books = [
    ("001-titlepage.txt", "Title"),
    ("002-testimonies.txt", "Testimonies"),
    ("003-1nephi.txt", "1 Nephi"),
    ("004-2nephi.txt", "2 Nephi"),
    ("005-jacob.txt", "Jacob"),
    ("006-enos.txt", "Enos"),
    ("007-jarom.txt", "Jarom"),
    ("008-omni.txt", "Omni"),
    ("009-wom.txt", "Word of Mormon"),
    ("010-mosiah.txt", "Mosiah"),
    ("011-alma.txt", "Alma"),
    ("012-helaman.txt", "Helaman"),
    ("013-3nephi.txt", "3 Nephi"),
    ("014-4nephi.txt", "4 Nephi"),
    ("015-mormon.txt", "Mormon"),
    ("016-ether.txt", "Ether"),
    ("017-moroni.txt", "Moroni"),
  ]
  let exclude_words = [
    "chapter",
    "the",
    "and",
    "of",
    "that",
    "to",
    "they",
    # "in",
    # "unto",
    # "i",
    # "he",
    # "it",
    # "their",
    # "them",
    # "for",
    # "be",
    # "shall",
    # "his",
    # "which",
    # "a",
    # "not",
    # "were",
    # "ye",
    # "did",
    # "have",
    # "all",
    # "had",
    # "people",
    # "my",
    # "god",
    # "came",
    # "behold",
    # "was",
    # "lord",
    # "pass",
    # "with",
    # "this",
    # "is",
    # "land",
    # "yea",
    # "now",
    # "who",
    # "by",
    # "you",
    # "should",
  ]
  echo "Excluding words: ", exclude_words.join(", ")
  var book_words:seq[tuple[name:string, words:seq[string]]]
  var all_words:seq[string]
  var book_range = initTable[string, HSlice[int, int]]()
  for (book, name) in books:
    echo name, book
    let words = open("bybook"/book).readAll().justwords(exclude=toHashSet(exclude_words)).toSeq
    # echo words[0..10]
    book_words.add((book, words))
    let start_idx = all_words.len
    all_words.add(words)
    let end_idx = all_words.len
    book_range[book] = start_idx..end_idx
  
  echo "Word count: ", $all_words.len
  var wordcounts = newCountTable[string]()
  for word in all_words:
    wordcounts.inc(word)
  echo "Most common words:"
  while true:
    let l = wordcounts.largest
    if l.val < 200:
      break
    echo " ", l.key, " ", l.val
    wordcounts.del(wordcounts.largest.key)

  # image generation
  createDir "out"

  # full book
  block:
    let chunks = all_words.distribute(IMAGE_DIM)
    var scores: array[IMAGE_DIM, array[IMAGE_DIM, int]]
    var maxscore = 0
    stdout.write("\n")
    for x in 0..<IMAGE_DIM:
      for y in 0..x:
        let xchunk = chunks[x]
        let ychunk = chunks[y]
        var score = 0
        for xword in xchunk:
          score.inc(ychunk.count(xword))
        scores[x][y] = score
        scores[y][x] = score
        if x != y:
          maxscore = max(maxscore, score)
      stdout.write("\r" & $(x / IMAGE_DIM * 100) & "%                       ")
      stdout.flushFile()
    stdout.write("\n")
    # echo "scores: ", $scores
    
    let i_linear = newImage(IMAGE_DIM, IMAGE_DIM)
    let i_expo = newImage(IMAGE_DIM, IMAGE_DIM)
    let i_invexp = newImage(IMAGE_DIM, IMAGE_DIM)
    for i in [i_linear, i_expo, i_invexp]:
      i.fill(rgba(255, 255, 255, 255))
    for x in 0..<IMAGE_DIM:
      for y in 0..<IMAGE_DIM:
        let linear_score = scores[x][y] / maxscore
        let expo_score = pow(scores[x][y] * 1 / maxscore, 2)
        # let invexp_score = 1 - expo_score
        i_linear.setColor(x, y, color(0, 0, 0, linear_score))
        i_expo.setColor(x, y, color(0, 0, 0, expo_score))
    i_linear.writeFile("out/fullbook_linear1.png")
    i_expo.writeFile("out/fullbook_expo1.png")

    # color by book
    var font = readFont("./Roboto-Regular.ttf")
    font.size = 20

    let wordcount = all_words.len
    for i,(book,name) in books:
      echo "coloring ", name
      let r = book_range[book]
      let hue = case i mod 3:
        of 0: color(0.5, 0, 0, 1)
        of 1: color(0, 0.5, 0, 1)
        of 2: color(0, 0, 0.5, 1)
        else: raise newException(ValueError, "How can i mod 3 be anything else?")
      echo "  hue: ", $hue
      let x0 = (IMAGE_DIM * r.a / wordcount).toInt
      let x1 = (IMAGE_DIM * r.b / wordcount).toInt
      for x in x0..<x1:
        for y in 0..<IMAGE_DIM:
          block:
            let c = i_linear.getColor(x, y)
            let newcolor = color(hue.r, hue.g, hue.b, c.a)
            # echo &"{x},{y} color from {c} to {newcolor}"
            i_linear.setColor(x, y, newcolor)
          block:
            let c = i_expo.getColor(x, y)
            let newcolor = color(hue.r, hue.g, hue.b, c.a)
            # echo &"{x},{y} color from {c} to {newcolor}"
            i_expo.setColor(x, y, newcolor)
      for img in [i_linear, i_expo]:
        img.fillText(
          font.typeset(name, vec2(max(toFloat(x1 - x0), 160), IMAGE_DIM / 2.0)),
          translate(vec2(x0.toFloat, toFloat(IMAGE_DIM - 20 * i))))

    i_linear.writeFile("out/fullbook_linear2.png")
    i_expo.writeFile("out/fullbook_expo2.png")

when isMainModule and not TESTMODE:
  # if paramCount() == 0:
  #   bookofmormon()
  # else:
  let source_file = paramStr(1)
  echo "reading ", source_file
  let guts = readFile(source_file)
  echo "done reading..."
  let outputfile = "out" / source_file.extractFilename.changeFileExt(".png")
  echo "output: ", outputfile
  makechart(guts, outputfile)
  
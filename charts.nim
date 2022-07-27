import std/os
import std/sequtils
import std/sets
import std/strformat
import std/strutils
import std/tables
import std/math
import std/json

import pixie

const IMAGE_DIM = 740

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

func groupWords(words: seq[string], size = 1): seq[string] =
  ## Group words into groups of `size` 
  for i in 0..(words.len - size):
    result.add(words[i..<(i+size)].join(" "))

when TESTMODE:
  test "groupWords":
    check groupWords(@["a","b","c","d"], 2) == @["a b", "b c", "c d"]
    check groupWords(@["a","b","c","d"], 3) == @["a b c", "b c d"]
    check groupWords(@["a","b","c","d"], 4) == @["a b c d"]

proc makechart(text: string, outputfile: string, groupsize = 1, writechunks = false, skip_top_words = 0.01) =
  var all_words = text.justwords.toSeq
  var wordcounts = newCountTable[string]()
  for word in all_words:
    wordcounts.inc(word)
  echo &"Word count: {all_words.len}"
  
  # filter out common words
  let cutoff = all_words.len.toFloat * skip_top_words
  echo &"Cutoff: {cutoff}"
  var toremove:seq[string]
  while true:
    let large = wordcounts.largest
    if large.val.toFloat >= cutoff:
      echo "  Removing ", large
      toremove.add(large.key)
      wordcounts.del(large.key)
    else:
      break
  echo "Word count post-filter: ", all_words.len
  var unfiltered_chunks = all_words.distribute(IMAGE_DIM)
  
  # Write out chunks
  if writechunks:
    let chunkdir = outputfile.changeFileExt("").changeFileExt("")
    if dirExists(chunkdir):
      removeDir(chunkdir)
    createDir(chunkdir)
    echo &"Writing chunks to {chunkdir}"
    for i, chunk in unfiltered_chunks:
      let chunkfile = chunkdir / &"chunk{i}.txt"
      writeFile(chunkfile, chunk.join(" "))
  
  # Chunks for analysis
  var chunks:seq[seq[string]]
  for chunk in unfiltered_chunks:
    chunks.add chunk.filterIt(it notin toremove)
  if groupsize > 1:
    chunks = chunks.mapIt(it.groupWords(groupsize))

  # image generation
  createDir outputfile.parentDir
  stdout.flushFile()

  # Score and generate image
  block:
    var scores: array[IMAGE_DIM, array[IMAGE_DIM, int]]
    var maxscore = 0
    stdout.write("\n")
    for x in 0..<IMAGE_DIM:
      for y in 0..x:
        let xchunk = chunks[x]
        let ychunk = chunks[y]
        var score = 0
        if x != y:
          for xword in xchunk:
            score.inc(ychunk.count(xword))
        scores[x][y] = score
        scores[y][x] = score
        maxscore = max(maxscore, score)
      stdout.write("\r" & $(x / IMAGE_DIM * 100).toInt & "%  ")
      stdout.flushFile()
    stdout.write("\n")
    
    var i_linear = newImage(IMAGE_DIM, IMAGE_DIM)
    var i_invert = newImage(IMAGE_DIM, IMAGE_DIM)
    var i_color = newImage(IMAGE_DIM, IMAGE_DIM)
    i_linear.fill(rgba(255, 255, 255, 255))
    i_invert.fill(rgba(255, 255, 255, 255))
    i_color.fill(rgba(255,255,255,255))
    for x in 0..<IMAGE_DIM:
      for y in 0..<IMAGE_DIM:
        let linear_score = scores[x][y] / maxscore
        # let linear_score = 1.0 - pow(1.0 - scores[x][y] / maxscore, 2)
        i_linear.setColor(x, y, color(0, 0, 0, linear_score))
        i_invert.setColor(x, y, color(0, 0, 0, 1.0 - linear_score))
        if linear_score > 0.5:
          i_color.setColor(x, y, color(0, 0, 1, (linear_score - 0.5) * 2))
        else:
          i_color.setColor(x, y, color(1, 0, 0, 1 - (linear_score * 2)))
    i_linear.writeFile(outputfile)
    i_invert.writeFile(outputfile.changeFileExt(".invert.png"))
    i_color.writeFile(outputfile.changeFileExt(".color.png"))

# proc bookofmormon() =
#   let books = [
#     ("001-titlepage.txt", "Title"),
#     ("002-testimonies.txt", "Testimonies"),
#     ("003-1nephi.txt", "1 Nephi"),
#     ("004-2nephi.txt", "2 Nephi"),
#     ("005-jacob.txt", "Jacob"),
#     ("006-enos.txt", "Enos"),
#     ("007-jarom.txt", "Jarom"),
#     ("008-omni.txt", "Omni"),
#     ("009-wom.txt", "Word of Mormon"),
#     ("010-mosiah.txt", "Mosiah"),
#     ("011-alma.txt", "Alma"),
#     ("012-helaman.txt", "Helaman"),
#     ("013-3nephi.txt", "3 Nephi"),
#     ("014-4nephi.txt", "4 Nephi"),
#     ("015-mormon.txt", "Mormon"),
#     ("016-ether.txt", "Ether"),
#     ("017-moroni.txt", "Moroni"),
#   ]
#   let exclude_words = [
#     "chapter",
#     "the",
#     "and",
#     "of",
#     "that",
#     "to",
#     "they",
#     # "in",
#     # "unto",
#     # "i",
#     # "he",
#     # "it",
#     # "their",
#     # "them",
#     # "for",
#     # "be",
#     # "shall",
#     # "his",
#     # "which",
#     # "a",
#     # "not",
#     # "were",
#     # "ye",
#     # "did",
#     # "have",
#     # "all",
#     # "had",
#     # "people",
#     # "my",
#     # "god",
#     # "came",
#     # "behold",
#     # "was",
#     # "lord",
#     # "pass",
#     # "with",
#     # "this",
#     # "is",
#     # "land",
#     # "yea",
#     # "now",
#     # "who",
#     # "by",
#     # "you",
#     # "should",
#   ]
#   echo "Excluding words: ", exclude_words.join(", ")
#   var book_words:seq[tuple[name:string, words:seq[string]]]
#   var all_words:seq[string]
#   var book_range = initTable[string, HSlice[int, int]]()
#   for (book, name) in books:
#     echo name, book
#     let words = open("bybook"/book).readAll().justwords(exclude=toHashSet(exclude_words)).toSeq
#     # echo words[0..10]
#     book_words.add((book, words))
#     let start_idx = all_words.len
#     all_words.add(words)
#     let end_idx = all_words.len
#     book_range[book] = start_idx..end_idx
  
#   echo "Word count: ", $all_words.len
#   var wordcounts = newCountTable[string]()
#   for word in all_words:
#     wordcounts.inc(word)
#   echo "Most common words:"
#   while true:
#     let l = wordcounts.largest
#     if l.val < 200:
#       break
#     echo " ", l.key, " ", l.val
#     wordcounts.del(wordcounts.largest.key)

#   # image generation
#   createDir "out"

#   # full book
#   block:
#     let chunks = all_words.distribute(IMAGE_DIM)
#     var scores: array[IMAGE_DIM, array[IMAGE_DIM, int]]
#     var maxscore = 0
#     stdout.write("\n")
#     for x in 0..<IMAGE_DIM:
#       for y in 0..x:
#         let xchunk = chunks[x]
#         let ychunk = chunks[y]
#         var score = 0
#         for xword in xchunk:
#           score.inc(ychunk.count(xword))
#         if x == y:
#           score = 0
#         else:
#           maxscore = max(maxscore, score)
#         scores[x][y] = score
#         scores[y][x] = score
#       stdout.write("\r" & $(x / IMAGE_DIM * 100) & "%                       ")
#       stdout.flushFile()
#     stdout.write("\n")
#     # echo "scores: ", $scores
    
#     let i_linear = newImage(IMAGE_DIM, IMAGE_DIM)
#     let i_expo = newImage(IMAGE_DIM, IMAGE_DIM)
#     for i in [i_linear, i_expo]:
#       i.fill(rgba(255, 255, 255, 255))
#     for x in 0..<IMAGE_DIM:
#       for y in 0..<IMAGE_DIM:
#         let linear_score = scores[x][y] / maxscore
#         # let expo_score = pow(scores[x][y] * 1 / maxscore, 2)
#         # let invexp_score = 1 - expo_score
#         i_linear.setColor(x, y, color(0, 0, 0, linear_score))
#         # i_expo.setColor(x, y, color(0, 0, 0, expo_score))
#     i_linear.writeFile("out/fullbook_linear1.png")
#     # i_expo.writeFile("out/fullbook_expo1.png")

#     # color by book
#     var font = readFont("./Roboto-Regular.ttf")
#     font.size = 20

#     let wordcount = all_words.len
#     for i,(book,name) in books:
#       echo "coloring ", name
#       let r = book_range[book]
#       let hue = case i mod 3:
#         of 0: color(0.5, 0, 0, 1)
#         of 1: color(0, 0.5, 0, 1)
#         of 2: color(0, 0, 0.5, 1)
#         else: raise newException(ValueError, "How can i mod 3 be anything else?")
#       echo "  hue: ", $hue
#       let x0 = (IMAGE_DIM * r.a / wordcount).toInt
#       let x1 = (IMAGE_DIM * r.b / wordcount).toInt
#       for x in x0..<x1:
#         for y in 0..<IMAGE_DIM:
#           block:
#             let c = i_linear.getColor(x, y)
#             let newcolor = color(hue.r, hue.g, hue.b, c.a)
#             # echo &"{x},{y} color from {c} to {newcolor}"
#             i_linear.setColor(x, y, newcolor)
#           block:
#             let c = i_expo.getColor(x, y)
#             let newcolor = color(hue.r, hue.g, hue.b, c.a)
#             # echo &"{x},{y} color from {c} to {newcolor}"
#             i_expo.setColor(x, y, newcolor)
#       for img in [i_linear, i_expo]:
#         img.fillText(
#           font.typeset(name, vec2(max(toFloat(x1 - x0), 160), IMAGE_DIM / 2.0)),
#           translate(vec2(x0.toFloat, toFloat(IMAGE_DIM - 20 * i))))

#     i_linear.writeFile("out/fullbook_linear2.png")
#     i_expo.writeFile("out/fullbook_expo2.png")

when isMainModule and not TESTMODE:
  for i in 1..paramCount():
    let source_file = paramStr(i)
    echo &"Reading {source_file} ..."
    let guts = readFile(source_file)
    let group1 = "out" / source_file.extractFilename.changeFileExt(".1.png")
    makechart(guts, group1, 1, writechunks = true)
    let group2 = "out" / source_file.extractFilename.changeFileExt(".2.png")
    makechart(guts, group2, 2)
    let group3 = "out" / source_file.extractFilename.changeFileExt(".3.png")
    makechart(guts, group3, 3)
      
  
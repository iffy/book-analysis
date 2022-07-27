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
    if c notin {'a'..'z','A'..'Z','-','\''}:
      continue
    result.add(c)
  result = result.strip(chars={'\''})

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
    # var i_invert = newImage(IMAGE_DIM, IMAGE_DIM)
    # var i_color = newImage(IMAGE_DIM, IMAGE_DIM)
    i_linear.fill(rgba(255, 255, 255, 255))
    # i_invert.fill(rgba(255, 255, 255, 255))
    # i_color.fill(rgba(255,255,255,255))
    for x in 0..<IMAGE_DIM:
      for y in 0..<IMAGE_DIM:
        let linear_score = scores[x][y] / maxscore
        # let linear_score = 1.0 - pow(1.0 - scores[x][y] / maxscore, 2)
        i_linear.setColor(x, y, color(0, 0, 0, linear_score))
        # i_invert.setColor(x, y, color(0, 0, 0, 1.0 - linear_score))
        # if linear_score > 0.5:
        #   i_color.setColor(x, y, color(0, 0, 1, (linear_score - 0.5) * 2))
        # else:
        #   i_color.setColor(x, y, color(1, 0, 0, 1 - (linear_score * 2)))
    i_linear.writeFile(outputfile)
    # i_invert.writeFile(outputfile.changeFileExt(".invert.png"))
    # i_color.writeFile(outputfile.changeFileExt(".color.png"))

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
      
  
# MIT License
#
# Copyright (c) 2024 Jason Beetham
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import pkg/pixie

type
  ImageComparison* = object
    isPath*: bool
    data*: string

proc compare*(a, b: ImageComparison, epsilon: float, debugPath = ""): bool =
  let
    imgA =
      if a.isPath:
        readImage(a.data)
      else:
        decodeImage(a.data)
    imgB =
      if b.isPath:
        readImage(b.data)
      else:
        decodeImage(b.data)

  if imgA.width != imgB.width or imgA.height != imgB.height:
    imgB[] = imgB.resize(imgA.width, imgA.height)[]


  var diffRatio: float

  for i, x in imgA.data:
    let y = imgB.data[i]
    diffRatio += float max(x.r, y.r) - min(x.r, y.r)
    diffRatio += float max(x.g, y.g) - min(x.g, y.g)
    diffRatio += float max(x.b, y.b) - min(x.b, y.b)

  diffRatio /= float imgA.data.len * 3  * 255 # rgb
  result = diffRatio <= epsilon
  if not result:
    if debugPath.len > 0:
      let debugImage = newImage(imgA.width, imgA.height)
      for i, x in imgA.data:
        let
          y = imgB.data[i]
          ratio = (max(x.r, y.r).float - min(x.r, y.r).float) / 3 +
            (max(x.g, y.g).float - min(x.g, y.g).float) / 3 +
            (max(x.b, y.b).float - min(x.b, y.b).float) / 3


        debugImage.data[i] = rgbx(y.r, y.g, y.b, y.a * (ratio.float > epsilon).uint8)
      debugImage.writeFile(debugPath)

    return false




when isMainModule:
  import std/[os, strutils]
  let
    pathA = ImageComparison(isPath: true, data: paramStr(2))
    pathB = ImageComparison(isPath: true, data: paramStr(3))
  echo compare(pathA, pathB, parseFloat(paramStr(1)), (try: paramStr(4) except: ""))


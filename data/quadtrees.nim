import std/[intsets, deques]

type
  QuadPos = enum
    TopLeft
    TopRight
    BottomLeft
    BottomRight

  QuadTreeIndex = distinct int

  QuadNodeKind = enum
    Parent
    Bucket

  QuadNode = object
    x, y: int
    width, height: int
    parent: int = -1
    case kind: QuadNodeKind
    of Bucket:
      bucket: array[64, QuadTreeIndex] # Should these just be `array[64, int]` where `int` is a ind into a sequence?
      entries: int # When this is == bucket.len we divide
    of Parent:
      children: array[QuadPos, int] = [TopLeft: -1, -1, -1, -1]

  QuadTree*[T] = object
    nodes: seq[QuadNode]
    values: seq[T]
    inactiveValues: Intset
    width, height: int


proc `[]`[T](tree: QuadTree[T], ind: QuadTreeIndex): lent T =
  tree.values[int ind]

proc `[]=`[T](tree: var QuadTree[T], ind: QuadTreeIndex, val: sink T) =
  tree.values.setLen(max(tree.values.len, ind.int + 1))
  tree.values[int ind] = val

proc `[]`[T](tree: var QuadTree[T], ind: QuadTreeIndex): var T =
  tree.values[int ind]

proc bucket(x, y, w, h, parent: int): QuadNode =
  QuadNode(
    kind: Bucket,
    x: x,
    y: y,
    width: w,
    height: h,
    parent: parent
  )

proc transition(node: var QuadNode, inds: array[QuadPos, int]) =
  node = QuadNode(
    kind: Parent,
    width: node.width,
    height: node.height,
    x: node.x,
    y: node.y,
    children: inds
  )

proc getNextIndex[T](tree: var QuadTree[T]): QuadTreeIndex =
  if tree.inactiveValues.len == 0:
    tree.values.setLen(tree.values.len + 1)
    QuadTreeIndex tree.values.high
  else:
    var ind: int
    for i in tree.inactiveValues:
      ind = i
      break
    QuadTreeIndex ind


proc init*[T](_: typedesc[QuadTree[T]], width, height: int): QuadTree[T] =
  QuadTree[T](
    width: width,
    height: height,
    nodes: @[bucket(0, 0, width, height, -1)]
  )

proc quadPos[T](tree: QuadTree[T], node: QuadNode, ind: QuadTreeIndex): QuadPos =
  let val = tree[ind]
  if val.x >= node.x + node.width div 2:
    if val.y >= node.y + node.height div 2:
      BottomRight
    else:
      TopRight
  else:
    if val.y >= node.y + node.height div 2:
      BottomLeft
    else:
      TopLeft

proc add(node: var QuadNode, val: QuadTreeIndex) =
  node.bucket[node.entries] = val
  inc node.entries

proc add[T](node: var QuadNode, tree: var QuadTree[T], val: sink T, ind: int, valInd: QuadTreeIndex): int =
  if val.x in node.x ..< node.x + node.width and val.y in node.y ..< node.y + node.height:

    if node.kind == Bucket:
      if node.entries == node.bucket.len:
        let
          newWidth = node.width div 2
          newHeight = node.height div 2
          offsetX = node.x + newWidth
          offsetY = node.y + newHeight


        var newNodes: array[QuadPos, QuadNode] = [
          bucket(node.x, node.y, newWidth, newHeight, ind),
          bucket(offsetX, node.y, newWidth, newHeight, ind),
          bucket(node.x, offsetY, newWidth, newHeight, ind),
          bucket(offsetX, offsetY, newWidth, newHeight, ind),
        ]

        for entry in newNodes.mitems:
          entry.width = newWidth
          entry.height = newHeight
          entry.parent = ind

        let len = tree.nodes.len
        for val in node.bucket.toOpenArray(0, node.entries - 1):
          let ind = tree.quadPos(node, val)
          newNodes[ind].add val
        node.transition [TopLeft: len, len + 1, len + 2, len + 3]

        tree.nodes.add newNodes

        let ind = tree.quadPos(node, QuadTreeIndex tree.values.high)
        tree.nodes[node.children[ind]].add(tree, val, node.children[ind], valInd)

      else:
        node.add valInd
        ind

    else:

      let ind = tree.quadPos(node, QuadTreeIndex tree.values.high)
      tree.nodes[node.children[ind]].add(tree, val, node.children[ind], valInd)
  else:
    -1

proc add*[T](tree: var QuadTree[T], val: sink T): (int, QuadTreeIndex) =
  let valInd = tree.getNextIndex()
  tree[valInd] = val
  (tree.nodes[0].add(tree, val, 0, valInd), valInd)

iterator items*[T](tree: QuadTree[T], ind: int): lent T =
  let node = tree.nodes[ind]
  if node.kind == Bucket:
    for x in node.bucket.toOpenArray(0, node.entries - 1):
      yield tree[x]
  else:
    var queue = @[ind]
    while queue.len > 0:
      let ind = queue.pop()
      if tree.nodes[ind].kind == Bucket:
        for x in tree.nodes[ind].bucket.toOpenArray(0, tree.nodes[ind].entries - 1):
          yield tree[x]
      else:
        queue.add tree.nodes[ind].children

iterator mitems*[T](tree: QuadTree[T], ind: int): var T =
  let node = tree.nodes[ind]
  if node.kind == Bucket:
    for x in node.bucket.toOpenArray(0, node.entries - 1):
      yield x
  else:
    var queue = @[ind]
    while queue.len > 0:
      let ind = queue.pop()
      if tree.nodes[ind] == Bucket:
        for x in tree.nodes[ind].bucket.toOpenArray(0, tree.nodes[ind].entries - 1).mitems:
          yield x
      else:
        queue.add tree.nodes[ind].children

iterator items*[T](tree: QuadTree[T]): lent T =
  for x in tree.items(0):
    yield x

iterator mitems*[T](tree: QuadTree[T]): var T =
  for x in tree.mitems(0):
    yield x

iterator upwardSearch*[T](tree: QuadTree[T], nodeIndex: int): lent T =
  var
    queue = @[nodeIndex].toDeque
    visited: IntSet
  visited.incl nodeIndex

  while queue.len > 0:
    let
      ind = queue.popFirst()
      node = tree.nodes[ind]
    case node.kind
    of Bucket:
      for item in tree.items(ind):
        yield item
    else:
      for child in node.children:
        if child notin visited:
          queue.addFirst child
          visited.incl child
        if node.parent != -1:
          queue.addLast(node.parent)
          visited.incl node.parent


when isMainModule:
  import std/enumerate
  type MyType = object
    x, y: int

  var tree = QuadTree[MyType].init(10, 10)
  for x in 0..<10:
    for y in 0..<10:
      discard tree.add MyType(x: x, y: y)

  for i, val in enumerate tree.upwardSearch(3):
    if i > 10:
      break
    echo val

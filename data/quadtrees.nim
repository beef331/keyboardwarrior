type
  QuadPos = enum
    TopLeft
    TopRight
    BottomLeft
    BottomRight

  QuadNode[T] = object
    x, y: int
    width, height: int
    parent: int = -1
    case isBucket: bool
    of true:
      bucket: array[64, T] # Should these just be `array[64, int]` where `int` is a ind into a sequence?
      entries: int # When this is == bucket.len we divide
    else:
      children: array[QuadPos, int] = [TopLeft: -1, -1, -1, -1]


  QuadTree*[T] = object
    nodes: seq[QuadNode[T]]
    width, height: int

proc transition[T](node: var QuadNode[T], inds: array[QuadPos, int]) =
  {.cast(uncheckedAssign).}:
    node.isBucket = false
    node.children = inds

proc init*[T](_: typedesc[QuadTree[T]], width, height: int): QuadTree[T] =
  QuadTree[T](
    width: width,
    height: height,
    nodes: @[QuadNode[T](isBucket: true, width: width, height: height)]
  )

proc quadPos[T](node: QuadNode[T], val: T): QuadPos =
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

proc add[T](node: var QuadNode[T], val: sink T) =
  node.bucket[node.entries] = val
  inc node.entries

proc bucket[T](x, y, w, h, parent: int): QuadNode[T] =
  QuadNode[T](
    isBucket: true,
    x: x,
    y: y,
    width: w,
    height: h,
    parent: parent
  )

proc add[T](node: var QuadNode[T], tree: var QuadTree[T], val: sink T, ind: int): int =
  if val.x in node.x ..< node.x + node.width and val.y in node.y ..< node.y + node.height:

    if node.isBucket:
      if node.entries == node.bucket.len:
        let
          newWidth = node.width div 2
          newHeight = node.height div 2
          offsetX = node.x + newWidth
          offsetY = node.y + newHeight


        var newNodes: array[QuadPos, QuadNode[T]] = [
          bucket[T](node.x, node.y, newWidth, newHeight, ind),
          bucket[T](offsetX, node.y, newWidth, newHeight, ind),
          bucket[T](node.x, offsetY, newWidth, newHeight, ind),
          bucket[T](offsetX, offsetY, newWidth, newHeight, ind),
        ]

        for entry in newNodes.mitems:
          entry.width = newWidth
          entry.height = newHeight
          entry.parent = ind

        let len = tree.nodes.len
        for val in node.bucket.mitems:
          let ind = node.quadPos(val)
          newNodes[ind].add ensuremove val

        node.transition [TopLeft: len, len + 1, len + 2, len + 3]

        tree.nodes.add newNodes

        let ind = node.quadPos(val)
        discard tree.nodes[node.children[ind]].add(tree, val, node.children[ind])
        node.children[ind]

      else:
        node.add val
        ind

    else:
      let ind = node.quadPos(val)
      tree.nodes[node.children[ind]].add(tree, val, node.children[ind])
  else:
    -1

proc add*[T](tree: var QuadTree[T], val: sink T): int =
  tree.nodes[0].add(tree, val, 0)

iterator items*[T](tree: QuadTree[T], ind: int): lent T =
  let node = tree.nodes[ind]
  if node.isBucket:
    for x in node.bucket.toOpenArray(0, node.entries - 1):
      yield x
  else:
    var queue = @[ind]
    while queue.len > 0:
      let ind = queue.pop()
      if tree.nodes[ind].isBucket:
        for x in tree.nodes[ind].bucket.toOpenArray(0, tree.nodes[ind].entries - 1):
          yield x
      else:
        queue.add tree.nodes[ind].children

iterator mitems*[T](tree: QuadTree[T], ind: int): var T =
  let node = tree.nodes[ind]
  if node.isBucket:
    for x in node.bucket.toOpenArray(0, node.entries - 1):
      yield x
  else:
    var queue = @[ind]
    while queue.len > 0:
      let ind = queue.pop()
      if tree.nodes[ind].isBucket:
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


when isMainModule:
  type MyType = object
    x, y: int

  var tree = QuadTree[MyType].init(10, 10)
  for x in 0..<10:
    for y in 0..<10:
      discard tree.add MyType(x: x, y: y)

  for val in tree:
    echo val

import std/[intsets, deques, setutils, math]
const bucketSize = 64
type
  QuadPos = enum
    TopLeft
    TopRight
    BottomLeft
    BottomRight

  QuadTreeIndex* = distinct int

  QuadNodeKind = enum
    Parent
    Bucket

  EntrySet = set[range[0 .. bucketSize - 1]]

  QuadNode = object
    x, y: int
    width, height: int
    parent: int = -1
    case kind: QuadNodeKind
    of Bucket:
      bucket: array[bucketSize, QuadTreeIndex]
      entries: EntrySet
    of Parent:
      children: array[QuadPos, int] = [TopLeft: -1, -1, -1, -1]

  QuadEntry* = concept q
    q.x is SomeNumber
    q.y is SomeNumber
    q.node is int

  QuadTree*[T: QuadEntry] = object
    nodes: seq[QuadNode]
    values: seq[T]
    inactiveValues: Intset
    width, height: int

proc `==`*(a, b: QuadTreeIndex): bool {.borrow.}

proc fullSet[T: range](_: typedesc[set[T]]): set[T] = {T.low..T.high}

proc `[]`*[T](tree: QuadTree[T], ind: QuadTreeIndex): lent T =
  tree.values[int ind]

proc `[]=`[T](tree: var QuadTree[T], ind: QuadTreeIndex, val: sink T) =
  tree.values.setLen(max(tree.values.len, ind.int + 1))
  tree.values[int ind] = val

proc `[]`*[T](tree: var QuadTree[T], ind: QuadTreeIndex): var T =
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
    children: inds,
    parent: node.parent
  )

proc getNextIndex[T](tree: var QuadTree[T]): QuadTreeIndex =
  if tree.inactiveValues.len == 0:
    tree.values.setLen(tree.values.len + 1)
    QuadTreeIndex tree.values.high
  else:
    var ind: int
    for i in tree.inactiveValues.items:
      ind = i
      break
    QuadTreeIndex ind


proc init*[T](_: typedesc[QuadTree[T]], width, height: int): QuadTree[T] =
  QuadTree[T](
    width: width,
    height: height,
    nodes: @[bucket(0, 0, width, height, -1)]
  )

proc contains*(node: QuadNode, val: QuadEntry): bool =
  val.x.int in node.x .. node.x + node.width and
  val.y.int in node.y .. node.y + node.height

proc quadPos[T](tree: QuadTree[T], node: QuadNode, ind: QuadTreeIndex): QuadPos =
  let val = tree[ind]
  if val.x.int >= node.x + node.width div 2:
    if val.y.int >= node.y + node.height div 2:
      TopRight
    else:
      BottomRight
  else:
    if val.y.int >= node.y + node.height div 2:
      TopLeft
    else:
      BottomLeft

proc add(node: var QuadNode, val: QuadTreeIndex) =
  assert node.kind == Bucket
  var ind = 0
  for entry in node.entries.complement.items:
    ind = entry
    break
  node.bucket[ind] = val
  node.entries.incl ind

proc add[T](node: var QuadNode, tree: var QuadTree[T], val: var T, ind: int, valInd: QuadTreeIndex) =
  if val.x.int in node.x ..< node.x + node.width and val.y.int in node.y ..< node.y + node.height:
    case node.kind:
    of Bucket:
      if node.entries == EntrySet.fullSet(): # Split bucket
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
        for val in node.bucket:
          let ind = tree.quadPos(node, val)
          newNodes[ind].add val
          tree[val].node = len + ind.ord()
        node.transition [len, len + 1, len + 2, len + 3]

        tree.nodes.add newNodes

        let childInd = tree.quadPos(node, QuadTreeIndex tree.values.high)
        tree.nodes[node.children[childInd]].add(tree, val, node.children[childInd], valInd)

      else:
        node.add valInd
        tree[valInd].node = ind

    of Parent:
      let childInd = tree.quadPos(node, QuadTreeIndex tree.values.high)
      tree.nodes[node.children[childInd]].add(tree, val, node.children[childInd], valInd)

proc add*[T](tree: var QuadTree[T], val: sink T): QuadTreeIndex =
  let valInd = tree.getNextIndex()
  tree[valInd] = val
  tree.nodes[0].add(tree, tree[valInd], 0, valInd)
  valInd

proc reposition*[T](tree: var QuadTree[T]) =
  for i, val in tree.values.mpairs:
    if i notin tree.inactiveValues:
      let startNode = val.node
      #assert tree.nodes[startNode].kind == Bucket

      if val notin tree.nodes[val.node]:
        tree.nodes[0].add(tree, val, 0, QuadTreeIndex i)

      if val.node != startNode:
        assert tree.nodes[val.node].kind == Bucket
        for entInd in tree.nodes[startNode].entries.items:
          if tree.nodes[startNode].bucket[entInd].int == i:
            tree.nodes[startNode].entries.excl entInd

iterator items*[T](tree: QuadTree[T], ind: int): lent T =
  let node = tree.nodes[ind]
  if node.kind == Bucket:
    for ind in node.entries.items:
      yield tree[node.bucket[ind]]
  else:
    var queue = @[ind]
    while queue.len > 0:
      let
        ind = queue.pop()
        node = tree.nodes[ind]

      if node.kind == Bucket:
        for ind in node.entries.items:
          yield tree[node.bucket[ind]]
      else:
        queue.add node.children

iterator pairs*[T](tree: QuadTree[T], ind: int): (QuadTreeIndex, lent T) =
  let node = tree.nodes[ind]
  if node.kind == Bucket:
    for ind in node.entries.items:
      yield (node.bucket[ind], tree[node.bucket[ind]])
  else:
    var queue = @[ind]
    while queue.len > 0:
      let
        ind = queue.pop()
        node = tree.nodes[ind]

      if node.kind == Bucket:
        for ind in node.entries.items:
          yield (node.bucket[ind], tree[node.bucket[ind]])
      else:
        queue.add node.children

iterator mitems*[T](tree: var QuadTree[T], ind: int): var T =
  let node = tree.nodes[ind]
  if node.kind == Bucket:
    for ind in node.entries.items:
      yield tree[node.bucket[ind]]
  else:
    var queue = @[ind]
    while queue.len > 0:
      let
        ind = queue.pop()
        node = tree.nodes[ind]

      if node.kind == Bucket:
        for ind in node.entries.items:
          yield tree[node.bucket[ind]]
      else:
        queue.add node.children

iterator items*[T](tree: QuadTree[T]): lent T =
  for x in tree.items(0):
    yield x

iterator mitems*[T](tree: var QuadTree[T]): var T =
  for x in tree.mitems(0):
    yield x

iterator pairs*[T](tree: QuadTree[T]): (QuadTreeIndex, lent T) =
  for (x, y) in tree.pairs(0):
    yield (x, y)

iterator upwardSearch*[T](tree: QuadTree[T], nodeIndex: int): (QuadTreeIndex, lent T) =
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
      for theInd, item in tree.pairs(ind):
        yield (theInd, item)
    else:
      for child in node.children.items:
        if child notin visited:
          queue.addFirst child
          visited.incl child

    if node.parent != -1 and node.parent notin visited:
      queue.addLast(node.parent)
      visited.incl node.parent


when isMainModule:
  import std/[enumerate, algorithm]
  type MyType = object
    x, y: int
    name: string
    node: int

  var
    tree = QuadTree[MyType].init(10, 10)
    firstVal: QuadTreeIndex
  for x in 0..<10:
    for y in 0..<10:
      if x == 0 and y == 0:
        firstVal = tree.add MyType(x: x, y: y, name: $x & ", " & $y)
      else:
        discard tree.add MyType(x: x, y: y, name: $x & ", " & $y)

  tree[firstVal].x = 6
  tree[firstVal].y = 4
  tree.reposition()


  var found: seq[MyType]
  for i, (_, val) in enumerate tree.upwardSearch(tree[firstVal].node):
    if i > 20:
      break
    found.add val

  echo found.sortedByIt(sqrt(
    ((it.x - tree[firstVal].x) * (it.x - tree[firstVal].x)).float +
    ((it.y - tree[firstVal].y) * (it.y - tree[firstVal].y)).float))

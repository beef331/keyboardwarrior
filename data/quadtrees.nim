import std/[intsets, deques, setutils, math, strutils]
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

  BucketArr = array[bucketSize, QuadTreeIndex]
  EntrySet = set[range[0 .. bucketSize - 1]]

  QuadNode = object
    x, y: int
    width, height: int
    parent: int = -1
    case kind: QuadNodeKind
    of Bucket:
      bucket: BucketArr
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
    activeValues: Intset
    inActiveValues: Intset
    width, height: int

proc `$`*(ind: QuadTreeIndex): string {.borrow.}

proc `==`*(a, b: QuadTreeIndex): bool {.borrow.}

proc fullSet[T: range](_: typedesc[set[T]]): set[T] = {T.low..T.high}

proc `[]`*[T](tree: QuadTree[T], ind: QuadTreeIndex): lent T =
  assert ind.int in tree.activeValues
  assert ind.int notin tree.inactiveValues
  tree.values[int ind]

proc `[]=`[T](tree: var QuadTree[T], ind: QuadTreeIndex, val: sink T) =
  tree.activeValues.incl ind.int
  tree.inactiveValues.excl ind.int
  tree.values.setLen(max(tree.values.len, ind.int + 1))
  tree.values[int ind] = val

proc `[]`*[T](tree: var QuadTree[T], ind: QuadTreeIndex): var T =
  assert ind.int in tree.activeValues
  assert ind.int notin tree.inactiveValues
  tree.values[int ind]

proc printNode[T](tree: QuadTree[T], ind, indent: int): string =
  let node = tree.nodes[ind]
  case node.kind
  of Bucket:
    result.add "  ".repeat(indent)  & "Bucket: \n"
    result.add "  ".repeat(indent + 1)  & $node.entries.len & "\n"
  of Parent:
    result.add "  ".repeat(indent)  & "Parent: \n"
    for child in node.children:
      result.add tree.printNode(child, indent + 1)

proc printTree*[T](tree: QuadTree[T]) =
  echo printNode(tree, 0, 0)


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
  assert node.kind == Bucket
  node = QuadNode(
    kind: Parent,
    width: node.width,
    height: node.height,
    x: node.x,
    y: node.y,
    children: inds,
    parent: node.parent
  )

proc transition(node: var QuadNode, children: openArray[QuadTreeIndex]) =
  assert node.kind == Parent
  node = bucket(node.x, node.y, node.width, node.height, node.parent)
  node.bucket[0..children.high] = children
  node.entries = {0..children.high}

proc getNextIndex[T](tree: var QuadTree[T]): QuadTreeIndex =
  ## Retuns the next valueindex
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

proc quadPos[T](tree: QuadTree[T], node: QuadNode, pos: tuple[x, y: int]): QuadPos =
  if pos.x > node.x + node.width div 2:
    if pos.y > node.y + node.height div 2:
      TopRight
    else:
      BottomRight
  else:
    if pos.y.int > node.y + node.height div 2:
      TopLeft
    else:
      BottomLeft

proc quadPos[T](tree: QuadTree[T], node: QuadNode, ind: QuadTreeIndex): QuadPos =
  let val = tree[ind]
  tree.quadPos(node, (val.x.int, val.y.int))

proc add(node: var QuadNode, val: QuadTreeIndex) =
  assert node.kind == Bucket
  var ind = 0
  for entry in node.entries.complement.items:
    ind = entry
    break
  node.bucket[ind] = val
  node.entries.incl ind

proc add[T](tree: var QuadTree[T], val: var T, ind: int, valInd: QuadTreeIndex) =
  let node = tree.nodes[ind]
  assert val in tree.nodes[0]
  assert val in node
  case node.kind:
  of Bucket:
    if node.entries == EntrySet.fullSet(): # Split bucket
      let
        leftWidth = ceil(node.width / 2).int
        bottomHeight = ceil(node.height / 2).int
        rightWidth = floor(node.width / 2).int
        topHeight = floor(node.height / 2).int
        offsetX = node.x + leftWidth
        offsetY = node.y + bottomHeight


      var newNodes: array[QuadPos, QuadNode] = [
        bucket(node.x, offsetY, leftWidth, topHeight, ind),
        bucket(offsetX, offsetY, rightWidth, topHeight, ind),
        bucket(node.x, node.y, leftWidth, bottomHeight, ind),
        bucket(offsetX, node.y, rightWidth, bottomHeight, ind),
      ]


      let len = tree.nodes.len
      for val in node.bucket:
        let ind = tree.quadPos(node, val)
        newNodes[ind].add val
        tree[val].node = len + ind.ord()
      tree.nodes[ind].transition [len, len + 1, len + 2, len + 3]

      tree.nodes.add newNodes

      let childInd = tree.quadPos(node, valInd)
      tree.add(val, tree.nodes[ind].children[childInd], valInd)
    else:
      tree.nodes[ind].add valInd
      tree[valInd].node = ind

  of Parent:
    let childInd = tree.quadPos(node, valInd)
    tree.add(val, node.children[childInd], valInd)

proc add*[T](tree: var QuadTree[T], val: sink T): QuadTreeIndex =
  let valInd = tree.getNextIndex()
  tree[valInd] = val
  tree.activeValues.incl valInd.int
  tree.inactiveValues.excl valInd.int
  tree.add(tree[valInd], 0, valInd)
  valInd

iterator items*(node: QuadNode): QuadTreeIndex =
  for val in node.entries.items:
    yield node.bucket[val]

iterator items*[T](tree: QuadTree[T], ind: int): lent T =
  let node = tree.nodes[ind]
  case node.kind
  of Bucket:
    for ind in node.items:
      yield tree[ind]
  of Parent:
    var queue {.global.}: seq[int]
    queue.setLen(1)
    queue[0] = ind
    while queue.len > 0:
      let
        ind = queue.pop()
        node = tree.nodes[ind]

      if node.kind == Bucket:
        for ind in node.items:
          yield tree[ind]
      else:
        queue.add node.children

iterator pairs*[T](tree: QuadTree[T], ind: int): (QuadTreeIndex, lent T) =
  let node = tree.nodes[ind]
  case node.kind
  of Bucket:
    for ind in node.items:
      yield (ind, tree[ind])
  of Parent:
    var queue {.global.}: seq[int]
    queue.setLen(1)
    queue[0] = ind
    while queue.len > 0:
      let
        ind = queue.pop()
        node = tree.nodes[ind]

      if node.kind == Bucket:
        for ind in node.items:
          yield (ind, tree[ind])
      else:
        queue.add node.children

iterator mitems*[T](tree: var QuadTree[T], ind: int): var T =
  let node = tree.nodes[ind]
  case node.kind
  of Bucket:
    for ind in node.items:
      yield tree[ind]
  of Parent:
    var queue {.global.}: seq[int]
    queue.setLen(1)
    queue[0] = ind
    while queue.len > 0:
      let
        ind = queue.pop()
        node = tree.nodes[ind]

      if node.kind == Bucket:
        for ind in node.items:
          yield tree[ind]
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
    queue {.global.}: Deque[int]
    visited: IntSet
  visited.incl nodeIndex
  queue.clear()
  queue.addFirst(nodeIndex)
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


proc toTransitionCount[T](tree: QuadTree[T], node: int): (int, BucketArr) =
  ## Returns `-1, ...` in the case count > 64
  ## Returns `0, ...` in the case the node should be considered for deletion
  ## Returns `ind,....` in the case the node should be be converted to a bucket
  var queue {.global.}: seq[int]
  queue.setLen(1)
  queue[0] = node

  while queue.len > 0:
    let
      ind = queue.pop()
      node = tree.nodes[ind]

    if node.kind == Bucket:
      if result[0] + node.entries.len >= bucketSize:
        result[0] = -1
        return

      for val in node.items:
        result[1][result[0]] = val
        inc result[0]
    else:
      queue.add node.children

proc maybeCollapse[T](tree: var QuadTree[T], nodeInd: int) =
  if tree.nodes[nodeInd].kind == Parent:
    let (ind, val) = tree.toTransitionCount(nodeInd)
    if ind > 0:
      tree.nodes[nodeInd].transition(val.toOpenArray(0, ind - 1))
      for val in tree.mitems(nodeInd):
        val.node = nodeInd

proc delete*(node: var QuadNode, ind: QuadTreeIndex) =
  var found: bool
  for i, x in node.bucket:
    if x == ind:
      found = true
      node.entries.excl i
  assert found

proc delete*[T](tree: var QuadTree[T], ind: QuadTreeIndex) =
  let nodeInd = tree[ind].node
  tree.nodes[nodeInd].delete(ind)
  tree.maybeCollapse(tree.nodes[nodeInd].parent)
  reset tree[ind]
  tree.inactiveValues.incl ind.int
  tree.activeValues.excl ind.int

iterator reposition*[T](tree: var QuadTree[T]): QuadTreeIndex =
  ## Repositions all entities to their proper bucket
  ## Any entity that leaves the tree is yielded then destroyed
  for i in tree.activeValues.items:
    let
      ind = QuadTreeIndex i
      startNode = tree[ind].node
      node = tree.nodes[startNode]

    if tree[ind] in tree.nodes[0]:
      if tree[ind] notin node and startNode != 0: # never need to move out of root
        assert tree.nodes[startNode].kind == Bucket

        tree.add(tree[ind], 0, QuadTreeIndex i)
        assert tree.nodes[tree[ind].node].kind == Bucket
        assert startNode != tree[ind].node
        for entInd in node.entries.items:
          if node.bucket[entInd] == ind:
            tree.nodes[startNode].entries.excl entInd
            break
        tree.maybeCollapse(tree.nodes[startNode].parent)
    else:
      yield ind
      tree.delete(ind)

proc contains(bottomLeft, topRight: tuple[x, y: int], point: tuple[x, y: int]): bool =
  point.x in bottomLeft.x .. topRight.x and
  point.y in bottomLeft.y .. topRight.y

proc overlap(node: QuadNode, bottomLeft, topRight: tuple[x, y: int]): bool =
  bottomLeft.x < node.x + node.width and node.x < topRight.x and
  bottomLeft.y < node.y + node.height and node.y < topRight.y

iterator inRangePairs*[T](tree: QuadTree[T], x, y, width, height: int): (QuadTreeIndex, lent T) =
  let
    x = clamp(x, 0, tree.width)
    y = clamp(x, 0, tree.height)
    width = min(width, tree.width - x)
    height = min(height, tree.height - y)

  let
    topLeftPos = (x - width, y + height)
    topRightPos = (x + width, y + height)
    bottomLeftPos = (x - width, y - height)
    bottomRightPos = (x + width, y - height)

  var queue {.global.}: seq[int]
  queue.setLen(0)
  queue.add [
    tree.nodes[0].children[tree.quadPos(tree.nodes[0], topLeftPos)],
    tree.nodes[0].children[tree.quadPos(tree.nodes[0], topRightPos)],
    tree.nodes[0].children[tree.quadPos(tree.nodes[0], bottomLeftPos)],
    tree.nodes[0].children[tree.quadPos(tree.nodes[0], bottomRightPos)]
    ]
  var visited: IntSet

  while queue.len > 0:
    let
      ind = queue.pop()
      node = tree.nodes[ind]
    if node.overlap(bottomLeftPos, topRightPos) and ind notin visited:
      case node.kind
      of Bucket:
        for (ind, val) in tree.pairs(ind):
          if contains(bottomLeftPos, topRightPos, (val.x.int, val.y.int)):
            yield (ind, val)
      else:
        for child in node.children:
          queue.add child
    visited.incl ind


iterator inRange*[T](tree: QuadTree[T], x, y, width, height: int): lent T =
  for _, val in tree.inRangePairs(x, y, width, height):
    yield val

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
  for val in tree.reposition:
    assert false

  var found: seq[MyType]
  for i, (_, val) in enumerate tree.upwardSearch(tree[firstVal].node):
    if i > 50:
      break
    found.add val

  echo found.sortedByIt(sqrt(
    ((it.x - tree[firstVal].x) * (it.x - tree[firstVal].x)).float +
    ((it.y - tree[firstVal].y) * (it.y - tree[firstVal].y)).float)).toOpenArray(0, 10)

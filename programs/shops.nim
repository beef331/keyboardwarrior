import gamestates
import ../data/spaceentity
import ../screenutils/[texttables, boxes]
import truss3D/inputs
import std/[random, strutils]

proc moneyFormat(val: SomeNumber): string = "$" & $val

type
  ShopState* = enum
    BrowsingShop
    BrowsingInventory
    Purchasing
    Selling

  Shop* = object
    target: string
    position: int
    amount: int = 1
    state: ShopState

  ShopEntry = object
    name {.tableAlign(alignLeft).}: string
    count: int
    cost {.tableStringify(moneyFormat[int]).}: int
    case isSystem {.tableSkip.}: bool
    of true:
      system {.tableSkip.}: System
    of false:
      item {.tableSkip.}: InventoryItem


var shopData: seq[ShopEntry]

for i in 0..59:
  shopData.add ShopEntry(name: "Mysterious Item " & $i, count: rand(1..30), cost: rand(1..4000))


proc name(shop: Shop): string = "Shop"
proc onExit(shop: var Shop, gameState: var GameState) = discard
proc getFlags(_: Shop): ProgramFlags = {}

proc update(shop: var Shop, gameState: var GameState, dt: float32, flags: ProgramFlags) =
  if Draw in flags:
    if TakeInput in flags:
      case shop.state
      of BrowsingShop:
        if KeyCodeUp.isDownRepeating():
          shop.position = max(shop.position - 1, 0)

        if KeyCodeDown.isDownRepeating():
          shop.position = min(shop.position + 1, shopData.high)

        if KeyCodeReturn.isDownRepeating():
          shop.state = Purchasing
          shop.amount = 1

      of Purchasing:
        if KeyCodeUp.isDownRepeating():
          shop.amount = min(shop.amount + 1, shopData[shop.position].count)

        if KeyCodeDown.isDownRepeating():
          shop.amount = max(shop.amount - 1, 1)

        if KeyCodeReturn.isDown():
          shopData[shop.position].count -= shop.amount
          if shopData[shop.position].count == 0:
            shopData.delete(shop.position)
          shop.position = clamp(shop.position, 0, shopData.high)
          shop.state = BrowsingShop


      of BrowsingInventory:
        assert false, "Unimplemented"
      of Selling:
        assert false, "Unimplemented"


    let
      countPerPage = gameState.buffer.lineHeight - 6
      page = shop.position div countPerPage

    let start = gameState.buffer.getPosition()
    var props: seq[GlyphProperties]

    let
      objRange = page * countPerPage .. min((page + 1) * countPerPage - 1, shopData.high)
      pageRelativeInd = shop.position mod countPerPage

    for i in objRange:
      let prop =
        if i mod countPerPage == pageRelativeInd:
          gameState.buffer.properties
        else:
          GlyphProperties(foreground: parseHtmlColor"#aaaaaa")
      props.add [prop, prop, prop]


    gameState.buffer.printPaged(shopData.toOpenArray(objRange.a, objRange.b), pageRelativeInd, entryProperties = props)
    gameState.buffer.setPosition(0, gameState.buffer.getPosition()[1])
    gameState.buffer.put "Press Return to purchase.\n"
    gameState.buffer.put "Press S to toggle Selling.\n"

    case shop.state
    of Purchasing:
      let
        pos = gameState.buffer.getPosition()
        x = start[0] + abs(10 - gameState.buffer.lineWidth div 2)
        y = start[1] + abs(gameState.buffer.lineHeight div 2 - 10)
      var prop = gameState.buffer.properties
      gameState.buffer.properties.background = parseHtmlColor"#111111"

      gameState.buffer.setPosition(x, y)
      gameState.buffer.drawBox(
        [
          "Buy " & $shop.amount,
          "$#s for" % shopData[shop.position].name,
          "$" & $(shop.amount * shopData[shop.position].cost) & "?"
        ],
        border = Outline
      )
      gameState.buffer.properties = prop

      gameState.buffer.setPosition(0, pos[1])

    else:
      discard

proc shopHandler(gameState: var GameState, input: string) =
  if gameState.hasProgram "Shop":
    gameState.enterProgram("Shop")
  else:
    gameState.enterProgram(Shop().toTrait(Program))

command(
  "shop",
  "Opens a shop with a seller",
  shopHandler
)

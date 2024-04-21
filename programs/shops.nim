import gamestates
import ../screenutils/texttables
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
    name: string
    count: int
    cost {.tableAlign(alignLeft), tableStringify(moneyFormat[int]).}: int

var shopData: seq[ShopEntry]

for i in 0..59:
  shopData.add ShopEntry(name: "Mysterious Item " & $i, count: rand(1..30), cost: rand(1..4000))


proc name(shop: Shop): string = "Shop"
proc onExit(shop: var Shop, gameState: var GameState) = discard

proc update(shop: var Shop, gameState: var GameState, dt: float32, active: bool) =
  if active:

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
        shop.state = BrowsingShop


    of BrowsingInventory:
      assert false, "Unimplemented"
    of Selling:
      assert false, "Unimplemented"


    let
      countPerPage = gameState.buffer.lineHeight - 4
      page = shop.position div countPerPage

    let start = gameState.buffer.getPosition()
    gameState.buffer.printPaged(shopData.toOpenArray(page * countPerPage, min((page + 1) * countPerPage - 1, shopData.high)), shop.position mod countPerPage)
    case shop.state
    of Purchasing:
      let
        pos = gameState.buffer.getPosition()
        x = start[0] + abs(10 - gameState.buffer.lineWidth div 2)
        y = start[1] + abs(5 - gameState.buffer.lineHeight div 2)
        prop = GlyphProperties(foreground: parseHtmlColor"white", background: parseHtmlColor"#111111")

      gameState.buffer.setPosition(x, y)
      gameState.buffer.put " ".repeat(10), prop
      gameState.buffer.setPosition(x, y + 1)
      gameState.buffer.put " Buying $# " % $shop.amount, prop
      gameState.buffer.setPosition(x, y + 2)
      gameState.buffer.put " $# " % shopData[shop.position].name, prop
      gameState.buffer.setPosition(x, y + 3)
      gameState.buffer.put " for ", prop
      gameState.buffer.setPosition(x, y + 4)
      gameState.buffer.put " $# " % $(shop.amount * shopData[shop.position].cost), prop
      gameState.buffer.setPosition(x, y + 5)
      gameState.buffer.put " ".repeat(10), prop

      gameState.buffer.setPosition(0, pos[1])

    else:
      discard



    gameState.buffer.put "Press Return to purchase. Press S to toggle Selling"
    gamestate.buffer.newLine()



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

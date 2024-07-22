import pkg/pixie
import screenrenderer

type
  Step = tuple[prop: GlyphProperties, progress: float32]
  Gradient* = openArray[Step]

proc lerp(a, b, t: float32): float32 =
  (b - a) + a * clamp(t, 0, 1)

proc evaluate*(gradient: Gradient, pos: float32): GlyphProperties =
  let pos = clamp(pos, 0, 1)
  if gradient.len == 1:
    result = gradient[0].prop

  for i, step in gradient.toOpenArray(0, gradient.high - 1):
    if pos in step.progress..gradient[i + 1].progress:
      result = step.prop
      let amount = (pos - step.progress) / (gradient[i + 1].progress - step.progress)
      for start, stop in fields(result, gradient[i + 1].prop):
        start = lerp(start, stop, amount)
      return

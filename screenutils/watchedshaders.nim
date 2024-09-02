import truss3D/shaders
import std/[os, times]

type WatchedShader* = ref object
  vertPath: string
  fragPath: string
  lastVertModified: Time
  lastFragModified: Time
  shader*: Shader

converter toShader*(watched: WatchedShader): lent Shader = watched.shader


proc loadWatchedShader*(vertPath, fragPath: string): WatchedShader =
  WatchedShader(
      vertPath: vertPath,
      fragPath: fragPath,
      lastVertModified: getLastModificationTime(vertPath),
      lastFragModified: getLastModificationTime(fragPath),
      shader: loadShader(ShaderPath vertPath, ShaderPath fragPath)
  )

proc reloadIfNeeded*(shader: WatchedShader) =
  let
    vertTime = getLastModificationTime(shader.fragPath)
    fragTime = getLastModificationTime(shader.fragPath)

  if vertTime > shader.lastVertModified or fragTime > shader.lastFragModified:
    shader.shader = loadShader(ShaderPath shader.vertPath, ShaderPath shader.fragPath)
    shader.lastVertModified = vertTime
    shader.lastFragModified = fragTime

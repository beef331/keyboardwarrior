#--define:useMalloc
--define:"truss3D.useAssimp:false"
when defined(mingw):
  --dynLibOverride:"sdl2" 
  switch("passL", gorgeEx("/usr/x86_64-w64-mingw32/bin/sdl2-config --static-libs")[0])
  --define:release
  --app:gui
when appType == "lib":
  switch("nimMainPrefix", "lib")
  switch("warnings", "off")
  switch("hints", "off")
--define:useMalloc

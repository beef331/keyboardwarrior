#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform vec2 screenSize;
uniform float time;
uniform float curve;
uniform float activeScreen;


/*
  //Center UVs for simple math
  float2 newUV = i.uv - float2(0.5, 0.5);
  //Divide by a scale based of length to get curve, 1.5 is hardcoded for scaling edges to fit
  newUV *= pow(length(newUV) / 0.5,_Fisheye * length(newUV));
  if(abs(newUV.x) >= 0.5 || abs(newUV.y) >= 0.5)
  {
      return 0;
  }
  newUV += float2(0.5, 0.5);
  i.uv = newUV;

*/

float rectangle(vec2 samplePosition, vec2 halfSize){
    vec2 componentWiseEdgeDistance = abs(samplePosition) - halfSize;
    float outsideDistance = length(max(componentWiseEdgeDistance, 0));
    float insideDistance = min(max(componentWiseEdgeDistance.x, componentWiseEdgeDistance.y), 0);
    return outsideDistance + insideDistance;
}


vec2 barrelUv(vec2 uv){
  uv -= 0.5;
  uv *= pow(length(uv) / 0.5, length(uv) * curve);
  uv += 0.5;
  return uv;
}

void main() {
  vec2 texSize = textureSize(tex, 0);
  vec2 fragCoord = gl_FragCoord.xy / screenSize;
  vec2 screenTexelSize = 4 / screenSize;
  vec2 uv = barrelUv(fragCoord) - fragCoord;
  vec2 finalUv = fUv + uv - 0.5;
  float sdf = rectangle(finalUv, vec2(0.5));
  float closeness = mod(uv.y, screenTexelSize.y) / screenTexelSize.y;
  float borderSize = -10 / length(texSize);
  float outline = float(sdf > borderSize);
  float isActive = (activeScreen + 1) / 2;
  vec4 col = mix(vec4(0, 0.2, 0.8, 1), vec4(1, 1, 0, 1), isActive);


  vec2 theUv = (finalUv) * (1 - borderSize * 5) + 0.5;

  frag_colour = mix(texture(tex, theUv) * (0.8 + activeScreen * 0.2), col, outline);// * pow(closeness, 0.2);
  //frag_colour = vec4(sdf > -5/ length(texSize));
}

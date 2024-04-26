#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform vec2 screenSize;
uniform float time;



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

vec2 barrelUv(vec2 uv){
  uv -= 0.5;
  uv *= pow(length(uv) / 0.5, length(uv) * 1);
  uv += 0.5;
  return uv;
}

void main() {
  vec2 texSize = textureSize(tex, 0);
  vec2 screenTexelSize = 4 / screenSize;
  vec2 uv = barrelUv(fUv);
  float closeness = mod(fUv.y, screenTexelSize.y) / screenTexelSize.y;

  frag_colour = texture(tex, uv) * pow(closeness, 0.2);
}

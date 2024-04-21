#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform float time;
uniform float lineHeight;

float scanLine(vec2 coord, float lineHeight){
  return mod(coord.y + time, lineHeight);
}

void main() {
  vec2 texSize = textureSize(tex, 0);
  float lineTexel = lineHeight / texSize.y;
  frag_colour = texture(tex, fUv) + scanLine(fUv, lineTexel) * 0.3;
}

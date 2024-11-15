#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform vec2 screenSize;
uniform float curve;

vec2 barrelUv(vec2 uv){
  uv -= 0.5;
  uv *= pow(length(uv) / 0.5, length(uv) * curve);
  uv += 0.5;
  return uv;
}

void main() {
  vec2 theUv = barrelUv(fUv);
  frag_colour = texture(tex, theUv);
}

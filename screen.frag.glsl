#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform vec2 screenSize;
uniform float time;

void main() {
  vec2 texSize = textureSize(tex, 0);
  vec2 screenTexelSize = 2 / screenSize;
  float closeness = mod(fUv.y, screenTexelSize.y) / screenTexelSize.y;
  frag_colour = vec4(closeness);
  frag_colour = texture(tex, fUv) * pow(closeness, 0.2);
}

#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform float lineHeight;

void main() {
  vec2 texSize = textureSize(tex, 0);
  vec2 texelSize = 2 / texSize;
  vec2 lineTexel = lineHeight / texSize;
  frag_colour = texture(tex, fUv);
}

#version 430

out vec4 frag_color;

in vec2 fUv;

uniform sampler2D fontTex;

layout(std430, binding = 2) buffer theFontData{
  vec4 fontData[];
};

flat in vec4 fg;
flat in vec4 bg;
flat in uint fontIndex;
void main() {
  uint mask = (1 << 31) ^ 0xffffffff;
  uint realIndex = mask & fontIndex;
  float whiteSpace = float((1 << 31) & fontIndex);
  vec2 offset = fontData[fontIndex - 1].xy;
  vec2 size = fontData[fontIndex - 1].zw;
  vec2 texSize = vec2(textureSize(fontTex, 0));
  vec4 col = texture(fontTex, offset / texSize + fUv * (size / texSize));
  frag_color = mix(bg, fg, col.a * (1 - whiteSpace));
}

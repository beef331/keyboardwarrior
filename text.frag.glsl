// MIT License
//
// Copyright (c) 2024 Jason Beetham
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

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
  float whiteSpace = float(fontIndex >> 31 & 1);
  vec2 offset = fontData[fontIndex - 1].xy;
  vec2 size = fontData[fontIndex - 1].zw;
  vec2 texSize = vec2(textureSize(fontTex, 0));
  vec4 col = texture(fontTex, offset / texSize + fUv * (size / texSize));
  frag_color = mix(bg, fg, col.a * (1 - whiteSpace));
}

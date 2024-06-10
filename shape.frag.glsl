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

vec4 textRender(){
  uint mask = (15 << 27) ^ 0xffffffff; // 27 cause we have 0b0111(16).... for shapes
  uint realIndex = mask & fontIndex;
  float whiteSpace = float(fontIndex >> 31 & 1);
  vec2 offset = fontData[fontIndex - 1].xy;
  vec2 size = fontData[fontIndex - 1].zw;
  vec2 texSize = vec2(textureSize(fontTex, 0));
  vec4 col = texture(fontTex, offset / texSize + fUv * (size / texSize));
  return mix(bg, fg, col.a * (1 - whiteSpace));
}

float rectangle(vec2 samplePosition, vec2 halfSize){
    vec2 componentWiseEdgeDistance = abs(samplePosition) - halfSize;
    float outsideDistance = length(max(componentWiseEdgeDistance, 0));
    float insideDistance = min(max(componentWiseEdgeDistance.x, componentWiseEdgeDistance.y), 0);
    return outsideDistance + insideDistance;
}

float circle(vec2 samplePosition, float radius){
    //get distance from center and grow it according to radius
    return length(samplePosition) - radius;
}

void main() {
  uint kind = (fontIndex >> 27) & 7; // & 0b0111 gets the shape kind
  switch(kind){
    case 0: // Text
      frag_color = textRender();
      break;
    case 1: // Rectangle
      frag_color = fg;
      break;
    case 2: // Outlined Rectangle
      frag_color = fg * float(abs(rectangle(fUv - 0.5, vec2(0.5))) < 0.01);
      break;
    case 3: // Ellipse
      frag_color = fg * abs(circle(fUv - 0.5, 0.48));
      break;
    case 4: // Outlined Ellipse
      frag_color = fg * float(abs(circle(fUv - 0.5, 0.48)) < 0.01);
      break;
    default:
      frag_color = vec4(kind / 7, 0, 0, 1);
      break;
  }
}

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
layout(location = 0) in vec2 vertex_position;
layout(location = 2) in vec2 uv;

struct data{
  int fg;
  int bg;
  uint fontIndex;
  mat4 matrix;
};

layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

layout(std430, binding = 1) buffer colourData{
  vec4 colours[];
};

out vec2 fUv;
flat out vec4 fg;
flat out vec4 bg;
flat out uint fontIndex;

void main(){
  data theData = instData[gl_InstanceID];
  gl_Position = theData.matrix * vec4(vertex_position, 0, 1);
  fUv = uv;
  fg = colours[theData.fg];
  bg = colours[theData.bg];

  fontIndex = theData.fontIndex;
}

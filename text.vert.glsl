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

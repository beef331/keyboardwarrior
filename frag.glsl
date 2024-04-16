#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;
uniform sampler2D tex;

void main() {
  frag_colour = vec4(238.0/255.0, 210.0/255.0, 168/255.0, 1);
  frag_colour *= round((dot(fNormal, normalize(vec3(1, 0, 1))) * 0.5 + 0.5) / 0.05) * 0.05;
}

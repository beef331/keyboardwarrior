#version 430
out vec4 frag_colour;
in vec3 fNormal;
in vec2 fUv;

uniform sampler2D tex;
uniform vec2 screenSize;
uniform float time;


vec2 barrelUv(vec2 uv){
  uv = 2.0 * uv - 1.0;
  float maxBarrelPower = sqrt(5.0);
  float radius = dot(uv, uv); //faster but doesn't match above accurately
  uv *= pow(vec2(radius), vec2(0.1));

  return uv * 0.5 + 0.5;
}

void main() {
  vec2 texSize = textureSize(tex, 0);
  vec2 screenTexelSize = 2 / screenSize;
  vec2 uv = barrelUv(fUv);
  float closeness = mod(uv.y, screenTexelSize.y) / screenTexelSize.y;

  frag_colour = texture(tex, uv) * pow(closeness, 0.2);
}

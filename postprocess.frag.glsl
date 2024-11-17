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

vec4 blur13(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
  vec4 color = vec4(0.0);
  vec2 off1 = vec2(1.411764705882353) * direction;
  vec2 off2 = vec2(3.2941176470588234) * direction;
  vec2 off3 = vec2(5.176470588235294) * direction;
  color += texture(image, uv) * 0.1964825501511404;
  color += texture(image, uv + (off1 / resolution)) * 0.2969069646728344;
  color += texture(image, uv - (off1 / resolution)) * 0.2969069646728344;
  color += texture(image, uv + (off2 / resolution)) * 0.09447039785044732;
  color += texture(image, uv - (off2 / resolution)) * 0.09447039785044732;
  color += texture(image, uv + (off3 / resolution)) * 0.010381362401148057;
  color += texture(image, uv - (off3 / resolution)) * 0.010381362401148057;
  return color;
}


void main() {
  vec2 theUv = barrelUv(fUv);
  vec4 blurCol = blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(1, 0));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(-1, 0));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(0, -1));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(0, 1));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(-1, 1));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(1, 1));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(-1, -1));
  blurCol +=  blur13(tex, theUv, vec2(textureSize(tex, 0)), vec2(1,1));
  blurCol /= 8;
  frag_colour = texture(tex, theUv);
  frag_colour += (vec4(1) - frag_colour) * blurCol;
}

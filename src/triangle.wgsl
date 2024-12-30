// Purpose: A simple shader that renders a triangle with different colors for each vertex.

// Vertex Shader
var<private> vertexIndex : i32;
var<private> vertexColor : vec4f;
var<private> vertexPosition : vec4f;

fn assignVertexAttributes() {
  var position : vec2f;
  if (vertexIndex == 0i) {
    position = vec2f(-1.0f, -1.0f);
    vertexColor = vec4f(1.0f, 0.0f, 0.0f, 1.0f);
  } else if (vertexIndex == 1i) {
    position = vec2f(1.0f, -1.0f);
    vertexColor = vec4f(0.0f, 1.0f, 0.0f, 1.0f);
  } else if (vertexIndex == 2i) {
    position = vec2f(0.0f, 1.0f);
    vertexColor = vec4f(0.0f, 0.0f, 1.0f, 1.0f);
  }
  vertexPosition = vec4f(position.x, position.y, 0.0f, 1.0f);
}

struct VertexOut {
  @location(0)
  color : vec4f,
  @builtin(position)
  position : vec4f,
}

@vertex
fn vertexMain(@builtin(vertex_index) vertexIndex_param : u32) -> VertexOut {
  vertexIndex = bitcast<i32>(vertexIndex_param);
  assignVertexAttributes();
  return VertexOut(vertexColor, vertexPosition);
}

// Fragment Shader
var<private> fragmentColor : vec4f;

fn assignFragmentColor() {
  fragmentColor = vertexColor;
}

struct FragmentOut {
  @location(0)
  color : vec4f,
}

@fragment
fn fragmentMain(@location(0) inputColor : vec4f) -> FragmentOut {
  vertexColor = inputColor;
  assignFragmentColor();
  return FragmentOut(fragmentColor);
}


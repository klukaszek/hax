// Purpose: A simple shader that renders a triangle with different colors for each vertex.

// Vertex Shader
struct VertexOut {
    float4 color : COLOR0;
    float4 position : SV_Position;
};

float4 assignVertexColor(int index) {
    if (index == 0) return float4(1.0f, 0.0f, 0.0f, 1.0f);
    else if (index == 1) return float4(0.0f, 1.0f, 0.0f, 1.0f);
    else if (index == 2) return float4(0.0f, 0.0f, 1.0f, 1.0f);
    return float4(1.0f, 1.0f, 1.0f, 1.0f); // Default fallback
}

float4 assignVertexPosition(int index) {
    if (index == 0) return float4(-1.0f, -1.0f, 0.0f, 1.0f);
    else if (index == 1) return float4(1.0f, -1.0f, 0.0f, 1.0f);
    else if (index == 2) return float4(0.0f, 1.0f, 0.0f, 1.0f);
    return float4(0.0f, 0.0f, 0.0f, 1.0f); // Default fallback
}

[shader("vertex")]
VertexOut vertexMain(uint vertexIndexParam : SV_VertexID) {
    VertexOut output;
    int index = int(vertexIndexParam);
    output.color = assignVertexColor(index);
    output.position = assignVertexPosition(index);
    return output;
}

// Fragment Shader
struct FragmentOut {
    float4 color : SV_Target;
};

[shader("fragment")]
FragmentOut fragmentMain(float4 inputColor : COLOR0) {
    FragmentOut output;
    output.color = inputColor;
    return output;
}


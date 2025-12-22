@group(0) @binding(0) var render_tex: texture_2d<f32>;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );
  return vec4<f32>(positions[vertex_index], 0.0, 1.0);
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4<f32>) -> @location(0) vec4<f32> {
  let dims = textureDimensions(render_tex);
  let coord = vec2<i32>(i32(frag_coord.x), i32(frag_coord.y));
  if (coord.x < 0 || coord.y < 0 || coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) {
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
  }
  let col = textureLoad(render_tex, coord, 0).xyz;
  return vec4<f32>(col, 1.0);
}

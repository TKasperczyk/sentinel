struct Uniforms {
  time: f32,
  intensity: f32,
  blend_factor: f32,
  scale: f32,
  current_state: u32,
  target_state: u32,
  frame_count: u32,
  _pad0: u32,
  resolution: vec2<f32>,
  position: vec2<f32>,
  damping: f32,
  noise_strength: f32,
  attraction: f32,
  speed: f32,
  trail_fade: f32,
  glow_intensity: f32,
  color_shift: f32,
  _pad1: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(1) @binding(0) var prev_state: texture_2d<f32>;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );
  return vec4<f32>(positions[vertex_index], 0.0, 1.0);
}

const VELOCITY_ROWS: i32 = 30;
const POS_SAMPLE_ROW: i32 = 100;
const INIT_FRAMES: u32 = 10u;

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var q = fract(p * vec3<f32>(443.8975, 397.2973, 491.1871));
  q = q + dot(q.zxy, q.yxz + vec3<f32>(19.1));
  return fract(vec3<f32>(q.x * q.y, q.z * q.x, q.y * q.z)) - vec3<f32>(0.5);
}

fn update_velocity(vel: vec3<f32>, pos: vec3<f32>, time: f32) -> vec3<f32> {
  let noise = hash3(vel + vec3<f32>(time, time, time)) * 2.0 * u.noise_strength;
  var v = vel * u.damping + noise;
  let d = pow(length(pos) * 1.2, 0.75);
  let mix_amt = sin(-time * 0.55) * 0.5 + 0.5;
  v = mix(v, -pos * d * u.attraction, mix_amt);
  return v;
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4<f32>) -> @location(0) vec4<f32> {
  let dims = textureDimensions(prev_state);
  let coord = vec2<i32>(i32(frag_coord.x), i32(frag_coord.y));
  if (coord.x < 0 || coord.y < 0 || coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) {
    return vec4<f32>(0.0);
  }

  if (u.frame_count < INIT_FRAMES) {
    let dims_f = vec2<f32>(f32(dims.x), f32(dims.y));
    let q = vec2<f32>(f32(coord.x), f32(coord.y)) / dims_f;
    let noise = hash3(vec3<f32>(q * 1.9, 0.0));
    if (coord.y < VELOCITY_ROWS) {
      return vec4<f32>(noise * 10.0, 1.0);
    } else {
      return vec4<f32>(noise * 0.5, 1.0);
    }
  }

  let pos_row = min(POS_SAMPLE_ROW, i32(dims.y) - 1);
  let vel_row = 0;
  let pos = textureLoad(prev_state, vec2<i32>(coord.x, pos_row), 0).xyz;
  let vel = textureLoad(prev_state, vec2<i32>(coord.x, vel_row), 0).xyz;

  let new_vel = update_velocity(vel, pos, u.time);
  let new_pos = pos + new_vel * (0.002 * u.speed);

  if (coord.y < VELOCITY_ROWS) {
    return vec4<f32>(new_vel, 1.0);
  }
  return vec4<f32>(new_pos, 1.0);
}

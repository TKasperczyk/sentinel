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

fn hash1(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);

  let n000 = hash1(i + vec3<f32>(0.0, 0.0, 0.0));
  let n100 = hash1(i + vec3<f32>(1.0, 0.0, 0.0));
  let n010 = hash1(i + vec3<f32>(0.0, 1.0, 0.0));
  let n110 = hash1(i + vec3<f32>(1.0, 1.0, 0.0));
  let n001 = hash1(i + vec3<f32>(0.0, 0.0, 1.0));
  let n101 = hash1(i + vec3<f32>(1.0, 0.0, 1.0));
  let n011 = hash1(i + vec3<f32>(0.0, 1.0, 1.0));
  let n111 = hash1(i + vec3<f32>(1.0, 1.0, 1.0));

  let nx00 = mix(n000, n100, u.x);
  let nx10 = mix(n010, n110, u.x);
  let nx01 = mix(n001, n101, u.x);
  let nx11 = mix(n011, n111, u.x);
  let nxy0 = mix(nx00, nx10, u.y);
  let nxy1 = mix(nx01, nx11, u.y);
  return mix(nxy0, nxy1, u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var q = p;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    sum = sum + noise3(q) * amp;
    q = q * 2.0 + vec3<f32>(17.0, 11.0, 5.0);
    amp = amp * 0.5;
  }
  return sum;
}

fn flow_noise(p: vec3<f32>) -> vec3<f32> {
  let n1 = fbm(p);
  let n2 = fbm(p + vec3<f32>(11.5, 7.2, 3.4));
  let n3 = fbm(p + vec3<f32>(5.2, 13.1, 9.7));
  return vec3<f32>(n1, n2, n3) * 2.0 - vec3<f32>(1.0);
}

fn sample_swarm_center(pos_row: i32) -> vec3<f32> {
  let dims = textureDimensions(prev_state);
  let max_index = i32(dims.x) - 1;
  var acc = vec3<f32>(0.0);
  acc = acc + textureLoad(prev_state, vec2<i32>(min(0, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(9, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(18, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(27, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(36, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(45, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(54, max_index), pos_row), 0).xyz;
  acc = acc + textureLoad(prev_state, vec2<i32>(min(63, max_index), pos_row), 0).xyz;
  return acc / 8.0;
}

fn state_mods(state: u32) -> vec4<f32> {
  if (state == 1u) {
    return vec4<f32>(0.45, 1.2, 0.9, 1.0);
  }
  if (state == 2u) {
    return vec4<f32>(1.8, 0.25, 0.2, 0.85);
  }
  if (state == 3u) {
    return vec4<f32>(0.6, 1.4, 0.5, 0.95);
  }
  if (state == 4u) {
    return vec4<f32>(-0.4, 1.6, 0.2, 0.95);
  }
  if (state == 5u) {
    return vec4<f32>(0.15, 0.2, 0.1, 0.75);
  }
  return vec4<f32>(0.55, 0.9, 0.35, 1.0);
}

fn state_force(
  state: u32,
  pos: vec3<f32>,
  vel: vec3<f32>,
  id: f32,
  time: f32,
  center: vec3<f32>,
  goal: vec3<f32>,
) -> vec3<f32> {
  let offset = pos - center;
  let offset_dir = normalize(offset + vec3<f32>(0.0001));
  let target_dir = normalize(goal - center + vec3<f32>(0.0001));

  if (state == 1u) {
    let probe = target_dir * (0.4 + 0.3 * sin(time * 0.25 + id * 0.37));
    let stretch = offset_dir * (0.2 + 0.2 * sin(time * 0.35 + id));
    return probe + stretch;
  }
  if (state == 2u) {
    let orbit = vec3<f32>(-offset.y, offset.x, 0.0) * 0.03;
    return orbit - vel * 0.15;
  }
  if (state == 3u) {
    let dart = step(0.95, hash1(vec3<f32>(id * 1.3, time * 0.7, 4.7)));
    let dart_dir =
      normalize(flow_noise(pos * 2.3 + vec3<f32>(time * 0.8, id, time * 0.5)) + vec3<f32>(0.0001));
    return dart_dir * dart * 2.6;
  }
  if (state == 4u) {
    let pulse = 0.5 + 0.5 * sin(time * 1.6 + id * 0.05);
    let burst = step(0.9, hash1(vec3<f32>(time * 0.4, id * 0.17, 2.1)));
    return offset_dir * (1.4 * pulse + burst * 3.0);
  }
  if (state == 5u) {
    let drift = offset_dir * 0.15;
    return vec3<f32>(0.0, -0.25, 0.0) + drift;
  }

  let orbit = vec3<f32>(-offset.y, offset.x, 0.0) * 0.06;
  let bob = vec3<f32>(0.0, sin(time * 0.2 + id * 0.5) * 0.03, 0.0);
  return orbit + bob;
}

fn update_velocity(
  vel: vec3<f32>,
  pos: vec3<f32>,
  id: f32,
  time: f32,
  center: vec3<f32>,
) -> vec3<f32> {
  let mods_cur = state_mods(u.current_state);
  let mods_tgt = state_mods(u.target_state);
  let mods = mix(mods_cur, mods_tgt, u.blend_factor);
  let energy = 0.35 + 0.65 * u.intensity;

  var v = vel * (u.damping * mods.w);

  let flow =
    flow_noise(pos * 1.1 + vel * 0.15 + vec3<f32>(time * 0.2, time * 0.17, time * 0.13));
  v = v + flow * (u.noise_strength * mods.y);

  let aspect = u.resolution.x / max(u.resolution.y, 1.0);
  let goal =
    vec3<f32>((u.position - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0) * 2.0, 0.0);
  let to_center = center - pos;
  let dist = length(to_center);
  let center_dir = normalize(to_center + vec3<f32>(0.0001));
  v = v + center_dir * dist * u.attraction * mods.x;

  let to_goal = goal - pos;
  let goal_dist = length(to_goal);
  let goal_dir = normalize(to_goal + vec3<f32>(0.0001));
  v = v + goal_dir * goal_dist * 0.18 * mods.z;

  let state_force_cur = state_force(u.current_state, pos, vel, id, time, center, goal);
  let state_force_tgt = state_force(u.target_state, pos, vel, id, time, center, goal);
  v = v + mix(state_force_cur, state_force_tgt, u.blend_factor) * energy;

  let boundary_center = goal;
  let boundary_radius = 1.7;
  let boundary_offset = pos - boundary_center;
  let boundary_dist = length(boundary_offset);
  if (boundary_dist > boundary_radius) {
    let push = normalize(boundary_offset + vec3<f32>(0.0001)) * (boundary_dist - boundary_radius);
    v = v - push * 1.4;
  }

  let speed = length(v);
  let max_speed = 6.0;
  if (speed > max_speed) {
    v = v * (max_speed / speed);
  }
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

  let swarm_center = sample_swarm_center(pos_row);
  let new_vel = update_velocity(vel, pos, f32(coord.x), u.time, swarm_center);
  let new_pos = pos + new_vel * (0.002 * u.speed);

  if (coord.y < VELOCITY_ROWS) {
    return vec4<f32>(new_vel, 1.0);
  }
  return vec4<f32>(new_pos, 1.0);
}

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
@group(1) @binding(0) var state_tex: texture_2d<f32>;
@group(1) @binding(1) var prev_render: texture_2d<f32>;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );
  return vec4<f32>(positions[vertex_index], 0.0, 1.0);
}

const TAU: f32 = 6.2831853;
const NUM_PARTICLES: u32 = 70u;    // Reduced from 140 for performance
const STEPS_PER_FRAME: u32 = 4u;   // Reduced from 7 for performance
const POS_SAMPLE_ROW: i32 = 100;

fn mag(p: vec3<f32>) -> f32 {
  return dot(p, p);
}

fn draw_particles(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
  var rez = vec3<f32>(0.0);
  let dims = textureDimensions(state_tex);
  let pos_row = min(POS_SAMPLE_ROW, i32(dims.y) - 1);
  let vel_row = 0;

  for (var i = 0u; i < NUM_PARTICLES; i = i + 1u) {
    let pos = textureLoad(state_tex, vec2<i32>(i32(i), pos_row), 0).xyz;
    let vel = textureLoad(state_tex, vec2<i32>(i32(i), vel_row), 0).xyz;
    var step_pos = pos;

    for (var j = 0u; j < STEPS_PER_FRAME; j = j + 1u) {
      let t = dot(step_pos - ro, rd);
      let closest = ro + rd * t;
      var d = mag(closest - step_pos);
      d = 0.14 / (pow(d * 1000.0, 1.1) + 0.03);

      let phase = u.time * 0.06 + f32(i) * 0.003 + 2.0 + u.color_shift * TAU;
      let color = abs(
        sin(vec3<f32>(2.0, 3.4, 1.2) * phase + vec3<f32>(0.8, 0.0, 1.2)) * 0.7 + 0.3
      );
      rez = rez + d * color * 0.08;  // Boosted to compensate for fewer particles
      step_pos = step_pos + vel * (0.002 * 0.2 * u.speed);
    }
  }

  rez = rez / f32(STEPS_PER_FRAME);
  return rez;
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4<f32>) -> @location(0) vec4<f32> {
  let dims = textureDimensions(prev_render);
  let res = vec2<f32>(f32(dims.x), f32(dims.y));
  var p = frag_coord.xy / res - vec2<f32>(0.5, 0.5);
  let aspect = res.x / res.y;
  p.x = p.x * aspect;

  let center_offset = (u.position - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0);
  p = (p - center_offset) / max(u.scale, 0.001);

  let ro = vec3<f32>(0.0, 0.0, 2.5);
  let rd = normalize(vec3<f32>(p, -0.5));

  var cola = draw_particles(ro, rd);
  cola = cola * u.glow_intensity * (0.55 + 0.45 * u.intensity);

  let coord = vec2<i32>(i32(frag_coord.x), i32(frag_coord.y));
  let colb = textureLoad(prev_render, coord, 0).xyz;

  var col = (cola + colb) * u.trail_fade;
  col = vec3<f32>(1.0) - exp(-col);

  if (u.frame_count < 5u) {
    col = vec3<f32>(0.0);
  }

  return vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}

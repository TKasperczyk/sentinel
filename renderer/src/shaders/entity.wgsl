struct Uniforms {
  time: f32,
  intensity: f32,
  blend_factor: f32,
  scale: f32,
  current_state: u32,
  target_state: u32,
  resolution: vec2<f32>,
  position: vec2<f32>,
  _pad1: vec2<f32>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );
  return vec4<f32>(positions[vertex_index], 0.0, 1.0);
}

// ============================================================================
// UTILITIES
// ============================================================================

const TAU: f32 = 6.2831853;
const PARTICLE_COUNT: u32 = 48u;

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn value_noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ============================================================================
// CLOUD PARAMETERS
// ============================================================================

struct CloudParams {
  color_core: vec3<f32>,
  color_edge: vec3<f32>,
  color_accent: vec3<f32>,
  swarm_radius: f32,
  density: f32,
  edge_softness: f32,
  internal_motion: f32,
  pulse_speed: f32,
  particle_size: f32,
  particle_strength: f32,
};

fn params_for_state(state: u32, k: f32) -> CloudParams {
  var p: CloudParams;
  p.color_core = vec3<f32>(0.2, 0.65, 0.95);
  p.color_edge = vec3<f32>(0.05, 0.4, 0.75);
  p.color_accent = vec3<f32>(0.4, 0.9, 1.0);
  p.swarm_radius = 0.12;
  p.density = 0.7;
  p.edge_softness = 0.2;
  p.internal_motion = 0.45;
  p.pulse_speed = 0.8;
  p.particle_size = 0.0030;
  p.particle_strength = 0.7;

  var t_core = p.color_core;
  var t_edge = p.color_edge;
  var t_accent = p.color_accent;
  var t_radius = p.swarm_radius;
  var t_density = p.density;
  var t_softness = p.edge_softness;
  var t_motion = p.internal_motion;
  var t_pulse = p.pulse_speed;
  var t_size = p.particle_size;
  var t_strength = p.particle_strength;

  if (state == 1u) { // curious
    t_core = vec3<f32>(0.15, 0.9, 1.0);
    t_edge = vec3<f32>(0.1, 0.6, 0.9);
    t_accent = vec3<f32>(0.35, 1.0, 0.95);
    t_radius = 0.16;
    t_density = 0.6;
    t_softness = 0.25;
    t_motion = 0.75;
    t_pulse = 1.2;
    t_size = 0.0032;
    t_strength = 0.75;
  } else if (state == 2u) { // focused
    t_core = vec3<f32>(0.55, 0.45, 0.95);
    t_edge = vec3<f32>(0.2, 0.1, 0.4);
    t_accent = vec3<f32>(0.75, 0.6, 1.0);
    t_radius = 0.08;
    t_density = 0.95;
    t_softness = 0.12;
    t_motion = 0.2;
    t_pulse = 0.55;
    t_size = 0.0024;
    t_strength = 0.85;
  } else if (state == 3u) { // amused
    t_core = vec3<f32>(0.1, 0.95, 0.6);
    t_edge = vec3<f32>(0.05, 0.7, 0.75);
    t_accent = vec3<f32>(0.35, 1.0, 0.7);
    t_radius = 0.14;
    t_density = 0.75;
    t_softness = 0.23;
    t_motion = 0.9;
    t_pulse = 1.6;
    t_size = 0.0034;
    t_strength = 0.9;
  } else if (state == 4u) { // alert
    t_core = vec3<f32>(1.0, 0.6, 0.25);
    t_edge = vec3<f32>(0.9, 0.25, 0.12);
    t_accent = vec3<f32>(1.0, 0.8, 0.4);
    t_radius = 0.18;
    t_density = 0.5;
    t_softness = 0.3;
    t_motion = 1.0;
    t_pulse = 2.1;
    t_size = 0.0036;
    t_strength = 1.0;
  } else if (state == 5u) { // sleepy
    t_core = vec3<f32>(0.15, 0.3, 0.5);
    t_edge = vec3<f32>(0.06, 0.2, 0.35);
    t_accent = vec3<f32>(0.2, 0.4, 0.6);
    t_radius = 0.10;
    t_density = 0.4;
    t_softness = 0.18;
    t_motion = 0.15;
    t_pulse = 0.35;
    t_size = 0.0022;
    t_strength = 0.5;
  }

  p.color_core = mix(p.color_core, t_core, k);
  p.color_edge = mix(p.color_edge, t_edge, k);
  p.color_accent = mix(p.color_accent, t_accent, k);
  p.swarm_radius = mix(p.swarm_radius, t_radius, k);
  p.density = mix(p.density, t_density, k);
  p.edge_softness = mix(p.edge_softness, t_softness, k);
  p.internal_motion = mix(p.internal_motion, t_motion, k);
  p.pulse_speed = mix(p.pulse_speed, t_pulse, k);
  p.particle_size = mix(p.particle_size, t_size, k);
  p.particle_strength = mix(p.particle_strength, t_strength, k);

  return p;
}

fn soft_particle(dist: f32, radius: f32) -> f32 {
  let r = max(radius, 0.0006);
  return 1.0 - smoothstep(r, r * 1.8, dist);
}

// ============================================================================
// MAIN RENDER
// ============================================================================

fn render_cloud(px: vec2<f32>, res: vec2<f32>, time: f32, params: CloudParams) -> vec3<f32> {
  let aspect = res.x / res.y;
  let center_offset = (u.position - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0);
  var uv = (px - res * 0.5) / res.y;
  uv = (uv - center_offset) / max(u.scale, 0.001);

  var col = vec3<f32>(0.008, 0.012, 0.018);
  let vignette = 1.0 - smoothstep(0.6, 1.4, length(uv));
  col = col + params.color_edge * 0.02 * vignette;

  let pulse = 1.0 + 0.05 * sin(time * params.pulse_speed);
  let drift_noise = vec2<f32>(
    value_noise(vec2<f32>(time * 0.12, time * 0.15)),
    value_noise(vec2<f32>(time * 0.17, time * 0.11))
  ) - vec2<f32>(0.5, 0.5);
  let drift = vec2<f32>(sin(time * 0.18), cos(time * 0.22)) * params.internal_motion * 0.05
    + drift_noise * params.internal_motion * 0.06;
  let local = uv - drift;

  let radius = params.swarm_radius * pulse;
  let warp = (value_noise(local * 8.0 + vec2<f32>(time * 0.2, time * 0.17)) - 0.5)
    * params.internal_motion * 0.08;
  let dist = length(local) + warp;

  let softness = max(radius * params.edge_softness, 0.002);
  let body = 1.0 - smoothstep(radius - softness, radius + softness, dist);
  let core = 1.0 - smoothstep(0.0, radius * 0.75, dist);
  var edge_band = smoothstep(radius - softness * 0.6, radius, dist)
    - smoothstep(radius, radius + softness * 0.6, dist);
  edge_band = max(edge_band, 0.0);

  let surface = ((value_noise(local * 14.0 + vec2<f32>(time * 0.35, time * 0.27)) - 0.5) * 0.6 + 0.4)
    * body;

  var particles = 0.0;
  for (var i = 0u; i < PARTICLE_COUNT; i = i + 1u) {
    let fi = f32(i);
    let h1 = hash21(vec2<f32>(fi, fi * 1.73));
    let h2 = hash21(vec2<f32>(fi * 3.11, fi * 0.91));
    let speed = mix(0.4, 1.1, h1);
    let angle = h2 * TAU + time * (0.35 + params.internal_motion * 0.65) * speed + h1 * 1.3;
    let radial = radius * mix(0.35, 0.95, sqrt(h2));

    let jitter_phase = time * (0.6 + h1) + h2 * TAU;
    let jitter = vec2<f32>(sin(jitter_phase), cos(jitter_phase)) * params.internal_motion * 0.02;

    let pos = vec2<f32>(cos(angle), sin(angle)) * radial + jitter;
    let dist_p = length(local - pos);
    let size = params.particle_size * mix(0.7, 1.3, h1);
    particles = particles + soft_particle(dist_p, size);
  }

  particles = particles * body;
  col = col + params.color_core * core * (0.45 + params.density * 0.55);
  col = col + params.color_edge * edge_band * (0.35 + params.density * 0.25);
  col = col + params.color_edge * surface * 0.18;
  col = col + params.color_accent * particles * params.particle_strength * 0.45;

  let grain = hash21(px + vec2<f32>(time, time)) * 0.015;
  col = col + vec3<f32>(grain);

  let intensity = mix(0.55, 1.0, u.intensity);
  col = col * intensity;

  return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4<f32>) -> @location(0) vec4<f32> {
  let time = u.time;
  let blend = saturate(u.blend_factor);

  let cp_cur = params_for_state(u.current_state, u.intensity);
  let cp_tgt = params_for_state(u.target_state, u.intensity);

  if (blend <= 0.001 || u.current_state == u.target_state) {
    return vec4<f32>(render_cloud(frag_coord.xy, u.resolution, time, cp_cur), 1.0);
  }
  if (blend >= 0.999) {
    return vec4<f32>(render_cloud(frag_coord.xy, u.resolution, time, cp_tgt), 1.0);
  }

  let col_a = render_cloud(frag_coord.xy, u.resolution, time, cp_cur);
  let col_b = render_cloud(frag_coord.xy, u.resolution, time, cp_tgt);
  return vec4<f32>(mix(col_a, col_b, blend), 1.0);
}

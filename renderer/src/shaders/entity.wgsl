struct Uniforms {
  time: f32,
  intensity: f32,
  blend_factor: f32,
  _pad0: f32,
  current_state: u32,
  target_state: u32,
  resolution: vec2<f32>,
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

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(57.0, 113.0)));
}

// Signed distance to a line segment
fn sd_segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = saturate(dot(pa, ba) / dot(ba, ba));
  return length(pa - ba * h);
}

// ============================================================================
// FACE PARAMETERS
// ============================================================================

struct FaceParams {
  line_color: vec3<f32>,
  node_color: vec3<f32>,
  glow_color: vec3<f32>,
  pulse_speed: f32,
  float_amount: f32,
  particle_speed: f32,
  eye_scale: f32,
  eye_y_offset: f32,
  brow_angle: f32,
  mouth_smile: f32,
  mouth_open: f32,
  head_tilt: f32,
};

fn params_for_state(state: u32, k: f32) -> FaceParams {
  var p: FaceParams;
  p.line_color = vec3<f32>(0.1, 0.6, 0.8);
  p.node_color = vec3<f32>(0.3, 0.8, 1.0);
  p.glow_color = vec3<f32>(0.0, 0.4, 0.6);
  p.pulse_speed = 1.0;
  p.float_amount = 1.0;
  p.particle_speed = 1.0;
  p.eye_scale = 1.0;
  p.eye_y_offset = 0.0;
  p.brow_angle = 0.0;
  p.mouth_smile = 0.0;
  p.mouth_open = 0.0;
  p.head_tilt = 0.0;

  var t_line = p.line_color;
  var t_node = p.node_color;
  var t_glow = p.glow_color;
  var t_pulse = p.pulse_speed;
  var t_float = p.float_amount;
  var t_part = p.particle_speed;
  var t_eye = p.eye_scale;
  var t_eye_y = p.eye_y_offset;
  var t_brow = p.brow_angle;
  var t_smile = p.mouth_smile;
  var t_open = p.mouth_open;
  var t_tilt = p.head_tilt;

  if (state == 1u) { // curious
    t_line = vec3<f32>(0.1, 0.7, 0.9);
    t_node = vec3<f32>(0.2, 0.9, 1.0);
    t_glow = vec3<f32>(0.0, 0.5, 0.7);
    t_pulse = 1.3;
    t_eye = 1.15;
    t_eye_y = 0.02;
    t_brow = 0.5;
    t_open = 0.2;
    t_smile = 0.1;
    t_tilt = 0.08;
  } else if (state == 2u) { // focused
    t_line = vec3<f32>(0.4, 0.3, 0.9);
    t_node = vec3<f32>(0.6, 0.4, 1.0);
    t_glow = vec3<f32>(0.3, 0.1, 0.6);
    t_pulse = 1.8;
    t_float = 0.6;
    t_eye = 0.8;
    t_brow = -0.3;
    t_smile = -0.15;
  } else if (state == 3u) { // amused
    t_line = vec3<f32>(0.1, 0.8, 0.6);
    t_node = vec3<f32>(0.2, 1.0, 0.7);
    t_glow = vec3<f32>(0.0, 0.5, 0.4);
    t_pulse = 1.5;
    t_part = 1.5;
    t_eye = 0.7;
    t_eye_y = -0.02;
    t_brow = 0.3;
    t_smile = 0.8;
    t_open = 0.15;
    t_tilt = -0.05;
  } else if (state == 4u) { // alert
    t_line = vec3<f32>(1.0, 0.5, 0.2);
    t_node = vec3<f32>(1.0, 0.7, 0.3);
    t_glow = vec3<f32>(0.6, 0.2, 0.0);
    t_pulse = 3.0;
    t_part = 2.0;
    t_float = 1.5;
    t_eye = 1.4;
    t_eye_y = 0.03;
    t_brow = 0.8;
    t_open = 0.5;
    t_smile = -0.2;
  } else if (state == 5u) { // sleepy
    t_line = vec3<f32>(0.15, 0.3, 0.5);
    t_node = vec3<f32>(0.2, 0.4, 0.6);
    t_glow = vec3<f32>(0.05, 0.15, 0.25);
    t_pulse = 0.4;
    t_part = 0.3;
    t_float = 0.4;
    t_eye = 0.4;
    t_eye_y = -0.04;
    t_brow = -0.2;
    t_smile = -0.1;
    t_tilt = 0.06;
  }

  p.line_color = mix(p.line_color, t_line, k);
  p.node_color = mix(p.node_color, t_node, k);
  p.glow_color = mix(p.glow_color, t_glow, k);
  p.pulse_speed = mix(p.pulse_speed, t_pulse, k);
  p.float_amount = mix(p.float_amount, t_float, k);
  p.particle_speed = mix(p.particle_speed, t_part, k);
  p.eye_scale = mix(p.eye_scale, t_eye, k);
  p.eye_y_offset = mix(p.eye_y_offset, t_eye_y, k);
  p.brow_angle = mix(p.brow_angle, t_brow, k);
  p.mouth_smile = mix(p.mouth_smile, t_smile, k);
  p.mouth_open = mix(p.mouth_open, t_open, k);
  p.head_tilt = mix(p.head_tilt, t_tilt, k);

  return p;
}

// ============================================================================
// FACE GEOMETRY
// ============================================================================

fn face_mesh(uv: vec2<f32>, fp: FaceParams, time: f32) -> f32 {
  let tilt = fp.head_tilt + 0.02 * sin(time * 0.5);
  let c = cos(tilt);
  let s = sin(tilt);
  var p = vec2<f32>(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
  p.y = p.y - 0.01 * sin(time * fp.pulse_speed) * fp.float_amount;

  let line_w = 0.003;
  var d = 1000.0;

  // HEAD OUTLINE (manually specified segments)
  d = min(d, sd_segment(p, vec2<f32>(0.0, 0.35), vec2<f32>(0.15, 0.32)));
  d = min(d, sd_segment(p, vec2<f32>(0.15, 0.32), vec2<f32>(0.25, 0.22)));
  d = min(d, sd_segment(p, vec2<f32>(0.25, 0.22), vec2<f32>(0.28, 0.05)));
  d = min(d, sd_segment(p, vec2<f32>(0.28, 0.05), vec2<f32>(0.25, -0.12)));
  d = min(d, sd_segment(p, vec2<f32>(0.25, -0.12), vec2<f32>(0.18, -0.25)));
  d = min(d, sd_segment(p, vec2<f32>(0.18, -0.25), vec2<f32>(0.08, -0.32)));
  d = min(d, sd_segment(p, vec2<f32>(0.08, -0.32), vec2<f32>(0.0, -0.35)));
  d = min(d, sd_segment(p, vec2<f32>(0.0, -0.35), vec2<f32>(-0.08, -0.32)));
  d = min(d, sd_segment(p, vec2<f32>(-0.08, -0.32), vec2<f32>(-0.18, -0.25)));
  d = min(d, sd_segment(p, vec2<f32>(-0.18, -0.25), vec2<f32>(-0.25, -0.12)));
  d = min(d, sd_segment(p, vec2<f32>(-0.25, -0.12), vec2<f32>(-0.28, 0.05)));
  d = min(d, sd_segment(p, vec2<f32>(-0.28, 0.05), vec2<f32>(-0.25, 0.22)));
  d = min(d, sd_segment(p, vec2<f32>(-0.25, 0.22), vec2<f32>(-0.15, 0.32)));
  d = min(d, sd_segment(p, vec2<f32>(-0.15, 0.32), vec2<f32>(0.0, 0.35)));

  // INTERNAL STRUCTURE
  d = min(d, sd_segment(p, vec2<f32>(-0.2, 0.2), vec2<f32>(0.2, 0.2)));
  d = min(d, sd_segment(p, vec2<f32>(-0.15, 0.28), vec2<f32>(0.15, 0.28)));
  d = min(d, sd_segment(p, vec2<f32>(-0.22, 0.0), vec2<f32>(-0.1, -0.05)));
  d = min(d, sd_segment(p, vec2<f32>(0.22, 0.0), vec2<f32>(0.1, -0.05)));
  d = min(d, sd_segment(p, vec2<f32>(-0.2, -0.15), vec2<f32>(0.2, -0.15)));
  d = min(d, sd_segment(p, vec2<f32>(0.0, 0.12), vec2<f32>(0.0, -0.08)));
  d = min(d, sd_segment(p, vec2<f32>(-0.04, -0.08), vec2<f32>(0.04, -0.08)));

  // EYES
  let eye_y = 0.08 + fp.eye_y_offset;
  let eye_h = 0.035 * fp.eye_scale;
  let eye_w = 0.06;

  // Left eye (diamond shape)
  d = min(d, sd_segment(p, vec2<f32>(-0.1 - eye_w, eye_y), vec2<f32>(-0.1, eye_y + eye_h)));
  d = min(d, sd_segment(p, vec2<f32>(-0.1, eye_y + eye_h), vec2<f32>(-0.1 + eye_w, eye_y)));
  d = min(d, sd_segment(p, vec2<f32>(-0.1 + eye_w, eye_y), vec2<f32>(-0.1, eye_y - eye_h)));
  d = min(d, sd_segment(p, vec2<f32>(-0.1, eye_y - eye_h), vec2<f32>(-0.1 - eye_w, eye_y)));

  // Right eye (diamond shape)
  d = min(d, sd_segment(p, vec2<f32>(0.1 - eye_w, eye_y), vec2<f32>(0.1, eye_y + eye_h)));
  d = min(d, sd_segment(p, vec2<f32>(0.1, eye_y + eye_h), vec2<f32>(0.1 + eye_w, eye_y)));
  d = min(d, sd_segment(p, vec2<f32>(0.1 + eye_w, eye_y), vec2<f32>(0.1, eye_y - eye_h)));
  d = min(d, sd_segment(p, vec2<f32>(0.1, eye_y - eye_h), vec2<f32>(0.1 - eye_w, eye_y)));

  // Eye connections to head
  d = min(d, sd_segment(p, vec2<f32>(-0.1 - eye_w, eye_y), vec2<f32>(-0.22, 0.0)));
  d = min(d, sd_segment(p, vec2<f32>(0.1 + eye_w, eye_y), vec2<f32>(0.22, 0.0)));
  d = min(d, sd_segment(p, vec2<f32>(-0.1, eye_y + eye_h), vec2<f32>(-0.1, 0.2)));
  d = min(d, sd_segment(p, vec2<f32>(0.1, eye_y + eye_h), vec2<f32>(0.1, 0.2)));

  // EYEBROWS
  let brow_y = 0.16 + fp.eye_y_offset;
  let brow_in_y = brow_y - fp.brow_angle * 0.03;
  let brow_out_y = brow_y + fp.brow_angle * 0.02;
  d = min(d, sd_segment(p, vec2<f32>(-0.14, brow_out_y), vec2<f32>(-0.05, brow_in_y)));
  d = min(d, sd_segment(p, vec2<f32>(0.05, brow_in_y), vec2<f32>(0.14, brow_out_y)));

  // MOUTH
  let mouth_y = -0.2;
  let mouth_w = 0.08 + fp.mouth_open * 0.02;
  let smile = fp.mouth_smile * 0.04;
  let open_amt = fp.mouth_open * 0.03;

  // Upper lip
  d = min(d, sd_segment(p, vec2<f32>(-mouth_w, mouth_y + smile * 0.5), vec2<f32>(0.0, mouth_y - 0.01)));
  d = min(d, sd_segment(p, vec2<f32>(0.0, mouth_y - 0.01), vec2<f32>(mouth_w, mouth_y + smile * 0.5)));

  // Lower lip
  let low_y = mouth_y - open_amt;
  d = min(d, sd_segment(p, vec2<f32>(-mouth_w, mouth_y + smile * 0.5), vec2<f32>(-mouth_w * 0.5, low_y - smile)));
  d = min(d, sd_segment(p, vec2<f32>(-mouth_w * 0.5, low_y - smile), vec2<f32>(0.0, low_y - smile * 0.5)));
  d = min(d, sd_segment(p, vec2<f32>(0.0, low_y - smile * 0.5), vec2<f32>(mouth_w * 0.5, low_y - smile)));
  d = min(d, sd_segment(p, vec2<f32>(mouth_w * 0.5, low_y - smile), vec2<f32>(mouth_w, mouth_y + smile * 0.5)));

  // Chin line
  d = min(d, sd_segment(p, vec2<f32>(0.0, low_y - smile * 0.5 - 0.02), vec2<f32>(0.0, -0.32)));

  return d - line_w;
}

fn face_nodes(uv: vec2<f32>, fp: FaceParams, time: f32) -> f32 {
  let tilt = fp.head_tilt + 0.02 * sin(time * 0.5);
  let c = cos(tilt);
  let s = sin(tilt);
  var p = vec2<f32>(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
  p.y = p.y - 0.01 * sin(time * fp.pulse_speed) * fp.float_amount;

  var glow = 0.0;
  let pulse = 0.5 + 0.5 * sin(time * fp.pulse_speed * 2.0);

  // Head outline nodes
  glow = max(glow, exp(-length(p - vec2<f32>(0.0, 0.35)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.15, 0.32)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.25, 0.22)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.28, 0.05)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.25, -0.12)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.18, -0.25)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.0, -0.35)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.18, -0.25)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.25, -0.12)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.28, 0.05)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.25, 0.22)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.15, 0.32)) * 80.0));

  // Eye nodes
  let eye_y = 0.08 + fp.eye_y_offset;
  let eye_h = 0.035 * fp.eye_scale;
  glow = max(glow, exp(-length(p - vec2<f32>(-0.16, eye_y)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.1, eye_y + eye_h)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.04, eye_y)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.1, eye_y - eye_h)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.04, eye_y)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.1, eye_y + eye_h)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.16, eye_y)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.1, eye_y - eye_h)) * 80.0));

  // Brow nodes
  let brow_y = 0.16 + fp.eye_y_offset;
  glow = max(glow, exp(-length(p - vec2<f32>(-0.14, brow_y + fp.brow_angle * 0.02)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(-0.05, brow_y - fp.brow_angle * 0.03)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.05, brow_y - fp.brow_angle * 0.03)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.14, brow_y + fp.brow_angle * 0.02)) * 80.0));

  // Mouth nodes
  let smile = fp.mouth_smile * 0.02;
  glow = max(glow, exp(-length(p - vec2<f32>(-0.08, -0.2 + smile)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.08, -0.2 + smile)) * 80.0));
  glow = max(glow, exp(-length(p - vec2<f32>(0.0, -0.21)) * 80.0));

  return glow * (0.7 + 0.3 * pulse);
}

fn particles(uv: vec2<f32>, fp: FaceParams, time: f32) -> f32 {
  var glow = 0.0;

  // Manually define 20 particles with different positions
  for (var i = 0u; i < 20u; i = i + 1u) {
    let fi = f32(i);
    let rnd_x = fract(sin(fi * 12.9898) * 43758.5453);
    let rnd_y = fract(sin(fi * 78.233) * 43758.5453);

    let angle = rnd_x * 6.28 + time * fp.particle_speed * (0.3 + rnd_y * 0.4);
    let radius = 0.35 + rnd_y * 0.25;
    let height = (rnd_x - 0.5) * 0.6;

    var pos = vec2<f32>(
      cos(angle) * radius,
      height + sin(angle * 2.0 + time * fp.particle_speed) * 0.05
    );

    let drift = sin(time * 0.5 + fi) * 0.1 * fp.float_amount;
    pos = pos * (1.0 + drift * 0.3);

    let dist = length(uv - pos);
    let size = 0.003 + rnd_y * 0.004;
    let brightness = 0.3 + 0.4 * sin(time * 2.0 + fi * 0.5);

    glow = glow + exp(-dist / size) * brightness * 0.12;
  }

  return glow;
}

fn particle_connections(uv: vec2<f32>, fp: FaceParams, time: f32) -> f32 {
  var line_glow = 0.0;

  for (var i = 0u; i < 10u; i = i + 1u) {
    let fi = f32(i);
    let rnd_x = fract(sin(fi * 23.456) * 43758.5453);
    let rnd_y = fract(sin(fi * 67.89) * 43758.5453);

    let angle = rnd_x * 6.28 + time * fp.particle_speed * 0.2;
    let radius = 0.4 + rnd_y * 0.2;

    let outer = vec2<f32>(cos(angle) * radius, (rnd_x - 0.5) * 0.5);
    let inner_angle = angle + 0.2;
    let inner = vec2<f32>(cos(inner_angle) * 0.28, sin(inner_angle) * 0.2);

    let vis = step(0.6, sin(time * 1.5 + fi * 0.7));

    let dist = sd_segment(uv, inner, outer);
    line_glow = line_glow + exp(-dist * 200.0) * 0.08 * vis;
  }

  return line_glow;
}

// ============================================================================
// MAIN RENDER
// ============================================================================

fn render(px: vec2<f32>, res: vec2<f32>, time: f32, fp: FaceParams) -> vec3<f32> {
  var uv = (px - res * 0.5) / res.y;

  // Dark background
  var col = vec3<f32>(0.01, 0.02, 0.04);
  col = col + vec3<f32>(0.01, 0.02, 0.03) * (1.0 - length(uv) * 0.8);

  // Background glow
  let bg_glow = exp(-length(uv) * 2.5) * 0.15;
  col = col + fp.glow_color * bg_glow;

  // Face wireframe
  let face_d = face_mesh(uv, fp, time);
  let face_line = exp(-max(0.0, face_d) * 150.0);

  // Nodes
  let nodes = face_nodes(uv, fp, time);

  // Particles
  let parts = particles(uv, fp, time);

  // Connections
  let connections = particle_connections(uv, fp, time);

  // Combine
  col = col + fp.line_color * face_line * 0.8;
  col = col + fp.node_color * nodes;
  col = col + fp.node_color * parts;
  col = col + fp.line_color * connections * 0.5;

  // Inner glow
  let face_fill = smoothstep(0.3, 0.0, length(uv)) * 0.05;
  col = col + fp.glow_color * face_fill;

  // Scanlines
  let scan = 0.98 + 0.02 * sin(px.y * 2.0);
  col = col * scan;

  // Vignette
  let vign = 1.0 - length(uv) * 0.5;
  col = col * vign;

  return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4<f32>) -> @location(0) vec4<f32> {
  let time = u.time;
  let blend = saturate(u.blend_factor);

  let fp_cur = params_for_state(u.current_state, u.intensity);
  let fp_tgt = params_for_state(u.target_state, u.intensity);

  if (blend <= 0.001 || u.current_state == u.target_state) {
    return vec4<f32>(render(frag_coord.xy, u.resolution, time, fp_cur), 1.0);
  }
  if (blend >= 0.999) {
    return vec4<f32>(render(frag_coord.xy, u.resolution, time, fp_tgt), 1.0);
  }

  let col_a = render(frag_coord.xy, u.resolution, time, fp_cur);
  let col_b = render(frag_coord.xy, u.resolution, time, fp_tgt);
  return vec4<f32>(mix(col_a, col_b, blend), 1.0);
}

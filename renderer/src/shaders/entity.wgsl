struct Uniforms {
  time: f32,
  intensity: f32,
  entity_state: u32,
  _pad0: u32,
  resolution: vec2<f32>,
  _pad1: vec2<f32>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexOut {
  @builtin(position) position: vec4<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
  // Fullscreen triangle.
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(3.0, -1.0),
    vec2<f32>(-1.0, 3.0),
  );

  var out: VertexOut;
  out.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
  return out;
}

fn saturate(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = saturate(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn rotate2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}

fn warp(p: vec3<f32>, t: f32, wobble: f32) -> vec3<f32> {
  let w0 = vec3<f32>(
    sin(p.y * 2.1 + t * 1.2),
    sin(p.z * 2.3 + t * 1.1),
    sin(p.x * 2.0 + t * 0.9),
  );
  let w1 = vec3<f32>(
    sin((p.y + p.z) * 3.1 + t * 1.6),
    sin((p.z + p.x) * 3.2 + t * 1.3),
    sin((p.x + p.y) * 3.0 + t * 1.4),
  );
  return p + wobble * (0.22 * w0 + 0.12 * w1);
}

struct Params {
  speed: f32,
  deform: f32,
  smooth_k: f32,
  eye_radius: f32,
  eye_sep: f32,
  eye_height: f32,
  tilt: f32,
  droop: f32,
  pulse_rate: f32,
  pulse_amp: f32,
  base_radius: f32,
  base_col: vec3<f32>,
  accent_col: vec3<f32>,
  glow: f32,
  warn: f32,
};

fn lerp_f(a: f32, b: f32, t: f32) -> f32 {
  return a + (b - a) * t;
}

fn lerp_v3(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return a + (b - a) * t;
}

fn params_for(state: u32, intensity: f32) -> Params {
  let k = saturate(intensity);

  // Idle (baseline).
  let base_speed = 0.35;
  let base_deform = 0.18;
  let base_smooth_k = 0.38;
  let base_eye_radius = 0.11;
  let base_eye_sep = 0.26;
  let base_eye_height = 0.10;
  let base_tilt = 0.0;
  let base_droop = 0.0;
  let base_pulse_rate = 0.6;
  let base_pulse_amp = 0.10;
  let base_radius = 0.88;
  let base_col = vec3<f32>(0.10, 0.12, 0.20);
  let base_accent = vec3<f32>(0.42, 0.20, 0.78);
  let base_glow = 0.55;
  let base_warn = 0.0;

  var tgt_speed = base_speed;
  var tgt_deform = base_deform;
  var tgt_smooth_k = base_smooth_k;
  var tgt_eye_radius = base_eye_radius;
  var tgt_eye_sep = base_eye_sep;
  var tgt_eye_height = base_eye_height;
  var tgt_tilt = base_tilt;
  var tgt_droop = base_droop;
  var tgt_pulse_rate = base_pulse_rate;
  var tgt_pulse_amp = base_pulse_amp;
  var tgt_radius = base_radius;
  var tgt_col = base_col;
  var tgt_accent = base_accent;
  var tgt_glow = base_glow;
  var tgt_warn = base_warn;

  switch state {
    // 0 = idle
    case 0u: {
    }

    // 1 = curious
    case 1u: {
      tgt_speed = 0.85;
      tgt_deform = 0.22;
      tgt_smooth_k = 0.34;
      tgt_eye_radius = 0.15;
      tgt_eye_height = 0.14;
      tgt_tilt = 0.18;
      tgt_pulse_rate = 1.2;
      tgt_pulse_amp = 0.12;
      tgt_col = vec3<f32>(0.08, 0.14, 0.22);
      tgt_accent = vec3<f32>(0.20, 0.75, 0.90);
      tgt_glow = 0.70;
    }

    // 2 = focused
    case 2u: {
      tgt_speed = 0.65;
      tgt_deform = 0.20;
      tgt_smooth_k = 0.18;
      tgt_eye_radius = 0.10;
      tgt_eye_sep = 0.24;
      tgt_pulse_rate = 2.6;
      tgt_pulse_amp = 0.22;
      tgt_col = vec3<f32>(0.10, 0.10, 0.19);
      tgt_accent = vec3<f32>(0.85, 0.20, 0.88);
      tgt_glow = 0.80;
    }

    // 3 = amused
    case 3u: {
      tgt_speed = 1.35;
      tgt_deform = 0.30;
      tgt_smooth_k = 0.44;
      tgt_eye_radius = 0.13;
      tgt_tilt = -0.14;
      tgt_pulse_rate = 1.8;
      tgt_pulse_amp = 0.18;
      tgt_col = vec3<f32>(0.09, 0.13, 0.22);
      tgt_accent = vec3<f32>(0.32, 0.92, 0.70);
      tgt_glow = 0.95;
    }

    // 4 = alert
    case 4u: {
      tgt_speed = 1.75;
      tgt_deform = 0.42;
      tgt_smooth_k = 0.22;
      tgt_eye_radius = 0.14;
      tgt_eye_sep = 0.30;
      tgt_pulse_rate = 4.4;
      tgt_pulse_amp = 0.40;
      tgt_radius = 0.98;
      tgt_col = vec3<f32>(0.12, 0.07, 0.09);
      tgt_accent = vec3<f32>(1.00, 0.42, 0.10);
      tgt_glow = 1.05;
      tgt_warn = 1.0;
    }

    // 5 = sleepy
    case 5u: {
      tgt_speed = 0.18;
      tgt_deform = 0.10;
      tgt_smooth_k = 0.40;
      tgt_eye_radius = 0.07;
      tgt_eye_height = 0.03;
      tgt_droop = 0.55;
      tgt_pulse_rate = 0.35;
      tgt_pulse_amp = 0.06;
      tgt_col = vec3<f32>(0.07, 0.08, 0.16);
      tgt_accent = vec3<f32>(0.26, 0.18, 0.50);
      tgt_glow = 0.35;
    }

    default: {
    }
  }

  var p: Params;
  p.speed = lerp_f(base_speed, tgt_speed, k);
  p.deform = lerp_f(base_deform, tgt_deform, k);
  p.smooth_k = lerp_f(base_smooth_k, tgt_smooth_k, k);
  p.eye_radius = lerp_f(base_eye_radius, tgt_eye_radius, k);
  p.eye_sep = lerp_f(base_eye_sep, tgt_eye_sep, k);
  p.eye_height = lerp_f(base_eye_height, tgt_eye_height, k);
  p.tilt = lerp_f(base_tilt, tgt_tilt, k);
  p.droop = lerp_f(base_droop, tgt_droop, k);
  p.pulse_rate = lerp_f(base_pulse_rate, tgt_pulse_rate, k);
  p.pulse_amp = lerp_f(base_pulse_amp, tgt_pulse_amp, k);
  p.base_radius = lerp_f(base_radius, tgt_radius, k);
  p.base_col = lerp_v3(base_col, tgt_col, k);
  p.accent_col = lerp_v3(base_accent, tgt_accent, k);
  p.glow = lerp_f(base_glow, tgt_glow, k);
  p.warn = lerp_f(base_warn, tgt_warn, k);
  return p;
}

struct MapResult {
  d: f32,
  glow: f32,
};

fn sdf_blob(p_in: vec3<f32>, p: Params, t: f32) -> MapResult {
  var p0 = p_in;

  // Expression-driven tilt/lean.
  p0.xz = rotate2(p0.xz, 0.10 * sin(t * (0.6 + p.speed)));
  p0.xy = rotate2(p0.xy, p.tilt);
  p0.x = p0.x + 0.10 * sin(t * 0.9) * (p.tilt / 0.18);

  // Sleepy droop.
  if (p.droop > 0.001) {
    let sag = p.droop * 0.22 * smoothstep(-0.2, 0.7, p0.y);
    p0.y = p0.y - sag;
    p0.y = mix(p0.y, p0.y * 0.85, p.droop);
  }

  let breath = 0.04 * sin(t * (0.55 + 0.35 * p.speed));
  let pulse = 0.5 + 0.5 * sin(t * p.pulse_rate);
  let radius = p.base_radius + breath + p.pulse_amp * (pulse - 0.5);

  var q = warp(p0, t, p.deform);

  // Core blob via smooth unions.
  var d = length(q) - radius;
  d = smin(d, length(q - vec3<f32>(0.38, 0.18, 0.05)) - radius * 0.72, p.smooth_k);
  d = smin(d, length(q - vec3<f32>(-0.34, 0.08, -0.12)) - radius * 0.68, p.smooth_k);
  d = smin(d, length(q - vec3<f32>(0.08, -0.42, -0.02)) - radius * 0.70, p.smooth_k);
  d = smin(d, length(q - vec3<f32>(-0.06, 0.34, 0.20)) - radius * 0.62, p.smooth_k);

  // Sharpening (focused) and spikiness (alert) via displacement.
  let hi = sin(q.x * 8.0 + t * 2.1) * sin(q.y * 8.0 - t * 2.3) * sin(q.z * 8.0 + t * 1.9);
  let lo = sin(q.x * 3.0 + t * 0.9) * sin(q.y * 3.1 - t * 1.0) * sin(q.z * 2.8 + t * 0.7);
  let ridge = (abs(hi) - 0.25) * 0.10;
  let spikes = (abs(hi) - 0.15) * 0.14;
  d = d + 0.10 * p.deform * lo;
  d = d + ridge * (1.0 - p.smooth_k * 1.8);
  d = d - spikes * p.warn;

  // Eye cavities (subtle in idle, stronger in curious).
  let eye_z = 0.58;
  let eye_l = length(q - vec3<f32>(p.eye_sep, p.eye_height, eye_z)) - p.eye_radius;
  let eye_r = length(q - vec3<f32>(-p.eye_sep, p.eye_height, eye_z)) - p.eye_radius;
  let eye = min(eye_l, eye_r);
  d = max(d, -eye);

  // Glow concentrates around eyes and inner core.
  let eye_glow = exp(-abs(eye) * 18.0);
  let core_glow = exp(-abs(length(q) - radius * 0.75) * 8.0);

  var mr: MapResult;
  mr.d = d;
  mr.glow = eye_glow * 0.9 + core_glow * 0.25;
  return mr;
}

fn map_dist(p_in: vec3<f32>, p: Params, t: f32) -> f32 {
  return sdf_blob(p_in, p, t).d;
}

fn calc_normal(p_in: vec3<f32>, p: Params, t: f32) -> vec3<f32> {
  let e = 0.0025;
  let ex = vec3<f32>(e, 0.0, 0.0);
  let ey = vec3<f32>(0.0, e, 0.0);
  let ez = vec3<f32>(0.0, 0.0, e);
  let nx = map_dist(p_in + ex, p, t) - map_dist(p_in - ex, p, t);
  let ny = map_dist(p_in + ey, p, t) - map_dist(p_in - ey, p, t);
  let nz = map_dist(p_in + ez, p, t) - map_dist(p_in - ez, p, t);
  return normalize(vec3<f32>(nx, ny, nz));
}

fn soft_shadow(ro: vec3<f32>, rd: vec3<f32>, p: Params, t: f32) -> f32 {
  var res = 1.0;
  var dist = 0.02;
  for (var i: i32 = 0; i < 32; i = i + 1) {
    let h = map_dist(ro + rd * dist, p, t);
    if (h < 0.001) {
      return 0.0;
    }
    res = min(res, 10.0 * h / dist);
    dist = dist + clamp(h, 0.02, 0.18);
    if (dist > 5.0) {
      break;
    }
  }
  return saturate(res);
}

fn ambient_occlusion(pos: vec3<f32>, nor: vec3<f32>, p: Params, t: f32) -> f32 {
  var occ = 0.0;
  var sca = 1.0;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let h = 0.03 + 0.08 * f32(i);
    let d = map_dist(pos + nor * h, p, t);
    occ = occ + (h - d) * sca;
    sca = sca * 0.7;
  }
  return saturate(1.0 - occ);
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4<f32>) -> @location(0) vec4<f32> {
  let res = u.resolution;
  let px = frag_coord.xy;
  let uv = px / res;

  let t = u.time;
  let p = params_for(u.entity_state, u.intensity);

  // Background: deep blue/purple gradient with subtle pulse (tied to state).
  let v = uv.y;
  let bg_pulse = 0.06 * sin(t * (0.25 + 0.2 * p.speed) + uv.x * 2.0);
  var bg = vec3<f32>(0.03, 0.04, 0.08) + vec3<f32>(0.02, 0.02, 0.05) * (1.0 - v);
  bg = bg + vec3<f32>(0.05, 0.02, 0.08) * bg_pulse;
  bg = mix(bg, bg + vec3<f32>(0.10, 0.02, 0.01), p.warn * 0.35);

  // Normalized screen coordinates (preserve aspect).
  let p2 = (2.0 * px - res) / res.y;

  // Camera.
  var ro = vec3<f32>(0.0, 0.0, 3.0);
  var rd = normalize(vec3<f32>(p2.x, -p2.y, -1.8));
  ro.x = ro.x + 0.10 * sin(t * 0.15);
  ro.y = ro.y + 0.05 * sin(t * 0.12);

  // Raymarch.
  var dist = 0.0;
  var glow_acc = 0.0;
  var hit = false;
  var mr: MapResult;

  for (var i: i32 = 0; i < 72; i = i + 1) {
    let pos = ro + rd * dist;
    mr = sdf_blob(pos, p, t);
    glow_acc = glow_acc + 0.03 * p.glow * exp(-abs(mr.d) * 6.0);
    if (mr.d < 0.0015) {
      hit = true;
      break;
    }
    dist = dist + mr.d;
    if (dist > 7.0) {
      break;
    }
  }

  if (!hit) {
    // Subtle vignette.
    let d2 = length(p2);
    let vignette = 1.0 - 0.35 * saturate(d2 * d2);
    let out_bg = bg * vignette + vec3<f32>(0.06, 0.03, 0.09) * glow_acc * 0.35;
    return vec4<f32>(out_bg, 1.0);
  }

  let pos = ro + rd * dist;
  let nor = calc_normal(pos, p, t);

  // Lighting.
  let light_dir = normalize(vec3<f32>(-0.45, 0.75, 0.55));
  let diff = saturate(dot(nor, light_dir));
  let sh = soft_shadow(pos + nor * 0.02, light_dir, p, t);
  let ao = ambient_occlusion(pos, nor, p, t);

  let half_dir = normalize(light_dir - rd);
  let spec = pow(saturate(dot(nor, half_dir)), 44.0) * (0.10 + 0.20 * p.warn);
  let rim = pow(1.0 - saturate(dot(nor, -rd)), 2.2);

  let pulse = 0.5 + 0.5 * sin(t * p.pulse_rate);
  let albedo = p.base_col + p.accent_col * (0.10 + 0.35 * pulse);

  var col = albedo * (0.20 * ao + diff * sh * 0.95) + vec3<f32>(0.02, 0.03, 0.05) * ao;
  col = col + p.accent_col * (spec + 0.45 * rim) * (0.35 + 0.55 * p.glow);

  // Emissive glow (eyes/core + accumulated mist).
  let emissive = (mr.glow * 0.9 + glow_acc * 0.7 + rim * 0.22) * (0.55 + 0.65 * p.glow);
  col = col + p.accent_col * emissive;

  // Blend in background haze, keep dark theme.
  col = mix(bg, col, 0.88);

  // Gentle tonemapping.
  col = col / (col + vec3<f32>(1.0));
  return vec4<f32>(col, 1.0);
}

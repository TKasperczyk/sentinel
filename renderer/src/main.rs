mod gpu;
mod ipc;

use std::{
    ffi::c_void,
    io::Read,
    path::PathBuf,
    ptr::NonNull,
    time::{Duration, Instant},
};

use calloop::{
    generic::Generic, timer::TimeoutAction, EventLoop, Interest, LoopHandle, LoopSignal, Mode,
    PostAction, RegistrationToken,
};
use calloop_wayland_source::WaylandSource;
use gpu::{GpuRenderer, Uniforms};
use log::{debug, error, info, warn};
use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState},
    delegate_compositor, delegate_layer, delegate_output, delegate_registry,
    output::{OutputHandler, OutputState},
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    shell::{
        wlr_layer::{
            Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
            LayerSurfaceConfigure,
        },
        WaylandSurface,
    },
};
use wayland_client::{
    globals::registry_queue_init,
    protocol::{wl_output, wl_surface},
    Connection, Proxy, QueueHandle,
};

#[derive(Debug, Copy, Clone)]
struct SmoothValue {
    current: f32,
    from: f32,
    target: f32,
    started_at: Instant,
}

impl SmoothValue {
    fn new(value: f32, now: Instant) -> Self {
        Self {
            current: value,
            from: value,
            target: value,
            started_at: now,
        }
    }

    fn set_target(&mut self, target: f32, now: Instant) {
        if self.target.to_bits() == target.to_bits() {
            return;
        }
        self.from = self.current;
        self.target = target;
        self.started_at = now;
    }

    fn update(&mut self, now: Instant, duration: Duration) {
        if self.current.to_bits() == self.target.to_bits() {
            return;
        }

        let duration_s = duration.as_secs_f32();
        if duration_s <= 0.000_1 {
            self.current = self.target;
            return;
        }

        let elapsed_s = now.duration_since(self.started_at).as_secs_f32();
        let mut t = (elapsed_s / duration_s).clamp(0.0, 1.0);
        t = t * t * (3.0 - 2.0 * t);
        self.current = self.from + (self.target - self.from) * t;
        if t >= 1.0 {
            self.current = self.target;
        }
    }
}

#[derive(Debug, Copy, Clone)]
struct StateBlend {
    current_state: u32,
    target_state: u32,
    blend: SmoothValue,
}

impl StateBlend {
    fn new(state: u32, now: Instant) -> Self {
        Self {
            current_state: state.min(5),
            target_state: state.min(5),
            blend: SmoothValue::new(0.0, now),
        }
    }

    fn set_target(&mut self, target_state: u32, now: Instant) {
        let target_state = target_state.min(5);
        if self.target_state == target_state {
            return;
        }

        if self.current_state != self.target_state && self.blend.current >= 0.5 {
            self.current_state = self.target_state;
        }

        self.target_state = target_state;
        if self.current_state == self.target_state {
            self.blend = SmoothValue::new(0.0, now);
            return;
        }

        self.blend = SmoothValue::new(0.0, now);
        self.blend.set_target(1.0, now);
    }

    fn update(&mut self, now: Instant, duration: Duration) {
        if self.current_state == self.target_state {
            self.blend = SmoothValue::new(0.0, now);
            return;
        }

        self.blend.update(now, duration);
        if self.blend.current >= 1.0 {
            self.current_state = self.target_state;
            self.blend = SmoothValue::new(0.0, now);
        }
    }

    fn blend_factor(&self) -> f32 {
        self.blend.current
    }
}

#[derive(Debug, Copy, Clone)]
struct MotionParams {
    base_scale: f32,
    scale_pulse: f32,
    pulse_speed: f32,
    drift_amp: [f32; 2],
    drift_speed: f32,
    bounce_mix: f32,
    bounce_speed: f32,
    base_offset: [f32; 2],
    smooth_time: f32,
}

impl MotionParams {
    fn for_state(state: u32, intensity: f32) -> Self {
        let intensity = intensity.clamp(0.0, 1.0);
        let energy = 0.35 + 0.65 * intensity;

        let mut params = match state {
            1 => Self {
                base_scale: 1.25,
                scale_pulse: 0.1,
                pulse_speed: 1.1,
                drift_amp: [0.16, 0.12],
                drift_speed: 0.45,
                bounce_mix: 0.6,
                bounce_speed: 0.25,
                base_offset: [0.0, 0.05],
                smooth_time: 0.7,
            },
            2 => Self {
                base_scale: 0.7,
                scale_pulse: 0.02,
                pulse_speed: 0.5,
                drift_amp: [0.02, 0.015],
                drift_speed: 0.12,
                bounce_mix: 0.0,
                bounce_speed: 0.1,
                base_offset: [0.0, 0.0],
                smooth_time: 0.8,
            },
            3 => Self {
                base_scale: 1.05,
                scale_pulse: 0.16,
                pulse_speed: 1.6,
                drift_amp: [0.12, 0.1],
                drift_speed: 0.8,
                bounce_mix: 0.4,
                bounce_speed: 0.9,
                base_offset: [0.02, 0.0],
                smooth_time: 0.45,
            },
            4 => Self {
                base_scale: 1.45,
                scale_pulse: 0.22,
                pulse_speed: 2.2,
                drift_amp: [0.2, 0.18],
                drift_speed: 1.2,
                bounce_mix: 0.8,
                bounce_speed: 1.1,
                base_offset: [0.0, 0.1],
                smooth_time: 0.35,
            },
            5 => Self {
                base_scale: 0.6,
                scale_pulse: 0.02,
                pulse_speed: 0.35,
                drift_amp: [0.03, 0.025],
                drift_speed: 0.08,
                bounce_mix: 0.0,
                bounce_speed: 0.1,
                base_offset: [0.0, -0.22],
                smooth_time: 1.4,
            },
            _ => Self {
                base_scale: 1.0,
                scale_pulse: 0.04,
                pulse_speed: 0.6,
                drift_amp: [0.06, 0.04],
                drift_speed: 0.2,
                bounce_mix: 0.0,
                bounce_speed: 0.15,
                base_offset: [0.0, 0.0],
                smooth_time: 1.1,
            },
        };

        params.drift_amp[0] *= energy;
        params.drift_amp[1] *= energy;
        params.scale_pulse *= 0.3 + 0.7 * intensity;
        params.drift_speed *= 0.4 + 0.6 * intensity;
        params.bounce_speed *= 0.4 + 0.6 * intensity;
        params.bounce_mix *= 0.2 + 0.8 * intensity;
        params.pulse_speed *= 0.5 + 0.5 * intensity;

        params
    }

    fn lerp(self, other: Self, t: f32) -> Self {
        Self {
            base_scale: lerp(self.base_scale, other.base_scale, t),
            scale_pulse: lerp(self.scale_pulse, other.scale_pulse, t),
            pulse_speed: lerp(self.pulse_speed, other.pulse_speed, t),
            drift_amp: lerp2(self.drift_amp, other.drift_amp, t),
            drift_speed: lerp(self.drift_speed, other.drift_speed, t),
            bounce_mix: lerp(self.bounce_mix, other.bounce_mix, t),
            bounce_speed: lerp(self.bounce_speed, other.bounce_speed, t),
            base_offset: lerp2(self.base_offset, other.base_offset, t),
            smooth_time: lerp(self.smooth_time, other.smooth_time, t),
        }
    }
}

#[derive(Debug, Copy, Clone)]
struct MotionState {
    pos_x: SmoothValue,
    pos_y: SmoothValue,
    scale: SmoothValue,
}

impl MotionState {
    fn new(now: Instant) -> Self {
        Self {
            pos_x: SmoothValue::new(0.5, now),
            pos_y: SmoothValue::new(0.5, now),
            scale: SmoothValue::new(1.0, now),
        }
    }

    fn update(&mut self, now: Instant, params: MotionParams, t: f32) -> ([f32; 2], f32) {
        let smooth_time = params.smooth_time.max(0.05);
        let smooth = Duration::from_secs_f32(smooth_time);
        self.pos_x.update(now, smooth);
        self.pos_y.update(now, smooth);
        self.scale.update(now, smooth);

        let target_pos = target_position(params, t);
        let target_scale = target_scale(params, t);

        self.pos_x.set_target(target_pos[0], now);
        self.pos_y.set_target(target_pos[1], now);
        self.scale.set_target(target_scale, now);

        ([self.pos_x.current, self.pos_y.current], self.scale.current)
    }
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn lerp2(a: [f32; 2], b: [f32; 2], t: f32) -> [f32; 2] {
    [lerp(a[0], b[0], t), lerp(a[1], b[1], t)]
}

fn tri_wave(t: f32) -> f32 {
    let f = t.fract();
    if f < 0.5 {
        f * 2.0
    } else {
        (1.0 - f) * 2.0
    }
}

fn target_position(params: MotionParams, t: f32) -> [f32; 2] {
    let base = [
        (0.5 + params.base_offset[0]).clamp(0.05, 0.95),
        (0.5 + params.base_offset[1]).clamp(0.05, 0.95),
    ];
    let drift = [
        (t * params.drift_speed).sin() * params.drift_amp[0],
        (t * params.drift_speed * 0.83 + 1.7).cos() * params.drift_amp[1],
    ];
    let bounce = [
        lerp(0.08, 0.92, tri_wave(t * params.bounce_speed + 0.13)),
        lerp(0.08, 0.92, tri_wave(t * params.bounce_speed * 0.93 + 0.57)),
    ];

    let mut pos = [base[0] + drift[0], base[1] + drift[1]];
    pos[0] = lerp(pos[0], bounce[0], params.bounce_mix);
    pos[1] = lerp(pos[1], bounce[1], params.bounce_mix);
    pos[0] = pos[0].clamp(0.05, 0.95);
    pos[1] = pos[1].clamp(0.05, 0.95);
    pos
}

fn target_scale(params: MotionParams, t: f32) -> f32 {
    let pulse = (t * params.pulse_speed).sin();
    let wobble = (t * (params.pulse_speed * 0.4 + 0.7)).sin();
    (params.base_scale + params.scale_pulse * pulse + params.scale_pulse * 0.35 * wobble)
        .clamp(0.35, 2.5)
}

fn attach_ipc_client<'l>(
    handle: &LoopHandle<'l, AppState>,
    state: &mut AppState,
    stream: std::os::unix::net::UnixStream,
    path: PathBuf,
) {
    let Ok(token) = handle.insert_source(
        Generic::new(stream, Interest::READ, Mode::Level),
        move |readiness, stream, state| {
            if readiness.error {
                warn!("IPC socket reported error; disconnecting");
                state.ipc_token = None;
                state.ipc_path = None;
                state.ipc_buffer.clear();
                return Ok(PostAction::Remove);
            }

            let mut buffer = std::mem::take(&mut state.ipc_buffer);
            let mut disconnected = false;
            let mut tmp = [0u8; 4096];

            loop {
                match (&**stream).read(&mut tmp) {
                    Ok(0) => {
                        disconnected = true;
                        break;
                    }
                    Ok(n) => buffer.extend_from_slice(&tmp[..n]),
                    Err(err) if err.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(err) => {
                        warn!("IPC read error: {err}");
                        disconnected = true;
                        break;
                    }
                }
            }

            let messages = ipc::drain_messages(&mut buffer);
            state.ipc_buffer = buffer;

            let now = Instant::now();
            let mut changed = false;
            for msg in messages {
                match msg {
                    ipc::IpcMessage::State {
                        state: entity_state,
                        intensity,
                    } => {
                        let new_state = entity_state.as_u32();
                        let new_intensity = intensity.clamp(0.0, 1.0);
                        if state.entity_state.target_state != new_state {
                            state.entity_state.set_target(new_state, now);
                            changed = true;
                        }
                        if state.intensity.target.to_bits() != new_intensity.to_bits() {
                            state.intensity.set_target(new_intensity, now);
                            changed = true;
                        }
                    }
                }
            }

            if changed && state.configured {
                state.draw();
            }

            if disconnected {
                if let Some(path) = state.ipc_path.as_ref() {
                    warn!("IPC disconnected from {}", path.display());
                } else {
                    warn!("IPC disconnected");
                }
                state.ipc_token = None;
                state.ipc_path = None;
                state.ipc_buffer.clear();
                return Ok(PostAction::Remove);
            }

            Ok(PostAction::Continue)
        },
    ) else {
        warn!("Failed to register IPC socket source");
        return;
    };

    state.ipc_token = Some(token);
    state.ipc_path = Some(path.clone());
    state.ipc_buffer.clear();
    info!("IPC connected: {}", path.display());
}

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    info!("Sentinel Renderer starting");

    let conn = Connection::connect_to_env().expect("Failed to connect to Wayland");
    let (globals, event_queue) = registry_queue_init(&conn).expect("Failed to init registry");
    let qh = event_queue.handle();

    let compositor = CompositorState::bind(&globals, &qh).expect("wl_compositor not available");
    let layer_shell = LayerShell::bind(&globals, &qh).expect("layer_shell not available");
    let surface = compositor.create_surface(&qh);

    let layer_surface =
        layer_shell.create_layer_surface(&qh, surface, Layer::Background, Some("sentinel"), None);

    layer_surface.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
    layer_surface.set_exclusive_zone(-1);
    layer_surface.set_keyboard_interactivity(KeyboardInteractivity::None);
    layer_surface.commit();

    let display_ptr = NonNull::new(conn.display().id().as_ptr().cast::<c_void>())
        .expect("Wayland display pointer was null");
    let surface_ptr = NonNull::new(layer_surface.wl_surface().id().as_ptr().cast::<c_void>())
        .expect("Wayland surface pointer was null");

    let entity_state = std::env::var("SENTINEL_ENTITY_STATE")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(0)
        .min(5);
    let intensity = std::env::var("SENTINEL_ENTITY_INTENSITY")
        .ok()
        .and_then(|v| v.parse::<f32>().ok())
        .unwrap_or(1.0)
        .clamp(0.0, 1.0);
    let cycle_states = std::env::var("SENTINEL_ENTITY_CYCLE")
        .ok()
        .is_some_and(|v| v == "1" || v.eq_ignore_ascii_case("true"));

    let transition_duration = std::env::var("SENTINEL_TRANSITION_DURATION")
        .ok()
        .and_then(|v| v.parse::<f32>().ok())
        .filter(|v| v.is_finite() && *v > 0.0)
        .map(Duration::from_secs_f32)
        .unwrap_or(Duration::from_millis(750));

    let ipc_candidates = ipc::socket_candidates();

    let gpu = GpuRenderer::new(display_ptr, surface_ptr, 256, 256)
        .expect("Failed to initialize wgpu renderer");

    let start_time = Instant::now();
    let mut state = AppState {
        registry_state: RegistryState::new(&globals),
        output_state: OutputState::new(&globals, &qh),
        gpu: Some(gpu),
        layer_surface: Some(layer_surface),
        width: 256,
        height: 256,
        configured: false,
        start_time,
        loop_signal: None,
        transition_duration,
        entity_state: StateBlend::new(entity_state, start_time),
        intensity: SmoothValue::new(intensity, start_time),
        motion: MotionState::new(start_time),
        cycle_states,
        ipc_token: None,
        ipc_buffer: Vec::new(),
        ipc_path: None,
    };

    let mut event_loop: EventLoop<AppState> =
        EventLoop::try_new().expect("Failed to create event loop");

    state.loop_signal = Some(event_loop.get_signal());
    let handle = event_loop.handle();

    // Set up a timer for animation (60fps)
    let timer = calloop::timer::Timer::from_duration(Duration::from_millis(16));
    handle
        .insert_source(timer, |_, _, state| {
            if state.configured {
                state.draw();
            }
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .expect("Failed to insert timer");

    // IPC reconnect loop (1Hz).
    let ipc_handle = handle.clone();
    let ipc_candidates_clone = ipc_candidates.clone();
    let reconnect_timer = calloop::timer::Timer::from_duration(Duration::from_secs(1));
    handle
        .insert_source(reconnect_timer, move |_, _, state| {
            if state.ipc_token.is_none() {
                if let Some((stream, path)) = ipc::try_connect(&ipc_candidates_clone) {
                    attach_ipc_client(&ipc_handle, state, stream, path);
                } else {
                    debug!("IPC not available yet; will retry");
                }
            }
            TimeoutAction::ToDuration(Duration::from_secs(1))
        })
        .expect("Failed to insert IPC reconnect timer");

    // Attempt an eager connect at startup (avoid waiting for first reconnect tick).
    if let Some((stream, path)) = ipc::try_connect(&ipc_candidates) {
        attach_ipc_client(&handle, &mut state, stream, path);
    }

    // Insert the Wayland event source
    WaylandSource::new(conn, event_queue)
        .insert(handle.clone())
        .expect("Failed to insert Wayland source");

    info!("Starting event loop");
    event_loop
        .run(None, &mut state, |_| {})
        .expect("Event loop failed");

    info!("Sentinel Renderer stopped");
}

struct AppState {
    registry_state: RegistryState,
    output_state: OutputState,
    // Drop order matters: `wgpu::Surface` inside `GpuRenderer` must be dropped before the
    // underlying Wayland `wl_surface` owned by `LayerSurface`. Rust drops struct fields in
    // declaration order, so keep `gpu` before `layer_surface`.
    gpu: Option<GpuRenderer>,
    layer_surface: Option<LayerSurface>,
    width: u32,
    height: u32,
    configured: bool,
    start_time: Instant,
    loop_signal: Option<LoopSignal>,
    transition_duration: Duration,
    entity_state: StateBlend,
    intensity: SmoothValue,
    motion: MotionState,
    cycle_states: bool,
    ipc_token: Option<RegistrationToken>,
    ipc_buffer: Vec<u8>,
    ipc_path: Option<PathBuf>,
}

impl AppState {
    fn draw(&mut self) {
        if self.layer_surface.is_none() {
            return;
        }

        let Some(gpu) = self.gpu.as_mut() else {
            return;
        };

        let now = Instant::now();
        let t = self.start_time.elapsed().as_secs_f32();

        if self.cycle_states {
            let cycle_state = ((t / 8.0).floor() as u32) % 6;
            self.entity_state.set_target(cycle_state, now);
        }

        self.entity_state.update(now, self.transition_duration);
        self.intensity.update(now, self.transition_duration);

        let blend = self.entity_state.blend_factor();
        let params_cur = MotionParams::for_state(self.entity_state.current_state, self.intensity.current);
        let params_tgt = MotionParams::for_state(self.entity_state.target_state, self.intensity.current);
        let motion_params = params_cur.lerp(params_tgt, blend);
        let (position, scale) = self.motion.update(now, motion_params, t);

        let uniforms = Uniforms::new(
            t,
            self.entity_state.current_state,
            self.entity_state.target_state,
            blend,
            self.intensity.current,
            scale,
            position,
            self.width,
            self.height,
        );
        if let Err(e) = gpu.render(&uniforms) {
            error!("wgpu render error: {e:?}");
            if let Some(signal) = &self.loop_signal {
                signal.stop();
            }
        }
    }
}

impl CompositorHandler for AppState {
    fn scale_factor_changed(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _surface: &wl_surface::WlSurface,
        _new_factor: i32,
    ) {
    }

    fn transform_changed(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _surface: &wl_surface::WlSurface,
        _new_transform: wl_output::Transform,
    ) {
    }

    fn frame(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _surface: &wl_surface::WlSurface,
        _time: u32,
    ) {
    }

    fn surface_enter(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _surface: &wl_surface::WlSurface,
        _output: &wl_output::WlOutput,
    ) {
    }

    fn surface_leave(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _surface: &wl_surface::WlSurface,
        _output: &wl_output::WlOutput,
    ) {
    }
}

impl OutputHandler for AppState {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.output_state
    }

    fn new_output(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _output: wl_output::WlOutput,
    ) {
    }

    fn update_output(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _output: wl_output::WlOutput,
    ) {
    }

    fn output_destroyed(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _output: wl_output::WlOutput,
    ) {
    }
}

impl LayerShellHandler for AppState {
    fn closed(&mut self, _conn: &Connection, _qh: &QueueHandle<Self>, _layer: &LayerSurface) {
        self.gpu = None;
        self.layer_surface = None;
        if let Some(signal) = &self.loop_signal {
            signal.stop();
        }
    }

    fn configure(
        &mut self,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
        _layer: &LayerSurface,
        configure: LayerSurfaceConfigure,
        _serial: u32,
    ) {
        if configure.new_size.0 > 0 {
            self.width = configure.new_size.0;
        }
        if configure.new_size.1 > 0 {
            self.height = configure.new_size.1;
        }

        info!("Display resolution: {}x{}", self.width, self.height);
        self.configured = true;
        if let Some(gpu) = self.gpu.as_mut() {
            gpu.resize(self.width, self.height);
        }

        // Draw initial frame
        self.draw();
    }
}

impl ProvidesRegistryState for AppState {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry_state
    }
    registry_handlers![OutputState];
}

delegate_compositor!(AppState);
delegate_output!(AppState);
delegate_layer!(AppState);
delegate_registry!(AppState);

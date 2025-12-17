mod gpu;

use std::{ffi::c_void, ptr::NonNull, time::Instant};

use calloop::{timer::TimeoutAction, EventLoop, LoopSignal};
use calloop_wayland_source::WaylandSource;
use gpu::{GpuRenderer, Uniforms};
use log::{error, info};
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

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    info!("Sentinel Renderer starting");

    let conn = Connection::connect_to_env().expect("Failed to connect to Wayland");
    let (globals, event_queue) = registry_queue_init(&conn).expect("Failed to init registry");
    let qh = event_queue.handle();

    let compositor = CompositorState::bind(&globals, &qh).expect("wl_compositor not available");
    let layer_shell = LayerShell::bind(&globals, &qh).expect("layer_shell not available");
    let surface = compositor.create_surface(&qh);

    let layer_surface = layer_shell.create_layer_surface(
        &qh,
        surface,
        Layer::Background,
        Some("sentinel"),
        None,
    );

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

    let gpu = GpuRenderer::new(display_ptr, surface_ptr, 256, 256)
        .expect("Failed to initialize wgpu renderer");

    let mut state = AppState {
        registry_state: RegistryState::new(&globals),
        output_state: OutputState::new(&globals, &qh),
        gpu: Some(gpu),
        layer_surface: Some(layer_surface),
        width: 256,
        height: 256,
        configured: false,
        start_time: Instant::now(),
        loop_signal: None,
        entity_state,
        intensity,
        cycle_states,
    };

    let mut event_loop: EventLoop<AppState> =
        EventLoop::try_new().expect("Failed to create event loop");

    state.loop_signal = Some(event_loop.get_signal());

    // Set up a timer for animation (60fps)
    let timer = calloop::timer::Timer::from_duration(std::time::Duration::from_millis(16));
    event_loop
        .handle()
        .insert_source(timer, |_, _, state| {
            if state.configured {
                state.draw();
            }
            TimeoutAction::ToDuration(std::time::Duration::from_millis(16))
        })
        .expect("Failed to insert timer");

    // Insert the Wayland event source
    WaylandSource::new(conn, event_queue)
        .insert(event_loop.handle())
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
    entity_state: u32,
    intensity: f32,
    cycle_states: bool,
}

impl AppState {
    fn draw(&mut self) {
        if self.layer_surface.is_none() {
            return;
        }

        let Some(gpu) = self.gpu.as_mut() else {
            return;
        };

        let t = self.start_time.elapsed().as_secs_f32();
        let entity_state = if self.cycle_states {
            ((t / 8.0).floor() as u32) % 6
        } else {
            self.entity_state
        };

        let uniforms = Uniforms::new(t, entity_state, self.intensity, self.width, self.height);
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

        info!("Layer surface configured: {}x{}", self.width, self.height);
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

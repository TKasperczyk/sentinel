use std::{ffi::c_void, num::NonZeroU64, ptr::NonNull};

use log::info;
use raw_window_handle::{
    RawDisplayHandle, RawWindowHandle, WaylandDisplayHandle, WaylandWindowHandle,
};
use wgpu::util::DeviceExt;

const STATE_TEXTURE_WIDTH: u32 = 256;
const STATE_TEXTURE_HEIGHT: u32 = 128;
const STATE_TEXTURE_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba32Float;
const RENDER_TEXTURE_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba32Float;

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Uniforms {
    pub time: f32,
    pub intensity: f32,
    pub blend_factor: f32,
    pub scale: f32,
    pub current_state: u32,
    pub target_state: u32,
    pub frame_count: u32,
    _pad0: u32,
    pub resolution: [f32; 2],
    pub position: [f32; 2],
    pub damping: f32,
    pub noise_strength: f32,
    pub attraction: f32,
    pub speed: f32,
    pub trail_fade: f32,
    pub glow_intensity: f32,
    pub color_shift: f32,
    _pad1: f32,
}

impl Uniforms {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        time: f32,
        current_state: u32,
        target_state: u32,
        blend_factor: f32,
        intensity: f32,
        scale: f32,
        position: [f32; 2],
        width: u32,
        height: u32,
        frame_count: u32,
        damping: f32,
        noise_strength: f32,
        attraction: f32,
        speed: f32,
        trail_fade: f32,
        glow_intensity: f32,
        color_shift: f32,
    ) -> Self {
        let scale = scale.clamp(0.35, 2.5);
        let position = [position[0].clamp(0.0, 1.0), position[1].clamp(0.0, 1.0)];
        Self {
            time,
            intensity: intensity.clamp(0.0, 1.0),
            blend_factor: blend_factor.clamp(0.0, 1.0),
            scale,
            current_state: current_state.min(5),
            target_state: target_state.min(5),
            frame_count,
            _pad0: 0,
            resolution: [width as f32, height as f32],
            position,
            damping: damping.clamp(0.95, 0.99999),
            noise_strength: noise_strength.clamp(0.0, 25.0),
            attraction: attraction.clamp(0.0, 2.0),
            speed: speed.clamp(0.0, 4.0),
            trail_fade: trail_fade.clamp(0.9, 0.99999),
            glow_intensity: glow_intensity.clamp(0.0, 4.0),
            color_shift: color_shift.clamp(-1.0, 1.0),
            _pad1: 0.0,
        }
    }
}

#[derive(Debug)]
struct PingPongTexture {
    texture: wgpu::Texture,
    view: wgpu::TextureView,
}

impl PingPongTexture {
    fn new(
        device: &wgpu::Device,
        size: wgpu::Extent3d,
        format: wgpu::TextureFormat,
        label: &str,
    ) -> Self {
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some(label),
            size,
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        Self { texture, view }
    }
}

fn create_simulation_bind_group(
    device: &wgpu::Device,
    layout: &wgpu::BindGroupLayout,
    prev_state: &wgpu::TextureView,
    label: &str,
) -> wgpu::BindGroup {
    device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some(label),
        layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: wgpu::BindingResource::TextureView(prev_state),
        }],
    })
}

fn create_render_bind_group(
    device: &wgpu::Device,
    layout: &wgpu::BindGroupLayout,
    state: &wgpu::TextureView,
    prev_render: &wgpu::TextureView,
    label: &str,
) -> wgpu::BindGroup {
    device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some(label),
        layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(state),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::TextureView(prev_render),
            },
        ],
    })
}

fn create_present_bind_group(
    device: &wgpu::Device,
    layout: &wgpu::BindGroupLayout,
    render: &wgpu::TextureView,
    label: &str,
) -> wgpu::BindGroup {
    device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some(label),
        layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: wgpu::BindingResource::TextureView(render),
        }],
    })
}

fn create_render_targets(
    device: &wgpu::Device,
    render_layout: &wgpu::BindGroupLayout,
    present_layout: &wgpu::BindGroupLayout,
    state_textures: &[PingPongTexture; 2],
    size: wgpu::Extent3d,
) -> (
    [PingPongTexture; 2],
    [wgpu::BindGroup; 2],
    [wgpu::BindGroup; 2],
) {
    let render_textures = std::array::from_fn(|index| {
        PingPongTexture::new(
            device,
            size,
            RENDER_TEXTURE_FORMAT,
            &format!("Sentinel Render Texture {index}"),
        )
    });

    let render_bind_groups = [
        create_render_bind_group(
            device,
            render_layout,
            &state_textures[0].view,
            &render_textures[1].view,
            "Sentinel Render Bind Group A",
        ),
        create_render_bind_group(
            device,
            render_layout,
            &state_textures[1].view,
            &render_textures[0].view,
            "Sentinel Render Bind Group B",
        ),
    ];

    let present_bind_groups = [
        create_present_bind_group(
            device,
            present_layout,
            &render_textures[0].view,
            "Sentinel Present Bind Group A",
        ),
        create_present_bind_group(
            device,
            present_layout,
            &render_textures[1].view,
            "Sentinel Present Bind Group B",
        ),
    ];

    (render_textures, render_bind_groups, present_bind_groups)
}

pub struct GpuRenderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    simulation_pipeline: wgpu::RenderPipeline,
    render_pipeline: wgpu::RenderPipeline,
    present_pipeline: wgpu::RenderPipeline,
    uniform_buffer: wgpu::Buffer,
    uniform_bind_group: wgpu::BindGroup,
    simulation_texture_bind_group_layout: wgpu::BindGroupLayout,
    render_texture_bind_group_layout: wgpu::BindGroupLayout,
    present_texture_bind_group_layout: wgpu::BindGroupLayout,
    state_textures: [PingPongTexture; 2],
    render_textures: [PingPongTexture; 2],
    simulation_bind_groups: [wgpu::BindGroup; 2],
    render_bind_groups: [wgpu::BindGroup; 2],
    present_bind_groups: [wgpu::BindGroup; 2],
    frame_index: u64,
}

impl GpuRenderer {
    pub fn new(
        display: NonNull<c_void>,
        surface: NonNull<c_void>,
        width: u32,
        height: u32,
    ) -> anyhow::Result<Self> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::VULKAN,
            ..Default::default()
        });

        let raw_display_handle = RawDisplayHandle::Wayland(WaylandDisplayHandle::new(display));
        let raw_window_handle = RawWindowHandle::Wayland(WaylandWindowHandle::new(surface));

        // SAFETY:
        // - The Wayland display + surface handles are valid objects coming from the Wayland connection.
        // - The underlying wl_display and wl_surface outlive the renderer and its wgpu::Surface.
        let surface: wgpu::Surface<'static> = unsafe {
            instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
                raw_display_handle,
                raw_window_handle,
            })?
        };

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .ok_or_else(|| anyhow::anyhow!("No suitable GPU adapter found"))?;

        let adapter_info = adapter.get_info();
        info!(
            "GPU adapter: {} (vendor={:#06x} device={:#06x} type={:?} backend={:?})",
            adapter_info.name,
            adapter_info.vendor,
            adapter_info.device,
            adapter_info.device_type,
            adapter_info.backend
        );

        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: None,
                required_features: wgpu::Features::empty(),
                required_limits: wgpu::Limits::default(),
            },
            None,
        ))?;

        let caps = surface.get_capabilities(&adapter);
        let format = caps
            .formats
            .iter()
            .copied()
            .find(wgpu::TextureFormat::is_srgb)
            .unwrap_or(caps.formats[0]);
        let alpha_mode = caps
            .alpha_modes
            .iter()
            .copied()
            .find(|m| *m == wgpu::CompositeAlphaMode::Opaque)
            .unwrap_or(caps.alpha_modes[0]);

        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: width.max(1),
            height: height.max(1),
            present_mode: wgpu::PresentMode::Fifo,
            alpha_mode,
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &config);
        info!(
            "Surface configured: {}x{} format={:?} alpha_mode={:?}",
            config.width, config.height, format, alpha_mode
        );

        let uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Sentinel Uniform Buffer"),
            contents: bytemuck::bytes_of(&Uniforms::new(
                0.0,
                0,
                0,
                0.0,
                0.0,
                1.0,
                [0.5, 0.5],
                config.width,
                config.height,
                0,
                0.998,
                5.0,
                0.5,
                1.0,
                0.995,
                1.0,
                0.0,
            )),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let uniform_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Sentinel Uniform Bind Group Layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: Some(
                            NonZeroU64::new(std::mem::size_of::<Uniforms>() as u64).unwrap(),
                        ),
                    },
                    count: None,
                }],
            });

        let uniform_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sentinel Uniform Bind Group"),
            layout: &uniform_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buffer.as_entire_binding(),
            }],
        });

        let simulation_texture_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Sentinel Simulation Texture Bind Group Layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                }],
            });

        let render_texture_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Sentinel Render Texture Bind Group Layout"),
                entries: &[
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: false },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: false },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                ],
            });

        let present_texture_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Sentinel Present Texture Bind Group Layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                }],
            });

        let simulation_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Sentinel Simulation Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/simulation.wgsl").into()),
        });
        let render_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Sentinel Render Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/render.wgsl").into()),
        });
        let present_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Sentinel Present Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/entity.wgsl").into()),
        });

        let simulation_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Sentinel Simulation Pipeline Layout"),
                bind_group_layouts: &[&uniform_bind_group_layout, &simulation_texture_bind_group_layout],
                push_constant_ranges: &[],
            });

        let render_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Sentinel Render Pipeline Layout"),
            bind_group_layouts: &[&uniform_bind_group_layout, &render_texture_bind_group_layout],
            push_constant_ranges: &[],
        });

        let present_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Sentinel Present Pipeline Layout"),
                bind_group_layouts: &[&present_texture_bind_group_layout],
                push_constant_ranges: &[],
            });

        let simulation_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Sentinel Simulation Pipeline"),
            layout: Some(&simulation_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &simulation_shader,
                entry_point: "vs_main",
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &simulation_shader,
                entry_point: "fs_main",
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: STATE_TEXTURE_FORMAT,
                    blend: None, // Rgba32Float doesn't support blending
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
        });

        let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Sentinel Render Pipeline"),
            layout: Some(&render_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &render_shader,
                entry_point: "vs_main",
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &render_shader,
                entry_point: "fs_main",
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: RENDER_TEXTURE_FORMAT,
                    blend: None, // Rgba32Float doesn't support blending
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
        });

        let present_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Sentinel Present Pipeline"),
            layout: Some(&present_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &present_shader,
                entry_point: "vs_main",
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &present_shader,
                entry_point: "fs_main",
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format,
                    blend: Some(wgpu::BlendState::REPLACE),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
        });

        let state_size = wgpu::Extent3d {
            width: STATE_TEXTURE_WIDTH,
            height: STATE_TEXTURE_HEIGHT,
            depth_or_array_layers: 1,
        };

        let state_textures = std::array::from_fn(|index| {
            PingPongTexture::new(
                &device,
                state_size,
                STATE_TEXTURE_FORMAT,
                &format!("Sentinel State Texture {index}"),
            )
        });

        let simulation_bind_groups = [
            create_simulation_bind_group(
                &device,
                &simulation_texture_bind_group_layout,
                &state_textures[1].view,
                "Sentinel Simulation Bind Group A",
            ),
            create_simulation_bind_group(
                &device,
                &simulation_texture_bind_group_layout,
                &state_textures[0].view,
                "Sentinel Simulation Bind Group B",
            ),
        ];

        let render_size = wgpu::Extent3d {
            width: config.width,
            height: config.height,
            depth_or_array_layers: 1,
        };

        let (render_textures, render_bind_groups, present_bind_groups) = create_render_targets(
            &device,
            &render_texture_bind_group_layout,
            &present_texture_bind_group_layout,
            &state_textures,
            render_size,
        );

        Ok(Self {
            surface,
            device,
            queue,
            config,
            simulation_pipeline,
            render_pipeline,
            present_pipeline,
            uniform_buffer,
            uniform_bind_group,
            simulation_texture_bind_group_layout,
            render_texture_bind_group_layout,
            present_texture_bind_group_layout,
            state_textures,
            render_textures,
            simulation_bind_groups,
            render_bind_groups,
            present_bind_groups,
            frame_index: 0,
        })
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        if self.config.width == width && self.config.height == height {
            return;
        }

        self.config.width = width;
        self.config.height = height;
        self.surface.configure(&self.device, &self.config);

        let render_size = wgpu::Extent3d {
            width: self.config.width,
            height: self.config.height,
            depth_or_array_layers: 1,
        };

        let (render_textures, render_bind_groups, present_bind_groups) = create_render_targets(
            &self.device,
            &self.render_texture_bind_group_layout,
            &self.present_texture_bind_group_layout,
            &self.state_textures,
            render_size,
        );

        self.render_textures = render_textures;
        self.render_bind_groups = render_bind_groups;
        self.present_bind_groups = present_bind_groups;
    }

    pub fn render(&mut self, uniforms: &Uniforms) -> anyhow::Result<()> {
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(uniforms));

        let frame = match self.surface.get_current_texture() {
            Ok(frame) => frame,
            Err(wgpu::SurfaceError::Outdated | wgpu::SurfaceError::Lost) => {
                self.surface.configure(&self.device, &self.config);
                return Ok(());
            }
            Err(wgpu::SurfaceError::Timeout) => return Ok(()),
            Err(wgpu::SurfaceError::OutOfMemory) => {
                return Err(anyhow::anyhow!("GPU out of memory"));
            }
        };

        let view = frame
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        let write_index = (self.frame_index % 2) as usize;
        let state_view = &self.state_textures[write_index].view;
        let render_view = &self.render_textures[write_index].view;

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Sentinel Render Encoder"),
            });

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Sentinel Simulation Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: state_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.simulation_pipeline);
            pass.set_bind_group(0, &self.uniform_bind_group, &[]);
            pass.set_bind_group(1, &self.simulation_bind_groups[write_index], &[]);
            pass.draw(0..3, 0..1);
        }

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Sentinel Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: render_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.render_pipeline);
            pass.set_bind_group(0, &self.uniform_bind_group, &[]);
            pass.set_bind_group(1, &self.render_bind_groups[write_index], &[]);
            pass.draw(0..3, 0..1);
        }

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Sentinel Present Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.present_pipeline);
            pass.set_bind_group(0, &self.present_bind_groups[write_index], &[]);
            pass.draw(0..3, 0..1);
        }

        self.queue.submit(Some(encoder.finish()));
        frame.present();
        self.device.poll(wgpu::Maintain::Poll);
        self.frame_index = self.frame_index.wrapping_add(1);

        Ok(())
    }
}

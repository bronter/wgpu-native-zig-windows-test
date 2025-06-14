const win32 = @import("win32");
const wgpu = @import("wgpu");

const Renderer = @This();

surface: *wgpu.Surface,
device: *wgpu.Device,
queue: *wgpu.Queue,
surface_config: wgpu.SurfaceConfiguration,
pipeline: *wgpu.RenderPipeline,

pub fn create(width: u32, height: u32, hinstance: win32.foundation.HINSTANCE, hwnd: win32.foundation.HWND) !Renderer {
    var self: Renderer = undefined;

    const instance = wgpu.Instance.create(null) orelse return error.CouldNotCreateInstance;
    defer instance.release();

    self.surface = instance.createSurface(&wgpu.surfaceDescriptorFromWindowsHWND(.{
        .label = "HWND_surface",
        .hinstance = hinstance,
        .hwnd = hwnd,
    })) orelse return error.CouldNotCreateSurface;

    const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
        .compatible_surface = self.surface,
    }, 0);
    const adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.AdapterRequestFailed
    };
    defer adapter.release();

    const device_request = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor {
        .required_limits = null,
    }, 0);
    self.device = switch(device_request.status) {
        .success => device_request.device.?,
        else => return error.DeviceRequestFailed,
    };

    self.queue = self.device.getQueue() orelse return error.CouldNotGetQueue;

    var surface_capabilities: wgpu.SurfaceCapabilities = undefined;
    if (self.surface.getCapabilities(adapter, &surface_capabilities) == wgpu.Status.@"error") {
        return error.FailedToGetDeviceCapabilities;
    }

    // TODO: Figure out if it's possible to get width/height from the window instead of having to pass them in.
    self.surface_config = wgpu.SurfaceConfiguration {
        .width = width,
        .height = height,
        .format = surface_capabilities.formats[0],
        .device = self.device,
    };

    self.surface.configure(&self.surface_config);
    surface_capabilities.freeMembers();

    // Render pipeline stuff
    // -------------------------------------------------------------------------
    const shader_module = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./shader.wgsl"),
    })) orelse return error.CouldNotCreateShader;
    defer shader_module.release();

    const color_targets = &[_]wgpu.ColorTargetState {
        wgpu.ColorTargetState {
            .format = self.surface_config.format,
            .blend = &wgpu.BlendState {
                .color = wgpu.BlendComponent {
                    .operation = wgpu.BlendOperation.add,
                    .src_factor = wgpu.BlendFactor.src_alpha,
                    .dst_factor = wgpu.BlendFactor.one_minus_src_alpha,
                },
                .alpha = wgpu.BlendComponent {
                    .operation = wgpu.BlendOperation.add,
                    .src_factor = wgpu.BlendFactor.zero,
                    .dst_factor = wgpu.BlendFactor.one,
                },
            },
        },
    };

    self.pipeline = self.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor {
        .vertex = wgpu.VertexState {
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
        },
        .primitive = wgpu.PrimitiveState {},
        .multisample = wgpu.MultisampleState {},
        .fragment = &wgpu.FragmentState {
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets.ptr,
        },
    }) orelse return error.CouldNotCreateRenderPipeline;

    return self;
}

pub fn render(self: *Renderer) !void {
    var surface_texture: wgpu.SurfaceTexture = undefined;
    self.surface.getCurrentTexture(&surface_texture);
    if (surface_texture.status != .success_optimal and surface_texture.status != .success_suboptimal) {
        return error.SurfaceTextureNotSuccessfulStatus; // TODO: find a better name for that
    }

    const target_view = surface_texture.texture.?.createView(&wgpu.TextureViewDescriptor {
        .label = wgpu.StringView.fromSlice("surface texture view"),
        .format = surface_texture.texture.?.getFormat(),
        .dimension = wgpu.ViewDimension.@"2d",
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return error.CouldNotCreateTextureView;

    const encoder = self.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor {
        .label = wgpu.StringView.fromSlice("render command encoder"),
    }) orelse return error.CouldNotCreateCommandEncoder;

    const render_pass_color_attachments = &[_]wgpu.ColorAttachment {
        wgpu.ColorAttachment {
            .view = target_view,
            .clear_value = wgpu.Color { .r = 0.9, .g = 0.1, .b = 0.2, .a = 1.0 },
        },
    };

    const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor {
        .color_attachment_count = render_pass_color_attachments.len,
        .color_attachments = render_pass_color_attachments.ptr,
    }) orelse return error.CouldNotBeginRenderPass;

    render_pass.setPipeline(self.pipeline);
    render_pass.draw(3, 1, 0, 0);
    render_pass.end();
    render_pass.release();

    const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor {
        .label = wgpu.StringView.fromSlice("render command buffer"),
    }) orelse return error.CouldNotFinishCommandEncoder;
    const commands = [_] *const wgpu.CommandBuffer {
        command_buffer,
    };
    encoder.release();

    self.queue.submit(&commands);

    command_buffer.release();
    target_view.release();

    if (self.surface.present() == wgpu.Status.@"error") {
        return error.SurfacePresentUnsuccessful;
    }

    _ = self.device.poll(false, null);
}

pub fn release(self: *Renderer) void {
    self.pipeline.release();
    self.surface.unconfigure();
    self.queue.release();
    self.surface.release();
    self.device.release();
}
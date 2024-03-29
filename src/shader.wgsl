@group(0) @binding(0) var<uniform> display_size: vec2f;

@vertex
fn vs_main(@location(0) vertex_position: vec2f) -> @builtin(position) vec4f {
    let ratio: vec2<f32> = min(vec2<f32>(2.0 * display_size.y / display_size.x, 1.0), vec2<f32>(1.0, display_size.x / (2.0 * display_size.y)));

    return vec4f(vertex_position * ratio, 0.0, 1.0);
}

@group(0) @binding(1) var<storage, read_write>  display: array<u32>;
@group(0) @binding(2) var<uniform> color: vec3f;

@fragment
fn fs_main(@builtin(position) pos: vec4f) -> @location(0) vec4f {
    let ratio: vec2<f32> = min(vec2<f32>(2.0 * display_size.y / display_size.x, 1.0), vec2<f32>(1.0, display_size.x / (2.0 * display_size.y)));
    let offset: vec2<f32> = (display_size - display_size * ratio) / 2.0;

    let scaled_pos: vec2<f32> = (pos.xy - offset) * vec2<f32>(64.0, 32.0) / (display_size * ratio);
    let coord: vec2<u32> = vec2<u32>(u32(scaled_pos.x), u32(scaled_pos.y));

    let index = coord.y * 2 + coord.x / 32;
    let shift = 31 - (coord.x % 32);

    return vec4f(color, f32((display[index] >> shift) & 1u));
}

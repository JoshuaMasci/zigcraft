const c = @import("c.zig");

const std = @import("std");
const panic = std.debug.panic;
const trait = std.meta.trait;

//TODO Replace with pipeline state object
pub fn init3dRendering() void {
    c.glEnable(c.GL_DEPTH_TEST);
    c.glDepthMask(c.GL_TRUE);
    c.glDepthFunc(c.GL_LESS);

    c.glFrontFace(c.GL_CCW);
    c.glEnable(c.GL_CULL_FACE);
    c.glCullFace(c.GL_BACK);

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
}

pub fn clearFramebuffer() void {
    //Need to enable depth test to clear depth buffer
    c.glEnable(c.GL_DEPTH_TEST);
    c.glDepthMask(c.GL_TRUE);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
}

pub fn setViewport(size: [2]i32) void {
    c.glViewport(0, 0, @intCast(c.GLsizei, size[0]), @intCast(c.GLsizei, size[1]));
}

pub const Mesh = struct {
    const Self = @This();

    vao: c.GLuint,
    vertex_buffer: c.GLuint,
    index_buffer: c.GLuint,
    index_count: c.GLint,
    index_type: c.GLenum,

    fn isVertexTypeValid(comptime VertexType: type) void {
        if(!comptime trait.hasFn("genVao")(VertexType)) {
            @compileError("VertexType doesn't have genVao Function");
        }
    }

    fn getIndexType(comptime IndexType: type) c.GLenum {
        var index_type: c.GLenum = undefined;
        if(comptime IndexType == u8) {
            return c.GL_UNSIGNED_BYTE;
        }
        else if(comptime IndexType == u16) {
            return c.GL_UNSIGNED_SHORT;
        }
        else if(comptime IndexType == u32) {
            return c.GL_UNSIGNED_INT;
        }
        else {
            @compileError("IndexType must be u8, u16, or u32");
        }
    }

    pub fn init(comptime VertexType: type, comptime IndexType: type, vertices: []const VertexType, indices: []const IndexType) Self {
        //Validate Types
        comptime isVertexTypeValid(VertexType);
        const index_type: c.GLenum = comptime getIndexType(IndexType);

        var vao: c.GLuint = undefined;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);

        var buffers: [2]c.GLuint = undefined;
        c.glGenBuffers(buffers.len, &buffers);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, buffers[0]);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_longlong, @sizeOf(VertexType) * vertices.len), vertices.ptr, c.GL_STATIC_DRAW);
        VertexType.genVao();

        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, buffers[1]);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_longlong, @sizeOf(u32) * indices.len), indices.ptr, c.GL_STATIC_DRAW);

        c.glBindVertexArray(0);
        c.glBindBuffer(c.GL_ARRAY_BUFFER,0);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);

        return Self {
            .vao = vao,
            .vertex_buffer = buffers[0],
            .index_buffer = buffers[1],
            .index_count = @intCast(c.GLint, indices.len),
            .index_type = index_type,
        };
    }

    pub fn deinit(self: *const Self) void {
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.vertex_buffer);
        c.glDeleteBuffers(1, &self.index_buffer);
    }

    pub fn draw(self: *const Self) void {
        //Setup
        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);

        //Draw
        c.glDrawElements(c.GL_TRIANGLES, self.index_count, self.index_type, null);

        //Cleanup
        c.glBindVertexArray(0);
        c.glBindBuffer(c.GL_ARRAY_BUFFER,0);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);
    }
};

pub const Shader = struct {
    const Self = @This();

    shader_program: c.GLuint,

    pub fn init(vertex_shader: []const u8, fragment_shader: []const u8) Self {
        const stdout = std.io.getStdOut().writer();

        var program = c.glCreateProgram();

        var vertex_module = Self.init_shader_module(vertex_shader, c.GL_VERTEX_SHADER);
        c.glAttachShader(program, vertex_module);

        var fragment_module = Self.init_shader_module(fragment_shader, c.GL_FRAGMENT_SHADER);
        c.glAttachShader(program, fragment_module);

        c.glLinkProgram(program);

        var program_info_size: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &program_info_size);
        if (program_info_size > 0) {
            var program_info_string = [_]u8{0} ** 512;
            c.glGetProgramInfoLog(program, @intCast(c.GLsizei, program_info_string.len ), null, &program_info_string);
            stdout.print("Shader Error: {s}!\n", .{program_info_string}) catch {};
        }

        c.glDeleteShader(vertex_module);
        c.glDeleteShader(fragment_module);

        return Self {
            .shader_program = program,
        };
    }

    pub fn deinit(self: *Self) void {
        c.glDeleteProgram(self.shader_program);
    }

    fn init_shader_module(shader_code: []const u8, stage: c.GLuint) c.GLuint {
        var shader = c.glCreateShader(stage);
        c.glShaderSource(shader, 1, &shader_code.ptr, &@intCast(c.GLint, shader_code.len));
        c.glCompileShader(shader);
        return shader;
    }
};

pub const Texture = struct {
    const Self = @This();

    handle: c.GLuint,

    //TODO format + sampling
    pub fn init(size: [2]u32, data: []const u8) Self {
        var texture: c.GLuint = undefined;
        c.glGenTextures(1, &texture);
        c.glBindTexture(c.GL_TEXTURE_2D, texture);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, @intCast(c.GLsizei, size[0]), @intCast(c.GLsizei, size[1]), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, data.ptr);

        return Self{
            .handle = texture,
        };
    }

    pub fn deinit(self: *Self) void {
        c.glDeleteTextures(1, &self.handle);
    }

    pub fn bind(self: *Self, index: u32) void {
        c.glActiveTexture(c.GL_TEXTURE0 + index);
        c.glBindTexture(c.GL_TEXTURE_2D, self.handle);
    }
};
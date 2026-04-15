const std = @import("std");

const log = std.log.scoped(.necromach_gpu_dawn);

pub fn build(b: *std.Build) !void {
    // const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = Options{
        .install_libs = true,
        .from_source = true,
    };
    const lib = try buildFromSource(b, target, .ReleaseFast, options);

    const install_art = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&install_art.step);
}

pub fn link(b: *std.Build, dep_name: []const u8, exe: *std.Build.Step.Compile) !void {
    const dawn = b.dependency(dep_name, .{});
    exe.root_module.addLibraryPath(dawn.path("./build/src/dawn/native"));
    exe.root_module.linkSystemLibrary("webgpu_dawn", .{});

    const dawn_artifact = dawn.artifact("dawn");
    exe.step.dependOn(&dawn_artifact.step);

    if (exe.root_module.resolved_target.?.result.os.tag == .windows) {
        // zdawn.root_module.linkSystemLibrary("mingw_helpers", .{});
        exe.root_module.addCSourceFile(.{ .file = .{ .dependency = .{ .dependency = dawn, .sub_path = "src/dawn/mingw_helpers.cpp" } } }); // FIXME: Not ideal.
    }
}

pub const Options = struct {
    /// Defaults to true on Windows
    d3d12: ?bool = null,

    /// Defaults to true on Darwin
    metal: ?bool = null,

    /// Defaults to true on Linux, Fuchsia
    // TODO(build-system): enable on Windows if we can cross compile Vulkan
    vulkan: ?bool = null,

    /// Defaults to true on Linux
    desktop_gl: ?bool = null,

    /// Defaults to true on Android, Linux, Windows, Emscripten
    // TODO(build-system): not respected at all currently
    opengl_es: ?bool = null,

    /// Whether or not minimal debug symbols should be emitted. This is -g1 in most cases, enough to
    /// produce stack traces but omitting debug symbols for locals. For spirv-tools and tint in
    /// specific, -g0 will be used (no debug symbols at all) to save an additional ~39M.
    debug: bool = false,

    /// Whether or not to produce separate static libraries for each component of Dawn (reduces
    /// iteration times when building from source / testing changes to Dawn source code.)
    separate_libs: bool = false,

    /// Whether or not to produce shared libraries instead of static ones
    shared_libs: bool = false,

    /// Whether to build Dawn from source or not.
    from_source: bool = false,

    /// Produce static libraries at zig-out/lib
    install_libs: bool = false,

    /// The binary release version to use from https://github.com/hexops/mach-gpu-dawn/releases
    binary_version: []const u8 = "release-9c05275",

    /// Detects the default options to use for the given target.
    pub fn detectDefaults(self: Options, target: std.Target) Options {
        const tag = target.os.tag;

        var options = self;
        if (options.d3d12 == null) options.d3d12 = tag == .windows;
        if (options.metal == null) options.metal = tag.isDarwin();
        if (options.vulkan == null) options.vulkan = tag == .fuchsia or isLinuxDesktopLike(tag);

        // TODO(build-system): technically Dawn itself defaults desktop_gl to true on Windows.
        if (options.desktop_gl == null) options.desktop_gl = isLinuxDesktopLike(tag);

        // TODO(build-system): OpenGL ES
        options.opengl_es = false;
        // if (options.opengl_es == null) options.opengl_es = tag == .windows or tag == .emscripten or target.isAndroid() or linux_desktop_like;

        return options;
    }
};

fn isLinuxDesktopLike(tag: std.Target.Os.Tag) bool {
    return switch (tag) {
        .linux,
        .freebsd,
        .openbsd,
        .dragonfly,
        => true,
        else => false,
    };
}

fn isTargetSupported(target: std.Target) bool {
    return switch (target.os.tag) {
        .windows => target.abi.isGnu(),
        .linux => (target.cpu.arch.isX86() or target.cpu.arch.isAARCH64()) and (target.abi.isGnu() or target.abi.isMusl()),
        .macos => blk: {
            if (!target.cpu.arch.isX86() and !target.cpu.arch.isAARCH64()) break :blk false;

            // The minimum macOS version with which our binaries can be used.
            const min_available = std.SemanticVersion{ .major = 11, .minor = 0, .patch = 0 };

            // If the target version is >= the available version, then it's OK.
            const order = target.os.version_range.semver.min.order(min_available);
            break :blk (order == .gt or order == .eq);
        },
        else => false,
    };
}

fn buildFromSource(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, options: Options) !*std.Build.Step.Compile {
    // TODO: Support options
    _ = options;

    const target_str = try target.result.zigTriple(b.allocator);
    defer b.allocator.free(target_str);

    if (!isTargetSupported(target.result)) {
        log.err("Target '{s}' is not currently supported.", .{target_str});
        return error.TargetNotSupported;
    } else {
        log.info("Building dawn for target {s}.", .{target_str});
    }

    const toolchain_path = b.path("zig-toolchain.cmake").getPath(b);
    const build_dir = b.path("./build").getPath(b);
    // CMake Configure Step
    var cmake_configure = b.addSystemCommand(&.{ "cmake", "-G", "Ninja", "-B", build_dir });
    cmake_configure.addArgs(&.{
        b.fmt("-DCMAKE_TOOLCHAIN_FILE={s}", .{toolchain_path}),
        b.fmt("-DTARGET={s}", .{target_str}),
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{switch (optimize) {
            .Debug => "Debug",
            .ReleaseSafe, .ReleaseFast, .ReleaseSmall => "Release",
        }}),
    });
    if (isLinuxDesktopLike(target.result.os.tag)) {
        cmake_configure.addArgs(&.{
            "-DDAWN_USE_WAYLAND=ON",
            "-DDAWN_USE_X11=ON",
        });
    }
    // Tell Zig this step depends on the source files
    cmake_configure.addDirectoryArg(b.path("libs/dawn"));
    cmake_configure.setCwd(b.path("."));

    // CMake Build Step
    var cmake_build = b.addSystemCommand(&.{ "cmake", "--build", build_dir, "--config", "Release" });
    cmake_build.setCwd(b.path("."));
    cmake_build.step.dependOn(&cmake_configure.step);

    const lib = b.addLibrary(.{
        .name = "dawn",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .root_source_file = b.path("src/empty.zig") }),
    });
    lib.step.dependOn(&cmake_build.step);
    // lib.root_module.addObjectFile(b.path("build/src/dawn/native/libwebgpu_dawn.a"));
    return lib;
}

fn exec(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.cwd = cwd;
    _ = try child.spawnAndWait();
}

fn getCurrentGitRevision(allocator: std.mem.Allocator, cwd: []const u8) ![]const u8 {
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "git", "rev-parse", "HEAD" }, .cwd = cwd });
    allocator.free(result.stderr);
    if (result.stdout.len > 0) return result.stdout[0 .. result.stdout.len - 1]; // trim newline
    return result.stdout;
}

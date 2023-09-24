const std = @import("std");

const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = .ReleaseFast;

    validateTarget(target.toTarget());

    const capstone_dep = b.dependency("capstone", .{
        .target = target,
        .optimize = optimize,
    });
    const capstone_lib = capstone_dep.artifact("capstone");

    const tracy_defines = defineOptions(b);

    const tracy_lib = b.addStaticLibrary(.{
        .name = "tracy",
        .target = target,
        .optimize = optimize,
    });
    if (optimize != .Debug) tracy_lib.defineCMacro("NDEBUG", null);
    if (tracy_lib.isDynamicLibrary()) tracy_lib.defineCMacro("TRACY_EXPORTS", null);
    for (tracy_defines) |d| tracy_lib.defineCMacro(d, null);
    tracy_lib.addCSourceFile(.{
        .file = .{ .path = "public/TracyClient.cpp" },
        .flags = &.{"-std=c++11"},
    });
    tracy_lib.linkLibCpp();
    b.installArtifact(tracy_lib);

    const tracy_mod = b.addModule(
        "tracy",
        .{ .source_file = .{ .path = "zig/tracy.zig" } },
    );
    _ = tracy_mod;

    const capture_exe = b.addExecutable(.{
        .name = "tracy-capture",
        .target = target,
        .optimize = optimize,
    });
    if (optimize != .Debug) capture_exe.defineCMacro("NDEBUG", null);
    capture_exe.defineCMacro("NO_PARALLEL_SORT", null); // TODO: figure out how to enable tbb in libc++
    capture_exe.defineCMacro("TRACY_NO_STATISTICS", null);
    capture_exe.addIncludePath(getInstallRelativePath(b, capstone_lib, "include/capstone"));
    capture_exe.addCSourceFiles(&capture_sources, &capture_cxx_flags);
    capture_exe.addCSourceFiles(&common_sources, &capture_cxx_flags);
    capture_exe.addCSourceFiles(&server_sources, &capture_cxx_flags);
    capture_exe.addCSourceFiles(&zstd_sources, &capture_c_flags);
    capture_exe.linkLibCpp();
    capture_exe.linkLibrary(capstone_lib);
    b.installArtifact(capture_exe);
}

fn validateTarget(t: std.Target) void {
    if (t.cpu.arch.endian() != .Little) @panic("only supported on little endian architectures");
}

fn defineOptions(b: *Build) [][]const u8 {
    const options = .{
        .{ "enable", true, "Enable profiling" },
        .{ "on_demand", false, "On-demand profiling" },
        .{ "callstack", false, "Enfore callstack collection for tracy regions" },
        .{ "no_callstack", false, "Disable all callstack related functionality" },
        .{ "no_callstack_inlines", false, "Disables the inline functions in callstacks" },
        .{ "only_localhost", false, "Only listen on the localhost interface" },
        .{ "no_broadcast", false, "Disable client discovery by broadcast to local network" },
        .{ "only_ipv4", true, "Tracy will only accept connections on IPv4 addresses (disable IPv6)" },
        .{ "no_code_transfer", false, "Disable collection of source code" },
        .{ "no_context_switch", false, "Disable capture of context switches" },
        .{ "no_exit", false, "Client executable does not exit until all profile data is sent to server" },
        .{ "no_sampling", false, "Disable call stack sampling" },
        .{ "no_verify", false, "Disable zone validation for C API" },
        .{ "no_vsync_capture", false, "Disable capture of hardware Vsync events" },
        .{ "no_frame_image", true, "Disable the frame image support and its thread" },
        .{ "no_system_tracing", false, "Disable systrace sampling" },
        .{ "timer_fallback", false, "Use lower resolution timers" },
        .{ "delayed_init", false, "Enable delayed initialization of the library (init on first call)" },
        .{ "manual_lifetime", false, "Enable the manual lifetime management of the profile" },
        .{ "fibers", false, "Enable fibers support" },
        .{ "no_crash_handler", true, "Disable crash handling" },
    };

    var defines = std.ArrayListUnmanaged([]const u8).initCapacity(
        b.allocator,
        options.len,
    ) catch @panic("OOM");
    errdefer defines.deinit(b.allocator);

    inline for (options) |o| {
        const name = "tracy_" ++ o[0];
        const enabled = b.option(bool, name, o[2]) orelse o[1];
        if (enabled) {
            const definition = comptime blk: {
                var buf: [name.len]u8 = undefined;
                break :blk std.ascii.upperString(&buf, name);
            };
            defines.appendAssumeCapacity(definition);
        }
    }

    return defines.toOwnedSlice(b.allocator) catch @panic("OOM");
}

const common_sources = [_][]const u8{
    "public/common/tracy_lz4.cpp",
    "public/common/tracy_lz4hc.cpp",
    "public/common/TracySocket.cpp",
    "public/common/TracyStackFrames.cpp",
    "public/common/TracySystem.cpp",
};

const server_sources = [_][]const u8{
    "server/TracyMemory.cpp",
    "server/TracyMmap.cpp",
    "server/TracyPrint.cpp",
    "server/TracyTaskDispatch.cpp",
    "server/TracyTextureCompression.cpp",
    "server/TracyThreadCompress.cpp",
    "server/TracyWorker.cpp",
};

const capture_sources = [_][]const u8{
    "capture/src/capture.cpp",
};
const capture_c_flags = [_][]const u8{
    "-std=c89",
};
const capture_cxx_flags = [_][]const u8{
    "-std=c++17",
};

const zstd_sources = [_][]const u8{
    "zstd/common/debug.c",
    "zstd/common/entropy_common.c",
    "zstd/common/error_private.c",
    "zstd/common/fse_decompress.c",
    "zstd/common/pool.c",
    "zstd/common/threading.c",
    "zstd/common/xxhash.c",
    "zstd/common/zstd_common.c",
    "zstd/compress/fse_compress.c",
    "zstd/compress/hist.c",
    "zstd/compress/huf_compress.c",
    "zstd/compress/zstdmt_compress.c",
    "zstd/compress/zstd_compress.c",
    "zstd/compress/zstd_compress_literals.c",
    "zstd/compress/zstd_compress_sequences.c",
    "zstd/compress/zstd_compress_superblock.c",
    "zstd/compress/zstd_double_fast.c",
    "zstd/compress/zstd_fast.c",
    "zstd/compress/zstd_lazy.c",
    "zstd/compress/zstd_ldm.c",
    "zstd/compress/zstd_opt.c",
    "zstd/decompress/huf_decompress.c",
    "zstd/decompress/zstd_ddict.c",
    "zstd/decompress/zstd_decompress.c",
    "zstd/decompress/zstd_decompress_block.c",
    "zstd/dictBuilder/cover.c",
    "zstd/dictBuilder/divsufsort.c",
    "zstd/dictBuilder/fastcover.c",
    "zstd/dictBuilder/zdict.c",
    "zstd/decompress/huf_decompress_amd64.S",
};

fn getInstallRelativePath(b: *Build, other: *Build.Step.Compile, to: []const u8) Build.LazyPath {
    const generated = b.allocator.create(Build.GeneratedFile) catch @panic("OOM");
    generated.step = &other.step;
    generated.path = b.pathJoin(&.{ other.step.owner.install_path, to });
    return .{ .generated = generated };
}

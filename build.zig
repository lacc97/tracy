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

    const build_profiler = b.option(
        bool,
        "profiler",
        "Build the profiler (requires system headers and libraries)",
    ) orelse false;

    const strip_binary = b.option(
        bool,
        "strip",
        "Strip output binaries of their debug symbols",
    ) orelse false;

    const tracy_defines = defineOptions(b);

    const tracy_lib = b.addStaticLibrary(.{
        .name = "tracy",
        .target = target,
        .optimize = optimize,
    });
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
    if (capture_exe.optimize != .Debug) capture_exe.defineCMacro("NDEBUG", null);
    capture_exe.defineCMacro("NO_PARALLEL_SORT", null); // TODO: figure out how to enable tbb in libc++
    capture_exe.defineCMacro("TRACY_NO_STATISTICS", null);
    capture_exe.addIncludePath(getInstallRelativePath(b, capstone_lib, "include/capstone"));
    capture_exe.addCSourceFiles(.{ .files = &capture_sources, .flags = &base_cxx_flags });
    capture_exe.addCSourceFiles(.{ .files = &zstd_sources, .flags = &base_c_flags });
    capture_exe.linkLibCpp();
    capture_exe.linkLibrary(capstone_lib);
    if (strip_binary) capture_exe.strip = strip_binary;
    b.installArtifact(capture_exe);

    if (build_profiler) {
        const profiler_exe = b.addExecutable(.{
            .name = "tracy-profiler",
            .target = target,
            .optimize = optimize,
        });
        if (profiler_exe.optimize != .Debug) profiler_exe.defineCMacro("NDEBUG", null);
        profiler_exe.defineCMacro("NO_PARALLEL_SORT", null); // TODO: figure out how to enable tbb in libc++
        profiler_exe.defineCMacro("IMGUI_ENABLE_FREETYPE", null);
        profiler_exe.addIncludePath(getInstallRelativePath(b, capstone_lib, "include/capstone"));
        profiler_exe.addIncludePath(.{ .path = "imgui" });
        profiler_exe.addCSourceFiles(.{ .files = &profiler_cxx_sources, .flags = &base_cxx_flags });
        profiler_exe.addCSourceFiles(.{ .files = &profiler_c_sources, .flags = &base_c_flags });
        profiler_exe.addCSourceFiles(.{ .files = &profiler_wayland_cxx_sources, .flags = &base_cxx_flags });
        profiler_exe.addCSourceFiles(.{ .files = &profiler_wayland_c_sources, .flags = &base_c_flags });
        profiler_exe.addCSourceFiles(.{ .files = &zstd_sources, .flags = &base_c_flags });
        profiler_exe.linkLibCpp();
        profiler_exe.linkSystemLibrary("dbus-1");
        profiler_exe.linkSystemLibrary("egl");
        profiler_exe.linkSystemLibrary("freetype2");
        profiler_exe.linkSystemLibrary("wayland-cursor");
        profiler_exe.linkSystemLibrary("wayland-egl");
        profiler_exe.linkSystemLibrary("xkbcommon");
        profiler_exe.linkLibrary(capstone_lib);
        if (strip_binary) profiler_exe.strip = strip_binary;
        b.installArtifact(profiler_exe);
    }
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

const base_c_flags = [_][]const u8{
    "-std=c99",
};
const base_cxx_flags = [_][]const u8{
    "-std=c++17",
};

const common_sources = [_][]const u8{
    "public/common/tracy_lz4.cpp",
    "public/common/tracy_lz4hc.cpp",
    "public/common/TracySocket.cpp",
    "public/common/TracyStackFrames.cpp",
    "public/common/TracySystem.cpp",
};

const capture_sources = common_sources ++ [_][]const u8{
    "capture/src/capture.cpp",

    "server/TracyMemory.cpp",
    "server/TracyMmap.cpp",
    "server/TracyPrint.cpp",
    "server/TracyTaskDispatch.cpp",
    "server/TracyTextureCompression.cpp",
    "server/TracyThreadCompress.cpp",
    "server/TracyWorker.cpp",
};

const profiler_cxx_sources = common_sources ++ [_][]const u8{
    "profiler/src/ConnectionHistory.cpp",
    "profiler/src/Filters.cpp",
    "profiler/src/Fonts.cpp",
    "profiler/src/HttpRequest.cpp",
    "profiler/src/ImGuiContext.cpp",
    "profiler/src/imgui/imgui_impl_opengl3.cpp",
    "profiler/src/IsElevated.cpp",
    "profiler/src/main.cpp",
    "profiler/src/ResolvService.cpp",
    "profiler/src/RunQueue.cpp",
    "profiler/src/WindowPosition.cpp",
    "profiler/src/winmain.cpp",
    "profiler/src/winmainArchDiscovery.cpp",

    "server/TracyBadVersion.cpp",
    "server/TracyColor.cpp",
    "server/TracyEventDebug.cpp",
    "server/TracyFileselector.cpp",
    "server/TracyFilesystem.cpp",
    "server/TracyImGui.cpp",
    "server/TracyMemory.cpp",
    "server/TracyMicroArchitecture.cpp",
    "server/TracyMmap.cpp",
    "server/TracyMouse.cpp",
    "server/TracyPrint.cpp",
    "server/TracyProtoHistory.cpp",
    "server/TracySourceContents.cpp",
    "server/TracySourceTokenizer.cpp",
    "server/TracySourceView.cpp",
    "server/TracyStorage.cpp",
    "server/TracyTaskDispatch.cpp",
    "server/TracyTexture.cpp",
    "server/TracyTextureCompression.cpp",
    "server/TracyThreadCompress.cpp",
    "server/TracyTimelineController.cpp",
    "server/TracyTimelineItem.cpp",
    "server/TracyTimelineItemCpuData.cpp",
    "server/TracyTimelineItemGpu.cpp",
    "server/TracyTimelineItemPlot.cpp",
    "server/TracyTimelineItemThread.cpp",
    "server/TracyUserData.cpp",
    "server/TracyUtility.cpp",
    "server/TracyView_Annotations.cpp",
    "server/TracyView_Callstack.cpp",
    "server/TracyView_Compare.cpp",
    "server/TracyView_ConnectionState.cpp",
    "server/TracyView_ContextSwitch.cpp",
    "server/TracyView_CpuData.cpp",
    "server/TracyView_FindZone.cpp",
    "server/TracyView_FrameOverview.cpp",
    "server/TracyView_FrameTimeline.cpp",
    "server/TracyView_FrameTree.cpp",
    "server/TracyView_GpuTimeline.cpp",
    "server/TracyView_Locks.cpp",
    "server/TracyView_Memory.cpp",
    "server/TracyView_Messages.cpp",
    "server/TracyView_Navigation.cpp",
    "server/TracyView_NotificationArea.cpp",
    "server/TracyView_Options.cpp",
    "server/TracyView_Playback.cpp",
    "server/TracyView_Plots.cpp",
    "server/TracyView_Ranges.cpp",
    "server/TracyView_Samples.cpp",
    "server/TracyView_Statistics.cpp",
    "server/TracyView_Timeline.cpp",
    "server/TracyView_TraceInfo.cpp",
    "server/TracyView_Utility.cpp",
    "server/TracyView_ZoneInfo.cpp",
    "server/TracyView_ZoneTimeline.cpp",
    "server/TracyView.cpp",
    "server/TracyWeb.cpp",
    "server/TracyWorker.cpp",

    "imgui/imgui.cpp",
    "imgui/imgui_demo.cpp",
    "imgui/imgui_draw.cpp",
    "imgui/imgui_tables.cpp",
    "imgui/imgui_widgets.cpp",
    "imgui/misc/freetype/imgui_freetype.cpp",

    "nfd/nfd_portal.cpp",
};
const profiler_c_sources = [_][]const u8{
    "profiler/src/ini.c",
};

const profiler_wayland_cxx_sources = [_][]const u8{
    "profiler/src/BackendWayland.cpp",
};
const profiler_wayland_c_sources = [_][]const u8{
    "profiler/src/wayland/xdg-shell.c",
    "profiler/src/wayland/xdg-activation.c",
    "profiler/src/wayland/xdg-decoration.c",
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

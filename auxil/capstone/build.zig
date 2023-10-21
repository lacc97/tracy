const std = @import("std");

const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const capstone_lib = b.addStaticLibrary(.{
        .name = "capstone",
        .target = target,
        .optimize = optimize,
    });
    switch (optimize) {
        .Debug => capstone_lib.defineCMacro("CAPSTONE_DEBUG", null),
        .ReleaseSmall => {
            capstone_lib.defineCMacro("CAPSTONE_DIET", null);
            capstone_lib.defineCMacro("NDEBUG", null);
        },
        else => capstone_lib.defineCMacro("NDEBUG", null),
    }
    capstone_lib.addIncludePath(.{ .path = "upstream/include" });
    addArchitectureSources(b, capstone_lib);
    capstone_lib.addCSourceFiles(.{ .files = &base_sources, .flags = &base_flags });
    capstone_lib.linkLibC();
    capstone_lib.installHeadersDirectory("upstream/include/capstone", "capstone");
    b.installArtifact(capstone_lib);
}

const base_sources = [_][]const u8{
    "upstream/cs.c",
    "upstream/Mapping.c",
    "upstream/MCInst.c",
    "upstream/MCInstrDesc.c",
    "upstream/MCRegisterInfo.c",
    "upstream/SStream.c",
    "upstream/utils.c",
};
const base_flags = [_][]const u8{
    "-std=c99",
    "-Wmissing-braces",
    "-Wunused-function",
    "-Warray-bounds",
    "-Wunused-variable",
    "-Wparentheses",
    "-Wint-in-bool-context",
};

const ArchitectureOption = struct {
    name: []const u8,
    sources: []const []const u8,
};
fn addArchitectureSources(b: *Build, compile: *Build.Step.Compile) void {
    const archs = [_]ArchitectureOption{
        .{
            .name = "ARM",
            .sources = &.{
                "upstream/arch/ARM/ARMDisassembler.c",
                "upstream/arch/ARM/ARMInstPrinter.c",
                "upstream/arch/ARM/ARMMapping.c",
                "upstream/arch/ARM/ARMModule.c",
            },
        },
        .{
            .name = "ARM64",
            .sources = &.{
                "upstream/arch/AArch64/AArch64BaseInfo.c",
                "upstream/arch/AArch64/AArch64Disassembler.c",
                "upstream/arch/AArch64/AArch64InstPrinter.c",
                "upstream/arch/AArch64/AArch64Mapping.c",
                "upstream/arch/AArch64/AArch64Module.c",
            },
        },
        .{
            .name = "M68K",
            .sources = &.{
                "upstream/arch/M68K/M68KDisassembler.c",
                "upstream/arch/M68K/M68KInstPrinter.c",
                "upstream/arch/M68K/M68KModule.c",
            },
        },
        .{
            .name = "MIPS",
            .sources = &.{
                "upstream/arch/Mips/MipsDisassembler.c",
                "upstream/arch/Mips/MipsInstPrinter.c",
                "upstream/arch/Mips/MipsMapping.c",
                "upstream/arch/Mips/MipsModule.c",
            },
        },
        .{
            .name = "PowerPC",
            .sources = &.{
                "upstream/arch/PowerPC/PPCDisassembler.c",
                "upstream/arch/PowerPC/PPCInstPrinter.c",
                "upstream/arch/PowerPC/PPCMapping.c",
                "upstream/arch/PowerPC/PPCModule.c",
            },
        },
        .{
            .name = "Sparc",
            .sources = &.{
                "upstream/arch/Sparc/SparcDisassembler.c",
                "upstream/arch/Sparc/SparcInstPrinter.c",
                "upstream/arch/Sparc/SparcMapping.c",
                "upstream/arch/Sparc/SparcModule.c",
            },
        },
        .{
            .name = "SystemZ",
            .sources = &.{
                "upstream/arch/SystemZ/SystemZDisassembler.c",
                "upstream/arch/SystemZ/SystemZInstPrinter.c",
                "upstream/arch/SystemZ/SystemZMapping.c",
                "upstream/arch/SystemZ/SystemZModule.c",
                "upstream/arch/SystemZ/SystemZMCTargetDesc.c",
            },
        },
        .{
            .name = "XCore",
            .sources = &.{
                "upstream/arch/XCore/XCoreDisassembler.c",
                "upstream/arch/XCore/XCoreInstPrinter.c",
                "upstream/arch/XCore/XCoreMapping.c",
                "upstream/arch/XCore/XCoreModule.c",
            },
        },
        .{
            .name = "x86",
            .sources = &.{
                "upstream/arch/X86/X86Disassembler.c",
                "upstream/arch/X86/X86DisassemblerDecoder.c",
                "upstream/arch/X86/X86IntelInstPrinter.c",
                "upstream/arch/X86/X86InstPrinterCommon.c",
                "upstream/arch/X86/X86Mapping.c",
                "upstream/arch/X86/X86Module.c",
            },
        },
        .{
            .name = "TMS320C64x",
            .sources = &.{
                "upstream/arch/TMS320C64x/TMS320C64xDisassembler.c",
                "upstream/arch/TMS320C64x/TMS320C64xInstPrinter.c",
                "upstream/arch/TMS320C64x/TMS320C64xMapping.c",
                "upstream/arch/TMS320C64x/TMS320C64xModule.c",
            },
        },
        .{
            .name = "M680x",
            .sources = &.{
                "upstream/arch/M680X/M680XDisassembler.c",
                "upstream/arch/M680X/M680XInstPrinter.c",
                "upstream/arch/M680X/M680XModule.c",
            },
        },
        .{
            .name = "EVM",
            .sources = &.{
                "upstream/arch/EVM/EVMDisassembler.c",
                "upstream/arch/EVM/EVMInstPrinter.c",
                "upstream/arch/EVM/EVMMapping.c",
                "upstream/arch/EVM/EVMModule.c",
            },
        },
        .{
            .name = "MOS65XX",
            .sources = &.{
                "upstream/arch/MOS65XX/MOS65XXModule.c",
                "upstream/arch/MOS65XX/MOS65XXDisassembler.c",
            },
        },
        .{
            .name = "WASM",
            .sources = &.{
                "upstream/arch/WASM/WASMDisassembler.c",
                "upstream/arch/WASM/WASMInstPrinter.c",
                "upstream/arch/WASM/WASMMapping.c",
                "upstream/arch/WASM/WASMModule.c",
            },
        },
        .{
            .name = "BPF",
            .sources = &.{
                "upstream/arch/BPF/BPFDisassembler.c",
                "upstream/arch/BPF/BPFInstPrinter.c",
                "upstream/arch/BPF/BPFMapping.c",
                "upstream/arch/BPF/BPFModule.c",
            },
        },
        .{
            .name = "RISCV",
            .sources = &.{
                "upstream/arch/RISCV/RISCVDisassembler.c",
                "upstream/arch/RISCV/RISCVInstPrinter.c",
                "upstream/arch/RISCV/RISCVMapping.c",
                "upstream/arch/RISCV/RISCVModule.c",
            },
        },
        .{
            .name = "SH",
            .sources = &.{
                "upstream/arch/SH/SHDisassembler.c",
                "upstream/arch/SH/SHInstPrinter.c",
                "upstream/arch/SH/SHModule.c",
            },
        },
        .{
            .name = "TriCore",
            .sources = &.{
                "upstream/arch/TriCore/TriCoreDisassembler.c",
                "upstream/arch/TriCore/TriCoreInstPrinter.c",
                "upstream/arch/TriCore/TriCoreMapping.c",
                "upstream/arch/TriCore/TriCoreModule.c",
            },
        },
    };

    @setEvalBranchQuota(10000);
    inline for (archs) |arch| {
        const option_name = comptime blk: {
            const orig = "no_" ++ arch.name;
            var buf: [orig.len]u8 = undefined;
            break :blk std.ascii.upperString(&buf, orig);
        };
        const disable = b.option(
            bool,
            option_name,
            "Disable support for " ++ arch.name ++ " architecture",
        ) orelse false;

        if (!disable) {
            const definition = comptime blk: {
                const orig = "capstone_has_" ++ arch.name;
                var buf: [orig.len]u8 = undefined;
                break :blk std.ascii.upperString(&buf, orig);
            };
            compile.defineCMacro(definition, null);
            compile.addCSourceFiles(.{ .files = arch.sources, .flags = &base_flags });

            if (std.mem.eql(u8, arch.name, "x86") and compile.optimize != .ReleaseSmall) {
                compile.addCSourceFile(.{
                    .file = .{ .path = "upstream/arch/X86/X86ATTInstPrinter.c" },
                    .flags = &base_flags,
                });
            }
        }
    }
}

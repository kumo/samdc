const std = @import("std");
const mdc = @import("mod.zig");

pub const PacketLogger = struct {
    verbose: bool,
    writer: std.fs.File.Writer,
    allocator: std.mem.Allocator,
    parser: mdc.PacketParser,

    pub fn init(allocator: std.mem.Allocator, verbose: bool, writer: std.fs.File.Writer) PacketLogger {
        return .{ .allocator = allocator, .verbose = verbose, .writer = writer, .parser = mdc.PacketParser.init(allocator) };
    }

    pub fn log(self: *PacketLogger, packet: []const u8) !void {
        if (self.verbose) {
            try self.writer.print("Packet: {any}\n", .{packet});
            const annotated_bytes = try self.parser.parse(packet);
            defer self.allocator.free(annotated_bytes);
            try self.writer.print("[ ", .{});
            for (annotated_bytes) |byte| {
                try self.writer.print("{X:0>2}:{d} ({s}) ", .{ byte.value, byte.value, byte.description });
            }
            try self.writer.print("]\n", .{});
        }
    }
};

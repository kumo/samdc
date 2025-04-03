const std = @import("std");

pub const PacketParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PacketParser {
        return .{ .allocator = allocator };
    }

    pub fn parse(self: *PacketParser, packet: []const u8) ![]AnnotatedByte {
        var annotated_bytes = std.ArrayList(AnnotatedByte).init(self.allocator);
        errdefer annotated_bytes.deinit();

        var packet_valid = packet.len >= 5;

        var i: usize = 0;
        while (i < packet.len) : (i += 1) {
            const byte = packet[i];

            if (i == 0 and byte != 0xAA) {
                packet_valid = false;
            }

            const desc: []const u8 = if (!packet_valid) "INV" else switch (i) {
                0 => "HDR",
                else => if (i == packet.len - 1) "CHK" else "???",
            };

            try annotated_bytes.append(.{ .value = byte, .description = desc });
        }

        return annotated_bytes.toOwnedSlice();
    }
};

pub const AnnotatedByte = struct {
    value: u8,
    description: []const u8,
};

test "parse with invalid header marks all bytes as invalid" {
    var parser = PacketParser.init(std.testing.allocator);

    const packet = "Hello, world!";
    const annotated_bytes = try parser.parse(packet);
    defer std.testing.allocator.free(annotated_bytes);

    try std.testing.expectEqual(annotated_bytes.len, packet.len);
    for (annotated_bytes) |byte| {
        try std.testing.expectEqual(byte.description, "INV");
    }
}

test "parse empty packet" {
    var parser = PacketParser.init(std.testing.allocator);

    const packet = "";
    const annotated_bytes = try parser.parse(packet);
    defer std.testing.allocator.free(annotated_bytes);

    try std.testing.expectEqual(annotated_bytes.len, packet.len);
}

test "parse packet with header" {
    var parser = PacketParser.init(std.testing.allocator);

    const packet = [_]u8{ 0xAA, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0xAA };
    const annotated_bytes = try parser.parse(&packet);
    defer std.testing.allocator.free(annotated_bytes);

    try std.testing.expectEqual(annotated_bytes.len, packet.len);
    try std.testing.expectEqual(annotated_bytes[0].value, 0xAA);
    try std.testing.expectEqual(annotated_bytes[0].description, "HDR");
    try std.testing.expectEqual(annotated_bytes[packet.len - 1].description, "CHK");
}

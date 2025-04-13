const std = @import("std");
const protocol = @import("protocol.zig");

// Renamed from PacketParser - focuses on annotation for debugging
pub const PacketAnnotator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PacketAnnotator {
        return .{ .allocator = allocator };
    }

    // Define packet direction
    pub const PacketDirection = enum {
        Command, // Outgoing/sent packet
        Response, // Incoming/received packet
    };

    /// Annotates the bytes of a packet based on expected MDC structure.
    /// Does minimal validation, assumes basic structure might be valid.
    pub fn annotate(self: *PacketAnnotator, packet: []const u8, direction: PacketDirection) ![]AnnotatedByte {
        switch (direction) {
            .Command => return self.annotateCommand(packet),
            .Response => return self.annotateResponse(packet),
        }
    }

    fn annotateCommand(self: *PacketAnnotator, packet: []const u8) ![]AnnotatedByte {
        var annotated_bytes = std.ArrayList(AnnotatedByte).init(self.allocator);
        errdefer annotated_bytes.deinit();

        if (packet.len == 0) {
            return annotated_bytes.toOwnedSlice();
        }

        const data_length: u8 = if (packet.len >= 4) packet[3] else 0;
        const cmd_byte: u8 = if (packet.len >= 2) packet[1] else 0;
        const command_type_opt = std.meta.intToEnum(protocol.CommandType, cmd_byte) catch null;

        var has_subcommand = false;
        if (packet.len >= 5) {
            if (command_type_opt) |command_type| {
                // Check subcommand possibility only if command type is known
                // Exclude Volume from this general check
                switch (command_type) {
                    .Power, .LauncherUrl => {
                        has_subcommand = data_length > 0;
                    },
                    // Volume handled in else, or explicitly if needed
                    // .Volume => {},
                    else => {}, // Handles .Volume and other types
                }
            }
        }

        // Process each byte for annotation
        for (packet, 0..) |byte, i| {
            var desc: []const u8 = "?";

            if (i == 0) {
                desc = "HDR";
            } else if (i == 1) {
                if (command_type_opt) |command_type| {
                    desc = switch (command_type) {
                        .Power => "CMD:Power",
                        .Volume => "CMD:Volume",
                        .LauncherUrl => "CMD:LaunchUrl",
                        else => "CMD:???",
                    };
                } else {
                    desc = "CMD:INV";
                }
            } else if (i == 2) {
                desc = "ID";
            } else if (i == 3) {
                desc = "LEN";
            } else if (i == packet.len - 1) {
                desc = if (packet.len >= 5) "CHK" else "DATA";
            } else if (i == 4 and command_type_opt == .Volume and data_length == 1) {
                desc = "DATA:Level";
            } else if (i == 4 and has_subcommand) {
                if (command_type_opt) |command_type| {
                    desc = switch (command_type) {
                        .Power => switch (byte) {
                            protocol.Subcommands.Power.OFF => "SUBC:PwOFF",
                            protocol.Subcommands.Power.ON => "SUBC:PwON",
                            protocol.Subcommands.Power.REBOOT => "SUBC:PwREBOOT",
                            else => "SUBC:Pw???",
                        },
                        .LauncherUrl => switch (byte) {
                            protocol.Subcommands.Launcher.URL => "SUBC:LUrlSET",
                            else => "SUBC:LUrl???",
                        },
                        else => "SUBC:???",
                    };
                } else {
                    desc = "SUBC:INV";
                }
            } else if (i >= 4) {
                desc = "DATA";
                if (command_type_opt) |cmd_type| {
                    switch (cmd_type) {
                        .LauncherUrl => {
                            if (i >= 5) {
                                desc = "DATA:Char";
                            } // URL data bytes
                        },
                        // Add cases for SerialNumber, ModelName etc. later
                        // .SerialNumber => { desc = "DATA:Char"; },
                        // .ModelName => { desc = "DATA:Char"; },
                        else => {},
                    }
                }
            }

            try annotated_bytes.append(.{ .value = byte, .description = desc });
        }

        return annotated_bytes.toOwnedSlice();
    }

    fn annotateResponse(self: *PacketAnnotator, packet: []const u8) ![]AnnotatedByte {
        var annotated_bytes = std.ArrayList(AnnotatedByte).init(self.allocator);
        errdefer annotated_bytes.deinit();

        if (packet.len == 0) {
            return annotated_bytes.toOwnedSlice();
        }

        const data_length: u8 = if (packet.len >= 4) packet[3] else 0;
        const echo_cmd_byte: u8 = if (packet.len >= 6) packet[5] else 0;
        const status_byte: u8 = if (packet.len >= 5) packet[4] else 0;
        const command_echo_type_opt = std.meta.intToEnum(protocol.CommandType, echo_cmd_byte) catch null;

        var has_subcommand_echo = false;
        if (packet.len >= 7) {
            if (command_echo_type_opt) |command_echo_type| {
                // Exclude Volume from subcommand echo check
                switch (command_echo_type) {
                    .Power, .LauncherUrl => {
                        has_subcommand_echo = data_length >= 2;
                    },
                    // Volume doesn't have subcommand echo in same way
                    // .Volume => {},
                    else => {}, // Handles .Volume and other types
                }
            }
        }

        for (packet, 0..) |byte, i| {
            var desc: []const u8 = "?";

            if (i == 0) {
                desc = "HDR";
            } else if (i == 1) {
                desc = "RSP";
            } else if (i == 2) {
                desc = "ID";
            } else if (i == 3) {
                desc = "LEN";
            } else if (i == 4) {
                desc = switch (status_byte) {
                    protocol.Constants.ACK => "ACK",
                    protocol.Constants.NAK => "NAK",
                    else => "STS:???",
                };
            } else if (i == 5) {
                if (command_echo_type_opt) |command_echo_type| {
                    desc = switch (command_echo_type) {
                        .Power => "ECHO:Power",
                        .Volume => "ECHO:Volume",
                        .LauncherUrl => "ECHO:LaunchUrl",
                        else => "ECHO:???",
                    };
                } else {
                    desc = "ECHO:INV";
                }
            } else if (i == packet.len - 1) {
                desc = if (packet.len >= 7) "CHK" else "DATA";
            } else if (i == 6 and command_echo_type_opt == .Volume and data_length >= 1) { // Check data_length >= 1
                desc = "DATA:Level";
            } else if (i == 6 and has_subcommand_echo) {
                if (command_echo_type_opt) |command_echo_type| {
                    desc = switch (command_echo_type) {
                        .Power => switch (byte) {
                            protocol.Subcommands.Power.OFF => "SUBCE:PwOFF",
                            protocol.Subcommands.Power.ON => "SUBCE:PwON",
                            protocol.Subcommands.Power.REBOOT => "SUBCE:PwREBOOT",
                            else => "SUBCE:Pw???",
                        },
                        .LauncherUrl => switch (byte) {
                            protocol.Subcommands.Launcher.URL => "SUBCE:LUrlSET",
                            else => "SUBCE:LUrl???",
                        },
                        else => "SUBCE:???", // Fallback for others
                    };
                } else {
                    desc = "SUBCE:INV";
                }
            } else if (i >= 6) {
                desc = "DATA";
                if (command_echo_type_opt) |echo_type| {
                    switch (echo_type) {
                        .LauncherUrl => {
                            if (i >= 7) {
                                desc = "DATA:Char";
                            } // URL data bytes (after subcommand echo)
                        },
                        // Add cases for SerialNumber, ModelName etc. later
                        // .SerialNumber => { desc = "DATA:Char"; },
                        // .ModelName => { desc = "DATA:Char"; },
                        else => {},
                    }
                }
            }

            try annotated_bytes.append(.{ .value = byte, .description = desc });
        }

        return annotated_bytes.toOwnedSlice();
    }

    // Removed parseWithoutDirection
};

// Keep AnnotatedByte struct
pub const AnnotatedByte = struct {
    value: u8,
    description: []const u8,
};

// --- Tests for Annotator ---
// Update tests to reflect annotation logic rather than strict parsing

test "annotate command packet" {
    var annotator = PacketAnnotator.init(std.testing.allocator);
    // Power on command: aa:11:01:01:01:13
    const packet = [_]u8{ 0xAA, 0x11, 0x01, 0x01, 0x01, 0x13 };
    const annotated_bytes = try annotator.annotate(&packet, .Command);
    defer std.testing.allocator.free(annotated_bytes);

    try std.testing.expectEqual(annotated_bytes.len, packet.len);
    try std.testing.expectEqual(annotated_bytes[0].description, "HDR");
    try std.testing.expectEqual(annotated_bytes[1].description, "CMD"); // Simplified annotation
    try std.testing.expectEqual(annotated_bytes[2].description, "ID");
    try std.testing.expectEqual(annotated_bytes[3].description, "LEN");
    try std.testing.expectEqual(annotated_bytes[4].description, "SUBC"); // Simplified annotation
    try std.testing.expectEqual(annotated_bytes[5].description, "CHK");
}

test "annotate response packet" {
    var annotator = PacketAnnotator.init(std.testing.allocator);
    // Power status response: aa:ff:01:03:41:11:01:fe
    const packet = [_]u8{ 0xAA, 0xFF, 0x01, 0x03, 0x41, 0x11, 0x01, 0xFE };
    const annotated_bytes = try annotator.annotate(&packet, .Response);
    defer std.testing.allocator.free(annotated_bytes);

    try std.testing.expectEqual(annotated_bytes.len, packet.len);
    try std.testing.expectEqual(annotated_bytes[0].description, "HDR");
    try std.testing.expectEqual(annotated_bytes[1].description, "RSP");
    try std.testing.expectEqual(annotated_bytes[2].description, "ID");
    try std.testing.expectEqual(annotated_bytes[3].description, "LEN");
    try std.testing.expectEqual(annotated_bytes[4].description, "ACK");
    try std.testing.expectEqual(annotated_bytes[5].description, "CMDE");
    try std.testing.expectEqual(annotated_bytes[6].description, "DATA"); // Simplified annotation
    try std.testing.expectEqual(annotated_bytes[7].description, "CHK");
}

// Remove old parser tests if they relied on validation logic
// test "parse with invalid header..."
// test "parse empty packet"
// test "parse command packet without subcommand"
// test "parse command packet with extra data"
// test "parse response packet with subcommand"
// test "parse using backward compatibility function"

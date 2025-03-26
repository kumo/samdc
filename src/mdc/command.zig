const std = @import("std");
const testing = std.testing;

const mdc = @import("mod.zig");

pub const PowerState = enum(u8) {
    Off = 0x00,
    On = 0x01,
    Reboot = 0x02,
};

pub const PowerData = union(enum) {
    Status, // No data needed for status query
    Set: PowerState,
};

pub const LauncherData = union(enum) {
    Status,
    Set: []const u8,
};

pub const VolumeData = union(enum) {
    Status,
    Set: u8,
};

pub const CommandData = union(mdc.Protocol.CommandType) {
    Power: PowerData,
    LauncherUrl: LauncherData,
    Volume: VolumeData,

    pub fn getCommandData(self: CommandData, allocator: std.mem.Allocator) ![]const u8 {
        // Determine the data to return
        const data = switch (self) {
            .Power => |power| switch (power) {
                .Status => &[_]u8{}, // Static empty slice
                .Set => |state| &[_]u8{@intFromEnum(state)}, // Convert enum to u8 value
            },
            .LauncherUrl => |launcher| switch (launcher) {
                .Status => &[_]u8{0x82}, // Static slice
                .Set => |url| return blk: {
                    if (url.len > 200) return mdc.Error.DataTooLong;

                    var result = try allocator.alloc(u8, url.len + 1);
                    result[0] = 0x82;
                    @memcpy(result[1 .. url.len + 1], url);
                    break :blk result;
                },
            },
            .Volume => |volume| switch (volume) {
                .Status => &[_]u8{}, // Static empty slice
                .Set => |level| &[_]u8{level}, // Use the volume level
            },
        };

        return allocator.dupe(u8, data);
    }
};

// MDC command structure
pub const Command = struct {
    header: u8 = 0xAA, // Fixed header for MDC
    command: CommandData,
    display_id: u8 = 0,

    pub fn init(command: CommandData, display_id: u8) Command {
        return .{
            .command = command,
            .display_id = display_id,
        };
    }

    pub fn calculateChecksum(self: Command, data: []const u8) u8 {
        var sum: u32 = 0;

        // Sum all bytes except header and checksum
        sum += @intFromEnum(@as(mdc.CommandType, self.command));
        sum += self.display_id;
        sum += @as(u8, @intCast(data.len)); // Length byte

        // Add all data bytes
        for (data) |byte| {
            sum += byte;
        }

        // Discard anything over 256 (keep only the lowest byte)
        return @truncate(sum);
    }

    pub fn serialize(self: Command, allocator: std.mem.Allocator) ![]u8 {
        // Get the command data (may allocate memory)
        const data = try self.command.getCommandData(allocator);
        defer allocator.free(data);

        const total_length = 5 + data.len; // header + cmd + id + len + data + checksum

        var buffer = try allocator.alloc(u8, total_length);

        buffer[0] = self.header;
        buffer[1] = @intFromEnum(@as(mdc.CommandType, self.command));
        buffer[2] = self.display_id;
        buffer[3] = @intCast(data.len);

        // Copy data if any
        if (data.len > 0) {
            @memcpy(buffer[4..][0..data.len], data);
        }

        // Calculate and append checksum
        buffer[total_length - 1] = self.calculateChecksum(data);

        return buffer;
    }
};

test "MdcCommand - Power Status Query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const packet = Command.init(.{ .Power = .Status }, 0);
    const bytes = try packet.serialize(allocator);

    // aa:11:00:00:11
    try testing.expectEqual(@as(usize, 5), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0x11), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x00), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x11), bytes[4]); // Checksum
}

test "MdcCommand - Power On Command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const packet = Command.init(.{ .Power = .{ .Set = .On } }, 0);
    const bytes = try packet.serialize(allocator);

    // aa:11:00:01:01:13
    try testing.expectEqual(@as(usize, 6), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0x11), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x01), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x01), bytes[4]); // Data (ON)
    try testing.expectEqual(@as(u8, 0x13), bytes[5]); // Checksum
}

test "MdcCommand - Launcher URL Status Query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const packet = Command.init(.{ .LauncherUrl = .Status }, 0);
    const bytes = try packet.serialize(allocator);

    // aa:c7:00:01:82:4a
    try testing.expectEqual(@as(usize, 6), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0xc7), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x01), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x82), bytes[4]); // Data
    try testing.expectEqual(@as(u8, 0x4a), bytes[5]); // Checksum
}

test "MdcCommand - Launcher URL http://example.com Command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const url = "http://example.com";
    const packet = Command.init(.{ .LauncherUrl = .{ .Set = url } }, 0);
    const bytes = try packet.serialize(allocator);

    // aa:c7:00:13:82 + "http://example.com" + 0d
    try testing.expectEqual(@as(usize, 24), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0xc7), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x13), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x82), bytes[4]); // Data
    try testing.expectEqual(@as(u8, 0x0d), bytes[23]); // Checksum

    inline for (5.., url) |i, byte| {
        try testing.expectEqual(@as(u8, byte), bytes[i]);
    }
}

test "MdcCommand - URL Too Long" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var long_url: [256]u8 = undefined;
    @memset(&long_url, 'a');

    const packet = Command.init(.{ .LauncherUrl = .{ .Set = &long_url } }, 0);
    try testing.expectError(mdc.Error.DataTooLong, packet.serialize(allocator));
}

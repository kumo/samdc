const std = @import("std");
const net = std.net;

pub const CommandType = enum(u8) {
    Power = 0x11,
    LauncherUrl = 0xC7,
};

pub const PowerData = union(enum) {
    Status, // No data needed for status query
    Set: bool, // true = on, false = off
};

pub const LauncherData = union(enum) {
    Status,
    Set: []const u8,
};

pub const Command = union(CommandType) {
    Power: PowerData,
    LauncherUrl: LauncherData,

    pub fn getCommandData(self: Command, allocator: std.mem.Allocator) ![]const u8 {
        // Determine the data to return
        const data = switch (self) {
            .Power => |power| switch (power) {
                .Status => &[_]u8{}, // Static empty slice
                .Set => |on| &[_]u8{if (on) 0x01 else 0x00}, // Static slice
            },
            .LauncherUrl => |launcher| switch (launcher) {
                .Status => &[_]u8{0x82}, // Static slice
                .Set => |url| return blk: {
                    var result = try allocator.alloc(u8, url.len + 1);
                    result[0] = 0x82;
                    @memcpy(result[1 .. url.len + 1], url);
                    break :blk result;
                },
            },
        };

        return allocator.dupe(u8, data);
    }
};

// MDC packet structure
pub const MdcPacket = struct {
    header: u8 = 0xAA, // Fixed header for MDC
    command: Command,
    display_id: u8 = 0,

    pub fn init(command: Command, display_id: u8) MdcPacket {
        return .{
            .command = command,
            .display_id = display_id,
        };
    }

    pub fn calculateChecksum(self: MdcPacket, data: []const u8) u8 {
        var sum: u32 = 0;

        // Sum all bytes except header and checksum
        sum += @intFromEnum(@as(CommandType, self.command));
        sum += self.display_id;
        sum += @as(u8, @intCast(data.len)); // Length byte

        // Add all data bytes
        for (data) |byte| {
            sum += byte;
        }

        // Discard anything over 256 (keep only the lowest byte)
        return @truncate(sum);
    }

    pub fn serialize(self: MdcPacket, allocator: std.mem.Allocator) ![]u8 {
        // Get the command data (may allocate memory)
        const data = try self.command.getCommandData(allocator);
        defer allocator.free(data);

        const total_length = 5 + data.len; // header + cmd + id + len + data + checksum

        var buffer = try allocator.alloc(u8, total_length);

        buffer[0] = self.header;
        buffer[1] = @intFromEnum(@as(CommandType, self.command));
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a TCP connection
    const address = try net.Address.parseIp4("127.0.0.1", 1515); // Default MDC port
    var stream = try net.tcpConnectToAddress(address);
    defer stream.close();

    // Example 1: Power Status Query (aa:11:00:00:11)
    {
        const packet = MdcPacket.init(.{ .Power = .Status }, 0);
        const bytes = try packet.serialize(allocator);
        defer allocator.free(bytes);

        std.debug.print("Power Status Query: ", .{});
        for (bytes) |byte| {
            std.debug.print("{x:0>2}:", .{byte});
        }
        std.debug.print("\n", .{});

        // Send the packet
        _ = try stream.write(bytes);

        // Read response
        var buffer: [1024]u8 = undefined;
        const bytes_read = try stream.read(&buffer);

        if (bytes_read > 0) {
            std.debug.print("Received response: ", .{});
            for (buffer[0..bytes_read]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
        }
        std.debug.print("\n", .{});
    }

    // Example 2: Power On Command (aa:11:00:01:01:13)
    {
        const packet = MdcPacket.init(.{ .Power = .{ .Set = true } }, 0);
        const bytes = try packet.serialize(allocator);
        defer allocator.free(bytes);

        std.debug.print("Power On Command: ", .{});
        for (bytes) |byte| {
            std.debug.print("{x:0>2}:", .{byte});
        }
        std.debug.print("\n", .{});

        // Send the packet
        _ = try stream.write(bytes);

        // Read response
        var buffer: [1024]u8 = undefined;
        const bytes_read = try stream.read(&buffer);

        if (bytes_read > 0) {
            std.debug.print("Received response: ", .{});
            for (buffer[0..bytes_read]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
        }
        std.debug.print("\n", .{});
    }

    // Example 3: Launcher URL Status Query (aa:c7:00:01:82:4a)
    {
        const packet = MdcPacket.init(.{ .LauncherUrl = .Status }, 0);
        const bytes = try packet.serialize(allocator);
        defer allocator.free(bytes);

        std.debug.print("Launcher URL Status Query: ", .{});
        for (bytes) |byte| {
            std.debug.print("{x:0>2}:", .{byte});
        }
        std.debug.print("\n", .{});

        // Send the packet
        _ = try stream.write(bytes);

        // Read response
        var buffer: [1024]u8 = undefined;
        const bytes_read = try stream.read(&buffer);

        if (bytes_read > 0) {
            std.debug.print("Received response: ", .{});
            for (buffer[0..bytes_read]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
        }
        std.debug.print("\n", .{});
    }

    // Example 4: Set Launcher URL (aa:c7:00:13:82 + "http://example.com" + checksum)
    {
        const url = "http://example.com";
        const packet = MdcPacket.init(.{ .LauncherUrl = .{ .Set = url } }, 0);
        const bytes = try packet.serialize(allocator);
        defer allocator.free(bytes);

        std.debug.print("Set Launcher URL: ", .{});
        for (bytes) |byte| {
            std.debug.print("{x:0>2}:", .{byte});
        }
        std.debug.print("\n", .{});

        // Send the packet
        _ = try stream.write(bytes);

        // Read response
        var buffer: [1024]u8 = undefined;
        const bytes_read = try stream.read(&buffer);

        if (bytes_read > 0) {
            std.debug.print("Received response: ", .{});
            for (buffer[0..bytes_read]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
        }
        std.debug.print("\n", .{});
    }
}

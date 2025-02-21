const std = @import("std");
const net = std.net;
const testing = std.testing;

pub const MdcError = error{
    PacketTooShort,
    InvalidResponseType,
    InvalidCommand,
    InvalidDataLength,
    InvalidChecksum,
    WrongCommandType,
    InvalidHeader,
    DataTooLong,
    BufferTooSmall,
};

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
                    if (url.len > 200) return MdcError.DataTooLong;

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

pub const ResponseType = enum(u8) {
    Ack = 0x41, // 'A'
    Nak = 0x4E, // 'N'
};

pub const Response = struct {
    response_type: ResponseType,
    command: CommandType,
    display_id: u8,
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn init(bytes: []const u8, allocator: std.mem.Allocator) !Response {
        // Header(1) + CommandType(1) + ResponseType(1) + Command(1) + DisplayID(1) + Length(1) + Checksum(1)
        const min_packet_size = 7;
        if (bytes.len < min_packet_size) return error.PacketTooShort;

        // Validate header and command type
        if (bytes[0] != 0xAA) return error.InvalidHeader;
        if (bytes[1] != 0xFF) return error.InvalidCommandType;

        // Extract data length and validate packet length
        const data_length = bytes[3];
        const expected_length = 5 + data_length;

        if (bytes.len != expected_length) return error.InvalidPacketLength;

        // Validate checksum (assuming last byte is checksum)
        const checksum = calculateChecksum(bytes[1 .. bytes.len - 1]);
        if (checksum != bytes[bytes.len - 1]) return error.InvalidChecksum;

        // Extract and allocate data portion
        var owned_data: []u8 = undefined;
        if (data_length > 0) {
            // Data starts at index 6
            owned_data = try allocator.dupe(u8, bytes[6 .. bytes.len - 1]);
        } else {
            owned_data = try allocator.alloc(u8, 0);
        }

        return Response{
            .response_type = std.meta.intToEnum(ResponseType, bytes[4]) catch return error.InvalidResponseType,
            .command = std.meta.intToEnum(CommandType, bytes[5]) catch return error.InvalidCommand,
            .display_id = bytes[2],
            .data = owned_data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.data);
    }

    fn calculateChecksum(bytes: []const u8) u8 {
        var sum: u8 = 0;
        for (bytes) |byte| {
            sum +%= byte; // Wrapping addition to simulate 8-bit overflow
        }
        return sum;
    }

    // Helper to parse power status response
    pub fn getPowerStatus(self: Response) !bool {
        if (self.command != .Power) return error.WrongCommandType;
        if (self.data.len < 1) return error.InvalidDataLength;
        return self.data[0] == 0x01;
    }

    // Helper to parse launcher URL response
    pub fn getLauncherUrl(self: Response) ![]const u8 {
        if (self.command != .LauncherUrl) return error.WrongCommandType;
        if (self.data.len < 1) return error.InvalidDataLength;
        // TODO: Handle the subcommand explicitly
        return self.data[1..self.data.len];
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

        var response = try Response.init(buffer[0..bytes_read], allocator);
        defer response.deinit();

        if (response.response_type == .Ack) {
            const is_on = try response.getPowerStatus();
            std.debug.print("Power is: {s}\n", .{if (is_on) "ON" else "OFF"});
        }
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

        var response = try Response.init(buffer[0..bytes_read], allocator);
        defer response.deinit();

        if (response.response_type == .Ack) {
            const url = try response.getLauncherUrl();
            std.debug.print("Launcher URL is: {s}\n", .{url});
        } else {
            std.debug.print("Launcher URL command was NAK", .{});
        }
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

test "MdcPacket - Power Status Query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const packet = MdcPacket.init(.{ .Power = .Status }, 0);
    const bytes = try packet.serialize(allocator);

    try testing.expectEqual(@as(usize, 5), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0x11), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x00), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x11), bytes[4]); // Checksum
}

test "MdcPacket - Power On Command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const packet = MdcPacket.init(.{ .Power = .{ .Set = true } }, 0);
    const bytes = try packet.serialize(allocator);

    try testing.expectEqual(@as(usize, 6), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0x11), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x01), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x01), bytes[4]); // Data (ON)
    try testing.expectEqual(@as(u8, 0x13), bytes[5]); // Checksum
}

test "MdcPacket - Launcher URL Status Query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const packet = MdcPacket.init(.{ .LauncherUrl = .Status }, 0);
    const bytes = try packet.serialize(allocator);

    try testing.expectEqual(@as(usize, 6), bytes.len);
    try testing.expectEqual(@as(u8, 0xAA), bytes[0]); // Header
    try testing.expectEqual(@as(u8, 0xc7), bytes[1]); // Power command
    try testing.expectEqual(@as(u8, 0x00), bytes[2]); // Display ID
    try testing.expectEqual(@as(u8, 0x01), bytes[3]); // Length
    try testing.expectEqual(@as(u8, 0x82), bytes[4]); // Data
    try testing.expectEqual(@as(u8, 0x4a), bytes[5]); // Checksum
}

test "MdcPacket - Launcher URL http://example.com Command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const url = "http://example.com";
    const packet = MdcPacket.init(.{ .LauncherUrl = .{ .Set = url } }, 0);
    const bytes = try packet.serialize(allocator);

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

test "Response - Parse Power Status" {
    const response_bytes = [_]u8{ 0xAA, 0xFF, 0x00, 0x03, 0x41, 0x11, 0x01, 0x55 };
    var response = try Response.init(&response_bytes, testing.allocator);
    defer response.deinit();

    try testing.expectEqual(ResponseType.Ack, response.response_type);
    try testing.expectEqual(CommandType.Power, response.command);
    try testing.expectEqual(@as(u8, 0x00), response.display_id);
    const is_on = try response.getPowerStatus();
    try testing.expect(is_on);
}

test "Response - Missing Headers" {
    const response_bytes = [_]u8{ 0x00, 0x00, 0x00, 0x03, 0x41, 0x11, 0x01, 0x00 }; // Wrong checksum
    try testing.expectError(MdcError.InvalidHeader, Response.init(&response_bytes, testing.allocator));
}

test "Response - Invalid Checksum" {
    const response_bytes = [_]u8{ 0xAA, 0xFF, 0x00, 0x03, 0x41, 0x11, 0x01, 0x00 }; // Wrong checksum
    try testing.expectError(MdcError.InvalidChecksum, Response.init(&response_bytes, testing.allocator));
}

test "Response - Packet Too Short" {
    const response_bytes = [_]u8{ 0xAA, 0xFF, 0x00, 0x41, 0x11, 0x00 }; // Too short
    try testing.expectError(MdcError.PacketTooShort, Response.init(&response_bytes, testing.allocator));
}

test "MdcPacket - URL Too Long" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var long_url: [256]u8 = undefined;
    @memset(&long_url, 'a');

    const packet = MdcPacket.init(.{ .LauncherUrl = .{ .Set = &long_url } }, 0);
    try testing.expectError(MdcError.DataTooLong, packet.serialize(allocator));
}

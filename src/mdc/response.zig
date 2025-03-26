const std = @import("std");
const net = std.net;
const testing = std.testing;

const mdc = @import("mod.zig");

pub const ResponseType = enum(u8) {
    Ack = 0x41, // 'A'
    Nak = 0x4E, // 'N'
};

pub const Response = struct {
    response_type: ResponseType,
    command: mdc.CommandType,
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
            .command = std.meta.intToEnum(mdc.CommandType, bytes[5]) catch return error.InvalidCommand,
            .display_id = bytes[2],
            .data = owned_data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.data);
    }

    // Format packet as hex string for debugging
    pub fn format(
        self: Response,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("MDC Response {{ ", .{});
        try writer.print("type: {s}, cmd: {s}, id: {d}, len: {d}, data: ", .{
            @tagName(self.response_type),
            @tagName(self.command),
            self.display_id,
            self.data.len,
        });

        // Format data as hex
        try writer.writeAll("[ ");
        for (self.data) |byte| {
            if (std.ascii.isPrint(byte)) {
                try writer.print("{X:0>2} ({c}) ", .{ byte, byte });
            } else {
                try writer.print("{X:0>2} ", .{byte});
            }
        }
        try writer.writeAll("] }}");
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

    // Helper to parse volume response
    pub fn getVolume(self: Response) !u8 {
        if (self.command != .Volume) return error.WrongCommandType;
        if (self.data.len < 1) return error.InvalidDataLength;
        return self.data[0];
    }
};

test "Response - Parse Power Status" {
    const response_bytes = [_]u8{ 0xAA, 0xFF, 0x00, 0x03, 0x41, 0x11, 0x01, 0x55 };
    var response = try Response.init(&response_bytes, testing.allocator);
    defer response.deinit();

    try testing.expectEqual(ResponseType.Ack, response.response_type);
    try testing.expectEqual(mdc.CommandType.Power, response.command);
    try testing.expectEqual(@as(u8, 0x00), response.display_id);
    const is_on = try response.getPowerStatus();
    try testing.expect(is_on);
}

test "Response - Missing Headers" {
    const response_bytes = [_]u8{ 0x00, 0x00, 0x00, 0x03, 0x41, 0x11, 0x01, 0x00 }; // Wrong checksum
    try testing.expectError(mdc.Error.InvalidHeader, Response.init(&response_bytes, testing.allocator));
}

test "Response - Invalid Checksum" {
    const response_bytes = [_]u8{ 0xAA, 0xFF, 0x00, 0x03, 0x41, 0x11, 0x01, 0x00 }; // Wrong checksum
    try testing.expectError(mdc.Error.InvalidChecksum, Response.init(&response_bytes, testing.allocator));
}

test "Response - Packet Too Short" {
    const response_bytes = [_]u8{ 0xAA, 0xFF, 0x00, 0x41, 0x11, 0x00 }; // Too short
    try testing.expectError(mdc.Error.PacketTooShort, Response.init(&response_bytes, testing.allocator));
}

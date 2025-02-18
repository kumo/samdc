const std = @import("std");
const net = std.net;

// MDC packet structure
const MdcPacket = struct {
    header: u8 = 0xAA, // Fixed header for MDC
    command: u8,
    display_id: u8 = 0,
    data: []const u8,

    pub fn init(command: u8, display_id: u8, data: []const u8) MdcPacket {
        return MdcPacket{
            .command = command,
            .display_id = display_id,
            .data = data,
        };
    }

    pub fn calculateChecksum(self: MdcPacket) u8 {
        var sum: u32 = 0;

        // Sum all bytes except header and checksum
        sum += self.command;
        sum += self.display_id;
        sum += @as(u8, @intCast(self.data.len)); // Length byte

        // Add all data bytes
        for (self.data) |byte| {
            sum += byte;
        }

        // Discard anything over 256 (keep only the lowest byte)
        return @as(u8, @truncate(sum));
    }

    pub fn serialize(self: MdcPacket, allocator: std.mem.Allocator) ![]u8 {
        const data_length = @as(u8, @intCast(self.data.len));
        const total_length = 5 + self.data.len; // header + command + id + length + data + checksum

        var buffer = try allocator.alloc(u8, total_length);

        buffer[0] = self.header;
        buffer[1] = self.command;
        buffer[2] = self.display_id;
        buffer[3] = data_length;

        // Copy data if any
        if (data_length > 0) {
            @memcpy(buffer[4..][0..data_length], self.data);
        }

        // Calculate and append checksum
        buffer[total_length - 1] = self.calculateChecksum();

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
        var packet = MdcPacket.init(0x11, 0x00, &[_]u8{});
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
        var packet = MdcPacket.init(0x11, 0x00, &[_]u8{0x01});
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

    // Example 3: Set Launcher URL (aa:c7:00:13:82 + "http://example.com" + checksum)
    {
        const url = "http://example.com";
        var packet = MdcPacket.init(0xC7, 0x00, &[_]u8{0x82} ++ url);
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

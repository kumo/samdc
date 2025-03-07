const std = @import("std");
const net = std.net;
const testing = std.testing;

const MdcCommand = @import("command.zig").MdcCommand;
const MdcResponse = @import("response.zig").MdcResponse;

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
        const packet = MdcCommand.init(.{ .Power = .Status }, 0);
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

        var response = try MdcResponse.init(buffer[0..bytes_read], allocator);
        defer response.deinit();

        if (response.response_type == .Ack) {
            const is_on = try response.getPowerStatus();
            std.debug.print("Power is: {s}\n", .{if (is_on) "ON" else "OFF"});
        }
    }

    // Example 2: Power On Command (aa:11:00:01:01:13)
    {
        const packet = MdcCommand.init(.{ .Power = .{ .Set = true } }, 0);
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
        const packet = MdcCommand.init(.{ .LauncherUrl = .Status }, 0);
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

        var response = try MdcResponse.init(buffer[0..bytes_read], allocator);
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
        const packet = MdcCommand.init(.{ .LauncherUrl = .{ .Set = url } }, 0);
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

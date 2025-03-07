const std = @import("std");
const net = std.net;
const testing = std.testing;

const MdcClient = @import("client.zig").MdcClient;
const MdcCommand = @import("command.zig").MdcCommand;
const MdcResponse = @import("response.zig").MdcResponse;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a TCP connection
    const address = try net.Address.parseIp4("127.0.0.1", 1515); // Default MDC port

    var client = try MdcClient.init(allocator, address, 0); // Default Display ID
    defer client.deinit();

    // Example 1: Power Status Query (aa:11:00:00:11)
    {
        const is_on = try client.getPowerStatus();
        std.debug.print("Power status: {s}\n", .{if (is_on) "ON" else "OFF"});
    }

    // Example 2: Power On Command (aa:11:00:01:01:13)
    {
        try client.setPower(true);
        std.debug.print("Power On Command: ", .{});
    }

    // Example 3: Launcher URL Status Query (aa:c7:00:01:82:4a)
    {
        const url = try client.getLauncherUrl();
        defer allocator.free(url);

        std.debug.print("Launcher URL is: {s}\n", .{url});
    }

    // Example 4: Set Launcher URL (aa:c7:00:13:82 + "http://example.com" + 0d)
    {
        const url = "http://example.com";
        try client.setLauncherUrl(url);
        std.debug.print("Set URL Command: ", .{});
    }
}

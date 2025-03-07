const std = @import("std");
const net = std.net;
const testing = std.testing;

const cli = @import("cli.zig");
const MdcClient = @import("client.zig").MdcClient;
const MdcCommand = @import("command.zig").MdcCommand;
const MdcResponse = @import("response.zig").MdcResponse;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var display = cli.Display.init();

    // Parse command line arguments
    const config = cli.Config.fromArgs(allocator) catch |err| {
        display.showError(err);
        return;
    };

    var client = MdcClient.init(allocator, config.address, 0); // Default Display ID
    defer client.deinit();

    display.showExamples(&client, allocator) catch |err| {
        display.showError(err);
        return;
    };
}

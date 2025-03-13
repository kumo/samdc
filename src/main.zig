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

    switch (config.action) {
        .demo => {
            display.showExamples(&client, allocator) catch |err| {
                display.showError(err);
                return;
            };
        },
        .wake => {
            client.setPower(true) catch |err| {
                display.showError(err);
            };
        },
        .sleep => {
            client.setPower(false) catch |err| {
                display.showError(err);
            };
        },
        .reboot => {
            client.reboot() catch |err| {
                display.showError(err);
            };
        },
        else => {},
    }
}

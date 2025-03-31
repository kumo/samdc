const std = @import("std");
const net = std.net;

const mdc = @import("mod.zig");
const Connection = @import("../net/connection.zig").Connection;

const log = std.log.scoped(.client);

pub const Client = struct {
    allocator: std.mem.Allocator,
    conn: Connection,
    display_id: u8,
    verbose: bool,

    pub fn init(allocator: std.mem.Allocator, address: net.Address, display_id: u8, verbose: bool, timeout: u32) Client {
        return Client{
            .allocator = allocator,
            .conn = Connection.init(address, timeout),
            .display_id = display_id,
            .verbose = verbose,
        };
    }

    pub fn deinit(self: *Client) void {
        self.conn.deinit();
    }

    fn sendCommand(
        self: *Client,
        command: mdc.Command,
    ) !mdc.Response {
        try self.conn.connect();

        // Create command packet
        const cmd_packet = try command.serialize(self.allocator);
        defer self.allocator.free(cmd_packet);

        if (self.verbose) {
            log.debug("Command: {any}", .{command});
            printBytes(cmd_packet);
        }

        // Send the command
        _ = try self.conn.send(cmd_packet);

        // Read response
        var buffer: [1024]u8 = undefined;
        const bytes_read = try self.conn.receive(&buffer);

        // Parse the response, let caller deinit
        const response = try mdc.Response.init(buffer[0..bytes_read], self.allocator);

        if (self.verbose) {
            log.debug("Response: {any}", .{response});
            printBytes(buffer[0..bytes_read]);
        }

        // Check if response is NAK
        if (response.response_type == .Nak) {
            return mdc.Error.NakReceived;
        }

        return response;
    }

    // Power control
    pub fn getPowerStatus(self: *Client) !bool {
        const command = mdc.Command.init(.{ .Power = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        return response.getPowerStatus();
    }

    pub fn setPower(self: *Client, on: bool) !void {
        const command = if (on)
            mdc.Command.init(.{ .Power = .{ .Set = .On } }, self.display_id)
        else
            mdc.Command.init(.{ .Power = .{ .Set = .Off } }, self.display_id);
        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    pub fn reboot(self: *Client) !void {
        const command = mdc.Command.init(.{ .Power = .{ .Set = .Reboot } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    // Launcher URL
    pub fn setLauncherUrl(self: *Client, url: []const u8) !void {
        const command = mdc.Command.init(.{ .LauncherUrl = .{ .Set = url } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    pub fn getLauncherUrl(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .LauncherUrl = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        const url = try response.getLauncherUrl();
        return try self.allocator.dupe(u8, url);
    }

    // Volume control
    pub fn getVolume(self: *Client) !u8 {
        const command = mdc.Command.init(.{ .Volume = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        return response.getVolume();
    }

    pub fn setVolume(self: *Client, level: u8) !void {
        if (level > 100) return mdc.Error.InvalidParameter;

        const command = mdc.Command.init(.{ .Volume = .{ .Set = level } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }
};

fn printBytes(bytes: []u8) void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var string = std.ArrayList(u8).init(fba.allocator());

    // Format the bytes into the buffer
    string.appendSlice("[ ") catch return;
    for (bytes) |byte| {
        if (std.ascii.isPrint(byte)) {
            string.writer().print("{X:0>2} ({c}) ", .{ byte, byte }) catch return;
        } else {
            string.writer().print("{X:0>2} ", .{byte}) catch return;
        }
    }
    string.appendSlice("]") catch return;

    // Log the formatted string
    log.debug("{s}", .{string.items});
}

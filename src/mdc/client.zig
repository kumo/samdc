const std = @import("std");
const net = std.net;

const mdc = @import("mod.zig");
const cli = @import("../cli.zig");
const Connection = @import("../net/connection.zig").Connection;
const command_def = @import("command.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    conn: Connection,
    display_id: u8,
    display: *cli.Display,

    pub fn init(allocator: std.mem.Allocator, address: net.Address, display_id: u8, display: *cli.Display, timeout: u32) Client {
        return Client{
            .allocator = allocator,
            .conn = Connection.init(address, timeout),
            .display_id = display_id,
            .display = display,
        };
    }

    pub fn deinit(self: *Client) void {
        self.conn.deinit();
    }

    fn sendCommandAndLog(
        self: *Client,
        command: mdc.Command,
    ) !mdc.Response {
        try self.conn.connect();

        const raw_tx_bytes = try command.serialize(self.allocator);
        defer self.allocator.free(raw_tx_bytes);

        // Pass command struct and raw bytes to logCommand
        try self.display.logCommand(&command, raw_tx_bytes);

        _ = try self.conn.send(raw_tx_bytes);

        var buffer: [1024]u8 = undefined;
        const bytes_read = try self.conn.receive(&buffer);
        const raw_rx_bytes_slice = buffer[0..bytes_read];

        var response = try mdc.Response.init(raw_rx_bytes_slice, self.allocator);
        errdefer response.deinit();

        try self.display.logResponse(&response);

        if (response.response_type == .Nak) {
            // Clean up allocated memory before returning error
            response.deinit();
            return mdc.Error.NakReceived;
        }

        return response;
    }

    // Wrap sendCommandAndLog to handle errors and finalize result
    fn sendCommandAndFinalizeOnError(self: *Client, command: mdc.Command) !mdc.Response {
        const result = self.sendCommandAndLog(command);

        if (result) |response| {
            return response; // Return the successful response
        } else |err| {
            // Error case: Finalize the error here
            const final_result: cli.Display.FinalResult = .{ .Error = .{ .error_type = @errorName(err) } };
            self.display.finalizeResult(self.conn.address, final_result) catch |e| {
                std.debug.print("ERROR finalizing error display: {}\n", .{e});
            };
            return err; // Propagate the original error
        }
    }

    pub fn getPowerStatus(self: *Client) !bool {
        const command = mdc.Command.init(.{ .Power = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();

        const status = try response.getPowerStatus();
        return status;
    }

    pub fn showPowerStatus(self: *Client) void {
        const status = self.getPowerStatus() catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Power = status }) catch {};
    }

    pub fn setPower(self: *Client, on: bool) void {
        const cmd_data: command_def.CommandData = if (on)
            .{ .Power = .{ .Set = .On } }
        else
            .{ .Power = .{ .Set = .Off } };
        const command = mdc.Command.init(cmd_data, self.display_id);
        _ = self.sendCommandAndLog(command) catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch {};
    }

    pub fn reboot(self: *Client) void {
        const command = mdc.Command.init(.{ .Power = .{ .Set = .Reboot } }, self.display_id);
        _ = self.sendCommandAndLog(command) catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch {};
    }

    pub fn setLauncherUrl(self: *Client, url: []const u8) void {
        const command = mdc.Command.init(.{ .LauncherUrl = .{ .Set = url } }, self.display_id);
        _ = self.sendCommandAndLog(command) catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch {};
    }

    pub fn getLauncherUrl(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .LauncherUrl = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();

        const url_slice = try response.getLauncherUrl();
        const owned_url = try self.allocator.dupe(u8, url_slice);
        return owned_url;
    }

    pub fn showLauncherUrl(self: *Client) void {
        const url = self.getLauncherUrl() catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };
        defer self.allocator.free(url);

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Url = url }) catch {};
    }

    // Internal helper - just gets the value
    fn getVolume(self: *Client) !u8 {
        const command = mdc.Command.init(.{ .Volume = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();

        const volume = try response.getVolume();
        return volume;
    }

    // Public method - gets and displays the value
    pub fn showVolume(self: *Client) void {
        const volume = self.getVolume() catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Volume = volume }) catch {};
    }

    // Public method - sets the value
    pub fn setVolume(self: *Client, level: u8) void {
        if (level > 100) {
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = "InvalidParameter" } }) catch {};
            return;
        }

        const command = mdc.Command.init(.{ .Volume = .{ .Set = level } }, self.display_id);
        _ = self.sendCommandAndLog(command) catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch {};
    }

    // Internal helper - just gets the value
    fn getSerial(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .Serial = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();

        const serial_slice = try response.getSerial();
        const owned_serial = try self.allocator.dupe(u8, serial_slice);
        return owned_serial;
    }

    // Public method - gets and displays the value
    pub fn showSerial(self: *Client) void {
        const serial = self.getSerial() catch |err| {
            // Display error and return
            self.display.finalizeResult(self.conn.address, .{ .Error = .{ .error_type = @errorName(err) } }) catch {};
            return;
        };
        defer self.allocator.free(serial);

        // Display success
        self.display.finalizeResult(self.conn.address, .{ .Serial = serial }) catch {};
    }
};

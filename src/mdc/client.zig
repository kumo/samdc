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
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        defer response.deinit();
        const status = try response.getPowerStatus();
        // Call finalizeResult with the specific boolean status on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Power = status }) catch |e| {
            std.debug.print("ERROR finalizing power status display: {}\n", .{e});
        };
        return status;
    }

    pub fn setPower(self: *Client, on: bool) !void {
        const cmd_data: command_def.CommandData = if (on)
            .{ .Power = .{ .Set = .On } }
        else
            .{ .Power = .{ .Set = .Off } };
        const command = mdc.Command.init(cmd_data, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        defer response.deinit();
        // Call finalizeResult explicitly on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch |e| {
            std.debug.print("ERROR finalizing setPower display: {}\n", .{e});
        };
    }

    pub fn reboot(self: *Client) !void {
        const command = mdc.Command.init(.{ .Power = .{ .Set = .Reboot } }, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        defer response.deinit();
        // Call finalizeResult explicitly on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch |e| {
            std.debug.print("ERROR finalizing reboot display: {}\n", .{e});
        };
    }

    pub fn setLauncherUrl(self: *Client, url: []const u8) !void {
        const command = mdc.Command.init(.{ .LauncherUrl = .{ .Set = url } }, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        defer response.deinit();
        // Call finalizeResult explicitly on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch |e| {
            std.debug.print("ERROR finalizing setUrl display: {}\n", .{e});
        };
    }

    pub fn getLauncherUrl(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .LauncherUrl = .Status }, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        // Do NOT defer deinit yet, need url slice
        const url_slice = response.getLauncherUrl() catch |err| {
            response.deinit(); // Deinit before returning error
            // Error already finalized by sendCommandAndFinalizeOnError
            return err;
        };
        // Call finalizeResult with the specific URL slice on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Url = url_slice }) catch |e| {
            std.debug.print("ERROR finalizing url display: {}\n", .{e});
            // If display fails, still need to deinit response and try to return URL
        };
        // Duplicate the URL *after* finalizeResult has used the slice
        const owned_url = self.allocator.dupe(u8, url_slice) catch |err| {
            response.deinit();
            // If duplication fails, we can't return the URL
            return err;
        };
        response.deinit(); // Deinit now we have the owned copy
        return owned_url;
    }

    pub fn getVolume(self: *Client) !u8 {
        const command = mdc.Command.init(.{ .Volume = .Status }, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        defer response.deinit();
        const volume = try response.getVolume();
        // Call finalizeResult with the specific volume on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Volume = volume }) catch |e| {
            std.debug.print("ERROR finalizing volume display: {}\n", .{e});
        };
        return volume;
    }

    pub fn setVolume(self: *Client, level: u8) !void {
        if (level > 100) return mdc.Error.InvalidParameter;
        const command = mdc.Command.init(.{ .Volume = .{ .Set = level } }, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        defer response.deinit();
        // Call finalizeResult explicitly on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Success = {} }) catch |e| {
            std.debug.print("ERROR finalizing setVolume display: {}\n", .{e});
        };
    }

    pub fn getSerial(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .Serial = .Status }, self.display_id);
        // Use the modified error-finalizing wrapper
        var response = try self.sendCommandAndFinalizeOnError(command);
        // Do NOT defer deinit yet, need serial slice
        const serial_slice = response.getSerial() catch |err| {
            response.deinit();
            // Error already finalized by sendCommandAndFinalizeOnError
            return err;
        };
        // Call finalizeResult with the specific serial slice on SUCCESS
        self.display.finalizeResult(self.conn.address, .{ .Serial = serial_slice }) catch |e| {
            std.debug.print("ERROR finalizing serial display: {}\n", .{e});
        };
        // Duplicate the serial *after* finalizeResult has used the slice
        const owned_serial = self.allocator.dupe(u8, serial_slice) catch |err| {
            response.deinit();
            return err;
        };
        response.deinit();
        return owned_serial;
    }
};

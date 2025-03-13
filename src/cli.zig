const std = @import("std");
const MdcClient = @import("client.zig").MdcClient;

pub const CliError = error{
    InvalidArgCount,
    InvalidAddress,
    InvalidAction,
};

const Action = enum {
    demo,
    wake,
    sleep,
    reboot,
    unknown,

    pub fn fromString(s: []const u8) Action {
        const lookup = [_]struct { []const u8, Action }{
            .{ "demo", .demo },
            .{ "wake", .wake },
            .{ "sleep", .sleep },
            .{ "reboot", .reboot },
        };

        for (lookup) |entry| {
            if (std.mem.eql(u8, s, entry[0])) {
                return entry[1];
            }
        }
        return .unknown;
    }
};

pub const Config = struct {
    address: std.net.Address,
    action: Action,

    pub fn fromArgs(allocator: std.mem.Allocator) !Config {
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        if (args.len != 3) {
            return CliError.InvalidArgCount;
        }

        const action = Action.fromString(args[1]);

        if (action == .unknown) {
            return CliError.InvalidAction;
        }

        // Create address with default port
        const address = std.net.Address.parseIp4(args[2], 1515) catch {
            return CliError.InvalidAddress;
        };

        return Config{
            .address = address,
            .action = action,
        };
    }
};

pub const Display = struct {
    writer: std.fs.File.Writer,

    pub fn init() Display {
        return .{
            .writer = std.io.getStdOut().writer(),
        };
    }

    pub fn showExamples(self: Display, client: *MdcClient, allocator: std.mem.Allocator) !void {
        // Example 1: Power Status Query (aa:11:00:00:11)
        {
            const is_on = try client.getPowerStatus();
            try self.writer.print("Power status: {s}\n", .{if (is_on) "ON" else "OFF"});
        }

        // Example 2: Power On Command (aa:11:00:01:01:13)
        {
            try client.setPower(true);
            try self.writer.writeAll("Sent Power On Command");
        }

        // Example 3: Launcher URL Status Query (aa:c7:00:01:82:4a)
        {
            const url = try client.getLauncherUrl();
            defer allocator.free(url);

            try self.writer.print("Launcher URL is: {s}\n", .{url});
        }

        // Example 4: Set Launcher URL (aa:c7:00:13:82 + "http://example.com" + 0d)
        {
            const url = "http://example.com";
            try client.setLauncherUrl(url);
            try self.writer.writeAll("Sent URL Command");
        }
    }

    pub fn printUsage(self: Display) void {
        self.writer.writeAll("Usage: samdc <action> <ip>\n") catch {};
        self.writer.writeAll("Example: samdc reboot 192.168.1.1\n") catch {};
    }

    pub fn showError(self: Display, err: anyerror) void {
        switch (err) {
            error.InvalidArgCount => self.printUsage(),
            error.InvalidAddress => self.writer.writeAll("Invalid IP address\n") catch {},
            error.ConnectionRefused => self.writer.writeAll("Couldn't contact device: connection refused\n") catch {},
            error.InvalidAction => self.writer.writeAll("Invalid action\n") catch {},
            else => self.writer.print("Error: {}\n", .{err}) catch {},
        }
    }
};

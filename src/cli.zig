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
    volume,
    url,
    unknown,

    pub fn fromString(s: []const u8) Action {
        const lookup = [_]struct { []const u8, Action }{
            .{ "demo", .demo },
            .{ "wake", .wake },
            .{ "sleep", .sleep },
            .{ "reboot", .reboot },
            .{ "volume", .volume },
            .{ "url", .url },
        };

        for (lookup) |entry| {
            if (std.mem.eql(u8, s, entry[0])) {
                return entry[1];
            }
        }
        return .unknown;
    }
};

// Argument types for commands
pub const CommandArg = union(enum) {
    Integer: u32,
    String: []const u8,
    Boolean: bool,

    pub fn asBool(self: CommandArg) bool {
        return switch (self) {
            .Boolean => |b| b,
            .Integer => |i| i > 0,
            .String => |s| s.len > 0,
        };
    }

    pub fn asInteger(self: CommandArg) !u32 {
        return switch (self) {
            .Integer => |i| i,
            .String => |s| std.fmt.parseInt(u32, s, 10),
            .Boolean => |b| if (b) @as(u32, 1) else @as(u32, 0),
        };
    }

    pub fn asString(self: CommandArg, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .String => |s| s,
            .Integer => |i| {
                const buf = try allocator.alloc(u8, 20);
                return std.fmt.bufPrint(buf, "{d}", .{i});
            },
            .Boolean => |b| if (b) "true" else "false",
        };
    }
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    action: Action,
    addresses: std.ArrayList(std.net.Address),
    positional_args: std.ArrayList(CommandArg),

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .allocator = allocator,
            .action = .unknown,
            .addresses = std.ArrayList(std.net.Address).init(allocator),
            .positional_args = std.ArrayList(CommandArg).init(allocator),
        };
    }

    pub fn deinit(self: *Config) void {
        self.addresses.deinit();
        self.positional_args.deinit();
    }

    pub fn fromArgs(allocator: std.mem.Allocator) !Config {
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        if (args.len < 2) {
            return CliError.InvalidArgCount;
        }

        const action = Action.fromString(args[1]);
        if (action == .unknown) {
            return CliError.InvalidAction;
        }

        var config = Config.init(allocator);
        config.action = action;

        // Process remaining arguments
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            // Try to parse as IP address
            if (std.net.Address.parseIp4(arg, 1515)) |address| {
                try config.addresses.append(address);
                continue;
            } else |_| {}

            // Handle positional arguments
            // Try to parse as integer first
            if (std.fmt.parseInt(u32, arg, 10)) |int_val| {
                try config.positional_args.append(.{ .Integer = int_val });
            } else |_| {
                try config.positional_args.append(.{ .String = arg });
            }
        }

        // Ensure we have at least one address
        if (config.addresses.items.len == 0) {
            return CliError.InvalidAddress;
        }

        return config;
    }

    // Helper methods to get arguments
    pub fn getPositionalInteger(self: Config, index: usize) ?u32 {
        if (index < self.positional_args.items.len) {
            const arg = self.positional_args.items[index];
            return arg.asInteger() catch null;
        }
        return null;
    }

    pub fn getPositionalString(self: Config, index: usize) ?[]const u8 {
        if (index < self.positional_args.items.len) {
            const arg = self.positional_args.items[index];
            if (arg == .String) {
                return arg.String;
            }
        }
        return null;
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
        self.writer.writeAll("Usage: samdc <command> [args] [ip_addresses...]\n\n") catch {};
        self.writer.writeAll("Commands:\n") catch {};
        self.writer.writeAll("  demo            Run a demo sequence\n") catch {};
        self.writer.writeAll("  wake            Turn on the display\n") catch {};
        self.writer.writeAll("  sleep           Turn off the display\n") catch {};
        self.writer.writeAll("  reboot          Reboot the display\n") catch {};
        self.writer.writeAll("  volume [level]  Get or set volume level (0-100)\n") catch {};
        self.writer.writeAll("  url [value]     Get or set launcher URL\n") catch {};
        self.writer.writeAll("\nExamples:\n") catch {};
        self.writer.writeAll("  samdc reboot 192.168.1.1                  # Reboot single display\n") catch {};
        self.writer.writeAll("  samdc wake 192.168.1.1 192.168.1.2        # Wake multiple displays\n") catch {};
        self.writer.writeAll("  samdc volume 50 192.168.1.1 192.168.1.2   # Set volume on multiple displays\n") catch {};
        self.writer.writeAll("  samdc url http://example.com 192.168.1.1  # Set URL on a display\n") catch {};
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

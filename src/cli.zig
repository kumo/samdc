const std = @import("std");
const testing = std.testing;

const mdc = @import("mdc/mod.zig");

pub const CliError = error{
    InvalidArgCount,
    InvalidAddress,
    InvalidAction,
    InvalidFlag,
};

const Action = enum {
    on,
    off,
    reboot,
    volume,
    url,
    help,
    version,
    unknown,

    pub fn fromString(s: []const u8) Action {
        const lookup = [_]struct { []const u8, Action }{
            .{ "on", .on },
            .{ "off", .off },
            .{ "reboot", .reboot },
            .{ "volume", .volume },
            .{ "url", .url },
            .{ "help", .help },
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
            .String => |s| std.fmt.parseInt(u32, s, 10) catch return error.InvalidInteger,
            .Boolean => |b| if (b) @as(u32, 1) else @as(u32, 0),
        };
    }

    pub fn asString(self: CommandArg, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .String => |s| s,
            .Integer => |i| {
                // Caller must free this buffer
                const buf = try allocator.alloc(u8, 20);
                errdefer allocator.free(buf);
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
    verbose: bool = false,
    timeout: u32 = 5,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .allocator = allocator,
            .action = .unknown,
            .addresses = std.ArrayList(std.net.Address).init(allocator),
            .positional_args = std.ArrayList(CommandArg).init(allocator),
            .verbose = false,
            .timeout = 5,
        };
    }

    pub fn deinit(self: *Config) void {
        self.addresses.deinit();
        // Free any string arguments
        for (self.positional_args.items) |arg| {
            if (arg == .String) {
                self.allocator.free(arg.String);
            }
        }
        self.positional_args.deinit();
    }

    pub fn fromArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
        if (args.len < 2) {
            return CliError.InvalidArgCount;
        }

        var config = Config.init(allocator);
        errdefer config.deinit();

        // Process arguments starting from index 1 (skip program name)
        var i: usize = 1; // Start from 1 instead of 0
        while (i < args.len) : (i += 1) {
            const arg = args[i]; // arg is now correctly []const u8

            // Handle flags - use 'arg' directly, not 'arg[0]'
            if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.eql(u8, arg, "--help")) {
                    config.action = .help;
                    return config;
                } else if (std.mem.eql(u8, arg, "--verbose")) {
                    config.verbose = true;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    config.action = .version;
                    return config;
                } else if (std.mem.eql(u8, arg, "--timeout")) {
                    // Check if a value exists after the flag
                    if (i + 1 >= args.len) {
                        std.log.warn("Missing value for --timeout flag", .{});
                        return CliError.InvalidFlag;
                    }
                    const timeout_str = args[i + 1];
                    // Try parsing, mapping errors to InvalidFlag
                    const parsed_timeout = std.fmt.parseInt(u32, timeout_str, 10) catch |err| {
                        std.log.warn("Invalid value for --timeout flag: '{s}' ({s})", .{ timeout_str, @errorName(err) });
                        return CliError.InvalidFlag;
                    };

                    // Validate the parsed value (must be > 0)
                    if (parsed_timeout == 0) {
                        std.log.warn("Timeout value must be greater than zero, got {d}", .{parsed_timeout});
                        return CliError.InvalidFlag;
                    }

                    // Validate upper bound
                    if (parsed_timeout > 120) {
                        std.log.warn("Timeout value must be less than 120 seconds, got {d}", .{parsed_timeout});
                        return CliError.InvalidFlag;
                    }

                    config.timeout = parsed_timeout;
                    i += 1; // Consume the value argument as well
                } else {
                    return CliError.InvalidFlag;
                }
                continue;
            }

            // Handle short flags - use 'arg' directly
            if (std.mem.startsWith(u8, arg, "-")) {
                if (std.mem.eql(u8, arg, "-h")) {
                    config.action = .help;
                    return config;
                } else if (std.mem.eql(u8, arg, "-v")) {
                    config.verbose = true;
                } else {
                    return CliError.InvalidFlag;
                }
                continue;
            }

            // First non-flag argument is the action - use 'arg' directly
            if (config.action == .unknown) {
                config.action = Action.fromString(arg);
                if (config.action == .unknown) {
                    return CliError.InvalidAction;
                }
                continue;
            }

            // Try to parse as IP address - use 'arg' directly
            if (std.net.Address.parseIp4(arg, 1515)) |address| {
                try config.addresses.append(address);
                continue;
            } else |_| {}

            // Handle positional arguments
            // Try to parse as integer first - use 'arg' directly
            if (std.fmt.parseInt(u32, arg, 10)) |int_val| {
                try config.positional_args.append(.{ .Integer = int_val });
            } else |_| {
                // Make a copy of the string - use 'arg' directly
                const str_copy = try allocator.dupe(u8, arg);
                // errdefer allocator.free(str_copy); // Keep errdefer for the dupe call itself
                // Important: The 'errdefer' for freeing str_copy should remain here
                // in case the *subsequent* append call fails.
                // If fromArgs itself fails later, config.deinit() handles freeing.
                errdefer allocator.free(str_copy);
                try config.positional_args.append(.{ .String = str_copy });
            }
        }

        if (config.action == .unknown) {
            return CliError.InvalidAction;
        }

        // Ensure we have at least one address for non-special actions
        if (config.action != .help and config.action != .version and config.addresses.items.len == 0) {
            return CliError.InvalidAddress;
        }

        return config;
    }

    // Helper methods to get arguments
    pub fn getPositionalInteger(self: Config, index: usize) ?u32 {
        if (index < self.positional_args.items.len) {
            const arg = self.positional_args.items[index];
            return arg.asInteger() catch |err| {
                std.log.err("Integer conversion error: {}", .{err});
                return null;
            };
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
    const VERSION = "0.1.2";

    pub fn init() Display {
        return .{
            .writer = std.io.getStdOut().writer(),
        };
    }

    pub fn showVersion(self: Display) void {
        self.writer.print("samdc version {s}\n", .{VERSION}) catch {};
    }

    pub fn printUsage(self: Display) void {
        self.writer.writeAll("Usage: samdc [options] <command> [args] [ip_addresses...]\n\n") catch {};
        self.writer.writeAll("Options:\n") catch {};
        self.writer.writeAll("  -h, --help     Show this help message\n") catch {};
        self.writer.writeAll("  -v, --version  Show version information\n") catch {};
        self.writer.writeAll("  --verbose      Enable verbose output\n") catch {};
        self.writer.writeAll("  --timeout      Set timeout in seconds (default 5)\n\n") catch {};
        self.writer.writeAll("Commands:\n") catch {};
        self.writer.writeAll("  on              Turn on the device\n") catch {};
        self.writer.writeAll("  off             Turn off the display\n") catch {};
        self.writer.writeAll("  reboot          Reboot the display\n") catch {};
        self.writer.writeAll("  volume [level]  Get or set volume level (0-100)\n") catch {};
        self.writer.writeAll("  url [value]     Get or set launcher URL\n") catch {};
        self.writer.writeAll("\nExamples:\n") catch {};
        self.writer.writeAll("  samdc reboot 192.168.1.1                  # Reboot single display\n") catch {};
        self.writer.writeAll("  samdc on 192.168.1.1 192.168.1.2          # Turn on multiple displays\n") catch {};
        self.writer.writeAll("  samdc volume 50 192.168.1.1 192.168.1.2   # Set volume on multiple displays\n") catch {};
        self.writer.writeAll("  samdc url http://example.com 192.168.1.1  # Set URL on a display\n") catch {};
    }

    pub fn showError(self: Display, err: anyerror) void {
        switch (err) {
            error.InvalidArgCount => self.printUsage(),
            error.InvalidAddress => std.log.err("Invalid IP address", .{}),
            error.ConnectionRefused => std.log.err("Couldn't contact device: connection refused", .{}),
            error.InvalidAction => std.log.err("Invalid action", .{}),
            error.InvalidFlag => std.log.err("Invalid flag", .{}),
            else => std.log.err("Operation failed: {}", .{err}),
        }
    }
};

test "Parse simple command" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "on", "192.168.1.10" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.on, config.action);
    try testing.expectEqual(@as(usize, 1), config.addresses.items.len);
    const expected_addr = try std.net.Address.parseIp4("192.168.1.10", 1515);
    try testing.expect(expected_addr.eql(config.addresses.items[0]));
    try testing.expectEqual(@as(usize, 0), config.positional_args.items.len);
    try testing.expectEqual(false, config.verbose);
}

test "Parse command with numeric arg" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "volume", "75", "10.0.0.1" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.volume, config.action);
    try testing.expectEqual(@as(usize, 1), config.addresses.items.len);
    const expected_addr = try std.net.Address.parseIp4("10.0.0.1", 1515);
    try testing.expect(expected_addr.eql(config.addresses.items[0]));
    try testing.expectEqual(@as(usize, 1), config.positional_args.items.len);
    const vol_arg = config.positional_args.items[0];
    try testing.expectEqualStrings("Integer", @tagName(vol_arg));
    try testing.expectEqual(@as(u32, 75), try vol_arg.asInteger());
    try testing.expectEqual(false, config.verbose);
}

test "Parse command with text arg" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "url", "http://example.com", "10.0.0.1" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit(); // deinit will free the duped string

    try testing.expectEqual(Action.url, config.action);
    try testing.expectEqual(@as(usize, 1), config.addresses.items.len);
    const expected_addr = try std.net.Address.parseIp4("10.0.0.1", 1515);
    try testing.expect(expected_addr.eql(config.addresses.items[0]));
    try testing.expectEqual(@as(usize, 1), config.positional_args.items.len);
    const url_arg = config.positional_args.items[0];
    try testing.expectEqualStrings("String", @tagName(url_arg));
    try testing.expectEqualStrings("http://example.com", url_arg.String);
    try testing.expectEqual(false, config.verbose);
}

test "Parse simple command with multiple IPs" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "off", "192.168.1.10", "192.168.1.11" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.off, config.action);
    try testing.expectEqual(@as(usize, 2), config.addresses.items.len);
    const expected_addr1 = try std.net.Address.parseIp4("192.168.1.10", 1515);
    const expected_addr2 = try std.net.Address.parseIp4("192.168.1.11", 1515);
    try testing.expect(expected_addr1.eql(config.addresses.items[0]));
    try testing.expect(expected_addr2.eql(config.addresses.items[1]));
    try testing.expectEqual(@as(usize, 0), config.positional_args.items.len);
    try testing.expectEqual(false, config.verbose);
}

test "Parse command with verbose flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--verbose", "on", "192.168.1.10" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.on, config.action);
    try testing.expectEqual(true, config.verbose);
}

test "Parse command with short verbose flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "-v", "on", "192.168.1.10" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.on, config.action);
    try testing.expectEqual(true, config.verbose);
}

test "Parse help flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--help" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.help, config.action);
}

test "Parse short help flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "-h" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.help, config.action);
}

test "Help flag should take precendence" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "on", "192.168.1.1", "--help" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.help, config.action);
}

test "Parse version flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--version" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.version, config.action);
}

test "Parse invalid action" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "invalidaction", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAction, result);
}

test "Parse invalid flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--invalidflag", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse invalid short flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "-x", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse missing ip address (for non-help/version)" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "on" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAddress, result);
}

test "Parse missing action" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAction, result);
}

test "Parse flag without action" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--verbose" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAction, result);
}

test "Parse no arguments" {
    const allocator = testing.allocator;

    const args1 = [_][]const u8{"samdc"};
    const result1 = Config.fromArgs(allocator, &args1);
    try testing.expectError(CliError.InvalidArgCount, result1);
}

test "Parse mixed positional args and addresses" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "url", "http://a.com", "10.0.0.1", "some_string", "50", "10.0.0.2" };
    // Parses as: action=url, pos="http://a.com", addr=10.0.0.1, pos="some_string", pos=50, addr=10.0.0.2
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.url, config.action);
    try testing.expectEqual(@as(usize, 2), config.addresses.items.len);
    const expected_addr1 = try std.net.Address.parseIp4("10.0.0.1", 1515);
    const expected_addr2 = try std.net.Address.parseIp4("10.0.0.2", 1515);
    try testing.expect(expected_addr1.eql(config.addresses.items[0]));
    try testing.expect(expected_addr2.eql(config.addresses.items[1]));

    try testing.expectEqual(@as(usize, 3), config.positional_args.items.len);
    // arg 0: "http://a.com" (String)
    const arg0 = config.positional_args.items[0];
    try testing.expectEqualStrings("String", @tagName(arg0));
    try testing.expectEqualStrings("http://a.com", arg0.String);
    // arg 1: "some_string" (String)
    const arg1 = config.positional_args.items[1];
    try testing.expectEqualStrings("String", @tagName(arg1));
    try testing.expectEqualStrings("some_string", arg1.String);
    // arg 2: 50 (Integer)
    const arg2 = config.positional_args.items[2];
    try testing.expectEqualStrings("Integer", @tagName(arg2));
    try testing.expectEqual(@as(u32, 50), try arg2.asInteger());
}

test "Parse timeout flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "10", "on", "192.168.1.1" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(10, config.timeout);
}

test "Parse timeout flag with non-integer value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "not_an_integer", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag with negative value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "-1", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag with zero value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "0", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag with large value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "1000000", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag without a value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

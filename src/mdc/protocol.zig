pub const Error = error{
    PacketTooShort,
    InvalidResponseType,
    InvalidCommand,
    InvalidDataLength,
    InvalidChecksum,
    WrongCommandType,
    InvalidHeader,
    DataTooLong,
    NakReceived,
    InvalidParameter,
};

pub const CommandType = enum(u8) {
    Power = 0x11,
    LauncherUrl = 0xC7,
    Volume = 0x12,
    Serial = 0x0B,
};

// Shared constants for the MDC Protocol
pub const Constants = struct {
    pub const HEADER: u8 = 0xAA;
    pub const RESPONSE_MARKER: u8 = 0xFF;
    pub const MINIMUM_COMMAND_LENGTH: usize = 5; // header + cmd + id + len + checksum
    pub const MINIMUM_RESPONSE_LENGTH: usize = 7; // header + FF + id + len + ack/nak + cmd + checksum
    pub const MAX_DATA_LENGTH: usize = 200; // Max length of the 'data' portion

    pub const ACK: u8 = 'A'; // 0x41
    pub const NAK: u8 = 'N'; // 0x4E
};

// Subcommand definitions for different command types
pub const Subcommands = struct {
    pub const Power = struct {
        pub const OFF: u8 = 0x00;
        pub const ON: u8 = 0x01;
        pub const REBOOT: u8 = 0x02;
    };

    pub const Launcher = struct {
        pub const URL: u8 = 0x82;
    };
};

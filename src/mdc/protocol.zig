pub const Error = error{
    PacketTooShort,
    InvalidResponseType,
    InvalidCommand,
    InvalidDataLength,
    InvalidChecksum,
    WrongCommandType,
    InvalidHeader,
    DataTooLong,
    BufferTooSmall,
    ReceiveFailed,
    NakReceived,
    ConnectionFailed,
    InvalidParameter,
};

pub const CommandType = enum(u8) {
    Power = 0x11,
    LauncherUrl = 0xC7,
    Volume = 0x12,
};

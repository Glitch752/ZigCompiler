const std = @import("std");
const pretty_error = @import("main.zig").pretty_error;

const ArgsFlags = struct { debug_tokens: bool };
const Args = struct {
    file_path: []const u8,
    flags: ArgsFlags,

    allocator: std.mem.Allocator,
    pub fn deinit(self: *const Args) void {
        self.allocator.free(self.file_path);
    }
};

const ArgParseError = error{ NoFileProvided, MultiplePathsProvided };

pub fn parse(allocator: std.mem.Allocator) !Args {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var file_path: ?[]u8 = null;
    var flags = ArgsFlags{ .debug_tokens = false };

    // Skip the first argument, which is the program name
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--debug-tokens")) {
            flags.debug_tokens = true;
        } else {
            if (file_path != null) {
                try pretty_error("Multiple file paths provided\n");
                return ArgParseError.MultiplePathsProvided;
            }

            file_path = arg;
        }
    }

    if (file_path == null) {
        try pretty_error(try std.fmt.allocPrint(allocator, "Usage: {s} <file>\n", .{ .name_string = args[0] }));
        return ArgParseError.NoFileProvided;
    }

    // Clone file_path into a new buffer
    const cloned_file_path: []u8 = try allocator.alloc(u8, file_path.?.len);
    std.mem.copyForwards(u8, cloned_file_path, file_path.?);

    return Args{ .file_path = cloned_file_path, .flags = flags, .allocator = allocator };
}
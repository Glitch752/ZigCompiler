const std = @import("std");
const io = @import("std").io;
const TokenData = @import("token.zig").TokenData;
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

const Tokenizer = @This();

buffer: []u8,
line: u32,
column: u32,
position: u32,

pub fn init(buffer: []u8) Tokenizer {
    return .{ .buffer = buffer, .line = 1, .column = 1, .position = 0 };
}

pub fn getNext(self: *Tokenizer, allocator: std.mem.Allocator) !TokenData {
    while (self.position < self.buffer.len) {
        // Read the next character
        const c = self.buffer[self.position];
        self.position += 1;

        // First, skip whitespace
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }

            continue;
        }

        // Next, handle comments
        if (c == '/') {
            if (self.buffer[self.position] == '/') {
                // Skip to the end of the line
                while (self.buffer[self.position] != '\n') {
                    self.position += 1;
                }
                self.line += 1;
                self.column = 1;
                continue;
            } else if (self.buffer[self.position] == '*') {
                // Skip to the end of the block comment
                while (self.buffer[self.position] != '*' or self.buffer[self.position + 1] != '/') {
                    if (self.buffer[self.position] == '\n') {
                        self.line += 1;
                        self.column = 1;
                    } else {
                        self.column += 1;
                    }
                    self.position += 1;
                }
                self.position += 2;
                continue;
            }
        }

        // Next, keywords
        if (std.ascii.isAlphanumeric(c)) {
            var keyword = try allocator.alloc(u8, 1);
            keyword[0] = c;
            var i: u16 = 1;
            while (std.ascii.isAlphanumeric(self.buffer[self.position])) {
                keyword = try allocator.realloc(keyword, i + 1);
                keyword[i] = self.buffer[self.position];
                i += 1;

                self.position += 1;
                self.column = 1;
            }

            // Print keyword
            std.debug.print("{s}\n", .{keyword});

            const token = Token.keyword_map.get(keyword);
            if (token != null) {
                allocator.free(keyword);
                return .{ .token = token.?, .line = self.line, .column = self.column };
            }

            // If it's not a keyword, it's an identifier
            return .{ .token = Token{ .Identifier = keyword }, .line = self.line, .column = self.column };
        }

        // Next, numbers
        if (std.ascii.isDigit(c)) {
            var number: u64 = 0;
            while (std.ascii.isDigit(self.buffer[self.position])) {
                number = number * 10 + (self.buffer[self.position] - '0');
                self.position += 1;
                self.column = 1;
            }

            return .{ .token = Token{ .IntLiteral = number }, .line = self.line, .column = self.column };
        }

        // Next, strings
        if (c == '"' or c == '\'') {
            const start = self.position;
            while (self.buffer[self.position] != c) {
                self.position += 1;
                self.column = 1;
                if (self.buffer[self.position] == '\n') {
                    self.line += 1;
                    self.column = 1;
                }
            }
            self.position += 1;

            const allocatedString = try allocator.alloc(u8, self.position - start);
            return .{ .token = Token{ .StringLiteral = allocatedString }, .line = self.line, .column = self.column };
        }

        // Then, temporarily, print the character.
        std.debug.print("{u}", .{c});
    }

    return .{ .token = Token.EOF, .line = self.line, .column = self.column };
}

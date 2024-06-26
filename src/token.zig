const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens
    OpenParen, // (
    CloseParen, // )
    OpenCurly, // {
    CloseCurly, // }
    Semicolon, // ;

    LessThan,
    LessThanEqual,
    GreaterThan,
    GreaterThanEqual,
    Equality, // ==
    NotEqual, // !=

    And, // &&
    Or, // ||

    Plus, // +
    Minus, // -
    Star, // *
    Slash, // /
    Percent, // %
    Negate, // !

    FunctionKeyword, // function
    ClassKeyword, // class

    SuperKeyword, // super
    ThisKeyword, // this
    ExtendingKeyword, // extending

    IfKeyword, // if
    ElseKeyword, // else
    ForKeyword, // for
    WhileKeyword, // while

    TrueKeyword, // true
    FalseKeyword, // false
    NullKeyword, // null

    ReturnKeyword, // return
    LetKeyword, // let

    // Literals
    NumberLiteral,
    StringLiteral,
    Identifier,

    Comma, // ,
    Dot, // .

    Assign, // =

    EOF,

    pub fn typeNameString(self: TokenType) []const u8 {
        return @tagName(self);
    }
};

pub const TokenLiteral = union(enum) {
    NumberLiteral: f64,
    StringLiteral: []const u8,
    Identifier: []const u8,

    False,
    True,
    Null,

    None,

    pub fn toString(self: TokenLiteral, allocator: std.mem.Allocator) ![]const u8 {
        switch (self) {
            .NumberLiteral => |number| return try std.fmt.allocPrint(allocator, "{d}", .{number}),
            .StringLiteral => |string| return try std.fmt.allocPrint(allocator, "{s}", .{string}),
            .Identifier => |identifier| return try std.fmt.allocPrint(allocator, "{s}", .{identifier}),
            .False => return try std.fmt.allocPrint(allocator, "False", .{}),
            .True => return try std.fmt.allocPrint(allocator, "True", .{}),
            .Null => return try std.fmt.allocPrint(allocator, "Null", .{}),
            .None => return try std.fmt.allocPrint(allocator, "None", .{}),
        }
    }
};

pub const Token = struct {
    type: TokenType,
    /// The actual text of the token.
    lexeme: []const u8,
    /// The literal value of the token, if applicable. Somewhat redundant with type, but I find it easier to write the parser when they're separate.
    literal: TokenLiteral,

    position: usize,

    pub fn init(@"type": TokenType, lexeme: []const u8, literal: TokenLiteral, position: usize) Token {
        return .{ .type = @"type", .lexeme = lexeme, .literal = literal, .position = position };
    }

    pub fn deinit(self: *const Token, allocator: std.mem.Allocator) void {
        switch (self.literal) {
            .StringLiteral => allocator.free(self.literal.StringLiteral),
            .Identifier => allocator.free(self.literal.Identifier),
            else => {},
        }
    }

    pub fn toString(self: *const Token, allocator: std.mem.Allocator) ![]const u8 {
        const literalString = try self.literal.toString(allocator);
        defer allocator.free(literalString);

        return try std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ self.type.typeNameString(), self.lexeme, literalString });
    }

    pub fn toCondensedString(self: *const Token, allocator: std.mem.Allocator) ![]const u8 {
        switch (self.literal) {
            .None => return try std.fmt.allocPrint(allocator, "{s} ", .{self.type.typeNameString()}),
            else => {},
        }
        const literalString = try self.literal.toString(allocator);
        defer allocator.free(literalString);
        return try std.fmt.allocPrint(allocator, "{s}({s}) ", .{ self.type.typeNameString(), literalString });
    }

    pub const keywordMap = std.ComptimeStringMap(TokenType, .{
        // This comment is to prevent zigfmt from collapsing the lines
        .{ "function", TokenType.FunctionKeyword },
        .{ "if", TokenType.IfKeyword },
        .{ "else", TokenType.ElseKeyword },
        .{ "for", TokenType.ForKeyword },
        .{ "return", TokenType.ReturnKeyword },
        .{ "let", TokenType.LetKeyword },
        .{ "while", TokenType.WhileKeyword },
        .{ "true", TokenType.TrueKeyword },
        .{ "false", TokenType.FalseKeyword },
        .{ "null", TokenType.NullKeyword },
        .{ "class", TokenType.ClassKeyword },
        .{ "super", TokenType.SuperKeyword },
        .{ "this", TokenType.ThisKeyword },
        .{ "extending", TokenType.ExtendingKeyword },
    });
    pub const symbolMap = std.ComptimeStringMap(TokenType, .{
        // This comment is to prevent zigfmt from collapsing the lines
        .{ "(", TokenType.OpenParen },
        .{ ")", TokenType.CloseParen },
        .{ "{", TokenType.OpenCurly },
        .{ "}", TokenType.CloseCurly },
        .{ ";", TokenType.Semicolon },
        .{ "<", TokenType.LessThan },
        .{ "<=", TokenType.LessThanEqual },
        .{ ">", TokenType.GreaterThan },
        .{ ">=", TokenType.GreaterThanEqual },
        .{ "=", TokenType.Assign },
        .{ "!=", TokenType.NotEqual },
        .{ "==", TokenType.Equality },
        .{ "+", TokenType.Plus },
        .{ "-", TokenType.Minus },
        .{ "*", TokenType.Star },
        .{ "/", TokenType.Slash },
        .{ "%", TokenType.Percent },
        .{ "&&", TokenType.And },
        .{ "||", TokenType.Or },
        .{ "!", TokenType.Negate },
        .{ ",", TokenType.Comma },
        .{ ".", TokenType.Dot },
    });
    pub const maxSymbolLength = symbolMap.kvs[symbolMap.kvs.len - 1].key.len;
};

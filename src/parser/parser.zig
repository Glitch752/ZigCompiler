const std = @import("std");

const TokenType = @import("../token.zig").TokenType;
const Token = @import("../token.zig").Token;
const TokenLiteral = @import("../token.zig").TokenLiteral;

const ArgsFlags = @import("../args_parser.zig").ArgsFlags;

const Program = @import("./program.zig").Program;
const Expression = @import("./expression.zig").Expression;
const Statement = @import("./statement.zig").Statement;
const ASTPrinter = @import("./ast_printer.zig").ASTPrinter;

const Parser = @This();

const prettyError = @import("../errors.zig").prettyError;
const errorContext = @import("../errors.zig").errorContext;

tokens: []Token,
current: usize = 0,

originalBuffer: []const u8,
fileName: []const u8,

allocator: std.mem.Allocator,
flags: ArgsFlags,

hasError: bool = false,

/// Errors in Zig can't hold payloads, so we separate the actual error data from the error type.
const ParseError = struct {
    @"error": union(enum) { ConsumeFailed: struct {
        string: []const u8,
        token: Token,
    } },

    fileName: []const u8,
    originalBuffer: []const u8,

    pub fn print(self: *const ParseError, allocator: std.mem.Allocator) void {
        switch (self.@"error") {
            .ConsumeFailed => |value| {
                const tokenString = value.token.toString(allocator) catch {
                    return;
                };
                defer allocator.free(tokenString);

                const errorMessage = std.fmt.allocPrint(allocator, "{s} at {s}", .{ value.string, tokenString }) catch {
                    return;
                };
                defer allocator.free(errorMessage);

                prettyError(errorMessage) catch {
                    return;
                };
                errorContext(self.originalBuffer, self.fileName, value.token.position, value.token.lexeme.len, allocator) catch {
                    return;
                };
            },
        }
    }

    pub fn consumeFailed(parser: *const Parser, string: []const u8, token: Token) ParseError {
        return .{ .@"error" = .{ .ConsumeFailed = .{ .string = string, .token = token } }, .fileName = parser.fileName, .originalBuffer = parser.originalBuffer };
    }
};

const ParseErrorEnum = error{
    Unknown,
};

pub fn init(tokens: []Token, fileName: []const u8, originalBuffer: []const u8, flags: ArgsFlags, allocator: std.mem.Allocator) !Parser {
    return .{ .tokens = tokens, .fileName = fileName, .originalBuffer = originalBuffer, .flags = flags, .allocator = allocator };
}

pub fn parse(self: *Parser) anyerror!Program {
    self.hasError = false;

    var program = Program.init(self.allocator);

    while (!self.isAtEnd()) {
        const declaration = self.consumeDeclarationAndSynchronize() orelse continue;
        try program.addStatement(declaration);
    }

    // We can't use matchToken here because it will detect we're at an EOF and return false
    if (self.peek().type != TokenType.EOF) {
        const err = ParseError.consumeFailed(self, "Expected EOF", self.peek());
        err.print(self.allocator);
        return ParseErrorEnum.Unknown;
    }

    return program;
}

pub fn parseExpression(self: *Parser) anyerror!*Expression {
    const expression = try self.consumeExpression();

    if (!self.isAtEnd()) {
        const err = ParseError.consumeFailed(self, "Expected EOF", self.peek());
        err.print(self.allocator);
        return ParseErrorEnum.Unknown;
    }

    return expression;
}

pub fn uninit(self: *Parser) void {
    _ = self;
}

/// Sets "hasError" to true and prints an error message on the current token.
/// If you want it to be an error that allows continued parsing of a statement, just don't reutrn anything (`_ = self.errorOccured("Error message")`).
fn errorOccured(self: *Parser, errorMessage: []const u8) void {
    const err = ParseError.consumeFailed(self, errorMessage, self.peek());
    err.print(self.allocator);
    self.hasError = true;
}

fn isAtEnd(self: *Parser) bool {
    return self.current >= self.tokens.len - 1; // -1 because the last token is always EOF
}

fn peek(self: *Parser) Token {
    return self.tokens[self.current];
}

fn peekPrevious(self: *Parser) Token {
    return self.tokens[self.current - 1];
}

fn advance(self: *Parser) Token {
    if (!self.isAtEnd()) {
        self.current += 1;
    }
    return self.peekPrevious();
}

fn matchToken(self: *Parser, @"type": TokenType) bool {
    if (self.isAtEnd()) {
        return false;
    }
    if (self.peek().type == @"type") {
        _ = self.advance();
        return true;
    }
    return false;
}

/// Attempts to consume a token of the given type. If the token is not of the given type, returns an error.
fn consume(self: *Parser, @"type": TokenType, errorMessage: []const u8) !Token {
    if (self.matchToken(@"type")) {
        return self.peekPrevious();
    }

    self.errorOccured(errorMessage);
    return ParseErrorEnum.Unknown;
}

//
// Grammar rules
//

fn consumeDeclarationAndSynchronize(self: *Parser) ?*Statement {
    return self.consumeDeclaration() catch {
        self.synchronize();
        return null;
    };
}

fn consumeDeclaration(self: *Parser) anyerror!*Statement {
    if (self.matchToken(TokenType.LetKeyword)) {
        return try self.consumeLetStatement();
    }

    return try self.consumeStatement();
}

fn consumeStatement(self: *Parser) anyerror!*Statement {
    if (self.matchToken(TokenType.OpenCurly)) {
        return try self.consumeBlockStatement();
    }

    return try self.consumeExpressionStatement();
}

fn consumeBlockStatement(self: *Parser) anyerror!*Statement {
    var statements = std.ArrayList(*Statement).init(self.allocator);

    while (!self.matchToken(TokenType.CloseCurly) and !self.isAtEnd()) {
        const statement = self.consumeDeclarationAndSynchronize() orelse continue;
        try statements.append(statement);
    }

    _ = try self.consume(TokenType.CloseCurly, "Expected '}' after a block statement.");

    return Statement.block(self.allocator, statements);
}

fn consumeLetStatement(self: *Parser) anyerror!*Statement {
    const name = try self.consume(TokenType.Identifier, "Expected variable name");
    const initializer = if (self.matchToken(TokenType.Assign))
        try self.consumeExpression()
    else
        try Expression.literal(self.allocator, TokenLiteral.Null);

    _ = try self.consume(TokenType.Semicolon, "Expected ';' after a variable declaration.");

    return Statement.let(self.allocator, name, initializer);
}

fn consumeExpressionStatement(self: *Parser) anyerror!*Statement {
    const expression = try self.consumeExpression();

    _ = try self.consume(TokenType.Semicolon, "Expected ';' after an expression statement.");

    return Statement.expression(self.allocator, expression);
}

// Expression parsing

fn consumeExpression(self: *Parser) anyerror!*Expression {
    return try self.consumeAssignment();
}

fn consumeAssignment(self: *Parser) anyerror!*Expression {
    const expression = try self.consumeEquality();

    if (self.matchToken(TokenType.Assign)) {
        // This is an assignment

        const equals = self.peekPrevious(); // Used for error reporting
        const value = try self.consumeAssignment();

        switch (expression.*) {
            .VariableAccess => {
                const variable = expression.VariableAccess.name;
                return Expression.variableAssignment(self.allocator, variable, value);
            },
            else => {},
        }

        const err = ParseError.consumeFailed(self, "Invalid assignment target", equals);
        err.print(self.allocator);
        return ParseErrorEnum.Unknown;
    }

    return expression;
}

fn consumeEquality(self: *Parser) anyerror!*Expression {
    var expression = try self.consumeComparison();

    while (self.matchToken(TokenType.NotEqual) or self.matchToken(TokenType.Equality)) {
        errdefer expression.uninit(self.allocator);

        const operator = self.peekPrevious();
        const right = try self.consumeComparison();
        expression = try Expression.binary(self.allocator, expression, operator, right);
    }

    return expression;
}

fn consumeComparison(self: *Parser) anyerror!*Expression {
    var expression = try self.consumeTerm();

    while (self.matchToken(TokenType.GreaterThan) or
        self.matchToken(TokenType.GreaterThanEqual) or
        self.matchToken(TokenType.LessThan) or
        self.matchToken(TokenType.LessThanEqual))
    {
        errdefer expression.uninit(self.allocator);

        const operator = self.peekPrevious();
        const right = try self.consumeTerm();
        errdefer right.uninit(self.allocator);

        expression = try Expression.binary(self.allocator, expression, operator, right);
    }

    return expression;
}

fn consumeTerm(self: *Parser) anyerror!*Expression {
    var expression = try self.consumeFactor();

    while (self.matchToken(TokenType.Minus) or self.matchToken(TokenType.Plus)) {
        errdefer expression.uninit(self.allocator);

        const operator = self.peekPrevious();
        const right = try self.consumeFactor();
        errdefer right.uninit(self.allocator);

        expression = try Expression.binary(self.allocator, expression, operator, right);
    }

    return expression;
}

fn consumeFactor(self: *Parser) anyerror!*Expression {
    var expression = try self.consumeUnary();

    while (self.matchToken(TokenType.Slash) or self.matchToken(TokenType.Star) or self.matchToken(TokenType.Percent)) {
        errdefer expression.uninit(self.allocator);

        const operator = self.peekPrevious();
        const right = try self.consumeUnary();
        errdefer right.uninit(self.allocator);

        expression = try Expression.binary(self.allocator, expression, operator, right);
    }

    return expression;
}

fn consumeUnary(self: *Parser) anyerror!*Expression {
    if (self.matchToken(TokenType.Negate) or self.matchToken(TokenType.Minus)) {
        const operator = self.peekPrevious();
        const right = try self.consumeUnary();
        errdefer right.uninit(self.allocator);

        return try Expression.unary(self.allocator, operator, right);
    }

    return try self.consumePrimary();
}

fn consumePrimary(self: *Parser) anyerror!*Expression {
    if (self.matchToken(TokenType.FalseKeyword)) {
        return Expression.literal(self.allocator, TokenLiteral.False);
    }
    if (self.matchToken(TokenType.TrueKeyword)) {
        return Expression.literal(self.allocator, TokenLiteral.True);
    }
    if (self.matchToken(TokenType.NullKeyword)) {
        return Expression.literal(self.allocator, TokenLiteral.Null);
    }

    if (self.matchToken(TokenType.NumberLiteral) or self.matchToken(TokenType.StringLiteral)) { // or self.matchToken(TokenType.Identifier)
        return Expression.literal(self.allocator, self.peekPrevious().literal);
    }

    if (self.matchToken(TokenType.OpenParen)) {
        const expression = try self.consumeExpression();
        if (!self.matchToken(TokenType.CloseParen)) {
            const err = ParseError.consumeFailed(self, "Expected ')'", self.peek());
            err.print(self.allocator);
            return ParseErrorEnum.Unknown;
        }
        return Expression.grouping(self.allocator, expression);
    }

    if (self.matchToken(TokenType.Identifier)) {
        return Expression.variableAccess(self.allocator, self.peekPrevious());
    }

    const err = ParseError.consumeFailed(self, "Expected expression", self.peek());
    err.print(self.allocator);
    return ParseErrorEnum.Unknown;
}

// Error handling

fn synchronize(self: *Parser) void {
    _ = self.advance();

    while (!self.isAtEnd()) {
        if (self.peekPrevious().type == TokenType.Semicolon) {
            return;
        }

        switch (self.peek().type) {
            .ClassKeyword => return,
            .FunctionKeyword => return,
            .LetKeyword => return,
            .IfKeyword => return,
            .WhileKeyword => return,
            .ForKeyword => return,
            .ReturnKeyword => return,
            else => {},
        }

        _ = self.advance();
    }
}

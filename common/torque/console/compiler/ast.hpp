#pragma once

// Syntax tree for the TorqueScript compiler. The parser builds it; codegen.cpp
// walks it once to emit DSO v33 code words. Nodes own their children.

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace Torque {
namespace Script {

struct Expr;
struct Stmt;
using ExprPtr = std::unique_ptr<Expr>;
using StmtPtr = std::unique_ptr<Stmt>;
using ExprList = std::vector<ExprPtr>;
using StmtList = std::vector<StmtPtr>;

enum class ExprKind {
  int_lit,    // number: integer literal
  float_lit,  // number: float literal
  str_lit,    // text: string literal (tagged when flag set)
  ident,      // text: bare word, loaded as an identifier
  var,        // text: %local or $global; indices: array subscripts
  field,      // a: object (null inside a new-object block); text: field name
  call,       // text: function; space: namespace; call_type; args (method: args[0] is the object)
  binary,     // op; a, b
  str_eq,     // flag: !$=; a, b
  concat,     // append_char: 0 for '@', else the joining byte; a, b
  logical,    // flag: true for ||; a, b
  unary,      // op: '-', '!', '~'; a
  assign,     // a: var or field target; op: 0 for '=', else the compound operator; b: value
  inc_dec,    // a: target; flag: true for ++
  conditional,// a ? b : c
  object      // new / datablock
};

enum class BinOp {
  none, add, sub, mul, div, mod, bit_and, bit_or, bit_xor, shl, shr,
  eq, ne, lt, le, gt, ge
};

struct ObjectDecl;

struct Expr {
  ExprKind kind;
  int line = 0;
  std::uint32_t number = 0;
  double real = 0.0;
  std::string text;
  std::string space;
  int call_type = 0;
  bool flag = false;
  char append_char = 0;
  char unary_op = 0;
  BinOp op = BinOp::none;
  ExprPtr a, b, c;
  ExprList indices;
  ExprList args;
  std::unique_ptr<ObjectDecl> object;
  explicit Expr(ExprKind k, int l) : kind(k), line(l) {}
};

struct SlotAssign {
  int line = 0;
  std::string name;
  ExprList indices;
  ExprPtr value;
};

struct ObjectDecl {
  ExprPtr class_name;   // usually an ident
  ExprPtr object_name;  // empty string literal when omitted
  std::string parent;   // "name : parent" form; empty when absent
  bool is_datablock = false;
  ExprList args;
  std::vector<SlotAssign> slots;
  std::vector<ExprPtr> children;  // nested object expressions
};

enum class StmtKind { expr, if_, loop, brk, cont, ret, function };

struct FunctionDecl {
  std::string name, space, package;
  std::vector<std::string> args;
  StmtList body;
};

struct Stmt {
  StmtKind kind;
  int line = 0;
  ExprPtr expr;           // expr; if/loop condition; return value (may be null)
  StmtList body;          // if-then; loop body
  StmtList else_body;     // if-else
  ExprPtr init, step;     // for-loop parts (may be null)
  bool test_first = true; // false for do/while
  std::unique_ptr<FunctionDecl> function;
  explicit Stmt(StmtKind k, int l) : kind(k), line(l) {}
};

} // namespace Script
} // namespace Torque

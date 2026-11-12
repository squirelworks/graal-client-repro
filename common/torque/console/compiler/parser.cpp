// TorqueScript lexer and recursive-descent parser.
//
// Grammar and operator precedence follow the published TorqueScript
// language (lowest first): assignment, ?:, ||, &&, |, ^, &, == != $= !$=,
// < > <= >=, @ SPC TAB NL, << >>, + -, * / %, unary ! ~ -, postfix.

#include "parser.hpp"

#include <cstdlib>
#include <cstring>
#include <utility>

namespace Torque {
namespace Script {
namespace {

enum class Tok { end, ident, local, global, integer, real, string, tag, punct };

struct Token {
  Tok kind = Tok::end;
  std::string text;
  std::uint32_t number = 0;
  double real = 0.0;
  int line = 1;
};

struct Failure {
  int line;
  std::string message;
};

bool id_start(char c) {
  return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
}
bool id_char(char c) { return id_start(c) || (c >= '0' && c <= '9'); }
bool digit(char c) { return c >= '0' && c <= '9'; }
int hex_value(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

class Lexer {
 public:
  explicit Lexer(const std::string& s) : src_(s) {}

  std::vector<Token> run() {
    std::vector<Token> out;
    for (;;) {
      Token t = next();
      out.push_back(t);
      if (t.kind == Tok::end) return out;
    }
  }

 private:
  const std::string& src_;
  std::size_t pos_ = 0;
  int line_ = 1;

  char at(std::size_t k) const { return k < src_.size() ? src_[k] : '\0'; }

  [[noreturn]] void fail(const std::string& m) { throw Failure{line_, m}; }

  void skip_space() {
    for (;;) {
      const char c = at(pos_);
      if (c == '\n') { ++line_; ++pos_; }
      else if (c == ' ' || c == '\t' || c == '\r' || c == '\f' || c == '\v') ++pos_;
      else if (c == '/' && at(pos_ + 1) == '/') {
        while (pos_ < src_.size() && src_[pos_] != '\n') ++pos_;
      } else if (c == '/' && at(pos_ + 1) == '*') {
        pos_ += 2;
        while (pos_ < src_.size() && !(src_[pos_] == '*' && at(pos_ + 1) == '/')) {
          if (src_[pos_] == '\n') ++line_;
          ++pos_;
        }
        if (pos_ >= src_.size()) fail("unterminated comment");
        pos_ += 2;
      } else return;
    }
  }

  // name(::name)* starting at pos_
  std::string read_name() {
    const std::size_t start = pos_;
    for (;;) {
      while (id_char(at(pos_))) ++pos_;
      // Later segments may start with a digit ($language::ServerList::3D).
      if (at(pos_) == ':' && at(pos_ + 1) == ':' && id_char(at(pos_ + 2))) pos_ += 2;
      else break;
    }
    return src_.substr(start, pos_ - start);
  }

  std::string read_quoted(char quote) {
    std::string out;
    ++pos_;
    for (;;) {
      if (pos_ >= src_.size() || src_[pos_] == '\n') fail("unterminated string");
      char c = src_[pos_++];
      if (c == quote) return out;
      if (c != '\\') { out += c; continue; }
      if (pos_ >= src_.size()) fail("unterminated string");
      c = src_[pos_++];
      switch (c) {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case 'x': {
          const int h = hex_value(at(pos_)), l = hex_value(at(pos_ + 1));
          if (h < 0 || l < 0) fail("bad \\x escape");
          out += static_cast<char>(h * 16 + l);
          pos_ += 2;
          break;
        }
        case 'c': {
          // Colour and style codes of the published TorqueScript string escapes.
          static const char colour[10] = {1, 2, 3, 4, 5, 6, 7, 11, 12, 14};
          const char d = at(pos_++);
          if (digit(d)) out += colour[d - '0'];
          else if (d == 'r') out += '\x0f';
          else if (d == 'p') out += '\x10';
          else if (d == 'o') out += '\x11';
          else fail("bad \\c escape");
          break;
        }
        default: out += c; break;  // \\ \" \' and any other character
      }
    }
  }

  Token next() {
    skip_space();
    Token t;
    t.line = line_;
    const char c = at(pos_);
    if (pos_ >= src_.size()) return t;
    if (id_start(c)) {
      t.kind = Tok::ident;
      t.text = read_name();
      if (t.text == "switch" && at(pos_) == '$') {
        ++pos_;
        t.text = "switch$";
      }
      return t;
    }
    if ((c == '%' || c == '$') && id_start(at(pos_ + 1))) {
      t.kind = c == '%' ? Tok::local : Tok::global;
      ++pos_;
      t.text = std::string(1, c) + read_name();
      return t;
    }
    if (digit(c) || (c == '.' && digit(at(pos_ + 1)))) return number(t);
    if (c == '"') { t.kind = Tok::string; t.text = read_quoted('"'); return t; }
    if (c == '\'') { t.kind = Tok::tag; t.text = read_quoted('\''); return t; }
    static const char* const ops[] = {
        "!$=", "<<=", ">>=", "==", "!=", "<=", ">=", "&&", "||", "<<", ">>",
        "++",  "--",  "+=",  "-=", "*=", "/=", "%=", "&=", "|=", "^=", "$=", "::"};
    for (const char* op : ops) {
      const std::size_t n = std::strlen(op);
      if (src_.compare(pos_, n, op) == 0) {
        t.kind = Tok::punct;
        t.text = op;
        pos_ += n;
        return t;
      }
    }
    if (std::strchr("+-*/%&|^~!<>=?:;,.()[]{}@", c) == nullptr)
      fail(std::string("unexpected character '") + c + "'");
    t.kind = Tok::punct;
    t.text = std::string(1, c);
    ++pos_;
    return t;
  }

  Token number(Token t) {
    const std::size_t start = pos_;
    if (at(pos_) == '0' && (at(pos_ + 1) == 'x' || at(pos_ + 1) == 'X') &&
        hex_value(at(pos_ + 2)) >= 0) {
      pos_ += 2;
      std::uint64_t v = 0;
      while (hex_value(at(pos_)) >= 0) v = v * 16 + static_cast<unsigned>(hex_value(src_[pos_++]));
      t.kind = Tok::integer;
      t.number = static_cast<std::uint32_t>(v);
      t.text = src_.substr(start, pos_ - start);
      return t;
    }
    bool real = false;
    while (digit(at(pos_))) ++pos_;
    if (at(pos_) == '.' && digit(at(pos_ + 1))) {
      real = true;
      ++pos_;
      while (digit(at(pos_))) ++pos_;
    }
    if ((at(pos_) == 'e' || at(pos_) == 'E') &&
        (digit(at(pos_ + 1)) ||
         ((at(pos_ + 1) == '+' || at(pos_ + 1) == '-') && digit(at(pos_ + 2))))) {
      real = true;
      pos_ += 2;
      while (digit(at(pos_))) ++pos_;
    }
    t.text = src_.substr(start, pos_ - start);
    if (real) {
      t.kind = Tok::real;
      t.real = std::strtod(t.text.c_str(), nullptr);
    } else {
      t.kind = Tok::integer;
      t.number = static_cast<std::uint32_t>(std::strtoull(t.text.c_str(), nullptr, 10));
    }
    return t;
  }
};

bool keyword(const std::string& s) {
  static const char* const words[] = {
      "function", "package", "datablock", "new", "if", "else", "while", "for", "do",
      "switch", "switch$", "case", "or", "default", "break", "continue", "return", "true",
      "false", "SPC", "TAB", "NL"};
  for (const char* w : words)
    if (s == w) return true;
  return false;
}

ExprPtr make(ExprKind k, int line) { return std::make_unique<Expr>(k, line); }

class Parser {
 public:
  explicit Parser(std::vector<Token> t) : toks_(std::move(t)) {}

  StmtList script() {
    StmtList out;
    while (cur().kind != Tok::end) top_level(out);
    return out;
  }

 private:
  std::vector<Token> toks_;
  std::size_t i_ = 0;
  int loops_ = 0;
  int depth_ = 0;
  bool in_function_ = false;

  // Reproduction limit: deep nesting (console input included) fails cleanly
  // instead of exhausting the native stack.
  static constexpr int max_depth = 256;
  struct Nest {
    Parser& p;
    explicit Nest(Parser& parser) : p(parser) {
      if (++p.depth_ > max_depth) p.fail("nesting too deep");
    }
    ~Nest() { --p.depth_; }
  };
  // Left-associative chains nest their left operand one level per operator.
  struct Chain {
    Parser& p;
    int added = 0;
    explicit Chain(Parser& parser) : p(parser) {}
    void grow() {
      ++added;
      if (++p.depth_ > max_depth) p.fail("nesting too deep");
    }
    ~Chain() { p.depth_ -= added; }
  };

  const Token& cur() const { return toks_[i_]; }
  const Token& peek(std::size_t n = 1) const {
    return toks_[i_ + n < toks_.size() ? i_ + n : toks_.size() - 1];
  }
  Token take() {
    Token t = toks_[i_];
    if (i_ + 1 < toks_.size()) ++i_;
    return t;
  }
  [[noreturn]] void fail(const std::string& m) const { throw Failure{cur().line, m}; }

  bool is(const char* p) const { return cur().kind == Tok::punct && cur().text == p; }
  bool is_word(const char* w) const { return cur().kind == Tok::ident && cur().text == w; }
  bool accept(const char* p) {
    if (!is(p)) return false;
    take();
    return true;
  }
  void expect(const char* p) {
    if (!accept(p)) fail(std::string("expected '") + p + "'");
  }
  std::string name() {
    if (cur().kind != Tok::ident || keyword(cur().text)) fail("expected a name");
    return take().text;
  }

  void top_level(StmtList& out) {
    if (is_word("function")) { out.push_back(function("")); return; }
    if (is_word("package")) {
      take();
      const std::string pkg = name();
      expect("{");
      while (!is("}")) {
        if (!is_word("function")) fail("only functions may appear in a package");
        out.push_back(function(pkg));
      }
      expect("}");
      expect(";");
      return;
    }
    out.push_back(statement());
  }

  StmtPtr function(const std::string& pkg) {
    if (in_function_) fail("nested function declaration");
    const int line = take().line;
    auto decl = std::make_unique<FunctionDecl>();
    decl->package = pkg;
    std::string full = name();
    if (accept("::")) {
      decl->space = full;
      full = name();
    }
    // The lexer joins a::b into one identifier.
    const auto split = full.rfind("::");
    if (split != std::string::npos) {
      if (!decl->space.empty()) fail("bad function name");
      decl->space = full.substr(0, split);
      full = full.substr(split + 2);
    }
    decl->name = full;
    expect("(");
    if (!is(")")) {
      do {
        if (cur().kind != Tok::local) fail("expected a %parameter");
        decl->args.push_back(take().text);
      } while (accept(","));
    }
    expect(")");
    in_function_ = true;
    decl->body = block();
    in_function_ = false;
    auto s = std::make_unique<Stmt>(StmtKind::function, line);
    s->function = std::move(decl);
    return s;
  }

  StmtList block() {
    StmtList out;
    expect("{");
    while (!is("}")) {
      if (cur().kind == Tok::end) fail("expected '}'");
      out.push_back(statement());
    }
    take();
    return out;
  }

  StmtList body() {
    if (is("{")) return block();
    StmtList out;
    out.push_back(statement());
    return out;
  }

  StmtPtr statement() {
    Nest nest(*this);
    const int line = cur().line;
    if (is_word("function") || is_word("package"))
      fail("function and package declarations belong at the top level");
    if (is_word("if")) {
      take();
      auto s = std::make_unique<Stmt>(StmtKind::if_, line);
      expect("(");
      s->expr = expression();
      expect(")");
      s->body = body();
      if (is_word("else")) {
        take();
        s->else_body = body();
      }
      return s;
    }
    if (is_word("while")) {
      take();
      auto s = std::make_unique<Stmt>(StmtKind::loop, line);
      expect("(");
      s->expr = expression();
      expect(")");
      ++loops_;
      s->body = body();
      --loops_;
      return s;
    }
    if (is_word("do")) {
      take();
      auto s = std::make_unique<Stmt>(StmtKind::loop, line);
      s->test_first = false;
      ++loops_;
      s->body = body();
      --loops_;
      if (!is_word("while")) fail("expected 'while'");
      take();
      expect("(");
      s->expr = expression();
      expect(")");
      expect(";");
      return s;
    }
    if (is_word("for")) {
      take();
      auto s = std::make_unique<Stmt>(StmtKind::loop, line);
      expect("(");
      if (!is(";")) s->init = expression();
      expect(";");
      if (is(";")) fail("a for loop needs a condition");
      s->expr = expression();
      expect(";");
      if (!is(")")) s->step = expression();
      expect(")");
      ++loops_;
      s->body = body();
      --loops_;
      return s;
    }
    if (is_word("switch") || is_word("switch$")) return switch_statement(line);
    if (is_word("break") || is_word("continue")) {
      const bool brk = take().text == "break";
      if (loops_ == 0) fail(brk ? "break outside a loop" : "continue outside a loop");
      expect(";");
      return std::make_unique<Stmt>(brk ? StmtKind::brk : StmtKind::cont, line);
    }
    if (is_word("return")) {
      take();
      auto s = std::make_unique<Stmt>(StmtKind::ret, line);
      if (!is(";")) s->expr = expression();
      expect(";");
      return s;
    }
    if (is_word("datablock")) {
      auto s = std::make_unique<Stmt>(StmtKind::expr, line);
      s->expr = datablock();
      expect(";");
      return s;
    }
    auto s = std::make_unique<Stmt>(StmtKind::expr, line);
    s->expr = expression();
    expect(";");
    return s;
  }

  // switch / switch$ become an if/else chain; each case compares the switch
  // value again, joining "or" alternatives with ||.
  StmtPtr switch_statement(int line) {
    const bool strings = take().text == "switch$";
    expect("(");
    ExprPtr value = expression();
    expect(")");
    expect("{");
    struct Case { ExprPtr cond; StmtList body; int line; };
    std::vector<Case> cases;
    StmtList fallback;
    bool have_default = false;
    while (!is("}")) {
      if (is_word("case")) {
        const int cl = take().line;
        ExprPtr cond;
        for (;;) {
          ExprPtr alt = ternary();
          auto cmp = make(strings ? ExprKind::str_eq : ExprKind::binary, cl);
          if (!strings) cmp->op = BinOp::eq;
          cmp->a = clone_expr(*value);
          cmp->b = std::move(alt);
          if (cond) {
            auto both = make(ExprKind::logical, cl);
            both->flag = true;
            both->a = std::move(cond);
            both->b = std::move(cmp);
            cond = std::move(both);
          } else cond = std::move(cmp);
          if (is_word("or")) { take(); continue; }
          break;
        }
        expect(":");
        Case c{std::move(cond), {}, cl};
        while (!is_word("case") && !is_word("default") && !is("}")) {
          if (cur().kind == Tok::end) fail("expected '}'");
          c.body.push_back(statement());
        }
        cases.push_back(std::move(c));
      } else if (is_word("default")) {
        if (have_default) fail("duplicate default");
        have_default = true;
        take();
        expect(":");
        while (!is_word("case") && !is_word("default") && !is("}")) {
          if (cur().kind == Tok::end) fail("expected '}'");
          fallback.push_back(statement());
        }
      } else fail("expected 'case' or 'default'");
    }
    take();
    if (cases.empty()) fail("switch without a case");
    StmtList tail = std::move(fallback);
    for (std::size_t k = cases.size(); k-- > 0;) {
      auto s = std::make_unique<Stmt>(StmtKind::if_, k == 0 ? line : cases[k].line);
      s->expr = std::move(cases[k].cond);
      s->body = std::move(cases[k].body);
      s->else_body = std::move(tail);
      tail.clear();
      tail.push_back(std::move(s));
    }
    return std::move(tail.front());
  }

  ExprPtr expression() {
    Nest nest(*this);
    ExprPtr lhs = ternary();
    static const struct { const char* tok; char op; } assigns[] = {
        {"=", 0},   {"+=", '+'}, {"-=", '-'}, {"*=", '*'}, {"/=", '/'}, {"%=", '%'},
        {"&=", '&'}, {"|=", '|'}, {"^=", '^'}, {"<<=", '<'}, {">>=", '>'}};
    for (const auto& a : assigns) {
      if (!is(a.tok)) continue;
      if (lhs->kind != ExprKind::var && lhs->kind != ExprKind::field)
        fail("cannot assign to this expression");
      const int line = take().line;
      auto e = make(ExprKind::assign, line);
      e->unary_op = a.op;
      e->a = std::move(lhs);
      e->b = expression();
      return e;
    }
    return lhs;
  }

  ExprPtr ternary() {
    ExprPtr c = logical_or();
    if (!is("?")) return c;
    const int line = take().line;
    auto e = make(ExprKind::conditional, line);
    e->a = std::move(c);
    e->b = expression();
    expect(":");
    e->c = expression();
    return e;
  }

  ExprPtr logical_or() {
    Chain chain(*this);
    ExprPtr l = logical_and();
    while (is("||")) {
      chain.grow();
      const int line = take().line;
      auto e = make(ExprKind::logical, line);
      e->flag = true;
      e->a = std::move(l);
      e->b = logical_and();
      l = std::move(e);
    }
    return l;
  }

  ExprPtr logical_and() {
    Chain chain(*this);
    ExprPtr l = binary(0);
    while (is("&&")) {
      chain.grow();
      const int line = take().line;
      auto e = make(ExprKind::logical, line);
      e->a = std::move(l);
      e->b = binary(0);
      l = std::move(e);
    }
    return l;
  }

  // Binary levels, loosest first: | ^ & (== != $= !$=) (< <= > >=)
  // (@ SPC TAB NL) (<< >>) (+ -) (* / %). All are left-associative.
  ExprPtr binary(int level) {
    if (level > 8) return unary();
    Chain chain(*this);
    ExprPtr l = binary(level + 1);
    for (;;) {
      const Token& t = cur();
      const int line = t.line;
      ExprPtr e;
      if (level == 5 && t.kind == Tok::ident &&
          (t.text == "SPC" || t.text == "TAB" || t.text == "NL")) {
        e = make(ExprKind::concat, line);
        e->append_char = t.text == "SPC" ? ' ' : t.text == "TAB" ? '\t' : '\n';
      } else if (t.kind == Tok::punct) {
        static const struct { int level; const char* tok; BinOp op; } ops[] = {
            {0, "|", BinOp::bit_or},  {1, "^", BinOp::bit_xor}, {2, "&", BinOp::bit_and},
            {3, "==", BinOp::eq},     {3, "!=", BinOp::ne},     {4, "<", BinOp::lt},
            {4, "<=", BinOp::le},     {4, ">", BinOp::gt},      {4, ">=", BinOp::ge},
            {6, "<<", BinOp::shl},    {6, ">>", BinOp::shr},    {7, "+", BinOp::add},
            {7, "-", BinOp::sub},     {8, "*", BinOp::mul},     {8, "/", BinOp::div},
            {8, "%", BinOp::mod}};
        for (const auto& o : ops) {
          if (o.level == level && t.text == o.tok) {
            e = make(ExprKind::binary, line);
            e->op = o.op;
          }
        }
        if (level == 3 && (t.text == "$=" || t.text == "!$=")) {
          e = make(ExprKind::str_eq, line);
          e->flag = t.text == "!$=";
        }
        if (level == 5 && t.text == "@") e = make(ExprKind::concat, line);
      }
      if (!e) return l;
      chain.grow();
      take();
      e->a = std::move(l);
      e->b = binary(level + 1);
      l = std::move(e);
    }
  }

  ExprPtr unary() {
    Nest nest(*this);
    const int line = cur().line;
    if (is("!") || is("~") || is("-")) {
      const char op = take().text[0];
      auto e = make(ExprKind::unary, line);
      e->unary_op = op;
      e->a = unary();
      return e;
    }
    return postfix(primary());
  }

  ExprList call_args() {
    ExprList args;
    expect("(");
    if (!is(")")) {
      do args.push_back(expression());
      while (accept(","));
    }
    expect(")");
    return args;
  }

  ExprList subscripts() {
    ExprList idx;
    expect("[");
    do idx.push_back(expression());
    while (accept(","));
    expect("]");
    return idx;
  }

  ExprPtr postfix(ExprPtr e) {
    Chain chain(*this);
    for (;;) {
      chain.grow();
      const int line = cur().line;
      if (is(".")) {
        take();
        const std::string field = name_or_keyword();
        if (is("(")) {
          auto call = make(ExprKind::call, line);
          call->text = field;
          call->call_type = 1;
          call->args.push_back(std::move(e));
          for (auto& a : call_args()) call->args.push_back(std::move(a));
          e = std::move(call);
          continue;
        }
        auto f = make(ExprKind::field, line);
        f->a = std::move(e);
        f->text = field;
        if (is("[")) f->indices = subscripts();
        e = std::move(f);
        continue;
      }
      if ((is("++") || is("--")) &&
          (e->kind == ExprKind::var || e->kind == ExprKind::field)) {
        auto inc = make(ExprKind::inc_dec, line);
        inc->flag = take().text == "++";
        inc->a = std::move(e);
        e = std::move(inc);
        continue;
      }
      return e;
    }
  }

  std::string name_or_keyword() {
    if (cur().kind != Tok::ident) fail("expected a name");
    return take().text;
  }

  ExprPtr primary() {
    const Token& t = cur();
    const int line = t.line;
    switch (t.kind) {
      case Tok::integer: {
        auto e = make(ExprKind::int_lit, line);
        e->number = t.number;
        e->real = static_cast<double>(t.number);
        e->text = t.text;
        take();
        return e;
      }
      case Tok::real: {
        auto e = make(ExprKind::float_lit, line);
        e->real = t.real;
        e->text = t.text;
        take();
        return e;
      }
      case Tok::string:
      case Tok::tag: {
        auto e = make(ExprKind::str_lit, line);
        e->text = t.text;
        e->flag = t.kind == Tok::tag;
        take();
        return e;
      }
      case Tok::local:
      case Tok::global: {
        auto e = make(ExprKind::var, line);
        e->text = take().text;
        if (is("[")) e->indices = subscripts();
        return e;
      }
      case Tok::punct:
        if (is("(")) {
          take();
          ExprPtr e = expression();
          expect(")");
          return e;
        }
        fail("expected an expression");
      case Tok::ident: {
        if (t.text == "new") return object_expr(false);
        if (t.text == "true" || t.text == "false") {
          auto e = make(ExprKind::int_lit, line);
          e->number = t.text == "true" ? 1 : 0;
          e->real = e->number;
          e->text = e->number ? "1" : "0";
          take();
          return e;
        }
        if (keyword(t.text)) fail("unexpected '" + t.text + "'");
        std::string word = take().text;
        std::string space;
        if (accept("::")) {
          space = word;
          word = name();
        } else {
          const auto split = word.rfind("::");
          if (split != std::string::npos) {
            space = word.substr(0, split);
            word = word.substr(split + 2);
          }
        }
        if (is("(")) {
          auto call = make(ExprKind::call, line);
          call->text = word;
          call->space = space;
          call->call_type = space == "Parent" ? 2 : 0;
          call->args = call_args();
          return call;
        }
        if (!space.empty()) fail("expected '(' after " + space + "::" + word);
        auto e = make(ExprKind::ident, line);
        e->text = word;
        return e;
      }
      case Tok::end: fail("unexpected end of script");
    }
    fail("expected an expression");
  }

  // new Class(name [: parent] [, args]) [{ slots and child objects }]
  ExprPtr object_expr(bool datablock) {
    Nest nest(*this);
    const int line = take().line;
    auto e = make(ExprKind::object, line);
    e->object = std::make_unique<ObjectDecl>();
    ObjectDecl& o = *e->object;
    o.is_datablock = datablock;
    if (is("(")) {
      take();
      o.class_name = expression();
      expect(")");
    } else {
      auto c = make(ExprKind::ident, cur().line);
      c->text = name();
      o.class_name = std::move(c);
    }
    expect("(");
    if (!is(")") && !is(":") && !is(",")) o.object_name = expression();
    if (accept(":")) o.parent = name();
    while (accept(",")) o.args.push_back(expression());
    expect(")");
    if (!o.object_name) {
      auto n = make(ExprKind::str_lit, line);
      o.object_name = std::move(n);
    }
    if (is("{")) {
      take();
      while (!is("}")) {
        if (cur().kind == Tok::end) fail("expected '}'");
        if (is_word("new")) {
          o.children.push_back(object_expr(false));
          expect(";");
          continue;
        }
        if (is_word("datablock")) fail("datablock inside an object block");
        SlotAssign slot;
        slot.line = cur().line;
        slot.name = name_or_keyword();
        if (is("[")) slot.indices = subscripts();
        expect("=");
        slot.value = expression();
        expect(";");
        o.slots.push_back(std::move(slot));
      }
      take();
    }
    return e;
  }

  ExprPtr datablock() {
    // "datablock" takes the place of "new"
    auto e = object_expr(true);
    if (e->object->class_name->kind != ExprKind::ident)
      fail("datablock needs a class name");
    return e;
  }
};

} // namespace

ExprPtr clone_expr(const Expr& e) {
  auto c = std::make_unique<Expr>(e.kind, e.line);
  c->number = e.number;
  c->real = e.real;
  c->text = e.text;
  c->space = e.space;
  c->call_type = e.call_type;
  c->flag = e.flag;
  c->append_char = e.append_char;
  c->unary_op = e.unary_op;
  c->op = e.op;
  if (e.a) c->a = clone_expr(*e.a);
  if (e.b) c->b = clone_expr(*e.b);
  if (e.c) c->c = clone_expr(*e.c);
  for (const auto& x : e.indices) c->indices.push_back(clone_expr(*x));
  for (const auto& x : e.args) c->args.push_back(clone_expr(*x));
  if (e.object) {
    const ObjectDecl& o = *e.object;
    auto d = std::make_unique<ObjectDecl>();
    d->class_name = clone_expr(*o.class_name);
    d->object_name = clone_expr(*o.object_name);
    d->parent = o.parent;
    d->is_datablock = o.is_datablock;
    for (const auto& x : o.args) d->args.push_back(clone_expr(*x));
    for (const auto& s : o.slots) {
      SlotAssign t;
      t.line = s.line;
      t.name = s.name;
      for (const auto& x : s.indices) t.indices.push_back(clone_expr(*x));
      t.value = clone_expr(*s.value);
      d->slots.push_back(std::move(t));
    }
    for (const auto& x : o.children) d->children.push_back(clone_expr(*x));
    c->object = std::move(d);
  }
  return c;
}

bool parse_script(const std::string& source, StmtList& out, ParseError& error) {
  try {
    Lexer lexer(source);
    Parser parser(lexer.run());
    StmtList result = parser.script();
    out = std::move(result);
    return true;
  } catch (const Failure& f) {
    error.line = f.line;
    error.message = f.message;
    return false;
  }
}

} // namespace Script
} // namespace Torque

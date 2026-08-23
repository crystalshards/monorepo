# Capturing the value of the final expression without compiler internals.
#
# Crystal forbids declarations inside expressions: a `def`, `class`, `module`,
# `macro` or `require` inside a `begin ... end` is rejected with "can't declare
# ... dynamically" (verified against Crystal 1.21.0). So the whole program
# cannot be wrapped. What works is wrapping ONLY the final top-level statement,
# which is an expression whenever it is not itself a declaration:
#
#     <every earlier line, untouched, declarations included>
#     __tc_v = begin
#       <the final statement, verbatim>
#     end
#     File.write(ENV["TC_VALUE_PATH"], __tc_v.inspect)
#
# The scanner finds where that final statement starts by walking lines
# backward and counting block closers against openers. It is deliberately
# conservative: any shape it cannot establish declines the wrap, and the
# submission then runs unchanged with value: null. Declining is always safe;
# wrapping the wrong range would break the program. Two nets back it up:
#
#   1. A declaration nested inside the would-be final statement (a conditional
#      def, for example) is detected and declines the wrap, because
#      `begin ... def ... end` is exactly the "dynamically" error above.
#   2. If a wrapped run still fails compilation with a wrap-shaped error
#      (syntax error, unterminated, "can't declare ... dynamically"), the
#      executor reruns the original source unwrapped. A user's own error of
#      the same class simply reproduces itself on the retry, so this costs one
#      extra run on a typo, never a wrong answer.
#
# The wrap shifts user lines by one, so compiler line numbers are mapped back
# (Executor rewrites "submission.cr:N" in stderr).

module TryCrystalRunner
  struct WrapPlan
    getter source : String
    getter? wrapped : Bool
    # 1-based line, in the user's original numbering, where the wrapped final
    # statement starts; 0 when not wrapped.
    getter start_line : Int32

    def initialize(@source, @wrapped, @start_line)
    end
  end

  # First tokens that declare rather than evaluate. A submission ending in one
  # of these has no final-expression value: it runs unchanged, value null.
  private NON_VALUE_FIRST = {
    "def", "class", "module", "struct", "enum", "lib", "fun", "macro",
    "annotation", "require", "include", "extend", "alias", "abstract",
    "private", "protected", "asm",
  }

  # Keywords that open a block closed by a later `end`.
  private BLOCK_OPENERS = {
    "def", "class", "module", "struct", "enum", "lib", "fun", "macro",
    "annotation", "if", "unless", "case", "while", "until", "begin", "select",
  }

  # Keywords that only appear mid-construct; a final line starting with one
  # means the statement began further up.
  private MID_KEYWORDS = {"else", "elsif", "when", "in", "rescue", "ensure"}

  # An assignment whose right side opens a block: `x = if cond`. The first
  # token is the variable, not the keyword, so the walk needs its own pattern.
  private ASSIGN_OPENER = /=\s*(if|unless|case|while|until|begin|select)\b/

  # Heredoc terminator or opener patterns.
  private HEREDOC_OPENER = /<<[-~]([A-Za-z_][A-Za-z0-9_]*)/

  # Trailing tokens that mean the statement continues on the next line.
  private CONTINUATION_SUFFIX = {
    "\\", ",", ".", "|", "{", "(", "[", "=", "=>", "&&", "||", "+", "-",
    "*", "/", "%", "<", ">", "<=", ">=", "==", "!=", "and", "or", "not", "do",
  }

  # Errors that a bad wrap produces. Seeing one of these on a wrapped run
  # triggers the unwrapped retry; they are never manufactured by a correct
  # wrap, and a user's own error of the same class survives the retry intact.
  WRAP_SHAPED_ERROR = /syntax error|can't declare|unexpected token|unterminated|expecting/i

  def self.wrap(source : String) : WrapPlan
    lines = source.lines
    last = last_code_index(lines)
    return WrapPlan.new(source, false, 0) unless last
    last = last.not_nil!

    start = final_statement_start(lines, last)
    return WrapPlan.new(source, false, 0) unless start

    first = first_token(stripped(lines[start]))
    return WrapPlan.new(source, false, 0) if NON_VALUE_FIRST.includes?(first)

    # A declaration inside the final statement (a def inside a conditional,
    # for example) cannot live inside the wrap either.
    (start + 1..last).each do |i|
      tok = first_token(stripped(lines[i]))
      return WrapPlan.new(source, false, 0) if NON_VALUE_FIRST.includes?(tok)
    end

    wrapped = String.build do |io|
      lines[0...start].each { |l| io << l << '\n' }
      io << "__tc_v = begin\n"
      lines[start..last].each { |l| io << l << '\n' }
      io << "end\n"
      io << %(File.write(ENV["TC_VALUE_PATH"], __tc_v.inspect)) << '\n'
    end

    WrapPlan.new(wrapped, true, start + 1)
  end

  private def self.last_code_index(lines)
    (lines.size - 1).downto(0) do |i|
      return i unless stripped(lines[i]).empty?
    end
    nil
  end

  # 0-based index of the line where the final statement starts, or nil.
  private def self.final_statement_start(lines, last)
    s = stripped(lines[last])
    return nil if s.empty?
    return nil if s.count('"').odd?

    if heredoc = heredoc_start(lines, last)
      return heredoc
    end

    unless continues_upward?(s)
      # A self-contained last line is itself the final statement.
      return last
    end

    walk_upward(lines, last)
  end

  # True when the last line cannot stand alone: it closes something, sits
  # mid-construct, or trails an operator expecting more.
  private def self.continues_upward?(s)
    return true if "})]".includes?(s[0]? || ' ')
    return true if first_token(s) == "end"
    return true if MID_KEYWORDS.includes?(first_token(s))
    CONTINUATION_SUFFIX.any? do |suffix|
      s == suffix || s.ends_with?(" " + suffix)
    end
  end

  private def self.heredoc_start(lines, last)
    word = lines[last].strip
    return nil unless word =~ /\A[A-Za-z_][A-Za-z0-9_]*\z/

    last.downto(0) do |i|
      next if i == last
      s = strip_comment(lines[i])
      if (match = s.match(HEREDOC_OPENER)) && match[1] == word
        return i
      end
    end
    nil
  end

  # Walks up counting closers against openers; returns the line where the
  # construct containing `last` begins, or nil when it cannot be established.
  private def self.walk_upward(lines, last)
    depth = 0_i32

    last.downto(0) do |i|
      s = stripped(lines[i])
      next if s.empty?

      d = closer_delta(s)
      if d > 0
        depth += d
        next
      end

      opens, amount = opener_delta(s)
      if opens
        depth -= amount
        return i if depth <= 0
        next
      end

      # Plain interior line: keep climbing.
    end

    nil
  end

  # How many constructs this line closes by its leading tokens.
  private def self.closer_delta(s)
    delta = 0
    delta += 1 if first_token(s) == "end"
    delta += 1 if "})]".includes?(s[0]? || ' ')

    net = bracket_net(s)
    if net < 0
      leading = "})]".includes?(s[0]? || ' ') || first_token(s) == "end" ? 1 : 0
      delta += (-net - leading)
    end
    delta
  end

  # Whether this line opens constructs, and how many.
  private def self.opener_delta(s)
    first = first_token(s)
    net = bracket_net(s)
    keyword = BLOCK_OPENERS.includes?(first)
    do_block = s.ends_with?(" do") || s == "do" || s =~ /do\s*\|[^|]*\|\z/

    if keyword || do_block
      return {true, (net > 0 ? net : 0) + 1}
    end

    return {true, 1} if s =~ ASSIGN_OPENER

    return {true, net} if net > 0

    {false, 0}
  end

  # Net ( opens - closes ) for (), [], {}, ignoring double-quoted strings.
  private def self.bracket_net(s)
    net = 0
    in_string = false
    escape = false
    s.each_char do |c|
      if in_string
        if escape
          escape = false
        elsif c == '\\'
          escape = true
        elsif c == '"'
          in_string = false
        end
        next
      end
      case c
      when '"' then in_string = true
      when '(', '[', '{' then net += 1
      when ')', ']', '}' then net -= 1
      end
    end
    net
  end

  def self.first_token(stripped_line)
    stripped_line.match(/\A[a-z_][A-Za-z0-9_]*[?!=]?/).try(&.[0]) || ""
  end

  private def self.stripped(line)
    strip_comment(line).strip
  end

  # Removes a trailing comment, respecting double-quoted strings. Single-line
  # heuristic by design: multi-line literals produce odd quote counts, which
  # the callers treat as "do not wrap".
  private def self.strip_comment(line)
    in_string = false
    escape = false
    line.each_char_with_index do |c, i|
      if in_string
        if escape
          escape = false
        elsif c == '\\'
          escape = true
        elsif c == '"'
          in_string = false
        end
        next
      end
      return line[0...i] if c == '#'
      in_string = true if c == '"'
    end
    line
  end
end

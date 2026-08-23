# The tutorial. Three lessons, each one submission long, each standing on
# the one before it: print a line, then ask a string a question, then braid
# the two together. A visitor who types the sample lines lands lesson one
# within seconds of arriving, which is the whole point of the product.
#
# Each submission runs in a fresh process, so lessons cannot share state:
# lesson three repeats the greeting from lesson one rather than remembering
# it. The progression is conceptual, one idea stacked on the last, which is
# honest about how the sandbox works and reads fine in the console.
module Lessons
  TOTAL_PHRASE = "three short lessons"

  ALL = [
    Lesson.new(
      id: "say-hello",
      prompt: "Start by saying hello. puts writes a line of output, and it is " \
              "about to give you your first answer from the machine.",
      code_sample: %q{puts "Hello, Crystal!"},
      hint: "puts prints whatever follows it, on a line of its own. The double " \
            "quotes make the words a String, and the capital letters count: the " \
            "compiler is polite about many things, spelling is not one of them.",
      success: "There it is. You typed, the machine answered. puts takes its " \
               "argument and writes it out, which is the simplest way a program " \
               "has of reaching a human. Everything else in this console builds " \
               "on that one move.",
      check: ->(result : ExecutionResult) {
        result.ran_clean? && result.stdout.includes?("Hello, Crystal!")
      }
    ),
    Lesson.new(
      id: "strings-answer",
      prompt: "In Crystal, everything is an object, and objects answer " \
              "messages. Leave the puts out this time and send that same " \
              "greeting a message: upcase.",
      code_sample: %q{"Hello, Crystal!".upcase},
      hint: "The dot sends upcase to the string, and the string answers with " \
            "a new one in capitals. No puts needed: the console shows the value " \
            "of the last expression by itself, on the line after the double " \
            "arrow.",
      success: "HELLO, CRYSTAL! indeed. Notice that puts was never involved: the " \
               "console inspects the last expression of every submission and " \
               "prints it after the double arrow. Printing a value and being a " \
               "value are different moves, and you have now used both.",
      check: ->(result : ExecutionResult) {
        shouted = result.unquoted_value == "HELLO, CRYSTAL!" ||
                  result.stdout.includes?("HELLO, CRYSTAL!")
        result.ran_clean? && shouted
      }
    ),
    Lesson.new(
      id: "braid-them",
      prompt: "Now braid the first two together. Interpolation runs any " \
              "expression inside a string, between \#{ and }, and slides the " \
              "answer into the text. Say hello the loud way, in one line.",
      code_sample: %q{puts "Hello, #{"Crystal".upcase}!"},
      hint: "Everything between \#{ and } is ordinary Crystal that runs first, " \
            "and double quotes inside the braces are fine: the string does not " \
            "end until its own closing quote does.",
      success: "And that is the whole craft in one line: puts from the first " \
               "lesson, a message from the second, interpolation holding them " \
               "together. Small pieces that compose are most of how Crystal " \
               "thinks. Three lessons, three for three against the real " \
               "compiler.",
      check: ->(result : ExecutionResult) {
        result.ran_clean? && result.stdout.strip == "Hello, CRYSTAL!"
      }
    ),
  ] of Lesson

  def self.total : Int32
    ALL.size
  end

  def self.first : Lesson
    ALL.first
  end

  def self.find(id : String?) : Lesson?
    return nil if id.nil?
    ALL.find { |lesson| lesson.id == id }
  end

  # One-based position of a lesson in the tutorial, or nil when unknown.
  def self.position_of(id : String) : Int32?
    ALL.index { |lesson| lesson.id == id }.try { |index| index + 1 }
  end

  # The lesson that follows the given one, or nil at the end of the tutorial.
  def self.after(id : String) : Lesson?
    index = ALL.index { |lesson| lesson.id == id }
    return nil if index.nil?
    ALL[index + 1]?
  end
end

require 'setup'
=begin
[:defn, :a, [:args], [:scope, [:block, [:call, nil, :puts, [:arglist, [:str, "A"]]]]]]
"def a\n  puts(\"A\")\nend"

[:defn, :b, [:args, :a, :b], [:scope, [:block, [:lvar, :a]]]]
"def b(a, b)\n  a\nend"

[:class, :Blah, nil, [:scope, [:alias, [:lit, :one], [:lit, :two]]]]
"class Blah\n  alias :one :two\nend"
=end

require 'ruby2ruby'
require 'ruby_parser'
require 'pp'

["def a\n  puts 'A'\nend", "def b(a,b)\n  a\nend", "class Blah; alias :one :two end", %q{
}].each do |ruby|
  parser    = RubyParser.new
  sexp      = parser.process(ruby)
  p sexp.to_a

  ruby2ruby = Ruby2Ruby.new
  p ruby2ruby.process(sexp)

  puts "\n\n"
end

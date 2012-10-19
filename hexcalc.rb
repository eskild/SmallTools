#!/bin/env ruby
#
#    Simple, simple, simple CLI-based Hex RPN calculator
#
#                 -- being a part of --
#
#    SmallTools -- a set of small tools and utilites.
#
#    Copyright (C) 2011 Martin Eskildsen.
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#    Comments, suggestions, questions to:
#             Martin Eskildsen
#             eskild.opensource@gmail.com

# Variable container. A hash with name -> value pairs.

require 'readline'

class Variables

  attr_reader :vars

  def initialize
    @vars = Hash.new
  end

  def assign(name, value)
    @vars[name] = value
  end

  def delete(name)
    @vars.delete(name)
  end

  def get(name)
    raise "No such variable: #{name}" unless @vars.has_key?(name)
    @vars[name]
  end

end



# Stack base class. Primary role is to complain if stack underflows.

class Stack

  def initialize
    @s = []
  end

  def size
    @s.length
  end

  def is_empty?
    size == 0
  end

  def push(val)
    @s << val
  end

  def pop
    raise "Stack empty" if is_empty?
    v = top
    @s = @s[0..-2]
    v
  end

  def top
    raise "Stack empty" if is_empty?
    @s[-1]
  end

  def rotate
    raise "Stack size < 2, cannot rotate" if @s.length < 2
    @s[0], @s[-1] = @s[-1], @s[0]
  end

  def values
    @s
  end

end



# The Calculator
class Calculator

  MAX_NESTING = 40

  def initialize
    @s = Stack.new

    @func = nil   # Non-nil: We're defining a func ( '[ ... ]' )
    @nesting = 0  # How deeply calls to parse_and_eval() are nested

    @vars = Variables.new
    @ops  = Hash.new
    @ops['+']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2+p1) }
    @ops['-']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2-p1) }
    @ops['*']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2*p1) }
    @ops['/']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2/p1) }
    @ops['^']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2^p1) }
    @ops['|']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2|p1) }
    @ops['&']    = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2&p1) }
    @ops['<<']   = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2<<p1) }
    @ops['>>']   = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2>>p1) }
    @ops['**']   = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p2**p1) }
    @ops['swap'] = Proc.new { p1=@s.pop; p2=@s.pop; @s.push(p1); @s.push(p2) }
    @ops['=']    = Proc.new { nm=@s.pop; v=@s.pop; @vars.assign(nm, v) }
    @ops['[']    = Proc.new { raise "Bug" if @func != nil; @func = [] }
    @ops['rot']  = Proc.new { @s.rotate }
    @ops['pop']  = Proc.new { @s.pop }
    @ops['dup']  = Proc.new { @s.push(@s.top) }
    @ops['!']    = @ops['not'] = Proc.new { @s.push(~@s.pop) }
    @ops['show'] = @ops['s']   = Proc.new { print_stack }
    @ops['neg']  = @ops['chs'] = Proc.new { @s.push(-@s.pop) }
    @ops['vars'] = Proc.new { print_vars }
    @ops['del']  = Proc.new { @vars.delete(@s.pop) }
    @ops['help'] = Proc.new { show_help }
  end

  def loop
    while line = Readline.readline('> ', true)
      begin
        parse_line(line)
        print_top
      rescue
        return
      end
    end
  end

  def print_top
    printf("top[sz:%2s] = %s\n", @s.size, top_str)
  end

  def load(filename)
    IO.readlines(filename).each { |line| parse_line(line) }
  end

  #----------------------------------------------------------------------------

private

  #
  # Formatting / output
  #

  # Split into blocks of len chars, separated with '.'
  def sep_s(s, len)
    if s[0] == '-'[0] then
      sign = '-'
      s = s[1..-1]
    else
      sign = ''
    end
    ln = s.length
    if ln > len then
      head, tail = s[0..ln-len-1], s[ln-len..-1]
      return sign + sep_s(head, len) + '.' + tail
    else
      return sign + s
    end
  end

  # Format a string
  def format(val,         # value
             format_str,  # printf-style format string
             width,       # resulting field width, space-padded from the left
             blockwidth,  # width of digit blocks (3 for thousands, etc.)
             prefix)      # prefix string to prepend seperated string
    s = prefix + sep_s( sprintf(format_str, val), blockwidth )
    ln = s.length
    ln = width if ln > width
    s = ' '*(width-ln) + s
    return s
  end

  # Convert number to multiple-base string
  def val_to_s(v)
    return "'#{v}'" if v.class == String
    hexval  = format(v, '%08x', 8+3, 4, '0x')
    decval  = format(v, '%d', 14+3, 3, v < 0 ? ' ' : '+')
    udecval = format(v, '%u', 14+3, 3, '')
    octval  = format(v, '%o', 24+3, 3, '0')
    binval  = format(v, '%032b', 32+3, 4, '0b')
    sep = ' | '
    return hexval + sep + binval + sep + decval + sep + udecval + sep + octval
  end

  def show_help
    puts "Reserved words and operators:"
    puts @ops.keys.sort.join(', ')
    puts "Variable assignment:  'varname' ="
    puts "Function declaration: [ ... ] 'funcname' ="
  end

  def print_stack
    i = @s.values.length
    @s.values.each { |v| puts sprintf("%10d = %s", i, val_to_s(v)); i -= 1 }
  end

  def print_vars
    @vars.vars.each { |k, v| puts sprintf("%-10s = %s", k, val_to_s(v)) }
  end

  def top_str
    @s.is_empty? ? "<empty>" : val_to_s(@s.top)
  end

  #
  # Factors
  #

  def suffix_factor(suffix)
    case suffix.upcase
    when 'G'
      return 1024*1024*1024
    when 'M'
      return 1024*1024
    when 'K'
      return 1024
    else
      return 1
    end
  end

  #
  # Function def.
  #

  def append_to_func_def(tok)
    return false if @func == nil
    case tok
    when '['
      @func = nil
      raise "Cannot handle recursive function definition"
    when ']'
      @s.push(@func.join(' '))
      @func = nil
    else
      @func << tok
    end
    return true
  end

  #
  # Parsing
  #

  def parse_line(line)
    tokens = line.strip.split(/[ \t\n]+/)
    tokens.each { |t|
      begin
        parse_and_eval(t)
      rescue => msg
        puts "Error: #{t}: #{msg}"
        return   # Abort processing of remainder of line
      end
    }
  end

  def parse_and_eval(tok)
    begin
      @nesting += 1
      if @nesting > MAX_NESTING then
        raise "Parsing nested too deeply (> #{MAX_NESTING} levels)" 
      end
      parse_and_eval_core(tok)
    ensure
      @nesting -= 1
    end
  end

  # NOTE - should be called by parse_and_eval() only
  def parse_and_eval_core(tok)
    return if append_to_func_def(tok)   # In-progress function definition

    # If we get here, we are not defining a func. Check if it's an operation:

    if @ops.has_key?(tok)
      @ops[tok].call
      return
    end

    # Not an operation, then it's a number, variable, etc.

    case tok
      when /^[+-]?[1-9][0-9]*\.?[0-9]*[eE][+-]?[0-9]+$/    # (Decimal) with exponent: 
        @s.push((tok.to_f).to_i)      
    when /^([+-]?[1-9][0-9]*)([GMk])$/     # (Decimal) giga/mega/kilo
      @s.push($1.to_i * suffix_factor($2))      
    when /^[+-]?0b[01_\.]+$/i,        # Binary
         /^[+-]?0x[0-9a-f_\.]+$/i,    # Hex
         /^[+-]?0[0-7_\.]*$/,         # Octal
         /^[+-]?[1-9][0-9_\.]*$/      # Decimal
      @s.push(eval(tok.gsub(/\./, '')))
    when /^[a-z_][a-z_0-9]*$/i        # Var value
      val = @vars.get(tok)
      if val.class == String then     # String var: Function invocation
        parse_line(val)
      else
        @s.push(val)                  # Non-string var: Push value
      end
    when /^'([a-z_][a-z_0-9]*)'?$/i   # Var name. Note: Final ' is optional
      name = $1
      if @ops.has_key?(name)
        raise "Reserved word cannot be used as variable name: #{name}" 
      end
      @s.push(name)
    else
      puts "Unmatched token: [#{tok}]"
    end
  end

end



#
# Main
#

RC_FILE = ENV['HOME'] + '/.hexcalcrc'

c = Calculator.new

c.load(RC_FILE) if File.exists?(RC_FILE)

if ARGV.length == 0 then
  puts "Hexcalc 1.2, a Reverse Polish Notation Hex Calculator. " +
    "(c) Martin Eskildsen 2011"
  c.loop
else
  ARGV.each { |a| c.parse_line(a) }
  c.print_top
end

puts "Bye"
exit(0)

require 'pp'

class HackyStack
	def initialize
		@stack = []
		@argnum = 0
	end

	def <<(val)
		@stack << val
	end

	def dup
		elem = pop
		@stack << elem << elem
	end

	def pop
		return @stack.pop if @stack.size > 0
		puts 'argument'
		@argnum += 1
		[:argument, @argnum]
	end

	def get num
		ret = []
		num.times do
			ret << pop
		end
		ret.reverse
	end
end

$builtins = {
	'dup' => lambda {|s| s.dup }, 
}

funcs = {
	'dot' => 2, 
	'vec2' => 2, 
	'vec3' => 3, 
	'vec4' => 4, 
	'mod' => 2, 
	'pow' => 2
}

funcs.each do |k, v|
	$builtins[k] = eval "lambda {|s| s << [:func, :#{k}, s.get(#{v})] }"
end

'+-/*%'.each_char do |op|
	$builtins[op] = eval "lambda {|s| s << ([:arith, :#{op}] + s.get(2)) }"
end

class ShaderForth
	def compile code
		parse code
		@words.each do |k, v|
			puts k
			compileword v.flatten
		end
		nil
	end

	def compileword wordup
		stack = HackyStack.new
		wordup.each do |word|
			if $builtins.has_key? word and not @words.has_key? word
				$builtins[word].call stack
			else
				stack << word
			end
		end
		pp stack
		puts
	end

	def parse ndata
		def wordify word
			return word.to_f if word =~ /^-?[0-9.]/
			if word =~ /\./
				word = word.split '.'
				[word[0], '.' + word[1]]
			else
				word
			end
		end
		@words = {}
		main = inWord = @words['$'] = []
		while ndata != ''
			cur, sep, ndata = ndata.lstrip.partition /[;\s]/
			if cur[0] == ':'
				inWord = @words[cur[1...cur.size]] = []
			else
				inWord << wordify(cur) if not cur.empty?
			end
			inWord = main if sep == ';'
		end
	end
end

code = %q{
@vec2 uniform =resolution
@float uniform =time

:ddot dup dup dot;

:frame
	time + =z

	fragcoord.xy resolution / 8 * 4 -
	z .0125 8 .1 + *
	ddot *
	ddot .1 / atan *

	ddot =v cos * z z 1.5 + v 8 1.5 * pow / abs sqrt .05 mod .1 / tan

	dup \/ sin swap 1 swap .y / cos * z .2 * 1 min * .2 * =v
	v 0 > if
		v .8 / v v 1.5 * 1
	else
		v -.2 * v .3 * z sin * v -.2 * 1
	then
	vec4
;

[ -.1 -.05 0 .05 .1 ] /frame \+ =gl_FragColor}

code = '@vec2 uniform =resolution :ddot dup dup dot; :add +; :add-five 5 +; gl_FragCoord.xy resolution / .5 - ddot dup dup dup =gl_FragColor'
puts ShaderForth.new.compile(code)

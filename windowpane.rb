require 'erb'
require 'jsmin'

class String
	def jsstr
		out = ''
		quote = self.include?("'") ? '"' : "'"
		self.each_char do |x|
			case x
				when "\n" then out += '\n'
				when "\t" then out += '\t'
				when quote then out += '\\' + quote
				else
					out += x
			end
		end
		quote + out + quote
	end
end

def shadermin(shader)
	shader.gsub! /\/\/.*$/, ''
	shader.gsub! /\s+/m, ' '
	shader.gsub! /\/\*.*?\*\//, ''
	shader.gsub! /\.0+([^0-9])/, '.\1'
	shader.gsub! /\s*(;|{|}|\(|\)|=|\+|-|\*|\/|\[|\]|,|\.|%|!|~|\?|:)\s*/m, '\1'
	shader.strip!
	shader
end

$i = 0
$alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'
$alphanum = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789'
def createIdentifier
	ident = ''
	$i += 1
	ti = $i
	while ti > 0
		if ident.size == 0
			ident += $alpha[ti % $alpha.size]
			ti /= $alpha.size
		else
			ident += $alphanum[ti % $alphanum.size]
			ti /= $alphanum.size
		end
	end
	'$' + ident
end

$defaultTransform = shadermin %q{
	attribute vec2 p;
	
	void main(void) {
		gl_Position = vec4(p.xy, 0.0, 1.0);
	}
}

def build(fn)
	$i = 0
	file = File.read(fn)
	
	title = /<title>(.*?)<\/title>/m.match(file) { |m| m[1].strip } || fn
	tfshaders = {}
	file.scan(/<fshader\s(.*?)>(.*?)<\/fshader>/m) do |m|
		tfshaders[m[0].strip] = "#ifdef GL_ES\nprecision highp float;\n#endif\n" + shadermin(m[1].strip)
	end
	tvshaders = {}
	file.scan(/<vshader\s(.*?)>(.*?)<\/vshader>/m) do |m|
		tvshaders[m[0].strip] = shadermin(m[1].strip)
	end
	tprograms = {}
	file.scan(/<program\s*?(\s.+?)?>(.*?)<\/program>/m) do |m|
		tprograms[(m[0] || 'main').strip] = m[1].strip.split ' '
	end
	update = /<update>(.*?)<\/update>/m.match(file) { |m| m[1].strip } || nil
	drawMulti = (file =~ /<singleframe>/) == nil
	errorChecking = (file =~ /<checkerrors>/) != nil
	
	tprograms.each do |k, v|
		next if v.size != 1
		tvshaders['defaultTransform'] ||= $defaultTransform
		tprograms[k] << 'defaultTransform'
	end
	
	remap = {}
	programs = {}
	tprograms.each do |k, v|
		remap[k] = createIdentifier
		programs[remap[k]] = v.map do |x|
			remap[x] = createIdentifier if not remap.include? x
			remap[x]
		end
	end
	
	vshaders = {}
	tvshaders.each do |k, v|
		vshaders[remap[k]] = v if remap.include? k
	end
	fshaders = {}
	tfshaders.each do |k, v|
		fshaders[remap[k]] = v if remap.include? k
	end
	
	count = {}
	programs.each do |k, v|
		v.each do |x|
			if not count.include? x
				count[x] = 1
			else
				count[x] += 1
			end
		end
	end
	
	fshadersinline = {}
	vshadersinline = {}
	count.each do |k, v|
		next if v != 1
		if fshaders.include? k
			fshadersinline[k] = fshaders[k]
			fshaders.delete k
		else
			vshadersinline[k] = vshaders[k]
			vshaders.delete k
		end
	end
	
	script = ERB.new(File.read('script.jst')).result(binding)
	script = JSMin.minify script
	script.gsub! /\}\n/, '}'
	script.gsub! /\n\{/, '{'
	script.strip!
	
	doc = %Q{<title>#{title}</title><script>#{script}</script><body onload="r()" style="margin:0px;overflow:hidden"><canvas style="width:100%;height:100%">}
	puts "Size: #{doc.size} bytes"
	doc
end

if ARGV.size == 0
	puts 'Usage: ruby windowpane.rb <demo.wpd> [<output.html>]'
	puts 'If you leave off the output file, Windowpane operates in server mode on port 4567'
elsif ARGV.size == 1
	require 'sinatra'
	require 'sinatra/reloader'
	
	get '/' do
		build ARGV[0]
	end
else
	File.open(ARGV[1], 'w').write(build ARGV[0])
end

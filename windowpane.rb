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
	shader.gsub! /\.0+([^1-9])/, '.\1'
	shader.gsub! /\s*(;|{|}|\(|\)|=|\+|-|\*|\/|\[|\]|,|\.|%|!|~|\?|:)\s*/m, '\1'
	shader
end

$defaultTransform = %q{
	attribute vec2 pos;
	varying vec2 p;
	
	void main(void) {
		p = pos;
		gl_Position = vec4(pos.xy, 0.0, 1.0);
	}
}

def build(fn)
	file = File.read(fn)
	
	title = /<title>(.*?)<\/title>/m.match(file) { |m| m[1].strip } || fn
	fshaders = {}
	file.scan(/<fshader\s(.*?)>(.*?)<\/fshader>/m) do |m|
		fshaders[m[0].strip] = "#ifdef GL_ES\nprecision highp float;\n#endif\n" + shadermin(m[1].strip)
	end
	vshaders = {}
	file.scan(/<vshader\s(.*?)>(.*?)<\/vshader>/m) do |m|
		vshaders[m[0].strip] = shadermin(m[1].strip)
	end
	programs = {}
	file.scan(/<program\s*?(\s.+?)?>(.*?)<\/program>/m) do |m|
		programs[(m[0] || 'main').strip] = m[1].strip.split ' '
	end
	update = /<update>(.*?)<\/update>/m.match(file) { |m| m[1].strip } || nil
	drawMulti = (file =~ /<singleframe>/) == nil
	
	programs.each do |k, v|
		next if v.size != 1
		vshaders['defaultTransform'] ||= $defaultTransform
		programs[k] << 'defaultTransform'
	end
	
	script = ERB.new(File.read('script.jst')).result(binding)
	script = JSMin.minify script
	
	doc = %Q{<!doctype html><title>#{title}</title><script>#{script}</script><body onload="r()" style="width:100%;height:100%;border:0px;padding:0px;margin:0px;overflow:hidden"><canvas id="c" style="width:100%;height:100%">}
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

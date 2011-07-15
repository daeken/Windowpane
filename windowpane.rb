require 'erb'
require 'jsmin'
require 'chunky_png'
require 'pp'

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
	shader.gsub! '$resolution', 'r'
	shader.gsub! '$time', 't'
	shader.gsub! /\/\/.*$/, ''
	shader.gsub! /\s+/m, ' '
	shader.gsub! /\/\*.*?\*\//, ''
	shader.gsub! /\.0+([^0-9])/, '.\1'
	shader.gsub! /0+([1-9]+\.[^a-z_])/i, '\1'
	shader.gsub! /0+([1-9]*\.[0-9])/, '\1'
	shader.gsub! /\s*(;|{|}|\(|\)|=|\+|-|\*|\/|\[|\]|,|\.|%|!|~|\?|:|<|>)\s*/m, '\1'
	shader.strip!
	shader
end

def scriptmin(script)
	script = JSMin.minify script
	script.gsub! /\}\n/, '}'
	script.gsub! /\n\{/, '{'
	script.gsub! /([a-z_0-9])\n/i, '\1;'
	script.gsub! /\n/, ''
	script.strip
end

$i = 0
$alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_' # abcdefghijklmnopqrstuvwxyz
$alphanum = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789' # abcdefghijklmnopqrstuvwxyz
def createIdentifier(x)
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
	ident
end

$defaultTransform = shadermin %q{
	attribute vec3 p;
	
	void main() {
		gl_Position = vec4(p.xyz-1.0, 1);
	}
}

def build(fn, png=false)
	$i = 0
	file = File.read(fn)
	
	title = /<title>(.*?)<\/title>/m.match(file) { |m| m[1].strip } || fn
	tfshaders = {}
	file.scan(/<fshader\s(.*?)>(.*?)<\/fshader>/m) do |m|
		tfshaders[m[0].strip] = "precision highp float;" + shadermin(m[1].strip) # "#ifdef GL_ES\nprecision highp float;\n#endif\n"
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
		remap[k] = createIdentifier(k)
		programs[remap[k]] = v.map do |x|
			remap[x] = createIdentifier(x) if not remap.include? x
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
	
	script = scriptmin ERB.new(File.read('script.jst')).result(binding)
	
	if not png
		doc = %Q{<body style=margin:0;overflow:hidden onload="#{script}"><canvas><title>#{title}}
	else
		doc = script
	end
	puts "Size: #{doc.size} bytes"
	doc
end

class MagicChunk < ChunkyPNG::Chunk::Generic
	def write_with_crc(io, content)
		io << [content.length-4].pack('N') << type << content[0...content.length-4]
		io << content[content.length-4...content.length]
	end
end

class ChunkyPNG::Chunk::ImageData
	def write_with_crc(io, content)
		io << 'c=#>' << type << content # [content.length].pack('N')
		#io << $magic
	end
end

class ChunkyPNG::Chunk::End
	def write_with_crc(io, content)
		#nope.
	end
end

def buildPng(fn)
	data = build fn, true
	fp = File.open('magic.js', 'wb')
	fp.write(data)
	fp.close
	data = data.reverse.chars.to_a.map { |x| x.ord }
	script = scriptmin(ERB.new(File.read('bootstrap.jst')).result(binding))
	puts "Script size: #{script.size} bytes"
	$magic = html = '<img onload=' + script + ' sr'
	puts "HTML size: #{html.size-script.size} bytes"
	png = ChunkyPNG::Image.new data.size, 1
	#png.metadata['foo'] = html
	data.size.times do |i|
		png[i, 0] = ChunkyPNG::Color.grayscale(data[i])
	end
	ds = png.to_datastream :color_mode => ChunkyPNG::COLOR_GRAYSCALE
	ds.other_chunks << MagicChunk.new('jawh', html)
	data = ds.to_blob.to_s
	fp = File.open('test.png', 'wb')
	fp.write(data)
	fp.close
	tsize = data.bytes.to_a.size
	puts "Other PNG size: #{tsize-html.size} bytes"
	puts "Total compressed size: #{tsize} bytes"
	data
end

if ARGV.size == 0
	puts 'Usage: ruby windowpane.rb <demo.wpd> [<output.html> [png]]'
	puts 'If you leave off the output file, Windowpane operates in server mode on port 4567'
elsif ARGV.size == 1
	require 'sinatra'
	require 'sinatra/reloader'
	
	get '/' do
		build ARGV[0]
	end

	get '/png' do
		buildPng ARGV[0]
	end

	get '/favicon.ico' do end
else
	if ARGV.size > 2 and ARGV[2] == 'png'
		File.open(ARGV[1], 'wb').write(buildPng ARGV[0])
	else
		File.open(ARGV[1], 'wb').write(build ARGV[0])
	end
end

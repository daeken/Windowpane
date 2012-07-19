require 'erb'
require 'jsmin'
require 'chunky_png'
require 'pp'

class String
	def jsstr(quote=nil)
		out = ''
        if not quote
		    quote = self.include?("'") ? '"' : "'"
        end
		self.each_char do |x|
			case x
				when "\n" then out += '\n'
				when "\t" then out += '\t'
				when quote then out += '\\' + quote
				else
					out += x
			end
		end
		#out.gsub! /void main\(\){/, (quote + '+n+' + quote)
		quote + out + quote
	end
end

def shadermin(shader)
	shader.gsub! '$resolution', 'r'
	shader.gsub! '$time', 'r.z'
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

def build(fn, png=false, svg=false)
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

	vshader = vshadersinline[vshadersinline.keys[0]]
	fshader = fshadersinline[fshadersinline.keys[0]]

	$rebind = rebind = true

	def name(func)
		func = func.to_s
		if $rebind
			if func == 'uniform3f'
				'g.' + func
			else
				func[0] + func[6]
			end
		else
			'g.' + func
		end
	end
	
	$binding = binding
	script = ERB.new(File.read(if svg then 'scriptsvg.jst' else 'script.jst' end)).result($binding)
	script = script.gsub(/@MIN@(.*?)@MIN@/m) do |s|
		s = s[5...-5]
		scriptmin(s).jsstr("'")
	end
	script = scriptmin script
	
	if png or svg
		doc = script
	else
		doc = %Q{<body id=s style=margin:0;overflow:hidden onload="#{script}"><canvas><title>#{title}}
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
	def self.split_in_chunks(data, level = Zlib::DEFAULT_COMPRESSION, chunk_size = 2147483647)
		#streamdata = Zlib::Deflate.deflate(data, level)
		z = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, 15, Zlib::MAX_MEM_LEVEL, Zlib::DEFAULT_STRATEGY)
		streamdata = z.deflate data, Zlib::FULL_FLUSH
		z.close
		$csize = streamdata.bytes.to_a.size
		# TODO: Split long streamdata over multiple chunks
		[ ChunkyPNG::Chunk::ImageData.new('IDAT', streamdata) ]
	end
	def write_with_crc(io, content)
		#io << 'c=#>' << type << content # [content.length].pack('N')
		io << [content.length].pack('N') << type << content
		io << '>' if content.include? '<'
		io << $magic
	end
end

class ChunkyPNG::Chunk::End
	def write_with_crc(io, content)
		#nope.
	end
end

def bwt(s)
	s += "\0"
	table = (0...s.size).map {|i|
		s[i...s.length] + s[0...i]
	}.sort
	table.map {|x| x[-1] }.join ''
end

def buildPng(fn)
	data = ';' + build(fn, true)
	fp = File.open('magic.js', 'wb')
	fp.write(data)
	fp.close
	#data = bwt data
	#puts data
	#puts "foo #{data.size}"
	data = data.reverse.chars.to_a.map { |x| x.ord }
	script = scriptmin(ERB.new(File.read('bootstrap.jst')).result(binding))
	puts "Script size: #{script.size} bytes"
	$magic = html = '<body id=s><canvas id=q><img onload=' + script + ' src=#>'
	puts "HTML size: #{html.size-script.size} bytes"
	png = ChunkyPNG::Image.new data.size, 1
	#png.metadata['foo'] = html
	data.size.times do |i|
		png[i, 0] = ChunkyPNG::Color.grayscale(data[i])
	end
	ds = png.to_datastream :color_mode => ChunkyPNG::COLOR_GRAYSCALE
	#ds.other_chunks << MagicChunk.new('jawh', html)
	data = ds.to_blob.to_s
	fp = File.open('test.png', 'wb')
	fp.write(data)
	fp.close
	tsize = data.bytes.to_a.size
	puts "Other PNG size: #{tsize-html.size} bytes"
	puts "IDAT size: #{$csize}"
	puts "Total PNG overhead: #{tsize-$csize}"
	puts "Total compressed size: #{tsize} bytes"
	data
end

require 'zlib'
def buildSvgz(fn)
	html = build ARGV[0]
	puts "HTML size: #{html.size}"
	puts "HTML compressed solo: #{compress(html).bytes.to_a.size}"
	enc = html.gsub(/&/, '&amp;').gsub(/</, '&lt;').gsub(/"/, '&quot;').gsub(/\\/, "\\\\\\\\").gsub(/'/, "\\\\'")
	puts "Encoded size: #{enc.size}"
	#out = '<svg xmlns="http://www.w3.org/2000/svg" onload="location=\'data:text/html,' + enc + '\'"/>'
	out = %q{<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN" 
 "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">

<svg xmlns="http://www.w3.org/2000/svg" 
 xmlns:xlink="http://www.w3.org/1999/xlink" 
 width='300px' height='300px'>

<title>Small SVG example</title>

<circle cx='120' cy='150' r='60' style='fill: gold;'>
 <animate attributeName='r' from='2' to='80' begin='0' 
 dur='3' repeatCount='indefinite' /></circle>

<polyline points='120 30, 25 150, 290 150' 
 stroke-width='4' stroke='brown' style='fill: none;' />

<polygon points='210 100, 210 200, 270 150' 
 style='fill: lawngreen;' /> 
   
<text x='60' y='250' fill='blue'>Hello, World!</text>

</svg>}
	puts "SVG size: #{out.size}"
	out = compress out
	puts "Compressed size: #{out.bytes.to_a.size}"

	out
end

def compress(data)
	#csvg = Zlib::Deflate.deflate data, Zlib::BEST_COMPRESSION
	#return csvg
	StringIO.open '', 'wb' do |io|
		w = Zlib::GzipWriter.new io, Zlib::BEST_COMPRESSION, Zlib::DEFAULT_STRATEGY
		w << data
		w.close
		return io
	end
end

if ARGV.size == 0
	puts 'Usage: ruby windowpane.rb <demo.wpd> [<output.html> [png]]'
	puts 'If you leave off the output file, Windowpane operates in server mode on port 4567'
elsif ARGV.size == 1
	require 'sinatra'
	#require 'sinatra/reloader'
	
	get '/' do
		build ARGV[0]
	end

	get '/png' do
		buildPng ARGV[0]
	end
	
	get '/svg' do
		headers 'Content-Type' => 'image/svg+xml'

		html = build ARGV[0]
		enc = html.gsub(/&/, '&amp;').gsub(/</, '&lt;').gsub(/"/, '&quot;').gsub(/\\/, "\\\\\\\\").gsub(/'/, "\\\\'")

		'<svg xmlns="http://www.w3.org/2000/svg" onload="window.location=\'data:text/html,' + enc + '\'"/>'
	end

	get '/svgz' do
		headers 'Content-Type' => 'image/svg+xml', 'Content-Encoding' => 'deflate'
		buildSvgz ARGV[0]
	end

	get '/favicon.ico' do end
else
	if ARGV.size > 2 and ARGV[2] == 'png'
		File.open(ARGV[1], 'wb').write(buildPng ARGV[0])
	elsif ARGV.size > 2 and ARGV[2] == 'svgz'
		File.open(ARGV[1], 'wb').write(buildSvgz ARGV[0])
	else
		File.open(ARGV[1], 'wb').write(build ARGV[0])
	end
end

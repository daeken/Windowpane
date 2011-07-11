require 'sinatra'
require 'sinatra/reloader'

get '/' do
	ERB.new(File.read('templates/main.erb')).result(binding)
end

get '/scripts/:name' do |name|
	return if name.include? '/' or name.include? '\\'
	ERB.new(File.read('scripts/' + name)).result(binding)
end

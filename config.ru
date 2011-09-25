$:.unshift(File.expand_path('../lib', __FILE__))

config_file_name = ENV['FOIL_CONFIG']
abort "You need to set FOIL_CONFIG to a configuration file" unless config_file_name

require 'foil/boot'

app = Foil::Application.new
app.configure!(YAML.load(File.read(config_file_name)))

run Foil::Handler

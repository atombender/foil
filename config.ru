$:.unshift(File.expand_path('../lib', __FILE__))

require 'foil/boot'
run Foil::Webapp

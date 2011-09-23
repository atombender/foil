require 'rubygems'

require 'bundler'
Bundler.require

require 'sinatra/base'

require 'time'
require 'logger'
require 'yaml'
require 'securerandom'
require 'active_support'
require 'active_support/core_ext'
require 'stringio'

require 'foil/application'
require 'foil/webapp'
require 'foil/repository'
require 'foil/mount'
require 'foil/configuration'
require 'foil/context'
require 'foil/daemon'
require 'foil/path'
require 'foil/adapters/s3_adapter'
require 'foil/adapters/local_adapter'

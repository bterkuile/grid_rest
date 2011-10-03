

Dir[File.join(File.expand_path(File.dirname(__FILE__)), 'support', '**', '*.rb')].each {|f| require f}
module Rails
  def self.root
    File.expand_path(File.dirname(__FILE__))
  end

  def self.env
    'test'
  end

  def self.logger
    Logger.new(File.join(root, 'log', 'test.log'))
  end
  class Engine
    def self.config(*args)
      RespondToEverything.new    
    end
    def self.initializer(*args)
      RespondToEverything.new    
    end
  end
end

class RespondToEverything
  def method_missing(m, *args)
  end
end

class GridRestTest
end

require 'grid_rest'
require 'capybara/rspec'
require 'i18n'
I18n.load_path << Dir[File.join(Rails.root, '..', 'config', 'locales', '*.{rb,yml}')]

RSpec.configure do |config|
  config.mock_with :rspec
end

GridRest.load_config!

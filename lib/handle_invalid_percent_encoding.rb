require 'atmosphere/json_error_handler'
require 'rack'
require 'logger'
class HandleInvalidPercentEncoding
  include Atmosphere::JsonErrorHandler

  DEFAULT_CONTENT_TYPE = 'text/html'
  DEFAULT_CHARSET      = 'utf-8'

  attr_reader :logger
  def initialize(app, stdout=STDOUT)
    @app = app
    @logger = defined?(Rails.logger) ? Rails.logger : Logger.new(stdout)
  end

  def call(env)
    begin
      # calling env.dup here prevents bad things from happening
      request = Rack::Request.new(env.dup)
      # calling request.params is sufficient to trigger the error
      # see https://github.com/rack/rack/issues/337#issuecomment-46453404
      request.params
      @app.call(env)
    rescue ArgumentError => e
      raise unless e.message =~ /invalid %-encoding/
      @logger.debug("Wywoływane!")
      render_json_error('Wrong encoding', status: :forbidden, type: :forbidden)
    end
  end
end
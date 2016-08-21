module Grape
  module Middleware
    class ThrottleMiddleware < Grape::Middleware::Base
      COUNTER_START = 0
      def before
        endpoint = env['api.endpoint']
        logger   = options[:logger] || Logger.new(STDOUT)
        return unless throttle_options = endpoint.route_setting(:throttle)

        if limit = throttle_options[:hourly]
          period = 1.hour
        elsif limit = throttle_options[:daily]
          period = 1.day
        elsif limit = throttle_options[:monthly]
          period = 1.month
        elsif period = throttle_options[:period]
          limit = throttle_options[:limit]
        end
        if limit.nil? || period.nil?
          raise ArgumentError.new('Please set a period and limit (see documentation)')
        end
        
        if limit.is_a?(Proc)
          limit = limit.call(params)
        end

        user_key = throttle_options[:user_key]
        user_value = nil
        user_value = user_key.call(params) unless user_key.nil?
        user_value ||= "ip:#{env['REMOTE_ADDR']}"

        r = endpoint.routes.first
        rate_key = "#{user_value}"
        
        redis = options[:cache]
        begin
          redis.ping
          current = redis.get(rate_key).to_i
          if limit != 0
            if !current.nil? && current >= limit
              endpoint.error!("too many requests, please try again later", 429)
            else
              redis.multi do
                # Set the value of the key to COUNTER_START if the key does not already exist and
                # set the expiry only on creation to avoid clobbering it later
                redis.set(rate_key, COUNTER_START, { :nx => true, :ex => period.to_i } )
                redis.incr(rate_key)
              end
            end
          end

        rescue Exception => e
          logger.warn(e.message)
        end

      end
      
      def request
        @request ||= ::Rack::Request.new(env)
      end
      
      def params
        @params ||= request.params.to_hash
      end

    end
  end
end

module Mongoriver
    module Logging
      def log
        @@logger ||=  Logger::Logger.new($stderr, progname: 'Stripe::Mongoriver')
      end
    end
end
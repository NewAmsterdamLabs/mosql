module MoSQL
  module Logging
    def log
      @@logger ||= Logger::Logger.new($stderr, progname: "Stripe::MoSQL")
    end
  end
end

require "spec_helper"

RSpec.describe Sentry::Rails, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:event) do
    transport.events.last.to_json_compatible
  end

  after do
    transport.events = []
  end

  context "with simplist config" do
    before do
      make_basic_app
    end

    it "has version set" do
      expect(described_class::VERSION).to be_a(String)
    end

    it "inserts middleware to a correct position" do
      app = Rails.application
      expect(app.middleware.find_index(Sentry::Rails::CaptureExceptions)).to eq(0)
      expect(app.middleware.find_index(Sentry::Rails::RescuedExceptionInterceptor)).to eq(app.middleware.count - 1)
    end

    it "sets Sentry.configuration.logger correctly" do
      expect(Sentry.configuration.logger).to eq(Rails.logger)
    end

    it "sets Sentry.configuration.project_root correctly" do
      expect(Sentry.configuration.project_root).to eq(Rails.root.to_s)
    end

   
    it "doesn't clobber a manually configured release" do
      expect(Sentry.configuration.release).to eq('beta')
    end

    it "sets transaction to ControllerName#method" do
      get "/exception"

      expect(transport.events.last.transaction).to eq("HelloController#exception")

      get "/posts"

      expect(transport.events.last.transaction).to eq("PostsController#index")
    end

    it "sets correct request url" do
      get "/exception"

      expect(event.dig("request", "url")).to eq("http://www.example.com/exception")
    end
  end

  context "with development config" do
    before do
      make_basic_app do |config, app|
        app.config.consider_all_requests_local = true
        config.rails.report_rescued_exceptions = report_rescued_exceptions
      end
    end

    context "with report_rescued_exceptions = true" do
      let(:report_rescued_exceptions) { true }

      it "captures exceptions" do
        get "/exception"

        expect(response.status).to eq(500)

        expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
        expect(event["exception"]["values"][0]["value"]).to eq("An unhandled exception!")
      end
    end

    context "with report_rescued_exceptions = false" do
      let(:report_rescued_exceptions) { false }

      it "doesn't report rescued exceptions" do
        get "/exception"

        expect(transport.events.count).to eq(0)
      end
    end
  end

  context "with production config" do
    before do
      make_basic_app do |config, app|
        app.config.consider_all_requests_local = false
      end
    end

    it "doesn't do anything on a normal route" do
      get "/"

      expect(response.status).to eq(200)
      expect(transport.events.size).to eq(0)
    end

    it "excludes commonly seen exceptions (like RecordNotFound)" do
      get "/not_found"

      expect(response.status).to eq(400)
      expect(transport.events).to be_empty
    end

    it "captures exceptions" do
      get "/exception"

      expect(response.status).to eq(500)

      expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
      expect(event["exception"]["values"][0]["value"]).to eq("An unhandled exception!")
      expect(event["sdk"]).to eq("name" => "sentry.ruby.rails", "version" => Sentry::Rails::VERSION)
    end

    it "filters exception backtrace with custom BacktraceCleaner" do
      get "/view_exception"

      traces = event.dig("exception", "values", 0, "stacktrace", "frames")
      expect(traces.dig(-1, "filename")).to eq("inline template")

      # we want to avoid something like "_inline_template__3014794444104730113_10960"
      expect(traces.dig(-1, "function")).to be_nil
    end

    it "doesn't filters exception backtrace if backtrace_cleanup_callback is overridden" do
      original_cleanup_callback = Sentry.configuration.backtrace_cleanup_callback

      begin
        Sentry.configuration.backtrace_cleanup_callback = nil

        get "/view_exception"

        traces = event.dig("exception", "values", 0, "stacktrace", "frames")
        expect(traces.dig(-1, "filename")).to eq("inline template")
        expect(traces.dig(-1, "function")).not_to be_nil
      ensure
        Sentry.configuration.backtrace_cleanup_callback = original_cleanup_callback
      end
    end

    context "with config.exceptions_app = self.routes" do
      before do
        make_basic_app do |config, app|
          app.config.exceptions_app = app.routes
        end
      end

      it "sets transaction to ControllerName#method" do
        get "/exception"

        expect(transport.events.last.transaction).to eq("HelloController#exception")

        get "/posts"

        expect(transport.events.last.transaction).to eq("PostsController#index")
      end

      it "sets correct request url" do
        get "/exception"

        expect(event.dig("request", "url")).to eq("http://www.example.com/exception")
      end
    end
  end
  
  context "with trusted proxies set" do
    before do
      make_basic_app do |config, app|
        app.config.action_dispatch.trusted_proxies = ["5.5.5.5"]
      end
    end

    it "sets Sentry.configuration.trusted_proxies correctly" do
      expect(Sentry.configuration.trusted_proxies).to eq(["5.5.5.5"])
    end
  end
end

require "http/client"

# Simple Prometheus-compatible metrics implementation for Crystal
module Metrics
  class Counter
    property name : String
    property help : String
    property value : Atomic(Int64)
    property labels : Hash(String, String)

    def initialize(@name : String, @help : String, @labels = Hash(String, String).new)
      @value = Atomic(Int64).new(0)
    end

    def increment(amount = 1)
      @value.add(amount)
    end

    def to_prometheus
      label_str = labels.empty? ? "" : "{#{labels.map { |k, v| "#{k}=\"#{v}\"" }.join(",")}}"
      "# HELP #{name} #{help}\n# TYPE #{name} counter\n#{name}#{label_str} #{value.get}\n"
    end
  end

  class Gauge
    property name : String
    property help : String
    property value : Atomic(Float64)
    property labels : Hash(String, String)

    def initialize(@name : String, @help : String, @labels = Hash(String, String).new)
      @value = Atomic(Float64).new(0.0)
    end

    def set(val : Float64)
      @value.set(val)
    end

    def inc(amount = 1.0)
      # Atomic add for Float64 isn't directly available, so we use compare_and_set loop
      loop do
        current = @value.get
        new_value = current + amount
        break if @value.compare_and_set(current, new_value)
      end
    end

    def dec(amount = 1.0)
      inc(-amount)
    end

    def to_prometheus
      label_str = labels.empty? ? "" : "{#{labels.map { |k, v| "#{k}=\"#{v}\"" }.join(",")}}"
      "# HELP #{name} #{help}\n# TYPE #{name} gauge\n#{name}#{label_str} #{value.get}\n"
    end
  end

  class Histogram
    property name : String
    property help : String
    property buckets : Array(Float64)
    property bucket_counts : Array(Atomic(Int64))
    property sum : Atomic(Float64)
    property count : Atomic(Int64)
    property labels : Hash(String, String)

    def initialize(@name : String, @help : String, @buckets = [0.1, 0.5, 1.0, 2.0, 5.0, 10.0], @labels = Hash(String, String).new)
      @bucket_counts = buckets.map { Atomic(Int64).new(0) }
      @sum = Atomic(Float64).new(0.0)
      @count = Atomic(Int64).new(0)
    end

    def observe(value : Float64)
      @count.add(1)
      
      # Add to sum using compare_and_set loop
      loop do
        current = @sum.get
        new_value = current + value
        break if @sum.compare_and_set(current, new_value)
      end

      # Increment appropriate buckets
      buckets.each_with_index do |bucket_limit, i|
        if value <= bucket_limit
          bucket_counts[i].add(1)
        end
      end
    end

    def to_prometheus
      label_str = labels.empty? ? "" : "{#{labels.map { |k, v| "#{k}=\"#{v}\"" }.join(",")}}"
      result = "# HELP #{name} #{help}\n# TYPE #{name} histogram\n"
      
      # Output buckets
      buckets.each_with_index do |bucket_limit, i|
        bucket_label = label_str.empty? ? "{le=\"#{bucket_limit}\"}" : "#{label_str[0..-2]},le=\"#{bucket_limit}\"}"
        result += "#{name}_bucket#{bucket_label} #{bucket_counts[i].get}\n"
      end
      
      # +Inf bucket
      inf_label = label_str.empty? ? "{le=\"+Inf\"}" : "#{label_str[0..-2]},le=\"+Inf\"}"
      result += "#{name}_bucket#{inf_label} #{count.get}\n"
      
      # Sum and count
      result += "#{name}_sum#{label_str} #{sum.get}\n"
      result += "#{name}_count#{label_str} #{count.get}\n"
      
      result
    end
  end

  # Registry to hold all metrics
  class Registry
    property counters : Array(Counter)
    property gauges : Array(Gauge)
    property histograms : Array(Histogram)

    def initialize
      @counters = Array(Counter).new
      @gauges = Array(Gauge).new
      @histograms = Array(Histogram).new
    end

    def counter(name : String, help : String, labels = Hash(String, String).new)
      counter = Counter.new(name, help, labels)
      @counters << counter
      counter
    end

    def gauge(name : String, help : String, labels = Hash(String, String).new)
      gauge = Gauge.new(name, help, labels)
      @gauges << gauge
      gauge
    end

    def histogram(name : String, help : String, buckets = [0.1, 0.5, 1.0, 2.0, 5.0, 10.0], labels = Hash(String, String).new)
      histogram = Histogram.new(name, help, buckets, labels)
      @histograms << histogram
      histogram
    end

    def to_prometheus
      result = ""
      counters.each { |c| result += c.to_prometheus }
      gauges.each { |g| result += g.to_prometheus }
      histograms.each { |h| result += h.to_prometheus }
      result
    end
  end

  # Global registry instance
  REGISTRY = Registry.new

  # Application-specific metrics for CrystalDocs
  HTTP_REQUESTS_TOTAL = REGISTRY.counter("http_requests_total", "Total HTTP requests")
  HTTP_REQUEST_DURATION = REGISTRY.histogram("http_request_duration_seconds", "HTTP request duration in seconds")
  ACTIVE_CONNECTIONS = REGISTRY.gauge("active_connections", "Current active connections")
  DOC_BUILD_DURATION = REGISTRY.histogram("doc_build_duration_seconds", "Documentation build duration in seconds")
  DOC_BUILD_FAILURES_TOTAL = REGISTRY.counter("doc_build_failures_total", "Total documentation build failures")
  STORAGE_OPERATIONS_TOTAL = REGISTRY.counter("storage_operations_total", "Total storage operations")
  DATABASE_CONNECTIONS = REGISTRY.gauge("database_connections", "Current database connections")
  CACHE_HITS_TOTAL = REGISTRY.counter("cache_hits_total", "Total cache hits")
  CACHE_MISSES_TOTAL = REGISTRY.counter("cache_misses_total", "Total cache misses")
  
  # Middleware to track HTTP metrics
  class MetricsHandler < Kemal::Handler
    def call(context)
      start_time = Time.utc
      
      begin
        HTTP_REQUESTS_TOTAL.increment
        ACTIVE_CONNECTIONS.inc
        
        call_next(context)
        
        # Record success
        duration = (Time.utc - start_time).total_seconds
        HTTP_REQUEST_DURATION.observe(duration)
        
        # Track search requests specifically
        if context.request.path.starts_with?("/search")
          SEARCH_DURATION.observe(duration)
        end
        
      rescue ex
        # Record error
        duration = (Time.utc - start_time).total_seconds
        HTTP_REQUEST_DURATION.observe(duration)
        raise ex
      ensure
        ACTIVE_CONNECTIONS.dec
      end
    end
  end
end
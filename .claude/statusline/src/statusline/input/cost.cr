class Statusline::Input::Cost
  include JSON::Serializable

  getter total_cost_usd : Float32
  getter total_duration_ms : Int32
  getter total_api_duration_ms : Int32
  getter total_lines_added : Int32
  getter total_lines_removed : Int32

  def total_duration
    Time::Span.new(seconds: (total_duration_ms / 1_000).to_i)
  end

  def total_api_duration
    Time::Span.new(seconds: (total_api_duration_ms / 1_000).to_i)
  end
end

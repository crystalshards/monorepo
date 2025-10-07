struct Colorize::ColorRGB
  def self.from_hex(hex : String) : ColorRGB
    if matches = /^\#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.match(hex)
      ColorRGB.new(
        matches[1].to_u8(16),
        matches[2].to_u8(16),
        matches[3].to_u8(16)
      )
    else
      raise "Invalid hex color: #{hex}"
    end
  end
end

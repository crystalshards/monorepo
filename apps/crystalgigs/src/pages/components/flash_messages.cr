class FlashMessages < Lucky::BaseComponent
  def render
    flash.each do |flash_type, flash_message|
      div class: "flash flash-#{flash_type}" do
        text flash_message
      end
    end
  end
end

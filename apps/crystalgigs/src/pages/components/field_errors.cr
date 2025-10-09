class FieldErrors < Lucky::BaseComponent
  needs attribute : Avram::PermittedAttribute

  def render
    if @attribute.errors.any?
      div class: "field-errors" do
        @attribute.errors.each do |error|
          para class: "field-error" do
            text error
          end
        end
      end
    end
  end
end

class Components::Breadcrumb < Lucky::BaseComponent
  needs items : Array(BreadcrumbItem)

  def render
    nav class: "breadcrumb", aria_label: "Breadcrumb" do
      ol class: "breadcrumb-list" do
        items.each_with_index do |item, index|
          li class: "breadcrumb-item" do
            if index < items.size - 1
              a item.label, href: item.href
              # The slash is a visual separator; the ol already conveys order.
              span " / ", class: "breadcrumb-separator", "aria-hidden": "true"
            else
              span item.label, class: "breadcrumb-current", "aria-current": "page"
            end
          end
        end
      end
    end
  end

  struct BreadcrumbItem
    getter label : String
    getter href : String

    def initialize(@label : String, @href : String)
    end
  end
end

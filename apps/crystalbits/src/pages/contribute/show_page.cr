class Contribute::ShowPage < MainLayout
  needs operation : SubmitContribution

  def page_title
    "Contribute to CrystalBits"
  end

  def content
    section class: "contribute-section" do
      render_pitch
      render_expectations
      render_form
    end
  end

  private def render_pitch
    div class: "contribute-header" do
      h1 "Write for CrystalBits"

      para class: "contribute-lede" do
        text "CrystalBits runs on what the Crystal community sends it. If you have " \
             "shipped something, learned something the hard way, or worked out why " \
             "a thing is slow, that is the post."
      end
    end
  end

  private def render_expectations
    div class: "contribute-expectations" do
      section class: "contribute-panel" do
        h2 "What we are after"
        ul do
          li "Something you did, with the specifics left in. Numbers, versions, the bit that did not work."
          li "Shard and tool write-ups from the person who built it, or from someone who used it in anger."
          li "Explanations of Crystal behaviour that took you a while to understand."
          li "Short is fine. A useful 400 words beats a padded 2000."
        end
      end

      section class: "contribute-panel" do
        h2 "What happens next"
        ol do
          li "Your submission is stored as a draft. It is not published and it is not public."
          li "An editor reads it. That is a person, and it is the only way anything reaches the site."
          li "If we publish it, it appears under your name with your canonical link if you gave one."
          li "If we do not, we tell you why using the contact you leave below."
        end

        para class: "contribute-note" do
          tag "i", class: "fa-solid fa-circle-info", "aria-hidden": "true"
          text " Nothing here is published automatically. Copyright in what you send stays yours."
        end
      end
    end
  end

  private def render_form
    div class: "contribute-form-wrapper" do
      h2 "Send us a draft"

      # form_for emits Lucky's authenticity token; a bare form tag is rejected
      # by Lucky::ProtectFromForgery with a 403.
      form_for Contributions::Create, class: "contribute-form" do
        field @operation.title, "Title", "text",
          hint: "What the piece is called. Up to 200 characters."

        field @operation.original_author, "Your name", "text",
          hint: "How you want to be credited."

        field @operation.submitter_contact, "Contact", "text",
          hint: "Email or a handle we can reach you on. Never published."

        field @operation.canonical_url, "Canonical link", "url",
          hint: "Optional. If this is already published somewhere, link it and we will point at your copy.",
          required: false

        body_field

        button type: "submit", class: "btn-primary contribute-submit" do
          text "Submit for review"
        end
      end
    end
  end

  private def field(attribute, label_text : String, input_type : String, hint : String, required : Bool = true)
    errors = attribute.errors
    id = "contribution-#{attribute.name}"

    div class: "form-field #{errors.empty? ? "" : "form-field-invalid"}" do
      label label_text, for: id

      para class: "form-hint", id: "#{id}-hint" do
        text hint
      end

      tag "input",
        type: input_type,
        id: id,
        name: "content_item:#{attribute.name}",
        value: attribute.value.to_s,
        "aria-describedby": errors.empty? ? "#{id}-hint" : "#{id}-hint #{id}-error",
        "aria-invalid": errors.empty? ? "false" : "true",
        class: "form-input",
        attrs: required ? [:required] : [] of Symbol

      render_errors(id, errors)
    end
  end

  private def body_field
    attribute = @operation.body
    id = "contribution-body"

    div class: "form-field #{attribute.errors.empty? ? "" : "form-field-invalid"}" do
      label "Post", for: id

      para class: "form-hint", id: "#{id}-hint" do
        text "Markdown. Headings, lists, links and fenced code blocks all work. " \
             "Raw HTML is stripped when we render it, so write Markdown."
      end

      textarea attribute.value.to_s,
        id: id,
        name: "content_item:body",
        rows: "18",
        "aria-describedby": attribute.errors.empty? ? "#{id}-hint" : "#{id}-hint #{id}-error",
        "aria-invalid": attribute.errors.empty? ? "false" : "true",
        class: "form-textarea",
        attrs: [:required]

      render_errors(id, attribute.errors)
    end
  end

  private def render_errors(id : String, errors : Array(String))
    return if errors.empty?

    para class: "form-error", id: "#{id}-error" do
      text errors.join(". ")
    end
  end
end

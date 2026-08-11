class About::ShowPage < MainLayout
  # What an "about" page on a documentation host is actually for: saying where
  # the pages come from and why you can trust what you are reading. The
  # provenance of the content is the product, so that is the whole page.
  def page_title
    "About"
  end

  def content
    render_intro
    render_pipeline
    render_own_rendering
    render_standard_library
    render_publishing
  end

  private def render_intro
    section class: "intro" do
      div class: "intro-copy" do
        h1 class: "intro-title" do
          text "Documentation you can "
          span class: "accent" do
            text "trace to a tag"
          end
        end

        para class: "intro-lede" do
          text "CrystalDocs builds and hosts API documentation for published " \
               "Crystal shards. Every page is generated from the source of a " \
               "tagged release, and rendered here by us."
        end
      end
    end
  end

  private def render_pipeline
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "How a page gets here"
        end
      end

      tag "ol", class: "about-steps" do
        pipeline_step(
          "A release is tagged",
          "The builder watches for tagged releases on the source repository. " \
          "There is no upload step and no dashboard to log into."
        )
        pipeline_step(
          "The compiler describes the code",
          "We run the Crystal compiler's own documentation generator against " \
          "that tag in a sandboxed build, and keep one machine-readable " \
          "document per version."
        )
        pipeline_step(
          "We render the pages",
          "Types, namespaces, signatures and READMEs are laid out by our " \
          "templates, from that document. The version in the URL is the " \
          "version you are reading."
        )
      end

      div class: "code-block" do
        pre do
          code do
            text "crystal docs --format=json"
          end
        end
      end
    end
  end

  private def pipeline_step(title : String, blurb : String)
    li do
      h3 do
        text title
      end
      para do
        text blurb
      end
    end
  end

  private def render_own_rendering
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "Why we do not serve the compiler's HTML"
        end
      end

      div class: "about-copy" do
        para do
          text "The compiler can emit a finished HTML tree as well as a " \
               "machine-readable document. We deliberately do not serve that " \
               "tree, for two reasons."
        end
        para do
          text "It ships its own theme and stylesheet, which cannot be " \
               "reconciled with ours, so the documentation would look like a " \
               "different site from the one you navigated in."
        end
        para do
          text "More importantly, it is markup written by whoever published " \
               "the shard. A doc comment can contain any markup its author " \
               "typed, and a README is Markdown, which permits inline HTML. " \
               "Serving either of those raw would hand shard authors script " \
               "execution on this origin. Both are treated as untrusted input " \
               "and sanitised before they reach a page."
        end
      end
    end
  end

  private def render_standard_library
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "The standard library is not a special case"
        end
      end

      div class: "about-copy" do
        para do
          text "Crystal's standard library is published through the same " \
               "pipeline as every shard, under the package name " \
               "#{CrystalDocs::CORE_PACKAGE}. It is built the same way, stored " \
               "the same way and rendered by the same templates."
        end
        para do
          text "That is what lets a signature mentioning a core type link " \
               "somewhere useful instead of sending you off to another site: " \
               "the page it points at is one of ours."
        end
      end

      div class: "section-footer" do
        a href: "/docs/#{CrystalDocs::CORE_PACKAGE}", class: "view-all-link" do
          text "Browse the standard library"
          tag "i", class: "fa-solid fa-arrow-right", "aria-hidden": "true"
        end
      end
    end
  end

  private def render_publishing
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "Getting your own shard documented"
        end
      end

      div class: "about-copy" do
        para do
          text "Tag a release and push the tag. The builder picks it up from " \
               "there, and the version appears once the build finishes. " \
               "There is nothing to upload and nothing to configure."
        end
      end

      div class: "code-block" do
        pre do
          code do
            text "git tag -a v1.0.0 -m \"Release v1.0.0\"\ngit push --tags"
          end
        end
      end

      div class: "section-footer" do
        a href: "/docs", class: "view-all-link" do
          text "Browse all documentation"
          tag "i", class: "fa-solid fa-arrow-right", "aria-hidden": "true"
        end
      end
    end
  end
end

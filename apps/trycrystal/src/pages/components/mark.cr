# The wordmark's mark: a faceted crystal, original geometry, drawn to sit
# beside "try crystal" at masthead size. A component rather than a CSS
# background so it is inline, scalable, and recolorable through the theme's
# currentColor without a second asset.
#
# This is a static, authored string. The `raw` below is the one place in the
# app that emits markup rather than text, and it never touches anything a
# visitor typed.
class Mark < Lucky::BaseComponent
  def render
    raw %(<svg class="mark" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false"><path d="M12 1.6 21.4 7v10L12 22.4 2.6 17V7Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M12 1.6v20.8M12 12 21.4 7M12 12 2.6 7" fill="none" stroke="currentColor" stroke-width="1" stroke-linejoin="round" opacity="0.55"/></svg>)
  end
end

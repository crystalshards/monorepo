# The middleware half of page view collection. PageViews decides what is
# recorded; this handler only decides when: after the rest of the stack has
# answered, so the row is written from the response's final status and the
# reader's page never waits on the write.
class PageViewHandler
  include HTTP::Handler

  def call(context : HTTP::Server::Context)
    call_next(context)
    PageViews.record(context)
  end
end

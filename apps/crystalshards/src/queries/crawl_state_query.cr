class CrawlStateQuery < CrawlState::BaseQuery
  def for_host(value : String) : CrawlState?
    clone.host(value).first?
  end
end

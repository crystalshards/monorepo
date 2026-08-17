# One recorded page view: the raw row the daily rollup reads and the pruner
# deletes once it is old. Nothing here identifies a person: visitor_hash is a
# salted digest (see PageViews.visitor_hash), the referrer is a host rather
# than a URL, and no address or agent string is ever stored.
class PageView < BaseModel
  # The migration's column list is the whole contract for this table. The row
  # is written once, read by the rollup, and pruned, so created_at/updated_at
  # would be dead weight on the highest-volume table the app keeps; Avram's
  # default would add both.
  skip_default_columns

  table do
    primary_key id : Int64
    column path : String
    column path_kind : String
    column referrer_host : String?
    column country : String?
    column visitor_hash : String
    column occurred_at : Time
  end
end

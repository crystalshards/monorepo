class Post < BaseModel
  table do
    column title : String
    column slug : String
    column content : String
    column excerpt : String?
    column author_name : String
    column author_email : String?
    column tags : Array(String) = [] of String
    column published_at : Time?
    column featured : Bool = false
    column view_count : Int32 = 0
  end
end

class Admin::Moderation::Update < BrowserAction
  include Auth::RequireEditor

  post "/admin/moderation/:content_item_id" do
    # Read from the submitted form rather than declaring a `param`, which
    # would make the decision part of the route and force every link that
    # points at this action to carry one.
    decision = params.get?("decision").to_s
    item = ContentItemQuery.new.id(content_item_id.to_i64).first?

    if item.nil?
      flash.failure = "That item no longer exists."
      redirect to: Admin::Moderation::Index
    else
      # No params are handed to the operation. The decision, the reviewer and
      # the note are read here and passed as attributes, so no request body
      # can nominate a state, forge a reviewer, or reach a column at all.
      ReviewContentItem.update(item,
        decision: decision,
        reviewer: current_editor,
        note: params.get?("note").presence || Avram::Nothing.new) do |operation, updated|
        if operation.saved?
          flash.success = "#{updated.title} is now #{updated.state}."
        else
          flash.failure = "Could not record that decision: #{operation.decision.errors.join(", ")}"
        end

        redirect to: Admin::Moderation::Index
      end
    end
  end
end

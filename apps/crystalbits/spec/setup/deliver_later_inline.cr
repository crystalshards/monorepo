# Runs a "later" send on the calling fiber, so an example observes what the
# send did instead of racing the spawned fiber Carbon::SpawnStrategy would
# give it.
class InlineDeliverLaterStrategy < Carbon::DeliverLaterStrategy
  def run(email : Carbon::Email, &block)
    block.call
  end
end

BaseEmail.configure do |settings|
  settings.deliver_later_strategy = InlineDeliverLaterStrategy.new
end

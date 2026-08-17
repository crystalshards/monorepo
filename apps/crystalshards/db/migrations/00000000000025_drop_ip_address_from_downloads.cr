class DropIpAddressFromDownloads::V00000000000025 < Avram::Migrator::Migration::V1
  # The downloads table recorded the caller's raw address on every download.
  # Nothing read it: no query, no page, no report. It was written because the
  # request had it to hand.
  #
  # The page view collector that now serves this site's statistics stores a
  # daily rotating salted hash and never the address itself, and a download
  # row cannot be held to a weaker rule than a page view of the same page.
  # Dropping the column is what makes the claim true of the whole database
  # rather than of one table.
  #
  # This drops data. The rollback restores the column, not the addresses,
  # which is the honest shape: a column of NULLs after a rollback is exactly
  # as much as this deployment can truthfully say about who downloaded what
  # before the migration ran.
  def migrate
    alter table_for(Download) do
      remove :ip_address
    end
  end

  def rollback
    alter table_for(Download) do
      add ip_address : String?
    end
  end
end

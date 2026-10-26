class DropLegacyEmail < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :legacy_email, :string
  end
end

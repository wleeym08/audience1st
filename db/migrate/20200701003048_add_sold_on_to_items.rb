class AddSoldOnToItems < ActiveRecord::Migration
  def change
    add_column :items, :sold_on, :datetime
    Item.reset_column_information
    # Set the sold_on date for CanceledItems to the date of cancellation (= item.updated_at)
    # Set the sold_on date for all other item types to the order's sold_on
    Item.transaction do
      Item.all.each do |i|
        i.sold_on =
          if i.kind_of?(CanceledItem) then i.updated_at else i.order.sold_on end
        i.save!
      end
    end
  end
end
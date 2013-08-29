class LapsedSubscribers < Report

  def initialize(output_options = {})
    sub_vouchers =  Vouchertype.subscription_vouchertypes
    @view_params = {
      :name => "Lapsed subscribers report",
      :have_vouchertypes => sub_vouchers,
      :dont_have_vouchertypes => sub_vouchers
    }
    super
  end

  def generate(params={})
    have = Report.list_of_ints_from_multiselect(params[:have_vouchertypes])
    have_not = Report.list_of_ints_from_multiselect(params[:dont_have_vouchertypes])
    unless have.size + have_not.size > 0
      add_error "You  must specify at least one type of voucher from at least one list."
      return nil
    end
    self.output_options = params[:output]
    purchased_any = if have.empty? then Customer.all_customers else
                      Customer.purchased_any_vouchertypes(have) end
    purchased_none = if have_not.empty? then [] else
                       Customer.purchased_no_vouchertypes(have_not) end
    return purchased_any & purchased_none
  end
end

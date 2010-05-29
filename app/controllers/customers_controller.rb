class CustomersController < ApplicationController

  require File.dirname(__FILE__) + '/../helpers/application_helper.rb'
  require 'net/http'
  require 'uri'

  include Enumerable

  # must be validly logged in before doing anything except login or create acct
  before_filter(:is_logged_in,
                :only=>%w[welcome welcome_subscriber change_password edit],
                :add_to_flash => 'Please log in or create an account to view this page.')
  before_filter :reset_shopping, :only => %w[welcome welcome_subscriber]

  # must be boxoffice to view other customer records or adding/removing vouchers
  before_filter :is_staff_filter, :only => %w[list switch_to search]
  before_filter :is_boxoffice_filter, :only=>%w[merge create]

  # only superadmin can destory customers, because that wreaks havoc
  before_filter(:is_admin_filter,
                :only => ['destroy'],
                :redirect_to => {:action => :list},
                :add_to_flash => 'Only super-admin can delete customer; use Merge instead')

  # prevent complaints on AJAX autocompletion
  skip_before_filter :verify_authenticity_token, :only => [:auto_complete_for_customer_full_name]

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => %w[destroy create user_create], :redirect_to => { :controller => :customers, :action => :welcome, :add_to_flash => "This action requires a POST." }

  # checks for SSL should be last, as they append a before_filter
  ssl_required :change_password, :new, :create, :user_create, :edit, :forgot_password
  ssl_allowed :auto_complete_for_customer_full_name

  # auto-completion for customer search
  def auto_complete_for_customer_full_name
    render :inline => "" and return if params[:__arg].blank?
    @customers =
      Customer.find_by_multiple_terms(params[:__arg].to_s.split( /\s+/ ))
    render(:partial => 'customers/customer_search_result',
           :locals => {:matches => @customers})
  end

  # the default is to show your welcome page, which automatically redirects
  # to login if you're not logged in or to subscriber welcome if you're a
  # subscriber.
  def index ; redirect_to :action => 'welcome' ; end

  # DEPRECATED legacy routes:
  def login ; redirect_to login_path ; end
  def logout ; redirect_to logout_path ; end

  # welcome screen: different for nonsubscribers vs. subscribers

  def welcome                   # for nonsubscribers
    @customer = @gCustomer
    # if customer is a subscriber, AND force_classic is not indicated,
    # redirect to correct page
    if (@customer.subscriber?)
      @subscriber = true
      unless ((params[:force_classic] && @gAdmin.is_boxoffice) ||
              !(Option.value(:force_classic_view).blank?))
        flash.keep :notice
        flash.keep :warning
        redirect_to :action=>'welcome_subscriber'
        return
      end
    else
      @subscriber = nil
    end
    @admin = current_admin
    @page_title = sprintf("Welcome, %s#{@customer.full_name.name_capitalize}",
                          @customer.subscriber? ? 'Subscriber ' : '')
    @vouchers = (@admin.is_boxoffice ?  @customer.vouchers :  @customer.active_vouchers).sort_by(&:created_on).reverse
    session[:store_customer] = @customer.id
  end

  def welcome_subscriber        # for subscribers
    @customer = @gCustomer
    unless @customer.subscriber?
      flash.keep :notice
      flash.keep :warning
      redirect_to :action=>'welcome'
      return
    end
    @admin = current_admin
    @page_title = "Welcome, Subscriber #{@customer.full_name.name_capitalize}"
    @vouchers = @customer.active_vouchers.sort_by(&:created_on)
    session[:store_customer] = @customer.id
    @subscriber = true
    # separate vouchers into these categories:
    # unreserved subscriber vouchers, reserved subscriber vouchers, others
    @subscriber_vouchers, @other_vouchers = @vouchers.partition { |v| v.part_of_subscription? }
    @reserved_vouchers,@unreserved_vouchers = @subscriber_vouchers.partition { |v| v.reserved? }
    # find all shows whose run dates overlap the validity period of any voucher.

    # BUG this should be computed from voucher validity period...
    @mindate = Time.now
    @maxdate = (@mindate + 1.year).at_beginning_of_year
    @shows = Show.find(:all, :conditions => ["opening_date > ? OR closing_date < ?",@mindate,@maxdate],
                       :order => "opening_date")
  end

  def link_user_accounts
    if self.current_user.nil?
      #register with fb
      Customer.create_from_fb_connect(facebook_session.user)
    else
      #connect accounts
      self.current_user.link_fb_connect(facebook_session.user.id) unless
        self.current_user.fb_user_id == facebook_session.user.id
    end
    redirect_to_stored
  end

  def edit
    @customer = current_user
    @is_admin = current_admin.is_staff
    @superadmin = current_admin.is_admin
    # editing contact info may be called from various places. correctly
    # set the return-to so that form buttons can do the right thing.
    @return_to = session[:return_to]
    return unless request.post? # fall thru to showing edit screen
    flash[:notice] = ''
    # squeeze empty-string params into nils.
    # params[:customer].each_pair { |k,v| params[:customer][k]=nil if v.blank? }
    # # this is messy: if this is part of a checkout flow, it's OK for customer
    # #  not to specify a password.  This will be obsolete when customers are
    # #  subclassed with different validations on each subclass.
    # temp_password = nil
    # if @gCheckoutInProgress && params[:customer][:password].blank?
    #   temp_password =  params[:customer][:password] = params[:customer][:password_confirmation] =  String.random_string(8)
    # end
    # unless admin, remove "extra contact" fields
    unless @is_admin
      Customer.extra_attributes.each { |a| params[:customer].delete(a) }
      # flash[:notice] << "Warning: Some new attribute values were ignored<br/>"
    end
    #
    #  special case: updating 'role' (privilege) is protected attrib
    #
    if ((newrole = params[:customer][:role]) &&
        (Customer.role_value(newrole) != Customer.role_value(@customer.role)))
      if Customer.find(logged_in_id).can_grant(newrole)
        @customer.role = Customer.role_value(params[:customer][:role])
        unless (@customer.save)
          flash[:notice] = "Update failed: #{@customer.errors.full_messages.join(', ')}.  Please fix this problem and try again."
          redirect_to(:action => 'edit') and return
        end
        confirm = "Role set to #{newrole}<br/>"
        Txn.add_audit_record(:txn_type => 'edit',
                             :customer_id => @customer.id,
                             :logged_in_id => logged_in_id,
                             :comments => confirm)
        flash[:notice] << confirm
      else
        flash[:notice] << "Change of patron privilege level is disallowed. "
      end
    end
    params[:customer].delete(:comments) unless @is_admin
    # update generic attribs
    # if login is empty - make it nil to avoid failing validation
    params[:customer].delete(:login) if params[:customer][:login].blank?
    if @customer.update_attributes(params[:customer])
      Txn.add_audit_record(:txn_type => 'edit',
                           :customer_id => @customer.id,
                           :logged_in_id => logged_in_id)
      flash[:notice] << 'Contact information was successfully updated.'
      if @customer.email_changed? && @customer.valid_email_address? &&
          params[:dont_send_email].blank? # && temp_password.blank?
        # send confirmation email
        email_confirmation(:send_new_password,@customer, nil,
                           "updated your email address in our system")
      end
      redirect_to_stored
    else                      # update was legal to try, but it failed
      flash[:notice] << 'Information was NOT updated: ' <<
        @customer.errors.full_messages.join("; ")
      redirect_to :action => 'edit'
    end
  end

  def change_password
    @customer = current_user
    if (request.post?)
      pass = params[:customer][:password].to_s.strip
      @customer.password = pass unless pass.blank?
      @customer.login = params[:customer][:login].to_s.strip
      if @customer.login.blank?
        flash[:notice] = "Login can't be blank. Please choose a login name."
        render(:action => 'change_password') and return
      end
      if (@customer.save)
        flash[:notice] = pass.blank? ? "New login confirmed (password unchanged)." : "New login and password are confirmed."
        email_confirmation(:send_new_password,@customer,
                           pass, "changed your login or password on our system")
        Txn.add_audit_record(:txn_type => 'edit',
                             :customer_id => @customer.id,
                             :comments => 'Change password')
        redirect_to :action => 'welcome'
      else
        render :action => 'change_password'
      end
    end
  end


  def user_create
    # this is messy: if this is part of a checkout flow, it's OK for customer
    #  not to specify a password.  This will be obsolete when customers are
    #  subclassed with different validations on each subclass.
    temp_password = nil
    if @gCheckoutInProgress && params[:customer][:password].blank?
      temp_password = params[:customer][:password] = params[:customer][:password_confirmation] =
        String.random_string(8)
    end
    @customer = Customer.new(params[:customer])
    flash[:notice] = ''
    if @gCheckoutInProgress && @customer.day_phone.blank?
      flash[:notice] = "Please provide a contact phone number in case we need to contact you about your order."
      render :action => 'new'
      return
    end
    if @customer.save && @customer.errors.empty?
      @customer.update_attribute(:last_login, Time.now)
      unless temp_password
        flash[:notice] = "Thanks for setting up an account!<br/>"
        email_confirmation(:send_new_password,@customer,
                         params[:customer][:password],"set up an account with us")
      end
      self.current_user = @customer
      logger.info "Session cid set to #{session[:cid]}"
      Txn.add_audit_record(:txn_type => 'edit',
                           :customer_id => @customer.id,
                           :comments => 'new customer self-signup')
      redirect_to_stored
    else
      flash[:notice] = "There was a problem creating your account.<br/>"
      render :action => 'new'
    end
  end

  # Following actions are for use by admins only:
  # list, switch_to, merge, search, create, destroy

  def list
    @customers_filter ||= params[:customers_filter]
    conds = Customer.match_any_content_column(@customers_filter)
    @customer_pages, @customers = paginate :customers, :per_page => 100, :order => 'last_name,first_name', :conditions => conds
    @count = Customer.count(:conditions => conds)
    curpage = @customer_pages.current_page
    @title = "#{curpage.first_item} - #{curpage.last_item} of #{@count} matching '#{@customers_filter}'"
  end

  def merge
    if request.get?
      # display info from two records and allow selection
      if (!params[:merge]) || (params[:merge].keys.length != 2)
        flash[:notice] = 'You must select exactly 2 records at a time to merge'
        redirect_to :action => 'list'
      else
        @cust = params[:merge].keys.map { |x| Customer.find(x.to_i) }
        # fall through to merge.rhtml
      end
      return
    end
    # post: do the merge
    c0 = Customer.find_by_id(params.delete(:cust0))
    c1 = Customer.find_by_id(params.delete(:cust1))
    unless c0 && c1
      flash[:error] = "At least one customer not found. Please try again."
      redirect_to :action => :list and return
    end
    result = c0.merge_with_params!(c1, params)
    # result is nil if merge failed, else string describing result
    if result
      flash[:notice] = result
      redirect_to :action => 'welcome'
    else                      # failure
      flash[:notice] = c0.errors.full_messages.join(';')
      redirect_to :action => 'list'
    end
  end

  def switch_to
    if (customer = Customer.find_by_id(params[:id]))
      act_on_behalf_of customer
      reset_shopping
      if params[:target_controller] && params[:target_action]
        redirect_to :controller => params[:target_controller], :action => params[:target_action], :id => customer.id
      else
        redirect_to :controller => 'customers',:action => 'welcome',:id => customer.id
      end
    else
      flash[:notice] = "No such customer: id# #{params[:id]}"
      redirect_to :controller => 'customers', :action => 'list'
    end
  end

  def search
    unless params[:searching]
      render :partial => 'search'
      return
    end
    str = ''
    if params[:match] =~ /any/i
      conds = %w[first_name last_name street city login].map {|x| "#{x} LIKE '%#{params[:any]}%'"}.join(" OR ")
    else
      k = params[:customer].keys
      if k.empty?
        flash[:notice] = "Please enter some constraints"
        render :partial => 'search'
      else
        conds = [ k.map { |x| "#{x} LIKE ?"}.join(" AND ") ] +
          params[:customer].values_at(*k).map { |s| "%#{s}%" }
      end
    end
    @customers = Customer.find(:all, :conditions => conds)
    render :partial => 'search_results'
  end

  def new
    @is_admin = current_admin.is_boxoffice
    @customer = Customer.new
  end
  
  def create
    @is_admin = true            # needed for choosing correct method in 'new' tmpl
    flash[:notice] = ''
    # if neither email address nor password was given, assign a random
    # password so validation doesn't fail.
    if params[:customer][:password].blank? && params[:customer][:login].blank?
      # assign a random password
      params[:customer][:login] = nil
      params[:customer][:password] =
        params[:customer][:password_confirmation] = String.random_string(6)
    end
    @customer = Customer.new(params[:customer])
    @customer.created_by_admin = true
    # then must have a password too....
    if @customer.save
      flash[:notice] <<  'Account was successfully created.'
      Txn.add_audit_record(:txn_type => 'edit',
                           :customer_id => @customer.id,
                           :comments => 'new customer added',
                           :logged_in_id => logged_in_id)
      # if valid email, send user a welcome message
      unless params[:dont_send_email]
        email_confirmation(:send_new_password,@customer,
                           params[:customer][:password],"set up an account with us")
      end
      session[:cid] = @customer.id
      if @gCheckoutInProgress
        redirect_to_stored
      else
        redirect_to :action => 'switch_to', :id => @customer.id
      end
    else
      flash[:notice] << 'Errors creating account'
      render :action => 'new'
    end
  end

  # DANGEROUS METHOD: restricted to super-admin
  # TBD: what this really should do is link all related stuff to
  # the placeholder 'walkup customer'

  def destroy
    p = session[:cid].to_i
    if p == logged_in_id
      flash[:notice] = "Can't delete yourself while logged in"
    elsif p.zero?
      flash[:notice] = "Can't delete placeholder customer 0"
    else
      begin
        c = Customer.find(p)
        msg = "Customer '#{c.full_name}' (ID #{c.id}) permanently deleted"
        c.destroy
        flash[:notice] = msg
      rescue Exception => e
        flash[:notice] = "Error deleting customer: #{e.message}"
      end
    end
    session[:cid] = @gAdmin.id
    redirect_to :action => 'list'
  end


  #  TBD this method only used by (eg) visits controller to replace-in-place
  # a customer id with a name. Should be obsoleted.
  def lookup
    if ((params[:id].to_i != 0) && (c=Customer.find_by_id(params[:id])))
      render :text => c.full_name
    else
      render(:text => 'No such customer') unless params[:silent]
    end
  end

  # TBD this is an AJAX handler that is called from the partial
  #  _validate.rhtml, which can be rendered as part of the customer
  # _form partial to validate US Mail address.  But first it needs to be
  # connected to a working validation service!

  def validate_address
    cust = params[:customer]
    url = "http://zip4.usps.com/zip4/zcl_0_results.jsp?visited=1&pagenumber=0&firmname=&address2=#{cust[:street]}&address1=&city=#{cust[:city]}&state=#{cust[:state]}&urbanization=&zip5=#{cust[:zip]}"
    res = Net::HTTP.get_response(URI.parse(URI.escape(url)))
    if res.code.to_i == 200 && res.body.match(/.*td headers="full"[^>]+>(.*)<br \/>\s+<\/td>\s+<td style=/m )
      street,csz = Regexp.last_match(1).split /<br \/>/
      city,state,zip = (csz.strip.split( /(&nbsp;)+/ )).values_at(0,2,4)
    end
    render :update do |page|
      page['customer_street'].value = street.strip
      page['customer_city'].value = city.strip
      page['customer_state'].value = state.strip
      page['customer_zip'].value = zip.strip
    end
  end

  def temporarily_disable_admin
    disable_admin
    flash[:notice] = "You are now logged in <strong>without</strong> admin privileges.  Logout and log back in to reestablish admin privileges."
    redirect_to_stored
  end

  private



  def forgot_password(login)
    if login.blank?
      flash[:notice] = "Please enter the login name with which you originally signed up, and we will email you a new password."
      redirect_to :action => :login and return
    end
    @customer = Customer.find_by_login(login)
    unless @customer
      flash[:notice] = "Sorry, '#{login}' is not in our database.  You might try under a different login name, or create a new account."
      redirect_to :action => :login and return
    end
    # valid email address?
    unless @customer.valid_email_address?
      flash[:notice] = "You're in our database but we don't have an email address for you.  Please set up a new account with an email address."
      redirect_to :action => :new and return
    end
    begin
      newpass = String.random_string(6)
      @customer.password = newpass
      @customer.save!
      email_confirmation(:send_new_password,@customer, newpass,
                         "requested your password for logging in")
      # will reach this point (and change password) only if mail delivery
      # doesn't raise any exceptions
      Txn.add_audit_record(:txn_type => 'edit',
                           :customer_id => @customer.id,
                           :comments => 'Password has been reset')
    rescue Exception => e
      flash[:notice] = e.message +
        "<br/>Please contact #{Option.value(:help_email)} if you need help."
    end
    redirect_to :action => :login
  end
end

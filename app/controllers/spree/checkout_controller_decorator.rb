module Spree
  CheckoutController.class_eval do
    before_filter :redirect_to_mollie, :only => [:update]

    private

    def redirect_to_mollie
      return if @order.completed? || @order.outstanding_balance == 0
      return unless params[:state] == "payment"

      # check to see if there is an existing mollie payment pending
      mollie_payment_method = PaymentMethod.find_by(type: 'Spree::Gateway::MolliePayment')
      payment = @order.payments.valid.where(payment_method: mollie_payment_method).first

      begin
        mollie = Mollie::API::Client.new.(MOLLIE_API_KEY)
        mollie_payment = mollie.payments.get(payment.source.transaction_id) if payment

        unless payment && mollie_payment && ['open','pending'].include?(mollie_payment.status)
          mollie_payment = mollie.payments.create \
            :amount       => @order.total,
            :description  => "Payment for order #{@order.number}",
            :redirect_url  => mollie_url(@order, :utm_nooverride => 1), # ensure that transactions are credited to the original traffic source
            :webhook_url => mollie_url(@order, :utm_nooverride => 1),
            :method       => params[:order][:payments_attributes][0][:payment_method_id],
            # :billingEmail => @order.email, # when email is provided, Mollie sends an email with payment details (e.g. for banktransfer)
            :metadata     => {
              :order => @order.number
            }

          # Create mollie payment & source
          source_params = {
            :transaction_id => mollie_payment.id,
            :mode => mollie_payment.mode,
            :status => mollie_payment.status,
            :amount => mollie_payment.amount,
            :description => mollie_payment.description,
            :created_at => mollie_payment.created_datetime
          }
          if mollie_payment.method == 'banktransfer'
            source_params[:banktransfer_bank_name] = mollie_payment.details.bankName
            source_params[:banktransfer_bank_account] = mollie_payment.details.bankAccount
            source_params[:banktransfer_bank_bic] = mollie_payment.details.bankBic
            source_params[:banktransfer_transfer_reference] = mollie_payment.details.transferReference
          end
          payment = @order.payments.create!({
            :source => Spree::MollieCheckout.create(source_params),
            :amount => @order.total,
            :payment_method => mollie_payment_method
          })
        end

        redirect_to mollie_payment.payment_url and return
      rescue Mollie::API::Exception => e
        logger.debug << "Mollie API call failed: " << (CGI.escapeHTML e.message)
      end
    end
  end
end

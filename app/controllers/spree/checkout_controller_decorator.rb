module Spree
  CheckoutController.class_eval do
    prepend_before_action :redirect_to_mollie, only: [:update]

    private

    def redirect_to_mollie
      @order = current_order
      return if @order.completed? || @order.outstanding_balance == 0
      # return unless params[:state] == "payment"

      return unless params[:state] == 'confirm'  && current_order

      payment = current_order.unprocessed_payments.first
      payment_method = payment.payment_method if payment
      return unless payment_method.try(:type) == 'Spree::PaymentMethod::MolliePayment'


      # check to see if there is an existing mollie payment pending
      # mollie_payment_method = PaymentMethod.find_by(type: 'Spree::PaymentMethod::MolliePayment')
      # payment = @order.payments.valid.where(payment_method: mollie_payment_method).first
      mollie_payment_method = payment_method
      begin
        api_key =  mollie_payment_method.preferred_api_key

        mollie = Mollie::Client.new(api_key)
        mollie_payment = payment && payment.source ? Mollie::Payment.get(payment.source.transaction_id) : nil


        unless payment && mollie_payment && ['open','pending'].include?(mollie_payment.status)
          create_args = {
            # amount:        @order.total,
            amount:        { "currency": "EUR", "value": '%.2f' % @order.total },
            description:   SpreeMollie.payment_subject.gsub('%{order}',  @order.number),
            redirect_url:  mollie_url(@order, utm_nooverride: 1), # ensure that transactions are credited to the original traffic source
            webhook_url:   Rails.env.development? ? nil : mollie_callback_url(ordernr: @order.number),
            #webhook_url:  'https://webshop.example.org/mollie-webhook/'
            locale:        SpreeMollie.locale,

            # :billingEmail => @order.email, # when email is provided, Mollie sends an email with payment details (e.g. for banktransfer)
            metadata: { order: @order.number }
          }
          puts "---- CREATE: --"
          puts create_args.to_json

          mollie_payment = Mollie::Payment.create(create_args)

          # Create mollie payment & source
          source_params = {
            transaction_id: mollie_payment.id,
            mode:           mollie_payment.mode,
            status:         mollie_payment.status,
            amount:         mollie_payment.amount.value,
            description:    mollie_payment.description,
            created_at:     mollie_payment.created_at
          }
          if mollie_payment.method == 'banktransfer'
            source_params[:banktransfer_bank_name] = mollie_payment.details.bank_name
            source_params[:banktransfer_bank_account] = mollie_payment.details.bank_account
            source_params[:banktransfer_bank_bic] = mollie_payment.details.bank_bic
            source_params[:banktransfer_transfer_reference] = mollie_payment.details.transfer_reference
          end
          payment = @order.payments.create!(
            source:         Spree::MollieCheckout.create(source_params),
            amount:         @order.total,
            payment_method: mollie_payment_method
          )
        end
        redirect_to mollie_payment.checkout_url and return
      rescue Mollie::Exception => e
        Rails.logger.warn "Mollie API call failed: #{e.message}"
        raise e
      end
    end
  end
end

class PaypalPayment < ApplicationRecord
  extend Enumerize
  include Paymentable

  belongs_to :billing
  belongs_to :promocode
  has_one :user, through: :billing
  validate :correct_licenses_amount
  scope :approved, -> { where.not('status = ? AND paypal_sale_id IS NULL', PaypalPayment.status
                                                                                        .find_value(:pending).value) }
  scope :not_approved, -> { with_status(:pending).where(paypal_sale_id: nil)
                                                 .where('paypal_payments.created_at < ?', 30.minutes.ago) }

  before_save :successful_operations, if: ->(payment) { (payment.changed_attributes[:status] || payment.new_record?) && payment.status.success? }
  before_save :failed_operations, if: ->(payment) { payment.changed_attributes[:status] && payment.status.fail? }
  before_create { promocode.increase_uses unless promocode_id.nil? }
  before_destroy { promocode.decrease_uses if promocode_can_be_redused? }
  after_commit :send_notifications, if: ->(payment) { payment.previous_changes[:status] }
  enumerize :status, in: { pending: 0, success: 1, fail: 2 }, default: :pending, scope: true

  private

  def promocode_can_be_redused?
    promocode_id.present? && promocode.number_of_uses > 0
  end

  def correct_licenses_amount
    errors.add(:paypal_payment, I18n.t('license.wrong_number')) if regular && licenses_amount < billing.licenses_amount
  end

  def successful_operations
    update_billing
    user.payment_applied!
  end

  def send_notifications
    if status.success?
      generate_invoice
      PaymentMailer.send_successful_payment_notification(id).deliver_later
    end
    PaymentMailer.send_failed_payment_notification(id).deliver_later if status.fail?
  end

  def failed_operations
    promocode.decrease_uses if promocode_can_be_redused?
  end

  def update_billing
    activating_condition = billing.waiting_for_activation?
    new_licenses_amount = regular || activating_condition ? licenses_amount : billing.licenses_amount + licenses_amount
    if regular || activating_condition
      billing.update(licenses_amount: new_licenses_amount, prev_expired_at: period_start.prev_day.end_of_day,
                     expired_at: period_end, trial_period: false)
      user.update_attribute(:payment_notification_visible, false)
    else
      billing.update(licenses_amount: new_licenses_amount, trial_period: false)
    end
  end

  def generate_invoice
    variables_for_invoice
    pdf = WickedPdf.new.pdf_from_string(
      ApplicationController.new.render_to_string('paypal_payments/invoice', layout: 'invoice',
                                                                            locals: { :@payment => self,
                                                                                      :@full_discount => @full_discount,
                                                                                      :@items => @items,
                                                                                      :@info => @info })
    )
    filename = "Invoice##{id}"
    folder_name = updated_at.strftime('%d_%m_%Y')
    dir = "public/pdfs/#{folder_name}"
    FileUtils.mkdir_p(dir) unless File.directory?(dir)

    File.open("#{dir}/#{filename}.pdf", 'wb') do |file|
      file << pdf
    end
    "pdfs/#{folder_name}/#{filename}.pdf"
  end

  def variables_for_invoice
    @promocode = promocode
    @fee_per_new_license = standart_fee
    @date_arrays = periods
    generate_items(licenses_amount, period_start)
  end
end

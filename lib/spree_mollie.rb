require 'spree_core'
# require 'Mollie/API/Client'
require 'spree_mollie/engine'


module SpreeMollie

  mattr_accessor :locale
  #@@article_grouper = Bp::Connector::ArticleImporter::ArticleGrouper
  def self.locale
    @@locale ||= 'en_US'  #en_US de_AT de_CH de_DE es_ES fr_BE fr_FR nl_BE nl_NL
  end

  mattr_accessor :payment_subject
  def self.payment_subject
    @@payment_subject ||= "Payment for order %{order}"
  end

end